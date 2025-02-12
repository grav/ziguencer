// todo - pattern change doesn't work
// todo - test midi input

const std = @import("std");
const pm = @import("portmidi.zig");
const lib = @import("lib.zig");
const dp = lib.dp;
const midilib = @import("midilib.zig");
const nc = @import("notcurses.zig");
const testPatterns = @import("testpatterns.zig");
const ui = @import("ui.zig");
const lp = @import("launchpad.zig");
const posix = @cImport({
    @cInclude("unistd.h");
});

const SeqEvent = midilib.SeqEvent;

pub const PmTimeProcPtr = ?fn (?*anyopaque) callconv(.C) pm.PmTimestamp;

// legacy - not to be used

const maxEvents = 100;

// var random: std.rand.Random = undefined;

fn pairsSliceToArrayList(comptime T: type, allocator: std.mem.Allocator, seqEventsSlice: []const [2]T) std.ArrayList(T) {
    var l = std.ArrayList(T).init(allocator);
    for (seqEventsSlice) |es| {
        l.append(es[0]) catch unreachable;
        l.append(es[1]) catch unreachable;
    }
    return l;
}

pub fn main() !void {
    lib.showDeviceInfo();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = try std.process.argsWithAllocator(allocator);

    var argsMap = std.StringHashMap([]const u8).init(allocator);
    defer argsMap.deinit();
    lib.parseArgsToMap(&args, &argsMap);

    // var tt = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    // random = tt.random();

    var metro = midilib.Sequencer{
        .midiPPQ = 1120,
    };
    var in: i32 = -1;
    if (argsMap.get("--look-ahead")) |v| {
        metro.lookAheadMs = std.fmt.parseInt(i32, v, 10) catch {
            std.debug.print("Error: Unable to parse '{s}' as integer for look-ahead!\n", .{v});
            std.process.exit(1);
        };
    } else {
        metro.lookAheadMs = 100;
    }

    var out: i32 = -1;

    if (argsMap.get("--out")) |v| {
        out = std.fmt.parseInt(i32, v, 10) catch lib.getDevice(allocator, lib.DeviceType.Output, v) orelse -1;
    }
    if (out == -1) {
        std.debug.print("Error: need to specify output device name/number with `--out [name/number]`!\n", .{});
        std.process.exit(1);
    }

    std.debug.print("Using look-ahead: {d} ms\n", .{metro.lookAheadMs});
    std.debug.print("Using output: {d}\n", .{out});

    if (argsMap.get("--in")) |v| {
        in = std.fmt.parseInt(i32, v, 10) catch lib.getDevice(allocator, lib.DeviceType.Input, v) orelse -1;
        if (in >= 0) {
            std.debug.print("Using input: {d}\n", .{in});
        }
    }

    var lpOut: i32 = undefined;
    if (argsMap.get("--launchpad-out")) |v| {
        lpOut = std.fmt.parseInt(i32, v, 10) catch {
            std.debug.print("Error: unable to parse '{s}' as integer for launchpad output!\n", .{v});
            std.process.exit(1);
        };
    }

    var lpIn: i32 = undefined;
    if (argsMap.get("--launchpad-in")) |v| {
        lpIn = std.fmt.parseInt(i32, v, 10) catch {
            std.debug.print("Error: unable to parse '{s}' as integer for launchpad input!\n", .{v});
            std.process.exit(1);
        };
    }
    if (argsMap.get("--launchpad")) |s| {
        if (std.mem.eql(u8, s, "auto")) {
            lpIn = lib.getDevice(
                allocator,
                lib.DeviceType.Input,
                "launchpad",
            ) orelse -1;
            lpOut = lib.getDevice(
                allocator,
                lib.DeviceType.Output,
                "launchpad",
            ) orelse -1;
        }
    }

    // legacy input handling, for compatibility with Linux Framebuffer Console (ie pre-X)
    const legacyInputHandling = argsMap.get("--legacy-input") != null;
    if (legacyInputHandling) {
        std.debug.print("Using legacy input handling\n", .{});
    }

    // zero-indexed
    const drumChannel = 9;

    // again, zero-indexed
    const bassChannel = 1;
    const melChannel = 0;

    var testPattern = midilib.Pattern.initWithRelNotes(allocator, &testPatterns.metronome, metro.midiPPQ, drumChannel);

    var testPattern2 = midilib.Pattern.initWithRelNotes(allocator, &testPatterns.beat1, metro.midiPPQ, drumChannel);

    var testPattern3 = midilib.Pattern.initWithRelNotes(allocator, &testPatterns.beat2, metro.midiPPQ, drumChannel);

    var bassPattern = midilib.Pattern.initWithRelNotes(allocator, &testPatterns.bassline, metro.midiPPQ, bassChannel);

    var bassPattern2 = midilib.Pattern.initWithRelNotes(allocator, &testPatterns.bassline2, metro.midiPPQ, bassChannel);

    var melodyPattern = midilib.Pattern.initWithRelNotes(allocator, &testPatterns.melody, metro.midiPPQ, melChannel);
    melodyPattern.patternLengthTicks = metro.midiPPQ * 3;

    var inputPattern = midilib.Pattern.initWithRelNotes(allocator, &[_]midilib.RelNote{}, metro.midiPPQ, 0);

    // TODO - why all these @constCasts?
    var metroTrack = midilib.Track.init(allocator, @constCast(&[_]*midilib.Pattern{ &testPattern, &testPattern2, &testPattern3 }), 9);
    var melodyTrack = midilib.Track.init(allocator, @constCast(&[_]*midilib.Pattern{&melodyPattern}), 0);
    melodyTrack.muted = true;
    var bassTrack = midilib.Track.init(allocator, @constCast(&[_]*midilib.Pattern{ &bassPattern, &bassPattern2 }), 0);
    bassTrack.muted = false;
    var inputTrack = midilib.Track.init(allocator, @constCast(&[_]*midilib.Pattern{&inputPattern}), 0);

    bassPattern.patternOffset = 0;
    testPattern.patternOffset = 0;
    melodyPattern.patternOffset = 0;
    metro.tracks = ([_]*midilib.Track{
        &metroTrack,
        &bassTrack,
        &melodyTrack,
        &inputTrack,
    })[0..];

    // // *** HERE BE MIDI STUFF ***
    _ = pm.Pm_Initialize();
    defer _ = pm.Pm_Terminate();
    const msPerCall = 5;
    _ = pm.Pt_Start(msPerCall, metro.callback, &metro);
    //latency: http://portmedia.sourceforge.net/portmidi/doxygen/group__grp__device.html
    const latency = 1;
    _ = pm.Pm_OpenOutput(&(metro.midiOut), out, null, 0, null, null, latency);
    if (metro.midiOut == null) {
        std.debug.print("Failed to start midi!\n", .{});
        std.process.exit(1);
    }
    defer _ = pm.Pm_Close(metro.midiOut);
    if (in >= 0) {
        _ = pm.Pm_OpenInput(&(metro.midiIn), in, null, 0, null, null);
        if (metro.midiIn == null) {
            std.debug.print("Failed to start midi!\n", .{});
            std.process.exit(1);
        }
    }
    defer _ = pm.Pm_Close(metro.midiIn);

    var lpMatrix: ?*lp.Launchpad = null;

    if (lpOut >= 0 and lpIn >= 0) {
        lpMatrix = @constCast(&lp.Launchpad.init(allocator, lpIn, lpOut));
        if (lpMatrix) |lpm| {
            lpm.clear();
        }
    }
    // TODO - how to deinit an optional?

    // make sure the first note will play
    metro.mainToMidi = pm.Pm_QueueCreate(32, @sizeOf(midilib.Msg)) orelse unreachable;
    const ncs = ui.init_nc();
    defer _ = nc.notcurses_stop(ncs);

    const root_plane = ui.create_nc_root_plane(ncs);
    const plane = ui.create_nc_plane(root_plane);
    try ui.runloop(allocator, legacyInputHandling, ncs, plane, &metro, lpMatrix);
}

// read from the midi in device:
//https://github.com/PortMidi/portmidi/blob/master/pm_test/midithru.c#L171C17-L171C57
