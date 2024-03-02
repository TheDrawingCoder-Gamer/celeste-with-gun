const tic = @import("common").tic;
const std = @import("std");
const types = @import("types.zig");

pub const BPP: *u4 = @as(*u4, @ptrFromInt(0x3ffc));

pub fn set1bpp() void {
    BPP.* = 8;
}
pub fn set2bpp() void {
    BPP.* = 4;
}
pub fn set4bpp() void {
    BPP.* = 2;
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
