const std = @import("std");
const s2s = @import("s2s");
const SavedLevel = @import("common").Level;
const math = @import("common").math;
const tic80_ext = @import("common").ticext;
const Spritesheet = @import("common").Spritesheet;
const json = std.json;
const tatl = @import("tatl");

const RawFieldInstance = struct { __identifier: []u8, __value: json.Value, __type: []u8 };
const EntityInstance = struct { __identifier: []u8, __grid: [2]i32, fieldInstances: []RawFieldInstance, __worldX: i32, __worldY: i32, width: u31, height: u31 };
const AutoLayerTile = struct { px: [2]u31, t: u32 };
const LayerInstance = struct { __type: []u8, __identifier: []u8, entityInstances: []EntityInstance, autoLayerTiles: []AutoLayerTile };
const Level = struct { worldX: i32, worldY: i32, pxWid: u31, pxHei: u31, cammode: u8, death_bottom: bool, layerInstances: []LayerInstance };
const PointType = struct { cx: i32, cy: i32 };

var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = false }){};
var alloc: std.mem.Allocator = undefined;

const RunMode = enum {
    pack,
    unpack,

    pub fn parse(in: []const u8) !RunMode {
        if (std.mem.eql(u8, in, "pack")) {
            return .pack;
        } else if (std.mem.eql(u8, in, "unpack")) {
            return .unpack;
        }
        return error.InvalidMode;
    }
};

const SPR_SIZE = 32;
const PIXELS_IN_SPR = 64;
pub fn main() !void {
    alloc = gpa.allocator();
    var args = try std.process.argsWithAllocator(alloc);
    if (!args.skip()) return error.TooFewArgs;
    const mode = try RunMode.parse(args.next() orelse return error.TooFewArgs);

    switch (mode) {
        .pack => {
            const respath = args.next() orelse return error.TooFewArgs;
            const unpackedpath = args.next() orelse return error.TooFewArgs;
            const rootdirpath = args.next() orelse return error.TooFewArgs;
            const listpath = args.next() orelse return error.TooFewArgs;
            const tilepath = args.next() orelse return error.TooFewArgs;
            const mappath = args.next() orelse return error.TooFewArgs;

            var rootdir = try std.fs.openDirAbsolute(rootdirpath, .{});
            defer rootdir.close();

            var files = try std.fs.openFileAbsolute(listpath, .{});
            defer files.close();
            const tilease = blk: {
                var file = try std.fs.openFileAbsolute(tilepath, .{});
                defer file.close();
                break :blk try tatl.import(alloc, file.reader());
            };
            defer tilease.free(alloc);

            const mapfile = try std.fs.openFileAbsolute(mappath, .{ .mode = .read_only });
            defer mapfile.close();
            const res_data = try packinator(rootdir, files, tilease);

            const in_map_data = try mapfile.readToEndAlloc(alloc, 1024 * 1024);
            const map_data = try get_compressed_map(in_map_data);

            var da_map: [32_640]u8 = .{0} ** 32_640;

            for (map_data.tiles) |tile| {
                da_map[@intCast(tile.pos.y * 240 + tile.pos.x)] = tile.tile;
            }
            const unpacked_data = blk: {
                const unpacked_file = try std.fs.openFileAbsolute(unpackedpath, .{ .mode = .read_only });
                defer unpacked_file.close();
                break :blk try unpacked_file.readToEndAlloc(alloc, 65536);
            };
            defer alloc.free(unpacked_data);

            var resfile = try std.fs.createFileAbsolute(respath, .{});
            defer resfile.close();
            try resfile.writeAll(unpacked_data);
            try resfile.writer().writeByte('\n');

            try save_bin_section(resfile.writer(), "MAP", &da_map, 240, true);

            @memset(@as([]u8, &da_map), 0);

            var map_data_fbs = std.io.fixedBufferStream(&da_map);
            try s2s.serialize(map_data_fbs.writer(), []SavedLevel, map_data.levels);
            try s2s.serialize(map_data_fbs.writer(), []Spritesheet, res_data.sheets);
            try save_bin_section(resfile.writer(), "MAP7", &da_map, 240, true);

            // row size is @sizeOf(tic_tile), which is an 8x8 sprite with 4bpp
            // 8x8 = 64 nibbles / 2 = 32 bytes
            try save_bin_section(resfile.writer(), "SPRITES", &res_data.sprites.bytes, SPR_SIZE, true);
            try save_bin_section(resfile.writer(), "TILES", &res_data.tiles.bytes, SPR_SIZE, true);
            try save_bin_section(resfile.writer(), "FLAGS", &res_data.flags, 256, true);
        },
        .unpack => {
            const packedpath = args.next() orelse return error.TooFewArgs;
            const unpackedpath = args.next() orelse return error.TooFewArgs;

            const unpacked_data = blk: {
                const file = try std.fs.openFileAbsolute(packedpath, .{});
                defer file.close();
                break :blk try extract_packed(file);
            };

            const unpacked_file = try std.fs.createFileAbsolute(unpackedpath, .{});
            defer unpacked_file.close();
            try unpacked_file.writeAll(unpacked_data);
        },
    }
}

