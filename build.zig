const std = @import("std");
const builtin = @import("builtin");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "freeglut",
        .root_source_file = .{ .path = "empty.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.disable_sanitize_c = true;
    lib.linkLibCpp();
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ "freeglut", "include" }) });
    b.installArtifact(lib);

    lib.step.dependOn(installHeaders(
        b,
        b.pathJoin(&.{ "freeglut", "include", "GL" }),
        "GL",
    ));

    var platform_folder: ?[]const u8 = null;

    // Only tested on/for windows for now
    switch (lib.target.os_tag orelse builtin.os.tag) {
        .windows => {
            lib.linkSystemLibrary("opengl32");
            lib.linkSystemLibrary("winmm");
            lib.linkSystemLibrary("gdi32");
            lib.linkSystemLibrary("user32");
            lib.linkSystemLibrary("glu32");
            platform_folder = b.build_root.join(b.allocator, &.{ "freeglut", "src", "mswin" }) catch @panic("File Not Found");
        },
        else => {
            return;
        },
    }

    lib.addCSourceFile(.{
        .file = .{ .path = b.pathJoin(&.{ "freeglut", "src", "util", "xparsegeometry_repl.c" }) },
        .flags = &.{
            "-Wall",
            "-DFREEGLUT_STATIC",
            "-DHAVE_SYS_TYPES_H",
            "-DHAVE_STDINT_H",
        },
    });

    const src_folder = b.build_root.join(b.allocator, &.{ "freeglut", "src" }) catch @panic("File Not Found");
    const platform_dir = std.fs.cwd().openIterableDir(platform_folder.?, .{}) catch unreachable;
    var src_dir = std.fs.cwd().openIterableDir(src_folder, .{}) catch unreachable;

    inline for (.{ src_dir, platform_dir }, .{ src_folder, platform_folder.? }) |dir, loc| {
        var iterator = dir.iterate();
        while (iterator.next() catch unreachable) |file| {
            if (file.kind != .file) {
                continue;
            }

            const name: []const u8 = file.name;

            if (std.ascii.eqlIgnoreCase(name, "gles_stubs.c")) continue;

            if (std.ascii.endsWithIgnoreCase(name, ".c")) {
                lib.addCSourceFile(.{
                    .file = .{ .path = b.pathJoin(&.{ loc, name }) },
                    .flags = &.{
                        "-Wall",
                        "-DFREEGLUT_STATIC",
                        "-DHAVE_SYS_TYPES_H",
                        "-DHAVE_STDINT_H",
                    },
                });
            }
        }
    }
}

fn installHeaders(b: *std.Build, folder: []const u8, out_folder: []const u8) *std.build.Step {
    var dir = std.fs.cwd().openIterableDir(b.build_root.join(b.allocator, &.{folder}) catch @panic("File Not Found"), .{}) catch unreachable;
    var it = dir.iterate();
    var step = b.allocator.create(std.Build.Step) catch @panic("OOM");
    step.* = std.Build.Step.init(.{
        .id = .custom,
        .name = "install headers",
        .owner = b,
    });

    while (it.next() catch unreachable) |file| {
        if (file.kind != .file) {
            continue;
        }

        const name: []const u8 = file.name;
        if (std.ascii.endsWithIgnoreCase(name, ".h")) {
            step.dependOn(&b.addInstallHeaderFile(b.pathJoin(&.{ folder, name }), b.pathJoin(&.{ out_folder, name })).step);
        }
    }

    return step;
}
