const pm = @import("portmidi.zig");
const std = @import("std");
const lib = @import("lib.zig");
const dp = lib.dp;

pub fn tickToTimestamp(tick: i32, midiPPQ: i32, tempo: i32) pm.PmTimestamp {
    return @divTrunc(tick * 60000, midiPPQ * tempo);
}

pub fn timestampToTickGivenOffset(ts: pm.PmTimestamp, offset: i32, midiPPQ: i32, tempo: i32) i32 {
    return @divTrunc((ts - offset) * midiPPQ * tempo, 60000);
}

// a relative note, with 16th note start and length
pub const RelNote = struct { pitch: i32, vel: i32, start: i32, length: i32 };
pub fn relNote(pitch: i32, vel: i32, start: i32, length: i32) RelNote {
    return RelNote{
        .pitch = pitch,
        .vel = vel,
        .start = start,
        .length = length,
    };
}

pub fn relNoteToSeqEvents(n: RelNote) [2]SeqEvent {
    _ = n;
}

// a sequence note
pub const SeqEvent = struct {
    pulse: i32,
    msg: pm.PmMessage,
    pub fn init(pulse: i32, msg: pm.PmMessage) SeqEvent {
        return SeqEvent{ .pulse = pulse, .msg = msg };
    }

    // todo - support note-off 0x8x
    pub fn isNoteOff(msg: pm.PmMessage) bool {
        return (msg & 0x0000FF >= 0x90 and
            msg & 0x0000F0 == 0x90 and
            msg & 0xFF0000 == 0) or msg & 0x0000F0 == 0x80;
    }

    pub fn isNoteOn(msg: pm.PmMessage) bool {
        return msg & 0x0000FF >= 0x90 and
            msg & 0x0000FF <= 0x9F and
            msg & 0xFF0000 > 0;
    }

    // get corresponding note-off for a note-on
    // also works with a note-on with velocity 0
    pub fn getNoteOffMsg(msg: pm.PmMessage) pm.PmMessage {
        // ignore velocity, keep note number, change into NoteOff
        return msg & 0x00FF0F | 0x000080;
    }
};

pub const Pattern = struct {
    const Self = @This();

    events: std.ArrayList(SeqEvent),
    patternLengthTicks: i32,
    patternOffset: i32 = 0,
    name: []const u8 = "<untitled>",
    allocator: std.mem.Allocator = undefined,

    fn pairsSliceToArrayList(comptime T: type, allocator: std.mem.Allocator, seqEventsSlice: []const [2]T) std.ArrayList(T) {
        var l = std.ArrayList(T).init(allocator);
        for (seqEventsSlice) |es| {
            l.append(es[0]) catch unreachable;
            l.append(es[1]) catch unreachable;
        }
        return l;
    }

    pub fn init(allocator: std.mem.Allocator, events: std.ArrayList(SeqEvent)) Self {
        _ = events;
        _ = allocator;
    }

    pub fn initWithRelNotes(allocator: std.mem.Allocator, relNotes: []const RelNote, midiPPQ: i32, channel: i32) Self {
        // TODO - what about dealloc'ing the slice?
        var events: [][2]SeqEvent = allocator.alloc([2]SeqEvent, relNotes.len) catch unreachable;
        // defer allocator.free(events);
        for (0.., relNotes) |i, n| {
            // maybe a relnote -> [2]SeqEvent fn instead?
            events[i] = note(midiPPQ, channel, n.pitch, n.vel, n.start, n.length);
        }
        return Pattern{
            .allocator = allocator,
            .events = pairsSliceToArrayList(SeqEvent, allocator, events[0..]),
            .patternLengthTicks = midiPPQ * 4,
            .patternOffset = 0,
        };
    }

    pub fn lowNote(self: *Self) ?pm.PmMessage {
        var msg: ?pm.PmMessage = null;
        for (self.events.items) |e| {
            if (msg) |m| {
                if ((e.msg & 0x00FF00) < (m & 0x00FF00)) {
                    msg = e.msg;
                }
            } else {
                msg = e.msg;
            }
        }
        return msg;
    }

    pub fn deinit(self: *Self) void {
        self.events.deinit();
    }
};

