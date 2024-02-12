const Level = @This();

const tic = @import("tic80.zig");
const std = @import("std");
const GameState = @import("GameState.zig");
const Player = @import("Player.zig");
const Destructible = @import("Destructible.zig");
const Spike = @import("Spike.zig");
const Crumble = @import("Crumble.zig");

height: i32,
width: i32,
x: i32,
y: i32,
player_x: i32,
player_y: i32,
state: *GameState,

pub fn setup(self: *Level) !void {
    try self.init();
    for (self.state.players) |player| {
        player.game_object.x = self.player_x * 8;
        player.game_object.y = self.player_y * 8;
    }
    self.state.camera_x = self.x;
    self.state.camera_y = self.y;
}
pub fn test_level(state: *GameState) *Level {
    state.loaded_level = .{ .x = 0, .y = 0, .width = 60, .height = 17, .player_x = 1, .player_y = 13, .state = state };
    return &state.loaded_level;
}

pub fn init(self: *Level) !void {
    var y = self.y;
    while (y <= self.height) : (y += 1) {
        var x = self.x;
        while (x <= self.width) : (x += 1) {
            switch (tic.mget(x, y)) {
                7 => {
                    _ = try Crumble.create(self.state.allocator, self.state, x * 8, y * 8);
                },
                35 => {
                    _ = try Destructible.create(self.state.allocator, x, y, self.state);
                },
                51, 52, 53, 54 => |it| {
                    _ = try Spike.create(self.state.allocator, self.state, x * 8, y * 8, @enumFromInt(@as(u2, @intCast(it - 51))));
                },
                16 => {
                    self.player_x = x;
                    self.player_y = y;
                },
                else => {},
            }
        }
    }
}
pub fn reset(self: *Level) !void {
    self.state.clean();
    try self.setup();
}
