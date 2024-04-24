const std = @import("std");
const midilib = @import("midilib.zig");
const pm = @import("portmidi.zig");
const lib = @import("lib.zig");
const posix = @cImport({
    @cInclude("unistd.h");
});

pub const ColorNone = 0b0000000;
const ColorRedLow = 0b0000001;
const ColorRedMed = 0b0000010;
const ColorGreenLow = 0b0010000;
const ColorGreenMed = 0b0100000;
const ColorGreenFull = ColorGreenLow | ColorGreenMed;
pub const ColorRedFull = ColorRedLow | ColorRedMed;
const ColorYellowMed = ColorGreenFull | ColorRedMed; //0b0110010;
pub const ColorAmberFull = ColorGreenFull | ColorRedFull; //0b0110011;
pub const ColorOrange = ColorGreenMed | ColorRedFull; //0b0100011;
const ColorYellowLow = ColorGreenMed | ColorRedMed; //0b0100010;

pub const nCells = 8 * 8; // number of cells on Launchpad matrix
pub const nCtrls = 16; // number of controls

pub const Ctrl = enum(pm.PmMessage) {
    arrowUp = 8349872,
    arrowDown = 8350128,
    arrowLeft = 8350384,
    arrowRight = 8350640,
    session = 8350896,
    user1 = 8351152,
    user2 = 8351408,
    mixer = 8351664,
    vol = 8325264,
    pan = 8329360,
    sndA = 8333456,
    sndB = 8337552,
    stop = 8341648,
    trkOn = 8345744,
    solo = 8349840,
    arm = 8353936,
};

pub const fields = std.meta.fields(Ctrl);

pub fn isKeyDown(msg: pm.PmMessage) bool {
    return msg & 0xFF0000 == 0x7F0000;
}

// specific to launchpad
pub fn getKeyDown(msg: pm.PmMessage) pm.PmMessage {
    return msg | 0x7F0000;
}

pub fn getKeyUp(msg: pm.PmMessage) pm.PmMessage {
    return msg & 0x00FFFF;
}

pub const UIState = struct {
    yOffset: i32 = 0,
    xOffset: i32 = 0,
    currentTrack: usize = 0,
};

pub fn seqStateToMatrixMessages(messages: *[nCells]pm.PmMessage, seq: *midilib.Sequencer, launchpad: *Launchpad) void {
    for (0..nCells) |idx| {
        const trackNum = @mod(idx, 8);
        if (trackNum > 3) {
            // HACK: guard against dangling tracks
            messages[idx] = ColorNone;
            continue;
        }
        if (idx < 8) {
            messages[idx] = if (launchpad.*.uiState.currentTrack == idx) ColorOrange else ColorNone;
        } else if (idx >= 8 and idx < 56) {
            const track = seq.*.tracks[trackNum];
            const patNum = @divTrunc(idx, 8) - 1;
            if (track.*.patterns.len > patNum) {
                const p = track.*.patterns[patNum];
                messages[idx] = if (p == track.currentPattern) ColorGreenFull else (if (p == track.nextPattern and track.currentPattern != track.nextPattern) ColorYellowMed else ColorGreenLow);
            } else {
                messages[idx] = ColorNone;
            }
        } else if (idx >= 56 and idx < 60) {
            messages[idx] = if (seq.*.tracks[trackNum].muted) ColorRedLow else ColorRedFull;
        } else {
            messages[idx] = ColorNone;
        }
    }
}

pub fn patternToMatrixMessages(messages: *[nCells]pm.PmMessage, midiPPQ: i32, pattern: *midilib.Pattern, stepOffset: i32, noteOffset: i32) void {
    const stepResolutionDenom: i32 = 16; // (ie 1/16, then 16)
    const stepDivisor = @divTrunc(stepResolutionDenom, 4);
    const pulsesPerStep = @divTrunc(midiPPQ, stepDivisor);
    for (0..nCells) |idx| {
        messages[idx] = ColorNone;
    }
    for (pattern.events.items) |e| {
        if (midilib.SeqEvent.isNoteOn(e.msg)) {
            const noteVal: i32 = @intCast((e.msg & 0x00FF00) >> 8);
            // std.debug.print("note val: 0x{x:0>6} {d}\n", .{ noteVal, noteVal });
            const row = @divTrunc(e.pulse, pulsesPerStep);
            if (row >= 0 + stepOffset and row < 8 + stepOffset) {
                const col = 56 - 8 * (noteVal - noteOffset);
                const idx: i32 = (row - stepOffset) + col;
                // std.debug.print("{d},{d},{d}\n", .{ e.pulse, idx, e.msg });
                if (idx >= 0 and idx < 64) {
                    messages[@intCast(idx)] = ColorOrange;
                } else {
                    // TODO - check when this happens?
                    // std.debug.print("lpmatrix: weird - got idx {d}\n", .{idx});
                }
            } else {
                // not visible
            }
        }
    }
}

