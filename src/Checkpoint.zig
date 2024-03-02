const Checkpoint = @This();

const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const tdraw = @import("draw.zig");
const tic = @import("common").tic;
const Voice = @import("Audio.zig").Voice;
const Player = @import("Player.zig");

pub const vtable: GameObject.VTable = .{ .ptr_draw = &draw, .get_object = &get_object, .destroy = &destroy, .ptr_update = &update, .touch = &touch, .can_touch = &can_touch };

const CheckpointList = std.DoublyLinkedList(*Checkpoint);
var checkpoints: CheckpointList = .{};
current: bool = false,
game_object: GameObject,
tile_x: i32,
tile_y: i32,
t_flag_anim: u8 = 0,
voice: *Voice,

pub fn create(allocator: Allocator, state: *GameState, tile_x: i32, tile_y: i32) !*Checkpoint {
    var obj = GameObject.create(state, tile_x * 8, tile_y * 8);
    obj.touchable = true;
    const self = try allocator.create(Checkpoint);
    self.game_object = obj;
    self.tile_x = tile_x;
    self.tile_y = tile_y;
    self.current = false;
    self.voice = state.voice;

    if (state.loaded_level.player_x == tile_x and state.loaded_level.player_y == tile_y) {
        self.current = true;
        self.t_flag_anim = 8;
    }
    const node = try state.wrap_node(.{ .ptr = self, .table = vtable });
    state.objects.append(node);

    const ck_node = try allocator.create(CheckpointList.Node);
    ck_node.data = self;
    checkpoints.append(ck_node);

    return self;
}

fn palette(current: bool) void {
    if (current) {
        tic.PALETTE_MAP.color1 = 5;
    }
}
fn get_object(ptr: *anyopaque) *GameObject {
    const self: *Checkpoint = @alignCast(@ptrCast(ptr));
    return &self.game_object;
}
fn draw(ptr: *anyopaque) void {
    const self: *Checkpoint = @alignCast(@ptrCast(ptr));

    defer tdraw.reset_pallete();

    const current = self.t_flag_anim >= 3;
    palette(current);

    const spr: i32 =
        switch (self.t_flag_anim / 2) {
        1, 4 => 305,
        2, 3 => 306,
        5 => 307,
        else => 304,
    };
    self.game_object.game_state.draw_spr(spr, self.game_object.x, self.game_object.y, .{ .transparent = &.{0} });
}

fn destroy(ptr: *anyopaque, allocator: Allocator) void {
    const self: *Checkpoint = @alignCast(@ptrCast(ptr));
    allocator.destroy(self);
    {
        var it = checkpoints.first;
        while (it) |node| : (it = node.next) {
            if (node.data == self) {
                checkpoints.remove(node);
            }
        }
    }
}

fn update(ptr: *anyopaque) void {
    const self: *Checkpoint = @alignCast(@ptrCast(ptr));
    if (self.current and self.t_flag_anim < 16) {
        self.t_flag_anim += 1;
    }
    if (self.t_flag_anim == 6)
        self.voice.play(3, .{ .volume = 8 });
}

fn touch(ctx: *anyopaque, player: *Player) void {
    _ = player;
    const self: *Checkpoint = @alignCast(@ptrCast(ctx));

    {
        var it = checkpoints.first;
        while (it) |node| : (it = node.next) {
            const ck = node.data;
            ck.current = false;
            ck.t_flag_anim = 0;
        }
    }

    self.t_flag_anim = 0;
    self.current = true;

    self.game_object.game_state.loaded_level.player_x = self.tile_x;
    self.game_object.game_state.loaded_level.player_y = self.tile_y;
}

fn can_touch(ctx: *anyopaque, player: *Player) bool {
    _ = player;

    const self: *Checkpoint = @alignCast(@ptrCast(ctx));

    return !self.current;
}