fn buf_empty(data: []const u8) bool {
    for (data) |i| {
        if (i != 0)
            return false;
    }
    return true;
}

fn buf2str(writer: anytype, data: []const u8, flip: bool) !void {
    for (data) |i| {
        var buf: [2]u8 = undefined;
        _ = try std.fmt.bufPrint(&buf, "{x:0>2}", .{i});
        if (flip) {
            std.mem.swap(u8, &buf[0], &buf[1]);
        }
        try writer.print("{s}", .{&buf});
    }
}
fn save_bin_buffer(writer: anytype, data: []const u8, row: usize, flip: bool) !void {
    if (buf_empty(data)) return;
    try writer.print("-- {:0>3}:", .{row});
    try buf2str(writer, data, flip);
    _ = try writer.write("\n");
}

fn save_bin_section(writer: anytype, tag: []const u8, data: []const u8, row_size: usize, flip: bool) !void {
    const count = @divExact(data.len, row_size);

    if (buf_empty(data)) {
        return;
    }
    try writer.print("-- <{s}>\n", .{tag});

    {
        var row: usize = 0;
        while (row < count) : (row += 1) {
            const offset = row_size * row;
            try save_bin_buffer(writer, data[offset .. offset + row_size], row, flip);
        }
    }

    try writer.print("-- </{s}>\n\n", .{tag});
}

fn get_compressed_map(map: []u8) !SavedLevel.CompressedMap {
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
    var tiles = std.ArrayList(SavedLevel.Tile).init(alloc);
    var out_levels = std.ArrayList(SavedLevel).init(alloc);
    for (good_levels) |good| {
        try process_level(&tiles, &out_levels, good);
    }
    const compressed_map = SavedLevel.CompressedMap{ .levels = out_levels.items, .tiles = tiles.items };

    return compressed_map;
}

fn process_level(o_tiles: *std.ArrayList(SavedLevel.Tile), o_levels: *std.ArrayList(SavedLevel), level: Level) !void {
    const tile_x = @divFloor(level.worldX, 8);
    const tile_y = @divFloor(level.worldY, 8);
    const tile_w = @divFloor(level.pxWid, 8);
    const tile_h = @divFloor(level.pxHei, 8);
    const pix_x = level.worldX;
    const pix_y = level.worldY;

    var entities = std.ArrayList(SavedLevel.Entity).init(alloc);
    for (level.layerInstances) |layer| {
        if (std.mem.eql(u8, layer.__identifier, "TileMap")) {
            for (layer.autoLayerTiles) |auto_tile| {
                const tx = @divFloor(auto_tile.px[0], 8);
                const ty = @divFloor(auto_tile.px[1], 8);
                try o_tiles.append(.{ .pos = .{ .x = tile_x + tx, .y = tile_y + ty }, .tile = @intCast(auto_tile.t) });
            }
        } else if (std.mem.eql(u8, layer.__identifier, "Entities")) {
            for (layer.entityInstances) |entity| {
                try process_entity(.{ .x = pix_x, .y = pix_y }, &entities, entity);
            }
        } else {
            return error.UnknownLayer;
        }
    }
    try o_levels.append(.{ .x = tile_x, .y = tile_y, .width = tile_w, .height = tile_h, .entities = entities.items, .cam_mode = @enumFromInt(level.cammode), .death_bottom = level.death_bottom });
}

