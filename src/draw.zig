const tic = @import("tic80.zig");
const std = @import("std");

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
        PaletteIO.set(tic.PALETTE_MAP_u8, i, 0, i);
    }
}