pub const Launchpad = struct {
    const Self = @This();
    matrixState: [nCells]pm.PmMessage = undefined,
    ctrlState: [nCtrls]pm.PmMessage = undefined,
    uiState: UIState = .{
        .yOffset = 0,
        .xOffset = 0,
        .currentTrack = 0,
    },
    midiInput: ?*pm.PmStream = null, // these probably could be non-optionals since they're currently required for the constructor
    midiOutput: ?*pm.PmStream = null,
    keyMap: std.AutoHashMap(pm.PmMessage, bool) = undefined,

    pub fn msgForField(i: usize) pm.PmMessage {
        inline for (std.meta.fields(Ctrl), 0..) |f, j| {
            if (j == i) return f.value;
        }
        unreachable;
    }

    pub fn isCtrl(k: pm.PmMessage) bool {
        inline for (std.meta.fields(Ctrl)) |f| {
            if (f.value == k) {
                return true;
            }
        }
        return false;
    }

    pub fn init(allocator: std.mem.Allocator, inNumber: i32, outNumber: i32) Self {
        var lp: Launchpad = .{};
        const latency = 1;
        _ = pm.Pm_OpenOutput(&lp.midiOutput, outNumber, null, 0, null, null, latency);
        if (lp.midiOutput == null) {
            // TODO - handle more gracefully!
            std.debug.print("Launchpad: Failed to start midi!\n", .{});
            std.process.exit(1);
        }
        lp.keyMap = std.AutoHashMap(pm.PmMessage, bool).init(allocator);

        _ = pm.Pm_OpenInput(&(lp.midiInput), inNumber, null, 0, null, null);

        return lp;
    }

    pub fn deinit(self: *Self) void {
        self.keyMap.deinit();
        _ = pm.Pm_Close(self.midiOutput);
    }

    // differential updating
    pub fn update(self: *Self, matrix: []pm.PmMessage, ctrls: []pm.PmMessage) usize {
        var msgs: [nCells + nCtrls]pm.PmEvent = undefined;
        var j: usize = 0;
        for (self.matrixState, 0..) |m, i| {
            const a = @divTrunc(i, 8) * 8;
            const note = @as(pm.PmMessage, @intCast(i + a));
            if (i >= matrix.len) {
                // interpret length < 64 as blanks
                if (m != ColorNone) {
                    self.matrixState[i] = ColorNone;
                    msgs[j] = .{
                        .message = ColorNone << 16 | note << 8 | 0x000090,
                        .timestamp = 0,
                    };
                    j += 1;
                }
            } else if (m != matrix[i]) {
                self.matrixState[i] = matrix[i];
                msgs[j] = .{
                    .message = matrix[i] << 16 | note << 8 | 0x000090,
                    .timestamp = 0,
                };
                j += 1;
            }
        }
        for (self.ctrlState, 0..) |c, i| {
            if (i > ctrls.len) {
                //

            } else {
                if (c != ctrls[i]) {
                    self.ctrlState[i] = ctrls[i];
                    msgs[j] = .{
                        .message = (ctrls[i] << 16) | (msgForField(i) & 0x00FFFF),
                        .timestamp = 0,
                    };
                    j += 1;
                }
            }
        }
        if (j > 0) {
            _ = pm.Pm_Write(self.midiOutput, &msgs, @intCast(j));
        }
        return j;
    }

    pub fn clear(self: *Self) void {
        var clearEvent: pm.PmEvent = .{
            .message = 0x0000b0,
            .timestamp = 0,
        };
        self.matrixState = std.mem.zeroes([nCells]pm.PmMessage);
        self.ctrlState = std.mem.zeroes([nCtrls]pm.PmMessage);
        _ = pm.Pm_Write(self.midiOutput, &clearEvent, 1);
    }

    pub fn noOtherKeysPressed(self: *Self, k: pm.PmMessage) bool {
        var it = self.keyMap.keyIterator();
        while (it.next()) |k2| {
            if (k2.* == k) continue;
            if (self.keyMap.get(k2.*) orelse unreachable) return false;
        }
        return true;
    }

    pub fn ctrlPressed(self: *Self, k: Ctrl) bool {
        return self.keyMap.get(@intFromEnum(k)) orelse false;
    }

    pub fn debugKeyMap(self: *Self) void {
        std.debug.print("---keymap---\n", .{});
        var it = self.keyMap.iterator();
        while (it.next()) |e| {
            if (!e.value_ptr.*) continue;
            const k2 = e.key_ptr.*;
            var desc: [:0]const u8 = "?";
            if (isCtrl(k2)) {
                const k3: Ctrl = @enumFromInt(k2);
                desc = @tagName(k3);
            }
            std.debug.print("0x{x:0>6} ({s})\n", .{ e.key_ptr.*, desc });
        }
        std.debug.print("---\n", .{});
    }

    pub fn rowFromKey(msg: pm.PmMessage) usize {
        return (msg & 0x00F000) >> 12;
    }

    pub fn colFromKey(msg: pm.PmMessage) usize {
        return (msg & 0x000F00) >> 8;
    }

    pub fn keyPressed(self: *Self, seq: *midilib.Sequencer, msg: pm.PmMessage) void {
        const keyDown = isKeyDown(msg);
        const k = if (keyDown) msg else getKeyDown(msg);
        self.keyMap.put(k, keyDown) catch unreachable;
        if (keyDown and isCtrl(k)) {
            // this is safe since we already checked with isCtrl
            const c: Ctrl = @enumFromInt(k);
            if (self.noOtherKeysPressed(k)) {
                switch (c) {
                    .arrowLeft => {
                        self.uiState.xOffset -= 8;
                    },
                    .arrowRight => {
                        self.uiState.xOffset += 8;
                    },
                    .arrowUp => {
                        self.uiState.yOffset += 1;
                    },
                    .arrowDown => {
                        self.uiState.yOffset -= 1;
                    },
                    else => {},
                }
            } else if (c != Ctrl.mixer and self.ctrlPressed(.mixer)) {
                switch (c) {
                    .arrowLeft => {
                        self.uiState.xOffset -= 1;
                    },
                    .arrowRight => {
                        self.uiState.xOffset += 1;
                    },
                    else => {},
                }
            } else if (self.ctrlPressed(.arrowUp) and self.ctrlPressed(.arrowDown)) {
                // scroll to lowest note
                var p = seq.*.tracks[self.uiState.currentTrack].currentPattern;
                if (p.lowNote()) |l| {
                    // std.debug.print("0x{x:0>6}, {d}\n", .{ l, (l & 0x00FF00) >> 8 });
                    self.uiState.yOffset = @intCast((l & 0x00FF00) >> 8);
                }
            } else if (self.ctrlPressed(.arrowLeft) and (self.ctrlPressed(.arrowRight))) {
                self.uiState.xOffset = 0;
            }
            self.uiState.xOffset = @min(8, @max(0, self.uiState.xOffset));
            self.uiState.yOffset = @min(127, @max(0, self.uiState.yOffset));
        } else if (keyDown and !isCtrl(k)) {
            if (self.ctrlPressed(.mixer)) {
                if (rowFromKey(k) == 0) {
                    // switch track
                    self.uiState.currentTrack = colFromKey(k);
                } else if (rowFromKey(k) > 0 and rowFromKey(k) < 7) {
                    // switch pattern
                    var seqMsg2 = midilib.Msg{
                        .type = midilib.MsgType.PatternQue,
                        .trackNumber = colFromKey(k),
                        .patternNumber = rowFromKey(k) - 1,
                    };
                    _ = pm.Pm_Enqueue(seq.mainToMidi, &seqMsg2);
                } else if (rowFromKey(k) == 7) {
                    // mute/unmute
                    var seqMsg2 = midilib.Msg{
                        .type = midilib.MsgType.TrackMute,
                        .trackNumber = colFromKey(k),
                    };
                    _ = pm.Pm_Enqueue(seq.mainToMidi, &seqMsg2);
                }
            } else {
                // std.debug.print("row: {d}, col: {d}\n", .{ rowFromKey(k), colFromKey(k) });
                var seqMsg = midilib.Msg{
                    //std
                    .type = .StepToggle,
                    .trackNumber = self.uiState.currentTrack,
                    .tick = @as(i32, @intCast(colFromKey(k))) + self.uiState.xOffset,
                    .note = 7 - @as(i32, @intCast(rowFromKey(k))) + self.uiState.yOffset,
                };
                _ = pm.Pm_Enqueue(seq.mainToMidi, &seqMsg);
            }
        }
        // std.debug.print("ui: {}\n", .{self.uiState});
    }
};