fn process_entity(world_pos: math.Point, o_entities: *std.ArrayList(SavedLevel.Entity), entity: EntityInstance) !void {
    const ex = entity.__worldX;
    const ey = entity.__worldY;
    const ew = entity.width;
    const eh = entity.height;
    var kind: ?SavedLevel.Entity.Kind = null;
    if (std.mem.eql(u8, entity.__identifier, "Crumble")) {
        kind = .crumble;
    } else if (std.mem.eql(u8, entity.__identifier, "PlayerStart")) {
        var world_start = false;
        for (entity.fieldInstances) |field| {
            if (std.mem.eql(u8, field.__identifier, "WorldStart")) {
                world_start = field.__value.bool;
                break;
            }
        }
        kind = .{ .player_start = world_start };
    } else if (std.mem.eql(u8, entity.__identifier, "Destructible")) {
        var shoot_only = false;
        for (entity.fieldInstances) |field| {
            if (std.mem.eql(u8, field.__identifier, "shoot_only")) {
                shoot_only = field.__value.bool;
                break;
            }
        }
        kind = .{ .destructible = .{ .shoot_only = shoot_only } };
    } else if (std.mem.eql(u8, entity.__identifier, "Switch")) {
        var can_shoot = false;
        var can_touch = true;
        var s_kind: u8 = 0;
        for (entity.fieldInstances) |field| {
            if (std.mem.eql(u8, field.__identifier, "kind")) {
                s_kind = @intCast(field.__value.integer);
            } else if (std.mem.eql(u8, field.__identifier, "can_shoot")) {
                can_shoot = field.__value.bool;
            } else if (std.mem.eql(u8, field.__identifier, "can_touch")) {
                can_touch = field.__value.bool;
            }
        }
        kind = .{ .switch_coin = .{ .kind = s_kind, .shootable = can_shoot, .touchable = can_touch } };
    } else if (std.mem.eql(u8, entity.__identifier, "SwitchDoor")) {
        var s_kind: u8 = 0;
        var target: PointType = .{ .cx = 0, .cy = 0 };
        for (entity.fieldInstances) |field| {
            if (std.mem.eql(u8, field.__identifier, "kind")) {
                s_kind = @intCast(field.__value.integer);
            } else if (std.mem.eql(u8, field.__identifier, "target")) {
                const res = try json.parseFromValue(PointType, alloc, field.__value, .{});
                defer res.deinit();
                target = res.value;
            }
        }
        kind = .{ .switch_door = .{ .kind = s_kind, .target = .{ .x = world_pos.x + target.cx * 8, .y = world_pos.y + target.cy * 8 } } };
    } else if (std.mem.eql(u8, entity.__identifier, "TrafficBlock")) {
        var target: PointType = .{ .cx = 0, .cy = 0 };
        var speed: f32 = 1.0;
        for (entity.fieldInstances) |field| {
            if (std.mem.eql(u8, field.__identifier, "target")) {
                const res = try json.parseFromValue(PointType, alloc, field.__value, .{});
                defer res.deinit();
                target = res.value;
            } else if (std.mem.eql(u8, field.__identifier, "Speed")) {
                const res = try json.parseFromValue(f32, alloc, field.__value, .{});
                defer res.deinit();
                speed = res.value;
            }
        }
        kind = .{ .traffic_block = .{ .target = .{ .x = world_pos.x + target.cx * 8, .y = world_pos.y + target.cy * 8 }, .speed = speed } };
    } else if (std.mem.eql(u8, entity.__identifier, "Spike")) {
        var dir: math.CardinalDir = .up;
        for (entity.fieldInstances) |field| {
            if (std.mem.eql(u8, field.__identifier, "Direction")) {
                const v = field.__value.string;
                if (std.mem.eql(u8, v, "Left")) {
                    dir = .left;
                } else if (std.mem.eql(u8, v, "Up")) {
                    dir = .up;
                } else if (std.mem.eql(u8, v, "Right")) {
                    dir = .right;
                } else if (std.mem.eql(u8, v, "Down")) {
                    dir = .down;
                }
            }
        }
        kind = .{ .spike = .{ .direction = dir } };
    } else if (std.mem.eql(u8, entity.__identifier, "DashCrystal")) {
        var dashes: u8 = 1;
        for (entity.fieldInstances) |field| {
            if (std.mem.eql(u8, field.__identifier, "Dashes")) {
                dashes = @intCast(field.__value.integer);
            }
        }
        kind = .{ .dash_crystal = dashes };
    } else if (std.mem.eql(u8, entity.__identifier, "Checkpoint")) {
        kind = .checkpoint;
    }

    if (kind) |k| {
        try o_entities.append(.{ .x = ex, .y = ey, .w = ew, .h = eh, .kind = k });
    }
}

