const tic = @import("common").tic;
const tic_ext = @import("common").ticext;
const std = @import("std");
const types = @import("common").math;

pub fn set1bpp() void {
    tic_ext.BPP.* = .one;
}
pub fn set2bpp() void {
    tic_ext.BPP.* = .two;
}
pub fn set4bpp() void {
    tic_ext.BPP.* = .four;
}

const PaletteIO = std.packed_int_array.PackedIntIo(u4, .little);
pub fn reset_pallete() void {
    for (0..16) |i| {
        PaletteIO.set(tic.PALETTE_MAP_u8, i, 0, @intCast(i));
    }
}

const pi = std.math.pi;
const halfpi = std.math.pi / 2.0;
const quartpi = std.math.pi / 4.0;
const tau = std.math.tau;

pub fn arcb(sx: i32, sy: i32, r: i32, v_from: types.Vec2, v_to: types.Vec2, color: u4) void {
    const from = v_from.to_radians();
    const to = v_to.to_radians();

    // squared
    var f = 1 - r;
    var ddF_x: i32 = 1;
    // ???
    var ddF_y = -2 * r;
    var x: i32 = 0;
    var y = r;

    if (types.angles_contain(halfpi, from, to)) {
        tic.pix(sx, sy - r, color);
    }
    if (types.angles_contain(-halfpi, from, to)) {
        tic.pix(sx, sy + r, color);
    }
    if (types.angles_contain(0, from, to)) {
        tic.pix(sx + r, sy, color);
    }
    if (types.angles_contain(pi, from, to)) {
        tic.pix(sx - r, sy, color);
    }

    while (x < y) {
        if (f >= 0) {
            y -= 1;
            ddF_y += 2;
            f += ddF_y;
        }
        x += 1;
        ddF_x += 2;
        f += ddF_x;

        // TODO: don't do 69 trig functions
        const to_radians = types.Point.to_radians;
        if (types.angles_contain(to_radians(.{ .x = x, .y = y }), from, to)) {
            tic.pix(sx + x, sy + y, color);
        }
        if (types.angles_contain(to_radians(.{ .x = -x, .y = y }), from, to)) {
            tic.pix(sx - x, sy + y, color);
        }
        if (types.angles_contain(to_radians(.{ .x = x, .y = -y }), from, to)) {
            tic.pix(sx + x, sy - y, color);
        }
        if (types.angles_contain(to_radians(.{ .x = -x, .y = -y }), from, to)) {
            tic.pix(sx - x, sy - y, color);
        }
        if (types.angles_contain(to_radians(.{ .x = y, .y = x }), from, to)) {
            tic.pix(sx + y, sy + x, color);
        }
        if (types.angles_contain(to_radians(.{ .x = -y, .y = x }), from, to)) {
            tic.pix(sx - y, sy + x, color);
        }
        if (types.angles_contain(to_radians(.{ .x = y, .y = -x }), from, to)) {
            tic.pix(sx + y, sy - x, color);
        }
        if (types.angles_contain(to_radians(.{ .x = -y, .y = -x }), from, to)) {
            tic.pix(sx - y, sy - x, color);
        }
    }
}

pub const MapperTile = struct { flip: tic.Flip = .no, rotate: tic.Rotate = .no, tile: u8, transparent: ?[]const u8 = null };
pub fn Mapper(
    comptime Context: type,
    comptime row_size: usize,
    comptime map_height: usize,
    comptime max_stack: usize,
    comptime TileInfo: type,
    comptime decodeFn: fn (ctx: Context, info: TileInfo, buf: *[max_stack]MapperTile) void,
) type {
    return struct {
        ctx: Context,

        const Self = @This();
        pub fn init(ctx: Context) Self {
            return .{ .ctx = ctx };
        }
        const MapArgs = struct {
            transparent: []const u8 = &.{},
        };
        // Draw map from an array of tile info.
        pub fn map(self: *const Self, cam: types.Point, buf: *const [row_size * map_height]TileInfo, args: MapArgs) void {
            const ccx = @divFloor(cam.x, 8);
            const ccy = @divFloor(cam.y, 8);

            const x_off = -@rem(cam.x, 8);
            const y_off = -@rem(cam.y, 8);

            const minx = @max(0, ccx);
            const miny = @max(0, ccy);

            const maxx = @min(row_size - 1, ccx + 32);
            const maxy = @min(map_height - 1, ccy + 18);

            for (minx..maxx) |i| {
                for (miny..maxy) |j| {
                    var tiles: [max_stack]MapperTile = undefined;
                    @memset(tiles, .{ .tile = 0 });
                    const t_info = buf[j * row_size + i];
                    decodeFn(self.ctx, t_info, &tiles);
                    for (tiles) |t| {
                        tic.spr(
                            t.tile,
                            i * 8 + x_off,
                            j * 8 + y_off,
                            .{ .rotate = t.rotate, .flip = t.flip, .transparent = if (t.transparent) |trans| trans else args.transparent },
                        );
                    }
                }
            }
        }
    };
}

fn default_map(ctx: void, info: u8, buf: *[1]MapperTile) void {
    _ = ctx;
    buf[0] = .{ .tile = info };
}

pub const DefaultMapper = Mapper(void, tic.MAP_WIDTH, tic.MAP_HEIGHT, 1, u8, default_map).init({});
