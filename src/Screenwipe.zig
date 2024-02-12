const Self = @This();

const tic = @import("tic80.zig");
const std = @import("std");
const Player = @import("Player.zig");
const GameState = @import("GameState.zig");

infade: u8 = 0,
wipe_timer: u8 = 0,

fn tic80sin(angle: f32) f32 {
    return -std.math.sin(angle * (std.math.tau));
}

fn tic80cos(angle: f32) f32 {
    return std.math.cos(angle * (std.math.tau));
}

pub fn update(self: *Self) void {
    self.infade = @min(self.infade + 1, 60);
}

pub fn draw(self: *const Self, game_state: *const GameState) void {
    if (self.wipe_timer > 10) {
        const e: f32 = @as(f32, @floatFromInt(self.wipe_timer - 10)) / 24;
        for (0..tic.HEIGHT) |i| {
            const s: i32 = @intFromFloat(@as(f32, tic.WIDTH + 128) * e - 32 + tic80sin(@as(f32, @floatFromInt(i)) * 0.2) * 16 + @as(f32, @floatFromInt(tic.WIDTH - i)) * 0.25);
            tic.rect(game_state.camera_x, game_state.camera_y + @as(i32, @intCast(i)), s, @intCast(i), 0);
        }
    }

    if (self.infade < 45) {
        const e = @as(f32, @floatFromInt(self.infade)) / 24;
        for (0..tic.HEIGHT) |i| {
            const s: i32 = @intFromFloat(@as(f32, tic.WIDTH + 64) * e - 32 + tic80sin(@as(f32, @floatFromInt(i)) * 0.2) * 16 + @as(f32, @floatFromInt(tic.WIDTH - i)) * 0.25);
            tic.rect(game_state.camera_x + s, game_state.camera_y + @as(i32, @intCast(i)), tic.WIDTH, 1, 0);
        }
    }
}

pub fn reset(self: *Self) void {
    self.infade = 0;
    self.wipe_timer = 0;
}