fn skip_to_end(allocator: std.mem.Allocator, input: anytype, a_output: anytype, tag: []const u8) !void {
    const GoodOutType = switch (@typeInfo(@TypeOf(a_output))) {
        .Optional => @TypeOf(a_output),
        .Null => ?void,
        else => ?@TypeOf(a_output),
    };
    // LOL
    const output: GoodOutType = a_output;
    if (output) |it| {
        const start_tag = try std.fmt.allocPrint(allocator, "-- <{s}>\n", .{tag});
        defer allocator.free(start_tag);
        try it.writeAll(start_tag);
    }
    const end_tag = try std.fmt.allocPrint(allocator, "-- </{s}>", .{tag});
    defer allocator.free(end_tag);

    while (true) {
        const data = blk: {
            var list = std.ArrayList(u8).init(allocator);
            defer list.deinit();
            try input.streamUntilDelimiter(list.writer(), '\n', null);
            break :blk try list.toOwnedSlice();
        };
        defer allocator.free(data);
        if (output) |it| {
            try it.writeAll(data);
            try it.writeByte('\n');
        }
        // startsWidth???
        if (std.mem.startsWith(u8, data, "-- <")) {
            return;
        }
    }
}
fn extract_packed(input_f: std.fs.File) ![]u8 {
    var input = input_f;
    const whitelist = [_][]const u8{ "WAVES", "SFX", "PATTERNS", "TRACKS", "PALETTE" };
    const len = try input.seekableStream().getEndPos();
    var good_data = try alloc.alloc(u8, @intCast(len));
    defer alloc.free(good_data);
    var fbs = std.io.fixedBufferStream(good_data);
    main: while (true) {
        const data = blk: {
            var list = std.ArrayList(u8).init(alloc);
            defer list.deinit();
            input.reader().streamUntilDelimiter(list.writer(), '\n', null) catch |err| switch (err) {
                error.EndOfStream => {
                    break :main;
                },
                else => return err,
            };
            break :blk try list.toOwnedSlice();
        };
        // try input.reader().skipBytes(1, .{});
        defer alloc.free(data);
        if (data.len > 4 and std.mem.startsWith(u8, data, "-- <")) {
            std.debug.assert(data[4] != '/');
            var good_tag: ?[]const u8 = null;
            for (whitelist) |tag| {
                // - start + end
                if (data.len - 5 < tag.len) continue;
                if (std.mem.startsWith(u8, data[4..], tag)) {
                    good_tag = tag;
                    break;
                }
            }
            if (good_tag) |_| {
                // to get any numbers that are tacked on
                const tag = data[4 .. data.len - 1];
                try skip_to_end(alloc, input.reader(), fbs.writer(), tag);
            } else {
                // skip section
                // assumes that line is trimmed, which should be true if i never ever manually touch the file
                const tag = data[4 .. data.len - 1];
                try skip_to_end(alloc, input.reader(), null, tag);

                newlines: while (true) {
                    const next = input.reader().readByte() catch |err| switch (err) {
                        error.EndOfStream => break :main,
                        else => return err,
                    };
                    if (next != '\n') {
                        try input.seekBy(-1);
                        break :newlines;
                    }
                }
            }
        } else {
            try fbs.writer().writeAll(data);
            try fbs.writer().writeByte('\n');
        }
    }
    const final_len = try fbs.getPos();
    const out_data = try alloc.alloc(u8, final_len);
    @memcpy(out_data, good_data[0..final_len]);
    return out_data;
}

