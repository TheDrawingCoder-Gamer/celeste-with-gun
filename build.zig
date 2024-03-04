const std = @import("std");
const json = std.json;

const SavedLevel = @import("common/Level.zig");
const math = @import("common/math.zig");
const s2s = @import("vendor/s2s/s2s.zig");

pub fn build(b: *std.Build) !void {
    const optimize = std.builtin.OptimizeMode.ReleaseSmall;
    const optimize_native = std.builtin.OptimizeMode.Debug;
    const buddy2_mod = b.addModule("buddy2", .{ .root_source_file = .{ .path = "vendor/zig-buddy2/src/buddy2.zig" } });
    const s2s_mod = b.addModule("s2s", .{ .root_source_file = .{ .path = "vendor/s2s/s2s.zig" } });
    const common_mod = b.addModule("common", .{ .root_source_file = .{ .path = "common/lib.zig" } });
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const native_target = b.resolveTargetQuery(.{});
    const test_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi });
    const exe = b.addExecutable(.{
        .name = "cart",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("buddy2", buddy2_mod);
    exe.root_module.addImport("s2s", s2s_mod);
    exe.root_module.addImport("common", common_mod);
    tic80ify_wasm(exe);

    b.installArtifact(exe);
    const wasmp_stripper = b.addExecutable(.{ .name = "wasmp_stripper", .root_source_file = .{ .path = "wasmp_parser/main.zig" }, .target = native_target, .optimize = optimize_native });
    const wasmp_run = b.addRunArtifact(wasmp_stripper);
    wasmp_run.addFileArg(.{ .path = "fun.wasmp" });
    const outfile = wasmp_run.addOutputFileArg("res.wasmp");
    const converter = b.addExecutable(.{ .name = "converter", .root_source_file = .{ .path = "converter/main.zig" }, .target = native_target, .optimize = optimize_native });

    converter.root_module.addImport("s2s", s2s_mod);
    converter.root_module.addImport("common", common_mod);
    converter.step.dependOn(&wasmp_run.step);
    const converter_run = b.addRunArtifact(converter);
    converter_run.addFileArg(outfile);
    converter_run.addFileArg(.{ .path = "assets/maps/map.ldtk" });

    const update_wasmp = b.addWriteFiles();
    update_wasmp.addCopyFileToSource(outfile, "fun.wasmp");
    update_wasmp.step.dependOn(&converter_run.step);

    const test_step = b.step("test", "Run build tests");
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = test_target,
        .name = "test",
    });
    tests.root_module.addImport("buddy2", buddy2_mod);

    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    const update_map_step = b.step("update_map", "Update Cart with new map");
    update_map_step.dependOn(&update_wasmp.step);
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
