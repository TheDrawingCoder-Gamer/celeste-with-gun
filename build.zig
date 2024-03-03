const std = @import("std");
const json = std.json;

const SavedLevel = @import("common/Level.zig");
const map = @embedFile("assets/maps/map.ldtk");
var buf: [65565 * 4]u8 = undefined;
const GPA = std.heap.GeneralPurposeAllocator(.{});
var gpa: GPA = undefined;
var alloc: std.mem.Allocator = undefined;

const RawFieldInstance = struct { __identifier: []u8, __value: json.Value, __type: []u8 };
const EntityInstance = struct { __identifier: []u8, __grid: [2]i32, fieldInstances: []RawFieldInstance, __worldX: i32, __worldY: i32, width: u31, height: u31 };
const AutoLayerTile = struct { px: [2]u31, t: u32 };
const LayerInstance = struct { __type: []u8, __identifier: []u8, entityInstances: []EntityInstance, autoLayerTiles: []AutoLayerTile };
const Level = struct { worldX: i32, worldY: i32, pxWid: u31, pxHei: u31, cammode: u8, death_bottom: bool, layerInstances: []LayerInstance };
const World = struct { levels: []Level };

fn save_json(b: *std.Build) ![]const u8 {
    const tmp = b.makeTempPath();
    var tmp_dir = try std.fs.openDirAbsolute(tmp, .{});
    defer tmp_dir.close();

    const out_str = try get_json_string();

    var file = try tmp_dir.createFile("map.ldtk", .{});
    defer file.close();
    try file.writeAll(out_str);
    return std.fs.path.join(alloc, &[_][]const u8{ tmp, "map.ldtk" });
}
pub fn build(b: *std.Build) !void {
    gpa = GPA{};
    alloc = gpa.allocator();

    const optimize = b.standardOptimizeOption(.{});
    const map_file = try save_json(b);
    const buddy2_mod = b.addModule("buddy2", .{ .root_source_file = .{ .path = "vendor/zig-buddy2/src/buddy2.zig" } });
    const s2s_mod = b.addModule("s2s", .{ .root_source_file = .{ .path = "vendor/s2s/s2s.zig" } });
    const common_mod = b.addModule("common", .{ .root_source_file = .{ .path = "common/lib.zig" } });
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
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
    const converter = b.addExecutable(.{ .name = "converter", .root_source_file = .{ .path = "converter/main.zig" }, .target = target, .optimize = optimize });

    converter.root_module.addImport("buddy2", buddy2_mod);
    converter.root_module.addImport("s2s", s2s_mod);
    converter.root_module.addImport("common", common_mod);
    converter.root_module.addAnonymousImport("map", .{ .root_source_file = .{ .path = map_file } });
    tic80ify_wasm(converter);

    b.installArtifact(converter);

    const test_step = b.step("test", "Run build tests");
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = test_target,
        .name = "test",
    });
    tests.root_module.addImport("buddy2", buddy2_mod);

    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
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

fn get_json_string() ![]const u8 {
    const val = try json.parseFromSliceLeaky(json.Value, alloc, map, .{});
    var v = val.object;
    const keys = v.keys();
    for (keys) |k| {
        if (!std.mem.eql(u8, k, "levels")) {
            _ = try v.put(k, json.Value.null);
        }
    }
    const levels = v.getPtr("levels") orelse return error.MissingField;
    for (levels.array.items) |*level| {
        var cam_mode: SavedLevel.CamMode = .locked;
        var death_bottom = true;
        for ((level.object.get("fieldInstances") orelse return error.MissingField).array.items) |field| {
            const raw_field = try json.parseFromValueLeaky(RawFieldInstance, alloc, field, .{ .ignore_unknown_fields = true });
            if (std.mem.eql(u8, raw_field.__identifier, "CameraType")) {
                const field_v = raw_field.__value.string;
                if (std.mem.eql(u8, field_v, "Locked")) {
                    cam_mode = .locked;
                } else if (std.mem.eql(u8, field_v, "FollowX")) {
                    cam_mode = .follow_x;
                } else if (std.mem.eql(u8, field_v, "FollowY")) {
                    cam_mode = .follow_y;
                } else if (std.mem.eql(u8, field_v, "FreeFollow")) {
                    cam_mode = .free_follow;
                }
            } else if (std.mem.eql(u8, raw_field.__identifier, "DeathBottom")) {
                death_bottom = raw_field.__value.bool;
            }
        }
        try level.object.put("cammode", json.Value{ .integer = @intFromEnum(cam_mode) });
        try level.object.put("death_bottom", json.Value{ .bool = death_bottom });
        try level.object.put("fieldInstances", json.Value.null);
    }
    const good_levels = try json.parseFromValueLeaky([]Level, alloc, levels.*, .{ .ignore_unknown_fields = true });

    const res = try json.stringifyAlloc(alloc, good_levels, .{ .whitespace = .minified });
    // std.debug.print("{s}", .{res});
    return res;
}
