const std = @import("std");
const nc = @import("notcurses.zig");
const midilib = @import("midilib.zig");
const pm = @import("portmidi.zig");
const lib = @import("lib.zig");
const lp = @import("launchpad.zig");
const posix = @cImport({
    @cInclude("unistd.h");
});

// figuring out what (shift+)numeric key was pressed
const shiftNumKeys = [_]u8{ '!', '@', '#', '$', '%', '^', '7', '8', '9', '0' }; // US/UK!
const numKeys = [_]u8{ '1', '2', '3', '4', '5', '6', '7', '8', '9', '0' };

pub fn init_nc() *nc.notcurses {
    var nc_opts: nc.notcurses_options = nc.default_notcurses_options;
    const ncs: *nc.notcurses = (nc.notcurses_core_init(&nc_opts, null) orelse @panic("notcurses_core_init() failed"));
    return ncs;
}

pub fn create_nc_root_plane(ncs: *nc.notcurses) *nc.ncplane {
    var dimy: c_uint = undefined;
    var dimx: c_uint = undefined;
    const n: *nc.ncplane = (nc.notcurses_stddim_yx(ncs, &dimy, &dimx) orelse unreachable);
    dimx = @max(dimx, 80);
    dimy = @max(dimy, 25);
    var std_chan: u64 = 0;
    nc.err(nc.ncchannels_set_bg_rgb(&std_chan, 0)) catch unreachable;
    nc.err(nc.ncplane_set_base(n, " ", 0, std_chan)) catch unreachable;
    return n;
}

pub fn create_nc_plane(parentPlane: *nc.ncplane) *nc.ncplane {

    // make box planes
    var opts = nc.default_ncplane_options;
    opts.rows = 1;
    opts.cols = 1;
    const plane = nc.ncplane_create(parentPlane, &opts) orelse unreachable;
    nc.err(nc.ncplane_move_yx(plane, 1, 1)) catch unreachable;
    nc.err(nc.ncplane_resize_simple(plane, 25, 35)) catch unreachable;
    return plane;
}

pub fn updatePlane(allocator: std.mem.Allocator, plane: *nc.ncplane, metro: *midilib.Sequencer) !void {
    nc.ncplane_erase(plane);
    try nc.err(nc.ncplane_cursor_move_yx(plane, 0, 0));
    var chans: u64 = 0;
    try nc.err(nc.ncchannels_set_bg_rgb(&chans, 0));
    try nc.err(nc.ncchannels_set_bg_alpha(&chans, nc.NCALPHA_BLEND));
    try nc.err(nc.ncplane_set_base(plane, " ", 0, chans));
    _ = nc.ncplane_rounded_box(plane, 0, 0, nc.ncplane_dim_y(plane) - 1, nc.ncplane_dim_x(plane) - 1, 0);

    for (0.., metro.tracks[0..]) |i, t| {
        const mutedState = if (t.muted) "muted" else "umuted";
        const patternNum = t.currentPatternIndex();
        const nextPatternNum = t.nextPatternIndex();
        const nextAsStr = if (nextPatternNum != null) std.fmt.allocPrint(allocator, "({d})", .{(nextPatternNum orelse unreachable) + 1}) catch unreachable else "";

        const str = std.fmt.allocPrint(allocator, "Track {d}: {s}, pattern {d} {s}", .{ i + 1, mutedState, patternNum + 1, nextAsStr }) catch unreachable;
        // add text
        // weird - consistently fails (error -26) after 6th beat
        // tempo 120 + in device!
        // edit: ok now it immediately fails with error -25

        _ = nc.ncplane_putstr_yx(plane, @intCast(i + 1), 2, @ptrCast(str));
        allocator.free(str);
        allocator.free(nextAsStr);
    }
}

