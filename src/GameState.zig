const GameState = @This();

const GameObject = @import("GameObject.zig");
const std = @import("std");
const tic = @import("tic80.zig");
const Level = @import("Level.zig");
const Player = @import("Player.zig");
const Screenwipe = @import("Screenwipe.zig");
const types = @import("types.zig");

pub const ObjectList = std.DoublyLinkedList(GameObject.IsGameObject);

objects: ObjectList,
time: u64 = 0,
allocator: std.mem.Allocator,
camera_x: i32 = 0,
camera_y: i32 = 0,
target_cam_x: i32 = 0,
target_cam_y: i32 = 0,
pan_speed: i16 = 5,
loaded_level: Level = undefined,
players: []const *Player,
screenwipe: Screenwipe = .{},
panning: bool = false,

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
    self.screenwipe.reset();
}

fn remap(x: i32, y: i32, info: *tic.RemapInfo) void {
    _ = x;
    _ = y;
    if (tic.fget(info.index, 1))
        info.index = 0;
}

pub fn camera(self: *const GameState) types.Point {
    return .{ .x = self.camera_x, .y = self.camera_y };
}
pub fn loop(self: *GameState) void {
    tic.cls(13);
    const should_update = self.screenwipe.infade > 45 and !self.panning and self.screenwipe.level_wipe > 45;
    // krill issue
    const ccx = @divTrunc(self.camera_x, 8) + @as(i32, if (@mod(self.camera_x, 8) == 0) 1 else 0);
    const ccy = @divTrunc(self.camera_y, 8) + @as(i32, if (@mod(self.camera_y, 8) == 0) 1 else 0);
    tic.map(.{ .remap = &remap, .x = ccx - 1, .w = 32, .y = ccy - 1, .h = 17, .sx = @rem(self.camera_x, 8), .sy = @rem(self.camera_y, 8) });
    {
        var it = self.objects.first;
        while (it) |node| : (it = node.next) {
            const obj = node.data;
            if (should_update)
                obj.update();
            obj.draw();

            if (obj.obj().destroyed) {
                self.objects.remove(node);
                obj.destroy(self.allocator);
                self.allocator.destroy(node);
            }
        }
    }
    for (self.players) |player| {
        if (should_update)
            player.update();
        player.draw();
    }
    if (self.screenwipe.level_wipe == 44) {
        self.camera_x = self.target_cam_x;
        self.camera_y = self.target_cam_y;
        self.screenwipe.infade = 0;
    }
    self.screenwipe.update();
    self.screenwipe.draw();
    self.time += 1;
    if ((self.camera_x != self.target_cam_x or self.camera_y != self.target_cam_y) and self.screenwipe.level_wipe > 45) {
        self.screenwipe.level_wipe = 0;
    }
}
