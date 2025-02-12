const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const windows = b.option(bool, "windows", "create windows build") orelse false;
    const pi = b.option(bool, "pi", "create pi build") orelse false;
    const mac = b.option(bool, "mac", "create mac build") orelse false;
    const vcpkg = b.option(bool, "vcpkg", "Add vcpkg paths to the build") orelse false;
    _ = vcpkg;

    var exe = b.addExecutable(.{
        .name = "ziguencer",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    // exe.addCSourceFile("stb_image-2.22/stb_image_impl.c", &[_][]const u8{"-std=c99"});
    //exe.setBuildMode(mode);

    if (windows) {
        // exe.setTarget(.{
        //     .cpu_arch = .x86_64,
        //     .os_tag = .windows,
        //     .abi = .gnu,
        // });
    }

    if (pi) {
        // exe.setTarget(.{ .cpu_arch = .arm, .os_tag = .linux, .abi = .musleabi });
        //exe.setMCPU("arm1176jzf_s");

        // exe.addLibraryPath(.{ .path = "rpi" });
    } else {
        // exe.addLibraryPath(.{ .cwd_relative = "../portmidi" });
    }

    // if (vcpkg) {
    //     exe.addVcpkgPaths(.static) catch @panic("Cannot add vcpkg paths.");
    // }

    // exe.addIncludePath(.{ .path = "../portmidi/pm_common" });
    // exe.addIncludePath(.{ .path = "../portmidi/porttime" });

    // important
    // exe.addLibraryPath(.{ .path = "/opt/homebrew/lib" });
    if (pi) {
        exe.addIncludePath(.{ .cwd_relative = "raspberry_pi_deps/include" });
        exe.addObjectFile(.{ .cwd_relative = "raspberry_pi_deps/libportmidi.so" });
        exe.addObjectFile(.{ .cwd_relative = "raspberry_pi_deps/libnotcurses-core.so" });
        exe.addObjectFile(.{ .cwd_relative = "raspberry_pi_deps/libnotcurses-ffi.so" });
        exe.addObjectFile(.{ .cwd_relative = "raspberry_pi_deps/libnotcurses.so" });
    } else if (mac) {
        exe.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
        exe.addObjectFile(.{ .cwd_relative = "/opt/homebrew/lib/libportmidi.dylib" });
        // `-core` is important ...
        exe.addObjectFile(.{ .cwd_relative = "/opt/homebrew/lib/libnotcurses-core.dylib" });
    } else {
        // linux - at least x86
        exe.linkSystemLibrary("portmidi");
        exe.linkSystemLibrary("notcurses");
    }
    exe.linkSystemLibrary("c");
    // exe.addLibraryPath(.{ .path = "/opt/homebrew/lib" });

    // exe.linkSystemLibrary("notcurses");

    // exe.linkSystemLibrary("glfw");
    // exe.linkSystemLibrary("epoxy");
    b.installArtifact(exe);

    // const play = b.step("play", "Play the game");
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    // play.dependOn(&run.step);
}
