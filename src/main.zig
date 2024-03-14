const common = @import("common");
const SavedLevel = common.Level;
const tic = common.tic;
const Player = @import("Player.zig");
const GameState = @import("GameState.zig");
const Input = @import("Input.zig");
const std = @import("std");
const Buddy2Allocator = @import("buddy2").Buddy2Allocator(.{});
const s2s = @import("s2s");
const Level = @import("Level.zig");
const Audio = @import("Audio.zig");
const sheets = @import("sheets.zig");

var buffer: [65536]u8 = undefined;
var game_state: GameState = undefined;
var input_1: Input = undefined;
var audio: Audio.Voice = .{ .channel = 3 };
var aux_audio: Audio.Voice = .{ .channel = 2 };
var buddy2: Buddy2Allocator = undefined;
var startup_t: u8 = 0;
// var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

var allocator: std.mem.Allocator = undefined;
export fn BOOT() void {
    buddy2 = Buddy2Allocator.init(&buffer);
    allocator = buddy2.allocator();

    input_1 = .{ .player = 0 };
    game_state = GameState.init(allocator, &input_1, &audio, &aux_audio);
    tic.sync(.{ .bank = 7, .sections = .{ .map = true } });
    var fb = std.io.fixedBufferStream(tic.MAP);
    Level.rooms = s2s.deserializeAlloc(fb.reader(), []SavedLevel, allocator) catch unreachable;
    Level.from_saved(&Level.rooms[0], &game_state).start() catch unreachable;
    const data = s2s.deserializeAlloc(fb.reader(), []common.Spritesheet, allocator) catch unreachable;
    defer allocator.free(data);
    sheets.bullet = data[0];
    sheets.checkpoint = data[1];
    sheets.crumble = data[2];
    sheets.dash_crystal = data[3];
    sheets.destructible = data[4];
    sheets.destructible_gun = data[5];
    sheets.innergear = data[6];
    sheets.misc = data[7];
    sheets.outergear = data[8];
    sheets.player = data[9];
    sheets.shield_icons = data[10];
    sheets.shotgun_blast = data[11];
    sheets.spikes = data[12];
    sheets.ammo_reload = data[13];
    sheets.bullet_ui = data[14];
    sheets.traffic_block = data[15];
    //for (Audio.music_patterns, 0..) |pattern, i| {
    //    tic.tracef("{d}, {any}", .{ i, pattern.get(0) });
    //}
}

export fn TIC() void {
    switch (startup_t) {
        0, 1 => {
            tic.sync(.{ .bank = 0, .sections = .{ .map = true } });
        },
        else => {
            input_1.update();
            audio.process();
            // audio.sfx(5, 10, 0);
            game_state.loop();
            return;
        },
    }
    startup_t += 1;
}

export fn BDR() void {}

export fn OVR() void {}

const MenuItem = enum(i32) { retry, _ };
export fn MENU(index: i32) void {
    const item: MenuItem = @enumFromInt(index);
    switch (item) {
        .retry => {
            if (game_state.player) |p| {
                p.die();
            }
        },
        _ => {},
    }
}
