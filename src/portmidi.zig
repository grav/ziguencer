pub usingnamespace @cImport({
    @cInclude("portmidi.h");
    @cInclude("porttime.h");
    @cInclude("pmutil.h");
});

pub const filt_active = (1 << 0x0e);
pub const filt_sysex = (1 << 0x00);
pub const filt_clock = (1 << 0x08);
