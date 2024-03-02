const Level = @This();

const tic = @import("common").tic;
const SavedLevel = @import("common").Level;
const std = @import("std");
const GameState = @import("GameState.zig");
const Player = @import("Player.zig");
const Destructible = @import("Destructible.zig");
const Spike = @import("Spike.zig");
const Crumble = @import("Crumble.zig");
const types = @import("types.zig");
const Checkpoint = @import("Checkpoint.zig");
const Switch = @import("Switch.zig");
const SwitchDoor = @import("SwitchDoor.zig");
const TrafficBlock = @import("TrafficBlock.zig");

height: i32,
width: i32,
x: i32,
y: i32,
player_x: i32 = 0,
player_y: i32 = 0,
cam_mode: SavedLevel.CamMode,
state: *GameState,
entities: []const SavedLevel.Entity,
player_starts: [64]types.Point = undefined,

// ???
pub var rooms: []SavedLevel = undefined;

pub fn from_saved(saved: *const SavedLevel, state: *GameState) *Level {
    state.loaded_level = .{
        .height = saved.height,
        .width = saved.width,
        .x = saved.x,
        .y = saved.y,
        .cam_mode = saved.cam_mode,
        .state = state,
        .entities = saved.entities,
    };
    return &state.loaded_level;
}
pub fn load(self: *Level) !void {
    self.state.clean(false);
    if (self.state.objects.pop()) |p_node| {
        self.state.allocator.destroy(p_node);
    }
    try self.init();
    self.state.snap_cam(self.x * 8, self.y * 8);
    const player = self.state.player orelse return;
    {
        const node = try self.state.wrap_node(player.as_table());
        self.state.objects.append(node);
    }
    const player_p = player.game_object.point().times(1 / 8).trunc();
    {
        var lowest: types.Point = .{ .x = -1, .y = -1 };
        var lowest_d: f32 = std.math.inf(f32);
        for (self.player_starts) |ps| {
            if (ps.x == -1 and ps.y == -1)
                break;
            const d = player_p.distance_squared(ps.as_float());
            if (d < lowest_d) {
                lowest = ps;
                lowest_d = d;
            }
        }
        self.player_x = lowest.x;
        self.player_y = lowest.y;
    }
}
pub fn start(self: *Level) !void {
    self.state.clean(true);
    try self.init();
    self.state.snap_cam(self.x * 8, self.y * 8);
    self.state.player = try Player.create(self.state.allocator, self.state, self.player_x * 8, self.player_y * 8, self.state.input, self.state.voice);
}

pub fn init(self: *Level) !void {
    var pstart_index: u7 = 0;
    @memset(&self.player_starts, .{ .x = -1, .y = -1 });
    for (self.entities) |entity| {
        switch (entity.kind) {
            .switch_coin => |block| {
                _ = try Switch.create(self.state.allocator, self.state, entity.x, entity.y, .{ .is_gun = block.shootable, .is_touch = block.touchable, .kind = block.kind });
            },
            .switch_door => |door| {
                _ = try SwitchDoor.create(self.state.allocator, self.state, entity.x, entity.y, .{ .kind = door.kind, .w = @divFloor(entity.w, 8), .h = @divFloor(entity.h, 8), .target = door.target });
            },
            .traffic_block => |traffic| {
                _ = try TrafficBlock.create(self.state, entity.x, entity.y, @divFloor(entity.w, 8), @divFloor(entity.h, 8), traffic.target);
            },
            .destructible => |d| {
                _ = try Destructible.create(self.state.allocator, entity.x, entity.y, d.shoot_only, self.state);
            },
            .crumble => {
                _ = try Crumble.create(self.state.allocator, self.state, entity.x, entity.y);
            },
            .player_start => |p| {
                const x = @divFloor(entity.x, 8);
                const y = @divFloor(entity.y, 8);
                if (p and self.player_x == 0 and self.player_y == 0) {
                    self.player_x = x;
                    self.player_y = y;
                }
                self.player_starts[pstart_index] = .{ .x = x, .y = y };
                pstart_index += 1;
            },
            .spike => |s| {
                _ = try Spike.create(self.state.allocator, self.state, entity.x, entity.y, s.direction, @divFloor(@max(entity.w, entity.h), 8));
            },
        }
    }
}
pub fn reset(self: *Level) !void {
    try self.start();
}

pub fn find_at(world_x: i32, world_y: i32) ?SavedLevel {
    const tile_x: i32 = @divFloor(world_x, 8);
    const tile_y: i32 = @divFloor(world_y, 8);
    for (rooms) |room| {
        const box = types.Box{ .x = room.x, .y = room.y, .w = room.width, .h = room.height };
        if (box.contains(tile_x, tile_y)) {
            return room;
        }
    }
    return null;
}