const PatternAndOffset = struct {
    pattern: *Pattern,
    addOffset: i32,
};

pub const Track = struct {
    const Self = @This();

    channel: i32,
    patterns: []*Pattern,
    currentPattern: *Pattern,
    nextPattern: ?*Pattern = null,
    muted: bool = false,
    noteMap: std.AutoHashMap(pm.PmMessage, void),
    recordMap: std.AutoHashMap(pm.PmMessage, SeqEvent),
    pub fn init(allocator: std.mem.Allocator, patterns: []*Pattern, channel: i32) Self {
        return .{
            .patterns = patterns,
            .currentPattern = patterns[0],
            .noteMap = std.AutoHashMap(pm.PmMessage, void).init(allocator),
            .recordMap = std.AutoHashMap(pm.PmMessage, SeqEvent).init(allocator),
            .channel = channel,
        };
    }

    pub fn deinit(self: *Self) void {
        self.noteMap.deinit();
        self.recordMap.deinit();
    }

    pub fn currentPatternIndex(self: *Self) usize {
        return lib.indexOf(*Pattern, self.patterns, self.currentPattern) catch unreachable;
    }

    pub fn nextPatternIndex(self: *Self) ?usize {
        if (self.currentPattern == self.getNextPattern()) return null;
        if (self.nextPattern) |np| {
            return lib.indexOf(*Pattern, self.patterns, np) catch unreachable;
        } else {
            return null;
        }
    }

    // why?
    pub fn setPattern(self: *Self, p: *Pattern) void {
        self.currentPattern = p;
    }

    // why?
    pub fn setNextPattern(self: *Self, p: *Pattern) void {
        self.nextPattern = p;
    }

    pub fn getNextPattern(self: *Self) *Pattern {
        if (self.nextPattern) |p| {
            return p;
        } else {
            return self.currentPattern;
        }
    }
};

pub fn note(midiPPQ: i32, channel: i32, pitch: i32, vel: i32, start: i32, length: i32) [2]SeqEvent {
    const noteOn = pm.Pm_Message(0x90 + channel, pitch, vel);
    const noteOff = SeqEvent.getNoteOffMsg(@intCast(noteOn));
    const startTick = @divTrunc(midiPPQ, 4) * start;
    const endTick = startTick + @divTrunc(midiPPQ, 4) * length;
    return [_]SeqEvent{
        SeqEvent.init(startTick, @intCast(noteOn)),
        SeqEvent.init(endTick, @intCast(noteOff)),
    };
}
pub const MsgType = enum(c_int) {
    PatternQue,
    TrackMute,
    StepToggle,
};

pub const Msg = struct {
    type: MsgType,
    trackNumber: usize,
    patternNumber: ?usize = null, // null means 'next'?
    tick: i32 = 0,
    note: i32 = 0,
};

