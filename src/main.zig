const tic = @import("tic80.zig");
const Player = @import("Player.zig");
const GameState = @import("GameState.zig");
const Input = @import("Input.zig");
const std = @import("std");
const Crumble = @import("Crumble.zig");
const Buddy2Allocator = @import("buddy2").Buddy2Allocator(.{});

var buffer: [65536 * 2]u8 = undefined;
var game_state: GameState = undefined;
var input_1: Input = undefined;
var player: *Player = undefined;
var buddy2: Buddy2Allocator = undefined;
// var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

var allocator: std.mem.Allocator = undefined;
export fn BOOT() void {
    buddy2 = Buddy2Allocator.init(&buffer);
    // gpa = .{};
    allocator = buddy2.allocator();
    game_state = GameState.init(allocator);
    input_1 = .{ .player = 0 };
    player = Player.create(allocator, &game_state, 2 * 8, 12 * 8, &input_1) catch {
        tic.trace("SO OOM!");
        unreachable;
    };
    _ = Crumble.create(allocator, 10, 12, &game_state) catch unreachable;
    _ = Crumble.create(allocator, 12, 12, &game_state) catch unreachable;
    _ = Crumble.create(allocator, 14, 12, &game_state) catch unreachable;
}

export fn TIC() void {
    tic.cls(13);
    tic.map(.{});
    input_1.update();
    var it = game_state.objects.first;
    while (it) |node| {
        const obj = node.data;
        obj.update();
        obj.draw();

        if (obj.obj().destroyed) {
            game_state.objects.remove(node);
            obj.destroy(allocator);
            it = node.next;
            allocator.destroy(node);
            continue;
        }
        it = node.next;
    }

    game_state.time += 1;
}

export fn BDR() void {}

export fn OVR() void {}
