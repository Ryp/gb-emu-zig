const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const exe = b.addExecutable(.{
        .name = "gbemu",
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
        .target = target,
    });

    const enable_tracy = b.option(bool, "tracy", "Enable Tracy support") orelse false;
    const tracy_callstack = b.option(bool, "tracy-callstack", "Include callstack information with Tracy data. Does nothing if -Dtracy is not provided") orelse false;

    const exe_options = b.addOptions();
    exe_options.addOption(bool, "enable_tracy", enable_tracy);
    exe_options.addOption(bool, "enable_tracy_callstack", tracy_callstack);
    exe.root_module.addOptions("build_options", exe_options);

    if (enable_tracy) {
        const tracy_path = "external/tracy";
        const client_cpp = "external/tracy/public/TracyClient.cpp";
        const tracy_c_flags: []const []const u8 = &[_][]const u8{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined" };

        exe.root_module.addIncludePath(b.path(tracy_path));
        exe.root_module.addCSourceFile(.{ .file = b.path(client_cpp), .flags = tracy_c_flags });

        exe.linkLibC();
        exe.linkLibCpp();
    }

    b.installArtifact(exe);

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");

    exe.root_module.linkLibrary(sdl_lib);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the program");
    run_step.dependOn(&run_cmd.step);

    // Test
    const test_a = b.addTest(.{
        .name = "test",
        .root_source_file = b.path("src/gb/test.zig"),
        .optimize = optimize,
    });

    b.installArtifact(test_a);

    const test_cmd = b.addRunArtifact(test_a);
    test_cmd.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_cmd.step);
}