fn processMidi(timestamp: pm.PmTimestamp, userData: ?*anyopaque) callconv(.C) void {
    if (userData) |_userData| {
        var metro: *Sequencer = @alignCast(@ptrCast(_userData));
        var result: pm.PmError = pm.pmNoError;
        var msg: Msg = undefined;

        while (true) {
            result = pm.Pm_Dequeue(metro.mainToMidi, &msg);
            if (result == pm.pmGotData) {
                dp("Received: {} Result: {d}\n", .{ msg, result });
                switch (msg.type) {
                    .TrackMute => {
                        const idx = msg.trackNumber;
                        if (idx < metro.tracks.len) {
                            var track = metro.tracks[idx];
                            track.muted = !track.muted;
                        } else {
                            std.debug.print("Unknown track num: {d}\n", .{idx});
                        }
                    },
                    .PatternQue => {
                        var t = metro.tracks[msg.trackNumber];
                        var nextPattern: ?*Pattern = null; // kind of fallback
                        if (msg.patternNumber) |pn| {
                            nextPattern = t.patterns[pn];
                        } else {
                            var found = false;
                            for (t.patterns) |p| {
                                if (found) {
                                    nextPattern = p;
                                    break;
                                }
                                if (p == t.currentPattern) {
                                    found = true;
                                }
                            }
                        }

                        var pp = nextPattern orelse t.patterns[0];
                        pp.patternOffset = t.currentPattern.patternOffset;
                        t.setNextPattern(pp);
                    },
                    .StepToggle => {
                        // std.debug.print("{}\n", .{msg});
                        const t = metro.tracks[msg.trackNumber];
                        var es = t.currentPattern.events;
                        const notes = note(metro.midiPPQ, t.channel, msg.note, 127, msg.tick, 1);
                        var found: ?usize = null;
                        for (es.items, 0..) |e, i| {
                            if (e.msg & 0x00FFFF == notes[0].msg & 0x00FFFF and e.pulse == notes[0].pulse) {
                                found = i;
                                break;
                            }
                        }
                        if (found) |i| {
                            // remove
                            // TODO - remove note off as well!
                            // std.debug.print("found!\n", .{});
                            // _ = es.swapRemove(i + 1);
                            const x = es.swapRemove(i);
                            _ = x;
                            // std.debug.print("remove: {}\n", .{x});
                        } else {
                            // add
                            t.currentPattern.events.append(notes[0]) catch unreachable;
                            t.currentPattern.events.append(notes[1]) catch unreachable;
                        }
                    },
                }
            }
            if (result == pm.pmNoError) {
                break;
            }
        }

        var buffer: pm.PmEvent = undefined;
        // https://github.com/PortMidi/portmidi/blob/master/pm_test/midithru.c#L168
        result = pm.Pm_Poll(metro.midiIn);

        if (result > 0) {
            // hack
            var inputTrack = metro.tracks[3];
            var numInputEventsQueued: usize = 0;
            _ = pm.Pm_Read(metro.midiIn, &buffer, 1);

            if (SeqEvent.isNoteOn(buffer.message)) {
                dp("in!\n", .{});
                const tick = timestampToTickGivenOffset(timestamp, inputTrack.currentPattern.patternOffset, metro.midiPPQ, 120);
                const recordEvent = SeqEvent{ .pulse = tick, .msg = buffer.message };
                inputTrack.recordMap.put(SeqEvent.getNoteOffMsg(buffer.message), recordEvent) catch unreachable;
                // std.debug.print("Generated: {x:0>6}\n", .{s[0].msg});
            } else if (SeqEvent.isNoteOff(buffer.message)) {
                const noteOn = inputTrack.recordMap.get(SeqEvent.getNoteOffMsg(buffer.message)) orelse unreachable;
                // std.debug.print("Recorded: {x:0>6}\n", .{noteOn.msg});
                const alteredNoteOn = SeqEvent.init(noteOn.pulse, noteOn.msg & 0xFFFF90 | 0x000005);
                // std.debug.print("Recorded 2: {x:0>6}\n", .{alteredNoteOn.msg});
                const noteOffMsg = SeqEvent.getNoteOffMsg(alteredNoteOn.msg);
                const tick = timestampToTickGivenOffset(timestamp, inputTrack.currentPattern.patternOffset, metro.midiPPQ, 120);

                inputTrack.currentPattern.events.append(alteredNoteOn) catch unreachable;
                inputTrack.currentPattern.events.append(SeqEvent.init(tick, noteOffMsg)) catch unreachable;
            } else {
                std.debug.print("Unknown message\n", .{});
            }
            // HACK - mirror received midi messages to output (monitoring)
            metro.outBuffer[numInputEventsQueued] = buffer;
            numInputEventsQueued += 1;
            _ = pm.Pm_Write(metro.midiOut, &(metro.outBuffer), @intCast(numInputEventsQueued));
        }

        _ = metro.queueEvents(timestamp);
    }
}
pub const Sequencer = struct {
    const Self = @This();
    const maxEvents = 100;

    mainToMidi: *pm.PmQueue = undefined,

    lastTick: pm.PmTimestamp = -1,
    tracks: []const *Track = undefined,
    threadTempo: i32 = 120,
    // resolution - ticks per quater note
    midiPPQ: i32, // = 1120,
    lookAheadMs: i32 = 100,
    outBuffer: [maxEvents]pm.PmEvent = undefined,
    midiOut: ?*pm.PmStream = null,
    midiIn: ?*pm.PmStream = null,

    callback: ?*const fn (i32, ?*anyopaque) callconv(.C) void = processMidi,

    pub fn queueEvents(self: *Self, timestamp: pm.PmTimestamp) usize {
        // if we've been triggered too early, do nothing
        if (self.lastTick != -1 and timestamp - self.lookAheadMs < self.lastTick) return 0;

        self.lastTick = timestamp;
        dp("starting at {d}\n", .{timestamp});
        var numEventsQueued: usize = 0;
        for (self.tracks) |track| {
            if (!track.muted) {
                const paos = [_]PatternAndOffset{
                    PatternAndOffset{ .pattern = track.currentPattern, .addOffset = 0 },
                    PatternAndOffset{ .pattern = track.getNextPattern(), .addOffset = tickToTimestamp(track.currentPattern.patternLengthTicks, self.midiPPQ, self.threadTempo) },
                };

                for (paos) |pao| {
                    const pattern = pao.pattern;
                    const offset = pao.addOffset;
                    for (pattern.events.items) |e| {
                        dp("{s}\n", .{e});
                        const t = tickToTimestamp(e.pulse, self.midiPPQ, self.threadTempo) + pattern.patternOffset + offset;
                        if (t >= timestamp and t < timestamp + self.lookAheadMs) {
                            const p: pm.PmEvent = .{
                                .message = e.msg,
                                .timestamp = t,
                            };
                            self.outBuffer[numEventsQueued] = p;
                            numEventsQueued += 1;
                            if (SeqEvent.isNoteOn(e.msg)) {
                                track.noteMap.put(SeqEvent.getNoteOffMsg(e.msg), {}) catch unreachable;
                                dp("Notes in noteMap: {d}\n", .{track.noteMap.count()});
                                dp("NoteOn @ {d}: {x}\n", .{ t, e.msg });
                            } else if (SeqEvent.isNoteOff(e.msg)) {
                                _ = track.noteMap.remove(e.msg);
                                dp("NoteOff @ {d}: {x}\n", .{ t, e.msg });
                            }
                            //break;
                        } else {
                            dp("{d} skipping {s}, t: {d}\n", .{ timestamp, e, t });
                        }
                    }
                }
            } else {
                var it = track.noteMap.keyIterator();
                while (it.next()) |k| {
                    var p: pm.PmEvent = undefined;
                    p.message = k.*;
                    p.timestamp = timestamp; // + 1000;
                    self.outBuffer[numEventsQueued] = p;
                    numEventsQueued += 1;
                }
                track.noteMap.clearAndFree();
            }
            // write queued events to midi device
            // check if we need to shift patternOffset
            const pattern = track.currentPattern;
            const patternLength = tickToTimestamp(pattern.patternLengthTicks, self.midiPPQ, self.threadTempo);
            const patternEnd = pattern.patternOffset + patternLength;
            if (patternEnd >= timestamp and patternEnd < timestamp + self.lookAheadMs) {
                dp("{d}: bump patternOffset from {d} to {d}\n", .{ timestamp, pattern.patternOffset, patternEnd });
                // TODO: consider moving this to Track
                track.currentPattern = track.getNextPattern();
                track.currentPattern.*.patternOffset = patternEnd;
            }
        }
        _ = pm.Pm_Write(self.midiOut, &(self.outBuffer), @intCast(numEventsQueued));

        return numEventsQueued;
    }
};

//
