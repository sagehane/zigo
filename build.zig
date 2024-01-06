// SPDX-FileCopyrightText: 2023 Sage Hane <sage@sagehane.com>
//
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigo = b.addModule("zigo", .{
        .root_source_file = .{ .path = "zigo/main.zig" },
    });

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "zigo/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    const cli = b.addExecutable(.{
        .name = "zigo-cli",
        .root_source_file = .{ .path = "cli/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    cli.root_module.addImport("zigo", zigo);
    b.installArtifact(cli);

    const run_cmd = b.addRunArtifact(cli);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