pub fn main() !void {
    lib.showDeviceInfo();
    _ = pm.Pm_Initialize();
    defer _ = pm.Pm_Terminate();
    const latency = 1;
    _ = latency;
    const outNum = 1;
    std.debug.print("Using output {d}\n", .{outNum});
    var lp = Launchpad.init(outNum);
    lp.clear();

    // just some short-hands for drawing
    const o = ColorNone;
    const r = ColorRedLow;
    const R = ColorRedFull;
    const G = ColorGreenFull;
    const O = ColorOrange;

    while (true) {
        // We can make images in code by temp. turning off formatting
        // zig fmt: off
    var yy = [_]pm.PmMessage{
        o,o,o,o,o,o,o,o,
        o,o,o,G,G,o,o,o,
        O,O,O,G,G,O,O,O,
        o,o,o,G,G,o,o,o,
        o,o,r,o,o,r,o,o,
        o,o,r,o,o,r,o,o,
        o,R,r,o,o,r,R,o,
    };
    // zig fmt: on
        const delay = 3.0e5;
        var nUpdates = lp.update(&yy);
        std.debug.print("Updates: {d}\n", .{nUpdates});
        _ = posix.usleep(delay);

        // zig fmt: off
    yy = [_]pm.PmMessage{
        O,o,o,o,o,o,o,O,
        o,O,o,G,G,o,O,o,
        o,o,O,G,G,O,o,o,
        o,o,o,G,G,o,o,o,
        o,o,r,o,o,r,o,o,
        o,R,o,o,o,o,R,o,
        R,o,o,o,o,o,o,R,
    };
    // zig fmt: on
        nUpdates = lp.update(&yy);
        std.debug.print("Updates: {d}\n", .{nUpdates});

        _ = posix.usleep(delay);
    }
}
