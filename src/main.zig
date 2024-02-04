const tic = @import("tic80.zig");
const Player = @import("Player.zig");
const GameState = @import("GameState.zig");
const Input = @import("Input.zig");
const std = @import("std");
const Crumble = @import("Crumble.zig");

var buffer: [65565]u8 = undefined;
var game_state: GameState = undefined;
var input_1: Input = undefined;
var player: *Player = undefined;
var fba: std.heap.FixedBufferAllocator = undefined;
// var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
var allocator: std.mem.Allocator = undefined;
export fn BOOT() void {
    fba = std.heap.FixedBufferAllocator.init(&buffer);
    // gpa = .{};
    allocator = fba.allocator();
    game_state = GameState.init(allocator);
    input_1 = .{ .player = 0 };
    player = Player.create(allocator, &game_state, 2 * 8, 12 * 8, &input_1) catch {
        tic.trace("oom?");
        unreachable;
    };
    _ = Crumble.create(allocator, 11, 11, &game_state) catch unreachable;
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
