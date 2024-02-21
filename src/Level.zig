const Level = @This();

const tic = @import("tic80.zig");
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

pub const CamMode = enum {
    locked,
    follow_x,
    follow_y,
    free_follow,
};

pub const Entity = struct {
    pub const Kind = union(enum) {
        const SwitchBlock = struct {
            kind: u8,
            shootable: bool,
            touchable: bool,
        };
        const Door = struct {
            kind: u8,
            w: u16,
            h: u16,
            target: types.Point,
        };
        const Traffic = struct {
            w: u16,
            h: u16,
            target: types.Point,
        };
        switch_block: SwitchBlock,
        switch_door: Door,
        traffic_block: Traffic,
    };
    x: i32,
    y: i32,
    kind: Kind,
};
pub const Room = struct {
    box: types.Box,
    cam_mode: CamMode = .locked,
    death_bottom: bool = true,
    entities: ?[]const Entity = null,
    pub fn load_level(self: Room, state: *GameState) *Level {
        state.loaded_level = .{ .x = self.box.x, .y = self.box.y, .width = self.box.w, .height = self.box.h, .state = state, .cam_mode = self.cam_mode, .entities = self.entities };
        return &state.loaded_level;
    }
};
const level1_entities = [_]Entity{.{ .x = 3 * 8, .y = 6 * 8, .kind = .{ .traffic_block = .{ .w = 3, .h = 3, .target = .{ .x = 3 * 8, .y = 4 * 8 } } } }};
const level3_entities = [_]Entity{ .{ .x = 68 * 8, .y = 15 * 8, .kind = .{ .switch_door = .{ .kind = 0, .w = 4, .h = 1, .target = .{ .x = 98 * 8, .y = 15 * 8 } } } }, .{ .x = 110 * 8, .y = 13 * 8, .kind = .{ .traffic_block = .{ .w = 3, .h = 3, .target = .{ .x = 130 * 8, .y = 13 * 8 } } } } };
pub const rooms = [_]Room{ .{ .box = .{ .x = 0, .y = 0, .w = 30, .h = 17 }, .entities = &level1_entities }, .{ .box = .{
    .x = 30,
    .y = 0,
    .w = 30,
    .h = 17,
} }, .{ .box = .{ .x = 60, .y = 0, .w = 90, .h = 17 }, .cam_mode = .follow_x, .entities = &level3_entities } };
height: i32,
width: i32,
x: i32,
y: i32,
player_x: i32 = 0,
player_y: i32 = 0,
cam_mode: CamMode,
state: *GameState,
entities: ?[]const Entity = null,

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
    const player_x: i32 = @divFloor(player.game_object.x, 8);
    const player_y: i32 = @divFloor(player.game_object.y, 8);
    player_spawn: {
        var di: i32 = 1;
        var dj: i32 = 0;
        var segment_length: i32 = 1;

        var i: i32 = player_x;
        var j: i32 = player_y;
        var segment_passed: i32 = 0;
        const max_size = @max(self.width, self.height);
        const points = max_size * max_size;
        var k: i32 = 0;
        while (k < points) : (k += 1) {
            if (i >= self.x and i <= self.x + self.width and j >= self.y and j <= self.y + self.height and tic.mget(i, j) == 16) {
                self.player_x = i;
                self.player_y = j;
                break :player_spawn;
            }
            i += di;
            j += dj;

            segment_passed += 1;

            if (segment_passed == segment_length) {
                segment_passed = 0;

                const buf = di;
                di = -dj;
                dj = buf;

                if (dj == 0) {
                    segment_length += 1;
                }
            }
        }
        // YIPDEE!
        self.player_x = player_x;
        self.player_y = player_y;
    }
}
pub fn start(self: *Level) !void {
    self.state.clean(true);
    try self.init();
    self.state.snap_cam(self.x * 8, self.y * 8);
    self.state.player = try Player.create(self.state.allocator, self.state, self.player_x * 8, self.player_y * 8, self.state.input, self.state.voice);
}

pub fn init(self: *Level) !void {
    var y = self.y;
    while (y <= self.y + self.height) : (y += 1) {
        var x = self.x;
        while (x <= self.x + self.width) : (x += 1) {
            switch (tic.mget(x, y)) {
                7 => {
                    _ = try Crumble.create(self.state.allocator, self.state, x * 8, y * 8);
                },
                35 => {
                    _ = try Destructible.create(self.state.allocator, x, y, self.state);
                },
                17, 18, 19 => |it| {
                    const res = it - 16;
                    const touching = res & 0b10 != 0;
                    const shootable = res & 0b1 != 0;

                    _ = try Switch.create(self.state.allocator, self.state, x * 8, y * 8, .{ .is_gun = shootable, .is_touch = touching });
                },
                20 => {
                    _ = try SwitchDoor.create(self.state.allocator, self.state, x * 8, y * 8, .{ .kind = 0, .w = 1, .h = 1, .target = .{ .x = 0, .y = 0 } });
                },
                51, 52, 53, 54 => |it| {
                    _ = try Spike.create(self.state.allocator, self.state, x * 8, y * 8, @enumFromInt(@as(u2, @intCast(it - 51))));
                },
                48 => {
                    _ = try Checkpoint.create(self.state.allocator, self.state, x, y);
                },
                16 => {
                    if (self.player_x == 0 and self.player_y == 0) {
                        self.player_x = x;
                        self.player_y = y;
                    }
                },
                else => {},
            }
        }
    }

    if (self.entities) |entities| {
        for (entities) |entity| {
            switch (entity.kind) {
                .switch_block => |block| {
                    _ = try Switch.create(self.state.allocator, self.state, entity.x, entity.y, .{ .is_gun = block.shootable, .is_touch = block.touchable, .kind = block.kind });
                },
                .switch_door => |door| {
                    _ = try SwitchDoor.create(self.state.allocator, self.state, entity.x, entity.y, .{ .kind = door.kind, .w = door.w, .h = door.h, .target = door.target });
                },
                .traffic_block => |traffic| {
                    _ = try TrafficBlock.create(self.state, entity.x, entity.y, traffic.w, traffic.h, traffic.target);
                },
            }
        }
    }
}
pub fn reset(self: *Level) !void {
    try self.start();
}

pub fn find_at(world_x: i32, world_y: i32) ?Room {
    const tile_x: i32 = @divFloor(world_x, 8);
    const tile_y: i32 = @divFloor(world_y, 8);
    for (rooms) |room| {
        if (room.box.contains(tile_x, tile_y)) {
            return room;
        }
    }
    return null;
}
