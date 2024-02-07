const Level = @This();

const tic = @import("tic80.zig");
const std = @import("std");
const GameState = @import("GameState.zig");
const Player = @import("Player.zig");
const Crumble = @import("Crumble.zig");

height: i32,
width: i32,
x: i32,
y: i32,
player_x: i32,
player_y: i32,
state: *GameState,
init: *const fn (*Level) std.mem.Allocator.Error!void = undefined,

pub fn setup(self: *Level) !void {
    for (self.state.players) |player| {
        player.game_object.x = self.player_x * 8;
        player.game_object.y = self.player_y * 8;
    }
    self.state.camera_x = self.x;
    self.state.camera_y = self.y;
    try self.init(self);
}
pub fn test_level(state: *GameState) *Level {
    state.loaded_level = .{ .x = 0, .y = 0, .width = 30, .height = 17, .player_x = 1, .player_y = 13, .state = state, .init = &test_level_init };
    return &state.loaded_level;
}

pub fn reset(self: *Level) !void {
    self.state.clean();
    try self.setup();
}

fn test_level_init(self: *Level) std.mem.Allocator.Error!void {
    const allocator = self.state.allocator;
    _ = try Crumble.create(allocator, 10, 12, self.state);
    _ = try Crumble.create(allocator, 12, 12, self.state);
    _ = try Crumble.create(allocator, 14, 12, self.state);
}
