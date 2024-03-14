//! Information about location of a spritesheet.
const Self = @This();
const tic80_ext = @import("tic80_ext.zig");
const tic80 = @import("tic80.zig");
const std = @import("std");

pub const SpritePalette = union(tic80_ext.Bpp) {
    one: u4,
    two: [3]u4,
    four: u4,
};
const PaletteIo = std.packed_int_array.PackedIntIo(u4, .little);
pub const Sprite = struct {
    id: u16,
    w: u16,
    h: u16,
    palette: SpritePalette,
    pub fn draw(self: *const Sprite, x: i32, y: i32, args: SpriteArgs) void {
        // we capture it bc i'm too lazy to rewrite a lot of code
        const bpp = tic80_ext.BPP.*;
        const cur_palette = tic80.PALETTE_MAP_u8.*;
        tic80_ext.BPP.* = std.meta.activeTag(self.palette);
        var trans_color: u4 = 0;
        switch (self.palette) {
            .one => |c| tic80.PALETTE_MAP.color1 = PaletteIo.get(&cur_palette, c, 0),
            .two => |c| {
                tic80.PALETTE_MAP.color1 = PaletteIo.get(&cur_palette, c[0], 0);
                tic80.PALETTE_MAP.color2 = PaletteIo.get(&cur_palette, c[1], 0);
                tic80.PALETTE_MAP.color3 = PaletteIo.get(&cur_palette, c[2], 0);
            },
            .four => |c| trans_color = c,
        }
        tic80.spr(self.id, x, y, .{ .w = self.w, .h = self.h, .flip = args.flip, .rotate = args.rotate, .transparent = &.{trans_color} });
        tic80_ext.BPP.* = bpp;
        tic80.PALETTE_MAP_u8.* = cur_palette;
    }
};
items: []Sprite,

pub const SpriteArgs = struct {
    rotate: tic80.Rotate = .no,
    flip: tic80.Flip = .no,
};
pub fn draw(self: *const Self, id: usize, x: i32, y: i32, args: SpriteArgs) void {
    self.items[id].draw(x, y, args);
}
