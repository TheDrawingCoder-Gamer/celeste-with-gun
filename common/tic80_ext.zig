//! Extras to tic80, or things that I think should be in there but don't want to edit the file for.

const tic = @import("tic80.zig");
const std = @import("std");

pub const BPP: *Bpp = @ptrFromInt(0x3ffc);
/// Bits per pixel. The tag is what the BPP memory area gets set to.
pub const Bpp = enum(u4) {
    one = 8,
    two = 4,
    four = 2,
    pub fn getMultiplier(self: Bpp) u4 {
        return @divFloor(@intFromEnum(self), 2);
    }
};

pub const Mapping = std.PackedIntArrayEndian(u4, .little, 16);

pub const PALETTE_MAP: *Mapping = @as(*Mapping, @ptrFromInt(0x3FF0));
