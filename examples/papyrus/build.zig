const std = @import("std");

pub fn build(b: *std.Build) void {
    // SKSE must build for the msvc target only.
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
            .abi = .msvc,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const dep = b.dependency("skse", .{
        .target = target,
        .optimize = optimize,
    });
    const mod = dep.module("skseplugin_zig");

    const lib = b.addLibrary(.{
        .name = "skse-plugin-zig-papyrus",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "skse", .module = mod },
            },
        }),
        .linkage = .dynamic,
        .version = @import("skse").version,
    });

    b.installArtifact(lib);
}
