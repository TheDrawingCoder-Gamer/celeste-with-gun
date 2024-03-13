//! Information about location of a spritesheet.
const Self = @This();
const tic80_ext = @import("tic80_ext.zig");
const tic80 = @import("tic80.zig");
const std = @import("std");

items: []u16,
bpp: tic80_ext.Bpp = .four,
tile_w: u16 = 1,
tile_h: u16 = 1,
