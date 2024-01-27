const midilib = @import("midilib.zig");
const std = @import("std");
const relNote = midilib.relNote;

const metro1 = 34;
const metro2 = 32;

pub const metronome = [_]midilib.RelNote{
    relNote(metro1, 100, 0, 1),
    relNote(metro2, 100, 4, 1),
    relNote(metro2, 100, 8, 1),
    relNote(metro2, 100, 12, 1),
};

const bd = 36;
const sd = 38;
const hh = 42;
const oh = 46;

pub const beat2 = [_]midilib.RelNote{
    relNote(bd, 100, 0, 1),
    relNote(bd, 100, 3, 1),
    relNote(sd, 100, 4, 1),
    relNote(bd, 100, 6, 1),
    relNote(bd, 60, 9, 1),
    relNote(bd, 100, 10, 1),
    relNote(sd, 100, 12, 1),
    relNote(hh, 100, 0, 1),
    relNote(hh, 100, 2, 1),
    relNote(hh, 100, 4, 1),
    relNote(hh, 100, 6, 1),
    relNote(hh, 100, 8, 1),
    relNote(oh, 100, 10, 1),
    relNote(hh, 60, 11, 1),
    relNote(hh, 100, 12, 1),
    relNote(hh, 100, 14, 1),
};

pub const beat1 = [_]midilib.RelNote{
    relNote(bd, 100, 0, 1),
    relNote(sd, 100, 4, 1),
    relNote(bd, 100, 8, 1),
    relNote(bd, 100, 10, 1),
    relNote(sd, 100, 12, 1),
    relNote(hh, 100, 0, 1),
    relNote(hh, 100, 2, 1),
    relNote(hh, 100, 4, 1),
    relNote(hh, 100, 6, 1),
    relNote(hh, 100, 8, 1),
    relNote(hh, 100, 10, 1),
    relNote(hh, 100, 12, 1),
    relNote(hh, 100, 14, 1),
};

pub const bassline = [_]midilib.RelNote{
    relNote(34, 100, 0, 1), relNote(34, 60, 2, 1),
    relNote(37, 100, 4, 1), relNote(34, 100, 6, 1),
    relNote(34, 60, 10, 1), relNote(39, 100, 12, 2),
    relNote(37, 80, 14, 1),
};

pub const bassline2 = [_]midilib.RelNote{
    relNote(34, 60, 2, 1),
    relNote(41, 100, 3, 1),
    relNote(37, 100, 4, 1),
    relNote(34, 100, 6, 1),
    relNote(37, 80, 7, 1),
    relNote(34, 60, 10, 1),
    relNote(39, 100, 12, 2),
    relNote(37, 80, 14, 1),
    relNote(37, 80, 14, 1),
};

pub const melody = [_]midilib.RelNote{
    relNote(37 + 24, 100, 0, 1), relNote(41 + 24, 100, 0, 1),
    relNote(34 + 24, 100, 2, 1),
    //
    relNote(34 + 24, 60, 6, 1),
    relNote(39 + 24, 100, 8, 2), relNote(43 + 24, 100, 8, 2),
    relNote(37 + 24, 80, 10, 1),
};

fn pairsSliceToArrayList(comptime T: type, allocator: std.mem.Allocator, seqEventsSlice: []const [2]T) std.ArrayList(T) {
    var l = std.ArrayList(T).init(allocator);
    for (seqEventsSlice) |es| {
        l.append(es[0]) catch unreachable;
        l.append(es[1]) catch unreachable;
    }
    return l;
}

pub fn makePattern(notes: []const midilib.RelNote, midiPPQ: i32, channel: i32, allocator: std.mem.Allocator) midilib.Pattern {
    var events: [][2]midilib.SeqEvent = allocator.alloc([2]midilib.SeqEvent, notes.len) catch unreachable;
    events.len = notes.len;
    for (0.., notes) |i, note| {
        // maybe a relnote -> [2]SeqEvent fn instead?
        events[i] = midilib.note(midiPPQ, channel, note.pitch, note.vel, note.start, note.length);
    }
    return midilib.Pattern{
        .events = pairsSliceToArrayList(midilib.SeqEvent, allocator, events[0..]),
        .patternLengthTicks = midiPPQ * 4,
        .patternOffset = 0,
    };
}
