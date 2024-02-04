const GameState = @This();

const GameObject = @import("GameObject.zig");
const std = @import("std");

pub const ObjectList = std.DoublyLinkedList(GameObject.IsGameObject);

objects: ObjectList,
time: u64 = 0,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) GameState {
    const list: std.DoublyLinkedList(GameObject.IsGameObject) = .{};
    return .{ .allocator = allocator, .objects = list };
}

pub fn wrap_node(self: *GameState, table: GameObject.IsGameObject) !*ObjectList.Node {
    var node = try self.allocator.create(ObjectList.Node);
    node.data = table;
    return node;
}