const SWEETIE_PALETTE = [16]tatl.RGBA{
    .{ .r = 26, .g = 28, .b = 44, .a = 255 },
    .{ .r = 93, .g = 39, .b = 93, .a = 255 },
    .{ .r = 177, .g = 64, .b = 83, .a = 255 },
    .{ .r = 239, .g = 125, .b = 87, .a = 255 },
    .{ .r = 255, .g = 205, .b = 117, .a = 255 },
    .{ .r = 167, .g = 240, .b = 112, .a = 255 },
    .{ .r = 56, .g = 183, .b = 100, .a = 255 },
    .{ .r = 37, .g = 113, .b = 121, .a = 255 },
    .{ .r = 41, .g = 54, .b = 111, .a = 255 },
    .{ .r = 59, .g = 93, .b = 201, .a = 255 },
    .{ .r = 65, .g = 166, .b = 246, .a = 255 },
    .{ .r = 115, .g = 239, .b = 247, .a = 255 },
    .{ .r = 244, .g = 244, .b = 244, .a = 255 },
    .{ .r = 148, .g = 176, .b = 194, .a = 255 },
    .{ .r = 86, .g = 108, .b = 134, .a = 255 },
    .{ .r = 51, .g = 60, .b = 87, .a = 255 },
};

// don't ask...
inline fn minus(comptime T: type, a: T, b: T) T {
    return @as(T, a) - @as(T, b);
}
fn nearest_color(color: tatl.RGBA, count: usize) u4 {
    var min: u32 = std.math.maxInt(u32);
    var nearest: u4 = 0;
    for (SWEETIE_PALETTE[0..count], 0..) |pal_col, i| {
        const dr: i32 = minus(i32, pal_col.r, color.r);
        const dg: i32 = minus(i32, pal_col.g, color.g);
        const db: i32 = minus(i32, pal_col.b, color.b);
        const ds: u31 = @intCast(dr * dr + dg * dg + db * db);
        if (ds < min) {
            min = ds;
            nearest = @intCast(i);
        }
    }
    return nearest;
}

fn color_at(color_depth: tatl.ColorDepth, ase_pallete: tatl.Palette, cel: tatl.Cel, bad_x: usize, bad_y: usize) !tatl.RGBA {
    const img_cel = try get_image_from_cel_or_cry(cel);
    const x = @as(isize, @intCast(bad_x)) - @as(isize, cel.x);
    const y = @as(isize, @intCast(bad_y)) - @as(isize, cel.y);
    if (x < 0 or y < 0) return error.OutsideCel;
    if (x >= img_cel.width or y >= img_cel.height) return error.OutsideCel;
    switch (color_depth) {
        .grayscale => return error.NoGrayscale,
        .rgba => {
            const idx: usize = @intCast((y * img_cel.width + x) * 4);
            const r = img_cel.pixels[idx];
            const g = img_cel.pixels[idx + 1];
            const b = img_cel.pixels[idx + 2];
            const a = img_cel.pixels[idx + 3];

            return .{ .r = r, .g = g, .b = b, .a = a };
        },
        .indexed => {
            const idx: usize = @intCast(y * img_cel.width + x);

            const pix = img_cel.pixels[idx];
            const color = ase_pallete.colors[pix];

            return color;
        },
    }
}

fn pal_color_at(color_depth: tatl.ColorDepth, ase_palette: tatl.Palette, cel: tatl.Cel, x: usize, y: usize, bpp: tic80_ext.Bpp) !?u4 {
    const col_at = color_at(color_depth, ase_palette, cel, x, y) catch |err| switch (err) {
        error.OutsideCel => return null,
        else => return err,
    };
    const bpp_num: usize = switch (bpp) {
        .one => 2,
        .two => 4,
        .four => 16,
    };
    return nearest_color(col_at, bpp_num);
}

fn infer_color_at(color_depth: tatl.ColorDepth, ase_palette: tatl.Palette, cel: tatl.Cel, x: usize, y: usize, trans_color: u4, pal: Spritesheet.SpritePalette) !u4 {
    const col_at = color_at(color_depth, ase_palette, cel, x, y) catch |err| switch (err) {
        error.OutsideCel => return trans_color,
        else => return err,
    };
    return infer_color(trans_color, pal, col_at);
}

