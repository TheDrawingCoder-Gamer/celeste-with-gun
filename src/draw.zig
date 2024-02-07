const tic = @import("tic80.zig");

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
