const GameState = @This();

const GameObject = @import("GameObject.zig");
const std = @import("std");
const tic = @import("tic80.zig");
const Level = @import("Level.zig");
const Player = @import("Player.zig");

pub const ObjectList = std.DoublyLinkedList(GameObject.IsGameObject);

objects: ObjectList,
time: u64 = 0,
allocator: std.mem.Allocator,
camera_x: i32 = 0,
camera_y: i32 = 0,
loaded_level: Level = undefined,
players: []const *Player,

pub fn init(allocator: std.mem.Allocator, players: []const *Player) GameState {
    const list: std.DoublyLinkedList(GameObject.IsGameObject) = .{};
    return .{ .allocator = allocator, .objects = list, .players = players };
}

pub fn wrap_node(self: *GameState, table: GameObject.IsGameObject) !*ObjectList.Node {
    var node = try self.allocator.create(ObjectList.Node);
    node.data = table;
    return node;
}

pub fn draw_spr(self: *GameState, id: i32, world_x: i32, world_y: i32, args: tic.SpriteArgs) void {
    tic.spr(id, world_x - self.camera_x, world_y - self.camera_y, args);
}

pub fn clean(self: *GameState) void {
    var it = self.objects.first;
    while (it) |node| : (it = node.next) {
        self.objects.remove(node);
        node.data.destroy(self.allocator);
        self.allocator.destroy(node);
    }
}

fn remap(x: i32, y: i32, info: *tic.RemapInfo) void {
    _ = x;
    _ = y;
    if (tic.fget(info.index, 1))
        info.index = 0;
}
pub fn loop(self: *GameState) void {
    tic.cls(13);
    // krill issue
    tic.map(.{ .remap = &remap });
    var it = self.objects.first;
    while (it) |node| : (it = node.next) {
        const obj = node.data;
        obj.update();
        obj.draw();

        if (obj.obj().destroyed) {
            self.objects.remove(node);
            obj.destroy(self.allocator);
            self.allocator.destroy(node);
        }
    }
    for (self.players) |player| {
        player.update();
        player.draw();
    }
    self.time += 1;
}