pub fn updateLaunchpad(seq: *midilib.Sequencer, launchpad: *lp.Launchpad) void {
    var matrix: [lp.nCells]pm.PmMessage = undefined;
    var ctrls: [lp.nCtrls]pm.PmMessage = undefined;
    if (launchpad.ctrlPressed(lp.Ctrl.mixer)) {
        lp.seqStateToMatrixMessages(&matrix, seq, launchpad);
    } else {
        lp.patternToMatrixMessages(
            &matrix,
            seq.*.midiPPQ,
            seq.*.tracks[launchpad.uiState.currentTrack].currentPattern,
            launchpad.uiState.xOffset,
            launchpad.uiState.yOffset,
        );
    }
    ctrls = [_]pm.PmMessage{
        lp.ColorNone,
        lp.ColorNone,
        lp.ColorNone,
        lp.ColorNone,
        lp.ColorNone,
        lp.ColorNone,
        lp.ColorNone,
        // weird - ColorNone doesn't seem to change anything
        if (launchpad.ctrlPressed(lp.Ctrl.mixer)) lp.ColorRedFull else lp.ColorOrange,
        lp.ColorNone,
        lp.ColorNone,
        lp.ColorNone,
        lp.ColorNone,
        lp.ColorNone,
        lp.ColorNone,
        lp.ColorNone,
        lp.ColorNone,
    };
    _ = launchpad.update(&matrix, &ctrls);

    const result = pm.Pm_Poll(launchpad.midiInput);
    if (result > 0) {
        var buffer: pm.PmEvent = undefined;
        _ = pm.Pm_Read(launchpad.midiInput, &buffer, 1);
        launchpad.keyPressed(seq, buffer.message);
    }
}

pub fn runloop(allocator: std.mem.Allocator, legacyInputHandling: bool, ncs: *nc.notcurses, plane: *nc.ncplane, metro: *midilib.Sequencer, lpMatrix: ?*lp.Launchpad) !void {
    outer: {
        var stop: bool = false;
        while (!stop) {
            try updatePlane(allocator, plane, metro);
            if (lpMatrix) |lpM| {
                updateLaunchpad(metro, lpM);
            }

            try nc.err(nc.notcurses_render(ncs));
            _ = posix.usleep(@divTrunc(1.0e6, 60));

            var nci: nc.ncinput = undefined;
            const keypress: c_uint = nc.notcurses_get_nblock(ncs, &nci);
            if (keypress == 'q') {
                stop = true;
                break :outer;
            }
            var msg: ?midilib.Msg = null;
            // nci.evype determines key-up/key-down
            if (nci.evtype == 1 and nci.id >= 49 and nci.id <= 57) {
                const trackNum = (std.fmt.parseInt(u32, ([1]u8{@intCast(keypress)})[0..], 10) catch unreachable) - 1;
                if (nci.shift) {
                    msg = midilib.Msg{
                        .type = midilib.MsgType.PatternQue,
                        .trackNumber = trackNum,
                    };
                } else {
                    // mute/unmute
                    msg = midilib.Msg{
                        .type = midilib.MsgType.TrackMute,
                        .trackNumber = trackNum,
                    };
                }
                if (msg) |_| {
                    _ = pm.Pm_Enqueue(metro.mainToMidi, &msg);
                }
            } else if (legacyInputHandling) {
                if (lib.indexOf(u8, &numKeys, @as(u8, @intCast(keypress))) catch null) |trackNum| {
                    msg = midilib.Msg{
                        .type = midilib.MsgType.TrackMute,
                        .trackNumber = trackNum,
                    };
                } else if (lib.indexOf(u8, &shiftNumKeys, @as(u8, @intCast(keypress))) catch null) |trackNum| {
                    msg = midilib.Msg{
                        .type = midilib.MsgType.PatternQue,
                        .trackNumber = trackNum,
                    };
                }

                if (msg) |_| {
                    _ = pm.Pm_Enqueue(metro.mainToMidi, &msg);
                }
            }
            // debug keyboard state
            // std.debug.print("nci {}\n", .{nci});
        }
    }
}
