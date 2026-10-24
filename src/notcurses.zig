// Nicked from https://github.com/dundalek/notcurses-zig-example/blob/master/src/notcurses.zig

// C bindings are supplied by build.zig.

pub const nc = @import("c");

const std = @import("std");

pub const default_notcurses_options = nc.notcurses_options{
    .termtype = null,
    .loglevel = nc.NCLOGLEVEL_SILENT,
    .margin_t = 0,
    .margin_r = 0,
    .margin_b = 0,
    .margin_l = 0,
    .flags = 0,
};
pub const default_ncplane_options = nc.ncplane_options{
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
const default_ncselector_options = nc.ncselector_options{
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

pub fn init_nc() *nc.notcurses {
    var nc_opts: nc.notcurses_options = default_notcurses_options;
    const ncs: *nc.notcurses = (nc.notcurses_core_init(&nc_opts, null) orelse @panic("notcurses_core_init() failed"));
    return ncs;
}

pub fn main() !void {

    // test input handling
    const ncs = init_nc();
    defer _ = nc.notcurses_stop(ncs);
    var nci: nc.ncinput = undefined;
    while (true) {
        const keypress: c_uint = nc.notcurses_get_blocking(ncs, &nci);
        std.debug.print("keypress {any}\n", .{keypress});
        std.debug.print("nci {any}\n", .{nci});
    }
}
