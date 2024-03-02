const Self = @This();

const tic = @import("common").tic;
const std = @import("std");
const Player = @import("Player.zig");
const GameState = @import("GameState.zig");
const types = @import("types.zig");

infade: u8 = 0,
wipe_timer: u8 = 0,
level_wipe: u8 = 60,

fn tic80sin(angle: f32) f32 {
    return -std.math.sin(angle * (std.math.tau));
}

fn tic80cos(angle: f32) f32 {
    return std.math.cos(angle * (std.math.tau));
}

pub fn update(self: *Self) void {
    self.infade = @min(self.infade + 1, 60);
    self.level_wipe = @min(self.level_wipe + 1, 60);
}

inline fn calc_line_size(max_size: i32, idx: usize, time: f32) i32 {
    return @intFromFloat(@as(f32, max_size + 128) * time - 32 + tic80sin(@as(f32, @floatFromInt(idx)) * 0.2) * 16 + (@as(f32, @floatFromInt(max_size)) - @as(f32, @floatFromInt(idx))) * 0.25);
}
fn draw_directional(dir: types.Direction, timer: i32, fadein: bool) void {
    const e: f32 = @as(f32, @floatFromInt(timer)) / 24;
    switch (dir) {
        .up, .down => {
            for (0..tic.WIDTH) |i| {
                const s: i32 = calc_line_size(tic.HEIGHT, i, e);

                tic.rect(@as(i32, @intCast(i)), (if (fadein) s else 0), 1, (if (fadein) tic.HEIGHT else s), 0);
            }
        },
        .left, .right => {
            for (0..tic.HEIGHT) |i| {
                const s: i32 = calc_line_size(tic.WIDTH, i, e);
                tic.rect((if (fadein) s else 0), @as(i32, @intCast(i)), (if (fadein) tic.WIDTH else s), 1, 0);
            }
        },
    }
}
pub fn draw(self: *const Self) void {
    if (self.wipe_timer > 10) {
        draw_directional(.right, self.wipe_timer - 10, false);
    }

    if (self.infade < 45) {
        draw_directional(.right, self.infade, true);
    }

    if (self.level_wipe < 45) {
        draw_directional(.right, self.level_wipe, false);
    }
}

pub fn reset(self: *Self) void {
    self.infade = 0;
    self.wipe_timer = 0;
}
