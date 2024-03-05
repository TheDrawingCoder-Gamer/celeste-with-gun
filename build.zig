const std = @import("std");
const json = std.json;

const SavedLevel = @import("common/Level.zig");
const math = @import("common/math.zig");
const s2s = @import("vendor/s2s/s2s.zig");

pub fn build(b: *std.Build) !void {
    const optimize = std.builtin.OptimizeMode.ReleaseSmall;
    const optimize_native = std.builtin.OptimizeMode.Debug;
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const native_target = b.resolveTargetQuery(.{});
    const test_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi });
    const buddy2_runtime_dep = b.dependency("buddy2", .{
        .target = target,
        .optimize = optimize,
    });
    const buddy2_test_dep = b.dependency("buddy2", .{
        .target = test_target,
    });
    const s2s_runtime_dep = b.dependency("s2s", .{ .target = target, .optimize = optimize });
    const s2s_native_dep = b.dependency("s2s", .{ .target = native_target, .optimize = optimize_native });
    const parsec_dep = b.dependency("parsec", .{ .target = native_target, .optimize = optimize_native });
    const common_mod = b.addModule("common", .{ .root_source_file = .{ .path = "common/lib.zig" } });
    const exe = b.addExecutable(.{
        .name = "cart",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("buddy2", buddy2_runtime_dep.module("buddy2"));
    exe.root_module.addImport("s2s", s2s_runtime_dep.module("s2s"));
    exe.root_module.addImport("common", common_mod);
    tic80ify_wasm(exe);

    b.installArtifact(exe);
    const converter = b.addExecutable(.{ .name = "converter", .root_source_file = .{ .path = "converter/main.zig" }, .target = native_target, .optimize = optimize_native });

    converter.root_module.addImport("s2s", s2s_native_dep.module("s2s"));
    converter.root_module.addImport("common", common_mod);
    converter.root_module.addImport("parsec", parsec_dep.module("parsec"));
    const converter_run = b.addRunArtifact(converter);
    converter_run.addFileArg(.{ .path = "fun.wasmp" });
    converter_run.addFileArg(.{ .path = "assets/maps/map.ldtk" });

    const test_step = b.step("test", "Run build tests");
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = test_target,
        .name = "test",
    });
    tests.root_module.addImport("buddy2", buddy2_test_dep.module("buddy2"));

    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    const update_map_step = b.step("update_map", "Update Cart with new map");
    update_map_step.dependOn(&converter_run.step);
}

fn tic80ify_wasm(s: *std.Build.Step.Compile) void {
    s.rdynamic = true;
    s.entry = .disabled;
    s.import_memory = true;
    s.stack_size = 8192;
    s.initial_memory = 65536 * 4;
    s.max_memory = 65536 * 4;

    s.export_table = true;

    // all the memory below 96kb is reserved for TIC and memory mapped I/O
    // so our own usage must start above the 96kb mark
    s.global_base = 96 * 1024;
}
