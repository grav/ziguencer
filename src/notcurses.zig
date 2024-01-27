// zig build-exe src/notcurses.zig -I/opt/homebrew/Cellar/notcurses/3.0.9_2/include -L/opt/homebrew/Cellar/notcurses/3.0.9_2/lib -lnotcurses -lnotcurses-core -lc

const c = @cImport({
    @cInclude("notcurses/notcurses.h");
});

const std = @import("std");

pub usingnamespace c;
pub const default_notcurses_options = c.notcurses_options{
    .termtype = null,
    .loglevel = c.NCLOGLEVEL_SILENT,
    .margin_t = 0,
    .margin_r = 0,
    .margin_b = 0,
    .margin_l = 0,
    .flags = 0,
};
pub const default_ncplane_options = c.ncplane_options{
    .y = 0,
    .userptr = null,
    .name = null,
    .rows = 0,
    .cols = 0,
    .margin_r = 0,
    .margin_b = 0,
    .x = 0,
    .flags = 0,
    .resizecb = null,
};
const default_ncselector_options = c.ncselector_options{
    .footchannels = 0,
    .boxchannels = 0,
    .defidx = 0,
    .opchannels = 0,
    .secondary = null,
    .footer = null,
    .title = null,
    .items = null,
    .flags = 0,
    .titlechannels = 0,
    .maxdisplay = 0,
    .descchannels = 0,
};
pub const Error = error{
    NotcursesError,
};
pub fn err(code: c_int) !void {
    if (code < 0) {
        std.debug.print("code: {d}\n", .{code});
        // time.sleep_ns(1.0e10);
        return Error.NotcursesError;
    }
}

pub fn init_nc() *c.notcurses {
    var nc_opts: c.notcurses_options = default_notcurses_options;
    const ncs: *c.notcurses = (c.notcurses_core_init(&nc_opts, null) orelse @panic("notcurses_core_init() failed"));
    return ncs;
}

pub fn main() !void {

    // test input handling
    const ncs = init_nc();
    defer _ = c.notcurses_stop(ncs);
    var nci: c.ncinput = undefined;
    while (true) {
        const keypress: c_uint = c.notcurses_get_blocking(ncs, &nci);
        std.debug.print("keypress {any}\n", .{keypress});
        std.debug.print("nci {any}\n", .{nci});
    }
}
