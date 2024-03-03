const tic = @import("common").tic;
const Buddy2Allocator = @import("buddy2").Buddy2Allocator(.{});
const s2s = @import("s2s");
const std = @import("std");
const json = std.json;
const SavedLevel = @import("common").Level;
const math = @import("common").math;

var buf: [1024 * 55]u8 = undefined;
var fba: std.heap.FixedBufferAllocator = undefined;
var allocator: std.mem.Allocator = undefined;

// WEEWOO! THIS IS REALLY BEEG!
const file = @embedFile("map");

var t: u32 = 0;
var levels: []SavedLevel = undefined;
var ouchie = false;
export fn BOOT() void {
    fba = std.heap.FixedBufferAllocator.init(&buf);
    allocator = fba.allocator();

    var fbs = std.io.fixedBufferStream(file);
    const data = s2s.deserializeAlloc(fbs.reader(), SavedLevel.CompressedMap, allocator) catch unreachable;
    levels = data.levels;
    @memset(tic.MAP, 0);
    for (data.tiles) |tile| {
        tic.mset(tile.pos.x, tile.pos.y, tile.tile);
    }
}

export fn TIC() void {
    tic.cls(0);
    switch (t) {
        0 => tic.sync(.{ .bank = 0, .sections = .{ .map = true }, .toCartridge = true }),
        1 => {
            if (!ouchie) {
                @memset(tic.MAP, 0);
                var stream = std.io.fixedBufferStream(tic.MAP);
                s2s.serialize(stream.writer(), []SavedLevel, levels) catch |err| {
                    tic.tracef("{any}", .{err});
                };
                tic.sync(.{ .bank = 7, .sections = .{ .map = true }, .toCartridge = true });
            }
        },
        else => {
            if (ouchie) {
                _ = tic.print("oopsies!", 0, 0, .{});
            } else {
                _ = tic.print("done :)", 0, 0, .{});
            }
        },
    }
    t += 1;
}

export fn BDR() void {}

export fn OVR() void {}