const TouchedTiles = struct {
    pub const TouchedTilesSet = std.StaticBitSet(16 * 4 * 16);
    data: TouchedTilesSet,

    // Because touched tiles is meant to be sensitive, this or's the results together
    pub fn get(self: *TouchedTiles, x: usize, y: usize, bpp: tic80_ext.Bpp) bool {
        const good_y = y * SHEET_HEIGHT * 4;
        switch (bpp) {
            .one => return self.data.isSet(good_y + x),
            .two => return self.data.isSet(good_y + x * 2) or self.data.isSet(good_y + x * 2 + 1),
            .four => {
                const good_x = x * 4;
                return self.data.isSet(good_y + good_x) or self.data.isSet(good_y + good_x + 1) or self.data.isSet(good_y + good_x + 2) or self.data.isSet(good_y + good_x + 3);
            },
        }
    }
    pub fn setValue(self: *TouchedTiles, x: usize, y: usize, value: bool, bpp: tic80_ext.Bpp) void {
        const good_y = y * SHEET_HEIGHT * 4;
        switch (bpp) {
            .one => self.data.setValue(good_y + x, value),
            .two => {
                const good_x = x * 2;
                self.data.setValue(good_y + good_x, value);
                self.data.setValue(good_y + good_x + 1, value);
            },
            .four => {
                const good_x = x * 4;
                self.data.setValue(good_y + good_x, value);
                self.data.setValue(good_y + good_x + 1, value);
                self.data.setValue(good_y + good_x + 2, value);
                self.data.setValue(good_y + good_x + 3, value);
            },
        }
    }
    pub fn set(self: *TouchedTiles, x: usize, y: usize, bpp: tic80_ext.Bpp) void {
        self.setValue(x, y, true, bpp);
    }
    pub fn init() TouchedTiles {
        return TouchedTiles{ .data = TouchedTilesSet.initEmpty() };
    }
};
const PackedTilesheet = std.PackedIntArrayEndian(u4, .little, 128 * 128);
const PackedResult = struct {
    sprites: PackedTilesheet,
    tiles: PackedTilesheet,
    flags: [16 * 16 * 2]u8,
    sheets: []Spritesheet,
};
fn data_at(ase: tatl.AsepriteImport, x: usize, y: usize) !u8 {
    for (ase.slices) |slice| {
        if (slice.user_data.text.len == 0) {
            continue;
        }
        for (slice.keys) |key| {
            if (key.x <= x and key.x + @as(i32, @intCast(key.width)) > x and key.y <= y and key.y + @as(i32, @intCast(key.height)) > y) {
                return std.fmt.parseInt(u8, slice.user_data.text, 0);
            }
        }
    }

    return 0x00;
}
fn get_image_from_cel_or_cry(cel: tatl.Cel) !tatl.ImageCel {
    switch (cel.data) {
        .raw_image, .compressed_image => |c| return c,
        else => return error.NotAnImage,
    }
}

