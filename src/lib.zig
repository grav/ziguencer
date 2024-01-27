// zig build-exe -I/opt/homebrew/Cellar/portmidi/2.0.4_1/include -L/opt/homebrew/Cellar/portmidi/2.0.4_1/lib -lportmidi src/lib.zig && ./lib

const std = @import("std");
const pm = @import("portmidi.zig");

pub fn dp(comptime fmt: []const u8, args: anytype) void {
    _ = args;
    _ = fmt;
    // comment out to disable debug logging
    // std.debug.print(fmt, args);
}

pub fn parseArgs(allocator: std.mem.Allocator, args: *std.process.ArgIterator) ![]i32 {
    var l = std.ArrayList(i32).init(allocator);
    _ = args.skip();
    var n = args.next();
    while (n != null) {
        const i = std.fmt.parseInt(i32, n.?, 10) catch {
            std.debug.print("Warning: couldn't parse '{s}' as integer\n", .{n.?});
            return l.toOwnedSlice();
        };
        try l.append(i);
        n = args.next();
    }
    return l.toOwnedSlice();
}

// parse command line args into a map, expecing `[key] [value]` pairs.
// any key with no value is ignored.
pub fn parseArgsToMap(args: *std.process.ArgIterator, argsMap: *std.StringHashMap([]const u8)) void {
    _ = args.next();
    var k = args.next();
    while (k) |k_| {
        const v = args.next();
        if (v) |v_| {
            argsMap.put(k_, v_) catch unreachable;
            k = args.next();
        } else {
            break;
        }
    }
}
pub const Error = error{
    NotFound,
};
pub fn indexOf(comptime T: type, hay: []const T, needle: T) !usize {
    var i: usize = 0;
    for (hay) |k| {
        if (k == needle) {
            return i;
        }
        i += 1;
    }
    return Error.NotFound;
}

pub const DeviceType = enum {
    Output,
    Input,
};

pub fn getDevice(allocator: std.mem.Allocator, deviceType: DeviceType, deviceNamePrefix: []const u8) ?c_int {
    var deviceNum: ?c_int = null;
    var i: c_int = 0;
    while (i < pm.Pm_CountDevices()) {
        const d = pm.Pm_GetDeviceInfo(i);
        // convert to zigstr
        const deviceName = std.mem.span(d.*.name);
        // find min length of prefix and device name
        const strLen = @min(deviceName.len, deviceNamePrefix.len);
        // normalize (limit length and convert to lower case
        const deviceNameNorm = std.ascii.allocLowerString(allocator, deviceName[0..strLen]) catch unreachable;
        const deviceNamePrefixNorm = std.ascii.allocLowerString(allocator, deviceNamePrefix[0..strLen]) catch unreachable;
        const testAttr = if (deviceType == .Input) d.*.input else d.*.output;
        if (std.mem.eql(u8, deviceNamePrefixNorm, deviceNameNorm) and testAttr == 1) {
            deviceNum = i;
            break;
        }
        allocator.free(deviceNameNorm);
        allocator.free(deviceNamePrefixNorm);
        i += 1;
    }
    return deviceNum;
}

pub fn showDeviceInfo() void {
    var i: c_int = 0;
    while (i < pm.Pm_CountDevices()) {
        const deviceInfo = pm.Pm_GetDeviceInfo(i);
        const portType = if (deviceInfo.*.input == 1) "Input" else "Output";
        std.debug.print("{d}: {s} - '{s}'\n", .{ i, portType, deviceInfo.*.name });

        i += 1;
    }
}

pub fn askUserForInteger() !i32 {
    const stdin = std.io.getStdIn().reader();

    var buf: [10]u8 = undefined;

    if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |user_input| {
        return std.fmt.parseint(i32, user_input, 10);
    } else {
        return @as(i32, 0);
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    showDeviceInfo();
    const prefix = "launchpad";
    if (getDevice(allocator, DeviceType.Output, prefix)) |d_| {
        std.debug.print("Found device num: {d}\n", .{d_});
    } else {
        std.debug.print("Couldn't find an input device starting with '{s}'\n", .{prefix});
    }
}
