const GameState = @This();

const GameObject = @import("GameObject.zig");
const std = @import("std");
const tic = @import("common").tic;
const Level = @import("Level.zig");
const Player = @import("Player.zig");
const Screenwipe = @import("Screenwipe.zig");
const types = @import("types.zig");
const Voice = @import("Audio.zig").Voice;
const Input = @import("Input.zig");
const sheets = @import("sheets.zig");

pub const ObjectList = std.DoublyLinkedList(GameObject.IsGameObject);

objects: ObjectList,
time: u64 = 0,
allocator: std.mem.Allocator,
camera_x: i32 = 0,
camera_y: i32 = 0,
pan_speed: i16 = 5,
loaded_level: Level = undefined,
input: *Input,
screenwipe: Screenwipe = .{},
panning: bool = false,
current_player_spawn: types.Point = .{ .x = 0, .y = 0 },
voice: *Voice,
// voice for extra effects
aux_voice: *Voice,
player: ?*Player = null,
reset_scheduled: bool = false,

pub fn init(allocator: std.mem.Allocator, input: *Input, voice: *Voice, aux_voice: *Voice) GameState {
    const list: std.DoublyLinkedList(GameObject.IsGameObject) = .{};
    return .{ .allocator = allocator, .objects = list, .input = input, .voice = voice, .aux_voice = aux_voice };
}

pub fn wrap_node(self: *GameState, table: GameObject.IsGameObject) !*ObjectList.Node {
    var node = try self.allocator.create(ObjectList.Node);
    node.data = table;
    return node;
}

pub fn draw_spr(self: *GameState, id: i32, world_x: i32, world_y: i32, args: tic.SpriteArgs) void {
    tic.spr(id, world_x - self.camera_x, world_y - self.camera_y, args);
}

pub fn clean(self: *GameState, kill_player: bool) void {
    var it = self.objects.first;
    if (kill_player) {
        self.player = null;
    }
    while (it) |node| : (it = node.next) {
        if (kill_player or node.data.obj().special_type != .player) {
            self.objects.remove(node);
            node.data.destroy(self.allocator);
            self.allocator.destroy(node);
        }
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
pub fn snap_cam(self: *GameState, x: i32, y: i32) void {
    self.camera_x = x;
    self.camera_y = y;
}

pub fn center_x(self: *GameState, on: i32) void {
    const half_width = tic.WIDTH / 2;
    const x_center = self.camera_x + half_width;

    if (on > x_center) {
        self.camera_x = @min(on - half_width, (self.loaded_level.x + self.loaded_level.width) * 8 - tic.WIDTH);
    } else {
        self.camera_x = @max(on - half_width, self.loaded_level.x * 8);
    }
}
pub fn center_y(self: *GameState, on: i32) void {
    const half_height = tic.HEIGHT / 2;
    const y_center = self.camera_y + half_height;

    if (on > y_center) {
        self.camera_y = @min(on - half_height, (self.loaded_level.y + self.loaded_level.height) * 8 - tic.HEIGHT);
    } else {
        self.camera_y = @max(on - half_height, self.loaded_level.y * 8);
    }
}

pub fn loop(self: *GameState) void {
    tic.cls(13);
    _ = tic.vbank(1);
    tic.cls(0);
    _ = tic.vbank(0);
    const should_update = self.screenwipe.infade > 45 and !self.panning and self.screenwipe.level_wipe > 45;
    // krill issue

    const ccx = @divFloor(self.camera_x, 8);
    const ccy = @divFloor(self.camera_y, 8);

    tic.map(.{ .remap = &remap, .x = ccx, .w = 32, .y = ccy, .h = 18, .sx = -@rem(self.camera_x, 8), .sy = -@rem(self.camera_y, 8) });
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
    if (self.player) |player| player: {
        if (player.game_object.y > (self.loaded_level.y + self.loaded_level.height) * 8) {
            if (player.state != .death) {
                player.die();
                break :player;
            }
        }

        if ((player.game_object.x > (self.loaded_level.x + self.loaded_level.width) * 8) or (player.game_object.x < self.loaded_level.x * 8) or (player.game_object.y > (self.loaded_level.y + self.loaded_level.height) * 8) or (player.game_object.y < self.loaded_level.y * 8)) {
            // TODO: Multiplayer
            const room = Level.find_at(player.game_object.x, player.game_object.y);
            if (room) |r| {
                // screen refill
                player.refill_dashes();
                tic.sfx(-1, .{});
                self.voice.play(null, .{});
                Level.from_saved(&r, self).load() catch unreachable;
            } else {
                // ???
                if (player.state != .death) {
                    player.die();
                }
            }
        }
    }
    if (self.screenwipe.level_wipe == 44) {
        self.screenwipe.infade = 0;
    }
    self.screenwipe.update();
    self.screenwipe.draw();
    self.time += 1;
    if (self.player) |player| {
        switch (self.loaded_level.cam_mode) {
            .locked => {},
            .follow_x => {
                self.center_x(player.game_object.x);
            },
            .follow_y => {
                self.center_y(player.game_object.y);
            },
            .free_follow => {
                const host = player;
                self.center_x(host.game_object.x);
                self.center_y(host.game_object.y);
            },
        }
    }
    if (self.reset_scheduled) {
        self.loaded_level.reset() catch unreachable;
        self.reset_scheduled = false;
    }
    self.draw_overlay();
}

fn draw_overlay(self: *GameState) void {
    if (self.player) |player| {
        tic.spr(sheets.bullet_ui.items[player.midair_shot_count], 2, tic.HEIGHT - 18, .{ .transparent = &.{0}, .w = 2, .h = 2 });
    }
}

pub fn check_solid_box(self: *GameState, box: types.Box) bool {
    var i: i32 = @divFloor(box.x, 8);

    const imax = @divFloor(box.x + box.w - 1, 8);
    const jmin = @divFloor(box.y, 8);
    const jmax = @divFloor(box.y + box.h - 1, 8);
    while (i <= imax) : (i += 1) {
        var j: i32 = jmin;
        while (j <= jmax) : (j += 1) {
            if (tic.fget(tic.mget(i, j), 0)) {
                return true;
            }
        }
    }

    {
        // ignore player
        var it = self.objects.first;
        while (it) |node| : (it = node.next) {
            var obj = node.data;
            const gameobj = obj.obj();
            if (gameobj.solid and !gameobj.destroyed and gameobj.overlaps_box(0, 0, box)) {
                return true;
            }
        }
    }

    return false;
}

pub fn check_solid_point(self: *GameState, point: types.Point) bool {
    const i = @divFloor(point.x, 8);
    const j = @divFloor(point.y, 8);
    if (tic.fget(tic.mget(i, j), 0)) {
        return true;
    }

    {
        var it = self.objects.first;
        while (it) |node| : (it = node.next) {
            var obj = node.data;
            const gameobj = obj.obj();
            if (gameobj.solid and !gameobj.destroyed and gameobj.world_hitbox().contains(point.x, point.y)) {
                return true;
            }
        }
    }

    return false;
}

pub fn shot_hitbox(self: *GameState, box: types.Box, strength: u8) void {
    {
        var it = self.objects.first;
        while (it) |node| : (it = node.next) {
            var obj = node.data;
            const gameobj = obj.obj();
            if (gameobj.special_type == .player) continue;
            if (!gameobj.destroyed and gameobj.world_hurtbox().overlapping(box)) {
                obj.shot(strength);
            }
        }
    }
}