// god hates us all
fn pixel_pos_to_tic80_index(x: usize, y: usize) usize {
    const tile_x = @divFloor(x, 8);
    const tile_y = @divFloor(y, 8);
    const offset_x = x % 8;
    const offset_y = y % 8;

    const idx = (tile_y * SHEET_HEIGHT + tile_x) * PIXELS_IN_SPR + (offset_y * 8 + offset_x);
    return idx;
}
const SHEET_HEIGHT = 16;
fn default_color(palette: tatl.Palette) u4 {
    return nearest_color(palette.colors[palette.transparent_index], 16);
}
// infer the color to be written to palette
fn infer_color(trans_color: u4, pal: Spritesheet.SpritePalette, color: tatl.RGBA) u4 {
    const res_color = nearest_color(color, 16);
    switch (pal) {
        .one => |c| {
            std.debug.assert(res_color == trans_color or res_color == c);
            return if (res_color == trans_color) 0 else 1;
        },
        .two => |c| {
            if (res_color == trans_color) {
                return 0;
            } else if (res_color == c[0]) {
                return 1;
            } else if (res_color == c[1]) {
                return 2;
            } else if (res_color == c[2]) {
                return 3;
            }
            unreachable;
        },
        .four => return res_color,
    }
}
fn infer_palette(trans_color: u4, bpp: tic80_ext.Bpp, ase: tatl.AsepriteImport, cel: tatl.Cel) !Spritesheet.SpritePalette {
    if (ase.color_depth != .indexed) {
        return switch (bpp) {
            .one => .{ .one = 1 },
            .two => .{ .two = .{ 1, 2, 3 } },
            .four => .{ .four = trans_color },
        };
    }
    var unique_colors = std.ArrayList(u4).init(alloc);
    defer unique_colors.deinit();
    for (0..ase.width) |x| {
        checker: for (0..ase.height) |y| {
            const color = try pal_color_at(ase.color_depth, ase.palette, cel, x, y, .four) orelse continue;
            if (color == trans_color) continue;
            for (unique_colors.items) |unique| {
                if (unique == color) {
                    continue :checker;
                }
            }
            try unique_colors.append(color);
            if (unique_colors.items.len > 3) {
                return .{ .four = trans_color };
            }
        }
    }
    std.debug.assert(unique_colors.items.len <= 3);
    if (unique_colors.items.len > 1) {
        const one = unique_colors.items[0];
        const two = unique_colors.items[1];
        const three = if (unique_colors.items.len > 2) unique_colors.items[2] else trans_color;
        return .{ .two = .{ one, two, three } };
    }
    std.debug.assert(unique_colors.items.len == 1);
    return .{ .one = unique_colors.items[0] };
}
fn tile_range(p: i16, len: i32, max: i32) !struct { usize, usize, usize } {
    const start: u16 = @intCast(@divFloor(@max(p, 0), 8));
    const end: usize = @intCast(try std.math.divCeil(i32, @min(p + len, max), 8));
    return .{ start, end, end - start };
}
fn pack_ase(bpp: tic80_ext.Bpp, ase: tatl.AsepriteImport, sprite_sheet: *PackedTilesheet, touched: *TouchedTiles) !Spritesheet {
    std.debug.assert(ase.width % 8 == 0);
    std.debug.assert(ase.height % 8 == 0);
    const t_width = @divFloor(ase.width, 8);
    const t_height = @divFloor(ase.height, 8);
    const sheet = Spritesheet{ .items = try alloc.alloc(Spritesheet.Sprite, ase.frames.len) };
    var real_tile: usize = 0;
    const def_color = if (ase.color_depth == .indexed) default_color(ase.palette) else 0;
    for (ase.frames, 0..) |frame, item_n| {
        const cel = frame.cels[0];
        const img_cel = try get_image_from_cel_or_cry(cel);
        const pal = try infer_palette(def_color, bpp, ase, cel);

        const bpp_multiplier: u16 = @as(u16, @as(tic80_ext.Bpp, pal).getMultiplier());
        const sheet_width: u16 = 16 * bpp_multiplier;
        // find next free position
        y: for (0..SHEET_HEIGHT) |y| {
            if (y + t_height > SHEET_HEIGHT) continue :y;
            x: for (0..@as(usize, @intCast(sheet_width))) |x| {
                if (x + t_width > sheet_width) continue :x;
                const valid =
                    valid: for (0..t_width) |i|
                {
                    for (0..t_height) |j| {
                        if (touched.get(x + i, y + j, @as(tic80_ext.Bpp, pal))) {
                            break :valid false;
                        }
                    }
                } else true;
                if (valid) {
                    real_tile = y * sheet_width + x;
                    break :y;
                }
            }
        } else return error.TooManySprites;

        const cur_x = real_tile % sheet_width;
        const pixel_cur_x = blk: {
            const root = @divFloor(cur_x * 8, bpp_multiplier);
            break :blk root;
        };
        const cur_y = @divFloor(real_tile, sheet_width);
        const pixel_cur_y = cur_y * 8;
        const x_start, const x_end, const x_len = try tile_range(cel.x, img_cel.width, ase.width);
        const y_start, const y_end, const y_len = try tile_range(cel.y, img_cel.height, ase.height);
        _ = y_start;
        sheet.items[item_n] = .{
            .id = @intCast(256 * bpp_multiplier + real_tile),
            .w = @intCast(x_len),
            .h = @intCast(y_len),
            .palette = pal,
        };
        const x_samples: usize = try std.math.divCeil(usize, x_len * 8, bpp_multiplier);
        for (0..x_samples) |i| {
            const x = x_start * 8 + i * bpp_multiplier;
            for (0..y_end * 8) |y| {
                const col: u4 = switch (pal) {
                    .four => try infer_color_at(ase.color_depth, ase.palette, cel, x, y, def_color, pal),
                    .two => blk: {
                        const col1 = try infer_color_at(ase.color_depth, ase.palette, cel, x, y, def_color, pal);
                        const col2 = try infer_color_at(ase.color_depth, ase.palette, cel, x + 1, y, def_color, pal);
                        break :blk (col2 << 2) + col1;
                    },
                    .one => blk: {
                        const col1 = try infer_color_at(ase.color_depth, ase.palette, cel, x, y, def_color, pal);
                        const col2 = try infer_color_at(ase.color_depth, ase.palette, cel, x + 1, y, def_color, pal);
                        const col3 = try infer_color_at(ase.color_depth, ase.palette, cel, x + 2, y, def_color, pal);
                        const col4 = try infer_color_at(ase.color_depth, ase.palette, cel, x + 3, y, def_color, pal);
                        break :blk (col4 << 3) + (col3 << 2) + (col2 << 1) + col1;
                    },
                };

                const pixel_y = pixel_cur_y + y;
                const pixel_x = pixel_cur_x + i;
                sprite_sheet.set(pixel_pos_to_tic80_index(pixel_x, pixel_y), col);
            }
        }
        // end bc len will cause jank
        for (cur_x..cur_x + x_end) |x| {
            for (cur_y..cur_y + y_end) |y| {
                touched.set(x, y, @as(tic80_ext.Bpp, pal));
            }
        }
    }
    return sheet;
}

