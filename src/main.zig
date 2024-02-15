const tic = @import("tic80.zig");
const Player = @import("Player.zig");
const GameState = @import("GameState.zig");
const Input = @import("Input.zig");
const std = @import("std");
const Buddy2Allocator = @import("buddy2").Buddy2Allocator(.{});
const Level = @import("Level.zig");
const Audio = @import("Audio.zig");

var buffer: [65536 * 2]u8 = undefined;
var game_state: GameState = undefined;
var input_1: Input = undefined;
var audio: Audio.Voice = .{ .channel = 3 };
var player: Player = undefined;
var buddy2: Buddy2Allocator = undefined;
// var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

var allocator: std.mem.Allocator = undefined;
export fn BOOT() void {
    buddy2 = Buddy2Allocator.init(&buffer);
    allocator = buddy2.allocator();

    game_state = GameState.init(allocator, &.{&player}, &audio);
    input_1 = .{ .player = 0 };
    player = Player.create(allocator, &game_state, 2 * 8, 12 * 8, &input_1, &audio) catch unreachable;
    player.host = true;
    Level.rooms[0].load_level(&game_state).start() catch unreachable;
    //for (Audio.music_patterns, 0..) |pattern, i| {
    //    tic.tracef("{d}, {any}", .{ i, pattern.get(0) });
    //}
}

export fn TIC() void {
    input_1.update();
    audio.process();
    // audio.sfx(5, 10, 0);
    game_state.loop();
}

export fn BDR() void {}

export fn OVR() void {}

const MenuItem = enum(i32) { retry, _ };
export fn MENU(index: i32) void {
    const item: MenuItem = @enumFromInt(index);
    switch (item) {
        .retry => {
            player.die();
        },
        _ => {},
    }
}