fn packinator(root_dir: std.fs.Dir, in_file: std.fs.File, tiles: tatl.AsepriteImport) !PackedResult {
    var tile_data = PackedTilesheet.initAllTo(0);
    {
        const cel = tiles.frames[0].cels[0];
        for (0..16) |i| {
            for (0..16) |j| {
                for (0..8) |ii| {
                    for (0..8) |jj| {
                        const x = (i * 8) + ii;
                        const y = (j * 8) + jj;
                        const col = try pal_color_at(tiles.color_depth, tiles.palette, cel, x, y, .four) orelse 0;
                        tile_data.set((j * 16 + i) * PIXELS_IN_SPR + (jj * 8 + ii), col);
                    }
                }
            }
        }
    }
    // end is sprite sheet
    var flags: [16 * 16 * 2]u8 = std.mem.zeroes([16 * 16 * 2]u8);
    for (0..16) |x| {
        for (0..16) |y| {
            const data = try data_at(tiles, x * 8, y * 8);
            flags[y * 16 + x] = data;
        }
    }
    var sprite_data = PackedTilesheet.initAllTo(0);
    var touched = TouchedTiles.init();
    var sheets = std.ArrayList(Spritesheet).init(alloc);
    defer sheets.deinit();
    {
        const data = try in_file.readToEndAlloc(alloc, 65536);
        defer alloc.free(data);
        // TODO: test more
        var iterator = std.mem.splitSequence(u8, data, "\n");
        while (iterator.next()) |it| {
            const ase = blk: {
                var file = root_dir.openFile(it, .{}) catch |err| switch (err) {
                    error.FileNotFound => {
                        continue;
                    },
                    else => return err,
                };
                defer file.close();
                break :blk try tatl.import(alloc, file.reader());
            };
            defer ase.free(alloc);
            const bpp: tic80_ext.Bpp = switch (std.fmt.parseInt(u4, ase.sprite_userdata.text, 10) catch 4) {
                1 => .one,
                2 => .two,
                4 => .four,
                else => return error.InvalidFile,
            };
            try sheets.append(try pack_ase(bpp, ase, &sprite_data, &touched));
        }
    }

    return .{ .sprites = sprite_data, .tiles = tile_data, .flags = flags, .sheets = try sheets.toOwnedSlice() };
}
