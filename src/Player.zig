const Player = @This();

const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const Input = @import("Input.zig");
const tic80 = @import("tic80.zig");
const std = @import("std");
const Bullet = @import("Bullet.zig");
const tdraw = @import("draw.zig");
const Audio = @import("Audio.zig");
const Crumble = @import("Crumble.zig");
const Voice = Audio.Voice;
const Allocator = std.mem.Allocator;
const types = @import("types.zig");

const State = enum { normal, death, dash, grapple_start, grapple_attach, grapple_pull };
const Mode = enum { none, dash, grapple };

pub const vtable: GameObject.VTable = .{ .ptr_update = @ptrCast(&update), .ptr_draw = @ptrCast(&draw), .get_object = @ptrCast(&get_object), .destroy = @ptrCast(&destroy), .as_rider = &as_rider };
const rider_vtable: GameObject.IRide.VTable = .{ .riding_platform_moved = &riding_platform_moved, .riding_platform_check = &riding_platform_check, .riding_platform_set_velocity = &riding_platform_set_velocity };

fn as_rider(ctx: *anyopaque) GameObject.IRide {
    return .{ .ctx = ctx, .table = &rider_vtable };
}

state: State = .normal,
t_var_jump: u32 = 0,
t_jump_grace: u8 = 0,
var_jump_speed: f32 = 0,
auto_var_jump: bool = false,
jump_grace_y: i32 = 0,
game_object: GameObject,
spr: i32 = 512,
input: *Input,
t_shoot_cooldown: u8 = 0,
allocator: std.mem.Allocator,
t_fire_pose: u8 = 0,
fire_dir: Bullet.Direction = .up,
t_death: u8 = 0,
voice: *Voice,
mode: Mode = .dash,
t_dash_time: u8 = 0,
can_dash: bool = true,
host: bool = false,
// doesn't affect hitbox, only used for detecting wave and hyper dashes
crouching: bool = false,
down_dash: bool = false,
t_recharge: u8 = 0,
recharging: bool = false,
t_platform_velocity_storage: u8 = 0,
platform_velocity: types.PointF = .{ .x = 0, .y = 0 },

pub fn create(allocator: Allocator, state: *GameState, x: i32, y: i32, input: *Input, voice: *Voice) !*Player {
    var obj = GameObject.create(state, x, y);
    // obj.x += 4;
    // obj.y += 8;
    // ???
    obj.hit_x = 2;
    obj.hit_y = 2;
    obj.hit_w = 5;
    obj.hit_h = 6;
    obj.persistent = true;
    obj.special_type = .player;

    const self = try allocator.create(Player);

    self.* = .{ .game_object = obj, .input = input, .allocator = allocator, .voice = voice };

    const node = try state.wrap_node(.{ .ptr = self, .table = vtable });
    state.objects.append(node);
    return self;
}

fn destroy(self: *Player, allocator: Allocator) void {
    _ = self;
    _ = allocator;
}
fn get_object(self: *Player) *GameObject {
    return &self.game_object;
}

fn approach(x: f32, target: f32, max_delta: f32) f32 {
    return if (x < target) @min(x + max_delta, target) else @max(x - max_delta, target);
}

fn shoot(self: *Player) void {
    _ = self.input.consume_gun_press();
    const dir: Bullet.Direction = blk: {
        if (self.input.input_y == -1) {
            break :blk .up;
        }
        if (self.input.input_y == 1) {
            break :blk .down;
        }
        if (self.game_object.facing == -1) {
            break :blk .left;
        }
        if (self.game_object.facing == 1) {
            break :blk .right;
        }
        return;
    };
    self.t_shoot_cooldown = 6;
    self.t_fire_pose = 8;
    self.fire_dir = dir;
    const x_offset: i32 =
        switch (dir) {
        .up, .down => 0,
        .left => -8,
        .right => 0,
    };
    _ = Bullet.create(self.allocator, self.game_object.game_state, self.game_object.x + x_offset, self.game_object.y, self.input.player, dir) catch |err| {
        switch (err) {
            error.TooMany => {},
            error.OutOfMemory => {
                tic80.trace("oom?");
            },
        }
        return;
    };
    tic80.sfx(3, .{ .duration = 10, .volume = 5 });
}
fn raw_jump(self: *Player, play_sound: bool) bool {
    _ = self.input.consume_jump_press();
    self.state = .normal;
    self.game_object.speed_y = -4;
    self.var_jump_speed = -4;
    self.game_object.speed_x += @as(f32, @floatFromInt(self.input.input_x)) * 0.2;
    self.t_var_jump = 4;
    self.t_jump_grace = 0;
    self.auto_var_jump = false;
    const did_play = self.add_platform_velocity(play_sound);
    _ = vtable.move_y(self, @floatFromInt(self.jump_grace_y - self.game_object.y), null);
    return did_play;
}

fn jump(self: *Player) void {
    const did_play = self.raw_jump(true);
    if (!did_play) {
        self.voice.play(5, .{ .volume = 5 });
    }
}

fn super_dash(self: *Player, recover: bool) void {
    self.game_object.speed_x = std.math.sign(self.game_object.speed_x) * 3;
    _ = self.raw_jump(false);
    self.can_dash = recover;
    self.reset_dash_info();
    self.voice.play(2, .{ .volume = 5 });
}
fn dash_jump(self: *Player, recover: bool) void {
    _ = self.input.consume_jump_press();
    self.state = .normal;
    self.game_object.speed_y = -2;
    self.var_jump_speed = -2;
    self.game_object.speed_x += @as(f32, @floatFromInt(self.input.input_x)) * 0.5;
    self.t_var_jump = 4;
    self.t_jump_grace = 0;
    self.auto_var_jump = false;
    self.reset_dash_info();
    self.can_dash = recover;
    _ = self.add_platform_velocity(false);
    self.voice.play(2, .{ .volume = 5 });
    _ = vtable.move_y(self, @floatFromInt(self.jump_grace_y - self.game_object.y), null);
}
fn wall_bounce(self: *Player, dir: i2) void {
    _ = self.input.consume_jump_press();
    self.state = .normal;
    self.game_object.speed_y = -5;
    self.var_jump_speed = -5;
    // =, not +=
    self.game_object.speed_x = @as(f32, @floatFromInt(dir)) * -2;
    self.t_var_jump = 4;
    self.auto_var_jump = false;
    self.game_object.facing = -dir;
    _ = vtable.move_x(self, @floatFromInt(-@as(i32, dir) * 3), null);
    self.voice.play(2, .{ .volume = 5 });
}

fn reset_dash_info(self: *Player) void {
    self.recharging = false;
    self.t_recharge = 0;
}
fn wall_jump(self: *Player, dir: i2) void {
    _ = self.input.consume_jump_press();
    self.state = .normal;
    self.game_object.speed_y = -3;
    self.var_jump_speed = -3;
    self.game_object.speed_x = @floatFromInt(3 * @as(i32, dir));
    self.t_var_jump = 4;
    self.auto_var_jump = false;
    self.game_object.facing = dir;
    _ = vtable.move_x(self, @floatFromInt(-@as(i32, dir) * 3), null);
    self.voice.play(5, .{ .volume = 5 });
}

fn dash(self: *Player) void {
    _ = self.input.consume_action_press();
    self.state = .dash;
    self.can_dash = false;
    self.recharging = false;
    self.t_recharge = 0;
    self.down_dash = self.input.input_y > 0;
    const x_dir =
        if (self.input.input_x == 0 and self.input.input_y == 0)
        self.game_object.facing
    else
        self.input.input_x;
    const x_speed: f32 =
        if (x_dir != 0 and @as(i2, @intFromFloat(std.math.sign(self.game_object.speed_x))) == x_dir)
        if (x_dir == 1)
            @max(4, self.game_object.speed_x)
        else
            @min(-4, self.game_object.speed_y)
    else
        4 * @as(f32, @floatFromInt(x_dir));
    self.game_object.speed_x = x_speed;
    self.game_object.speed_y = @as(f32, @floatFromInt(self.input.input_y)) * 4;
    self.t_dash_time = 8;
    self.voice.play(4, .{ .volume = 5 });
}
fn end_dash(self: *Player) void {
    self.state = .normal;
    if (!self.down_dash) {
        self.game_object.speed_x = 2 * std.math.sign(self.game_object.speed_x);
        self.game_object.speed_y = 2 * std.math.sign(self.game_object.speed_y);
    }
}
pub fn die(self: *Player) void {
    self.state = .death;
    self.t_death = 0;
    self.voice.play(1, .{ .volume = 10 });
    // self.voice.sfx(5, 10, 0);
}

fn touching_wall(self: *Player) i2 {
    if (self.game_object.check_solid(-1, 0))
        return -1;
    if (self.game_object.check_solid(1, 0))
        return 1;
    return 0;
}
pub fn update(self: *Player) void {
    const on_ground = self.game_object.check_solid(0, 1);
    if (on_ground) {
        self.t_jump_grace = 8;
        self.jump_grace_y = self.game_object.y;
    } else {
        if (self.t_jump_grace > 0)
            self.t_jump_grace -= 1;
    }
    if (self.t_shoot_cooldown > 0)
        self.t_shoot_cooldown -= 1;
    if (self.t_fire_pose > 0)
        self.t_fire_pose -= 1;
    if (self.t_recharge > 0)
        self.t_recharge -= 1;
    if (self.t_platform_velocity_storage > 0)
        self.t_platform_velocity_storage -= 1;
    var sliding = false;
    switch (self.state) {
        .normal => {
            if (self.input.input_x != 0) {
                self.game_object.facing = self.input.input_x;
            }

            if (on_ground) {
                if (self.input.input_y > 0) {
                    self.crouching = true;
                } else {
                    self.crouching = false;
                }
            }

            var target: f32 = 0;
            var accel: f32 = 0.2;
            if (std.math.sign(self.game_object.speed_x) * self.game_object.speed_x > 2 and self.input.input_x == @as(i2, @intFromFloat(std.math.sign(self.game_object.speed_x)))) {
                target = 1;
                accel = 0.05;
            } else if (on_ground) {
                target = 1;
                if (self.crouching) {
                    accel = 0.25;
                } else {
                    accel = 0.4;
                }
            } else if (self.input.input_x != 0) {
                target = 1;
                accel = 0.2;
            }
            self.game_object.speed_x = approach(self.game_object.speed_x, @as(f32, @floatFromInt(self.input.input_x)) * target, accel);

            if (!on_ground) {
                self.recharging = false;
                self.t_recharge = 0;
                const fast_fall: f32 = if (self.input.input_y == 1) 2.6 else 2;
                if (self.input.input_x != 0) {
                    sliding = self.game_object.check_solid(self.input.input_x, 0);
                }
                const slide_penalty: f32 = if (sliding) 1 else 0;
                const max = fast_fall - slide_penalty;

                if (std.math.sign(self.game_object.speed_y) * self.game_object.speed_y < 0.2 and self.input.input_jump) {
                    self.game_object.speed_y = @min(self.game_object.speed_y + 0.2, max);
                } else {
                    self.game_object.speed_y = @min(self.game_object.speed_y + 0.8, max);
                }
            } else {
                if (!self.can_dash and self.t_recharge == 0) {
                    if (self.recharging) {
                        self.recharging = false;
                        self.can_dash = true;
                    } else {
                        self.recharging = true;
                        self.t_recharge = 6;
                    }
                }
            }

            if (self.t_var_jump > 0) {
                if (self.input.input_jump or self.auto_var_jump) {
                    self.game_object.speed_y = self.var_jump_speed;
                    self.t_var_jump -= 1;
                } else {
                    self.t_var_jump = 0;
                }
            }

            if (self.input.input_jump_pressed > 0) {
                if (self.t_jump_grace > 0) {
                    self.jump();
                } else if (sliding) {
                    self.wall_jump(-self.input.input_x);
                }
            }
            if (self.input.input_gun_pressed > 0) {
                if (self.t_shoot_cooldown == 0)
                    self.shoot();
            }
            if (self.input.input_action_pressed > 0) {
                switch (self.mode) {
                    .grapple => {},
                    .dash => {
                        if (self.can_dash)
                            self.dash();
                    },
                    .none => {},
                }
            }
        },
        .dash => {
            self.t_dash_time -= 1;

            if (self.down_dash and on_ground) {
                self.crouching = true;
            }

            if (self.input.input_jump_pressed > 0) {
                if (!on_ground and self.touching_wall() != 0) {

                    // womp womp
                    self.wall_bounce(self.touching_wall());
                } else if (self.t_jump_grace > 0) {
                    if (self.crouching) {
                        self.dash_jump(on_ground);
                    } else {
                        self.super_dash(on_ground);
                    }
                }
            }
            if (self.t_dash_time == 0) {
                self.end_dash();
            }
        },
        .grapple_start => {},
        .grapple_attach => {},
        .grapple_pull => {},
        .death => {
            self.t_death += 1;
            self.game_object.game_state.screenwipe.wipe_timer += 1;
            if (self.game_object.game_state.screenwipe.wipe_timer > 40) {
                // this will destroy us!
                self.game_object.game_state.reset_scheduled = true;
            }
            return;
        },
    }

    // apply
    const gravity_multiplier: f32 = if (self.t_fire_pose > 0 and self.game_object.speed_y > 0) 0.2 else 1;
    vtable.move(self, .{ .x = self.game_object.speed_x, .y = self.game_object.speed_y * gravity_multiplier }, move_args);

    // sprite
    if (self.state == .dash) {
        self.spr = 538;
    } else if (self.t_fire_pose > 0) {
        self.spr = switch (self.fire_dir) {
            .right, .left => 527,
            .up => 528,
            .down => 529,
        };
    } else if (!on_ground) {
        if (sliding) {
            self.spr = 522;
        } else {
            if (self.game_object.speed_y > 0) {
                self.spr = 517;
            } else {
                self.spr = 515;
            }
        }
    } else if (self.input.input_x != 0) {
        if (self.crouching) {
            const frame = @divFloor(self.game_object.game_state.time, 9);
            self.spr = 560 + @as(i32, @intCast(frame % 3));
        } else {
            const frame = @divFloor(self.game_object.game_state.time, 8);
            self.spr = 513 + @as(i32, @intCast(frame % 4));
        }
    } else {
        if (self.crouching) {
            self.spr = 560;
        } else {
            self.spr = 512;
        }
    }

    // object interactions
    {
        var it = self.game_object.game_state.objects.first;
        while (it) |node| : (it = node.next) {
            const o = node.data;
            const obj = o.obj();

            if (obj.touchable) {
                if (o.can_touch(self) and obj.overlaps_box(0, 0, self.sniff_zone())) {
                    o.touch(self);
                }
            }
        }
    }

    // death triggers
    switch (self.state) {
        .death => {},

        else => {
            if (self.hazard_check(.{})) {
                self.die();
            }
        },
    }
}
const HazardArgs = struct {
    ox: i32 = 0,
    oy: i32 = 0,
};
pub fn hazard_check(self: *Player, args: HazardArgs) bool {
    var it = self.game_object.game_state.objects.first;
    while (it) |node| : (it = node.next) {
        const o = node.data;
        const obj = o.obj();
        if (obj.hazard != .none and self.game_object.overlaps(o, args.ox, args.oy)) {
            const res = switch (obj.hazard) {
                .none => unreachable,
                .all => true,
                .up => self.game_object.speed_y >= 0,
                .down => self.game_object.speed_y <= 0,
                .right => self.game_object.speed_x <= 0,
                .left => self.game_object.speed_x >= 0,
            };
            if (res)
                return true;
        }
    }
    {
        var i: i32 = @divFloor(self.game_object.x + self.game_object.hit_x, 8);
        // in 4k?
        const imax = @divFloor(self.game_object.x + self.game_object.hit_x + @as(i32, self.game_object.hit_w) - 1, 8);
        const jmin = @divFloor(self.game_object.y + self.game_object.hit_y, 8);
        const jmax = @divFloor(self.game_object.y + self.game_object.hit_y + @as(i32, self.game_object.hit_h) - 1, 8);

        while (i <= imax) {
            var j = jmin;
            while (j <= jmax) {
                if (tic80.fget(tic80.mget(i, j), 2)) {
                    return true;
                }
                j += 1;
            }
            i += 1;
        }
    }
    return false;
}
const CornerCorrectArgs = struct {
    func: ?*const fn (*Player, i32, i32) bool = null,
    only_sign: i2 = 1,
};
pub fn corner_correct(self: *Player, dir_x: i32, dir_y: i32, side_dist: usize, args: CornerCorrectArgs) bool {
    const only_sign = args.only_sign;
    const func = args.func;
    if (dir_x != 0) {
        for (1..side_dist) |i| {
            for ([_]i2{ -1, 1 }) |s| {
                if (s == -only_sign) {
                    continue;
                }

                if (!self.game_object.check_solid(dir_x, @as(i32, @intCast(i)) * s)) {
                    const res =
                        if (func) |f| f(self, dir_x, @as(i32, @intCast(i)) * s) else true;
                    if (res) {
                        self.game_object.x += dir_x;
                        self.game_object.y += @as(i32, @intCast(i)) * s;
                        return true;
                    }
                }
            }
        }
    } else if (dir_y != 0) {
        for (1..side_dist) |i| {
            for ([_]i2{ -1, 1 }) |s| {
                if (s == -only_sign) {
                    continue;
                }
                if (!self.game_object.check_solid(@as(i32, @intCast(i)) * s, dir_y)) {
                    const res =
                        if (func) |f| f(self, @as(i32, @intCast(i)) * s, dir_y) else true;
                    if (res) {
                        self.game_object.x += @as(i32, @intCast(i)) * s;
                        self.game_object.y += dir_y;
                        return true;
                    }
                }
            }
        }
    }

    return false;
}
fn correction_func(self: *Player, ox: i32, oy: i32) bool {
    return !self.hazard_check(.{ .ox = ox, .oy = oy });
}
pub fn on_collide_x(self: *Player, moved: i32, target: i32) bool {
    switch (self.state) {
        .normal => {
            if (@as(i2, @intCast(std.math.sign(target))) == self.input.input_x and self.corner_correct(0, 2, 2, .{ .only_sign = -1, .func = &correction_func })) {
                return false;
            }
        },
        .dash => {
            if (self.corner_correct(0, 2, 2, .{ .only_sign = 0, .func = &correction_func })) {
                return false;
            }
        },
        else => {},
    }
    return GameObject.on_collide_x(&self.game_object, moved, target);
}

const move_args: GameObject.VTable.MoveArgs = .{
    .wall_bonk = @ptrCast(&wall_bonk),
    .vert_bonk = @ptrCast(&vert_bonk),
};
fn vert_bonk(self: *Player, moved: types.PointF, target: types.PointF) bool {
    if (target.y < 0 and self.corner_correct(0, -1, 2, .{ .only_sign = 1, .func = &correction_func })) {
        return false;
    }
    if (self.state == .dash and self.corner_correct(0, @intFromFloat(std.math.sign(target.y)), 4, .{ .only_sign = 0, .func = &correction_func })) {
        return false;
    }

    self.t_var_jump = 0;
    return GameObject.vert_bonk(&self.game_object, moved, target);
}
fn wall_bonk(self: *Player, moved: types.PointF, target: types.PointF) bool {
    switch (self.state) {
        .normal => {
            if (@as(i2, @intFromFloat(std.math.sign(target.x))) == self.input.input_x and self.corner_correct(0, 2, 2, .{ .only_sign = -1, .func = &correction_func })) {
                return false;
            }
        },
        .dash => {
            if (self.corner_correct(0, 2, 2, .{ .only_sign = 0, .func = &correction_func })) {
                return false;
            }
        },
        else => {},
    }
    return GameObject.wall_bonk(&self.game_object, moved, target);
}
pub fn on_collide_y(self: *Player, moved: i32, target: i32) bool {
    if (target < 0 and self.corner_correct(0, -1, 2, .{ .only_sign = 1, .func = &correction_func })) {
        return false;
    }
    if (self.state == .dash and self.corner_correct(0, std.math.sign(target), 4, .{ .only_sign = 0, .func = &correction_func })) {
        return false;
    }

    return GameObject.on_collide_y(&self.game_object, moved, target);
}

pub fn pallete(player: u2) void {
    @call(.always_inline, dash_palette, .{ player, false, false });
}

pub fn dash_palette(player: u2, dashing_player: bool, recharging: bool) void {
    const baseColor: u4 = switch (player) {
        0 => if (dashing_player) 9 else 2,
        1 => if (dashing_player) 1 else 3,
        // ???
        2 => 5,
        3 => 9,
    };
    if (recharging) {
        tic80.PALETTE_MAP.color1 = 12;
    } else {
        tic80.PALETTE_MAP.color1 = baseColor;
    }
    tic80.PALETTE_MAP.color2 = baseColor + 1;
    tic80.PALETTE_MAP.color3 = 12;
}

pub fn reset_pallete() void {
    tic80.PALETTE_MAP.color1 = 1;
    tic80.PALETTE_MAP.color2 = 2;
    tic80.PALETTE_MAP.color3 = 3;
}
pub fn reset(self: *Player) void {
    self.state = .normal;
    self.t_var_jump = 0;
    self.t_fire_pose = 0;
    self.auto_var_jump = false;
    self.t_shoot_cooldown = 0;
    self.t_jump_grace = 0;
    self.jump_grace_y = 0;
    self.t_dash_time = 0;
    self.game_object.speed_x = 0;
    self.game_object.speed_y = 0;
}

pub fn sniff_zone(self: *const Player) types.Box {
    return .{
        .x = self.game_object.x - 2,
        .y = self.game_object.y - 1,
        .w = 10,
        .h = 10,
    };
}

pub fn draw(self: *Player) void {
    const obj = self.get_object();
    dash_palette(self.input.player, !self.can_dash, self.recharging);
    defer reset_pallete();
    defer tdraw.set4bpp();
    if (self.state == .death) {
        // fx...
        var frame: i32 = self.t_death;
        if (frame > 7) {
            frame = 7;
        }
        tdraw.set1bpp();
        self.game_object.game_state.draw_spr(1280 + (frame * 4), obj.x - 13, obj.y - 13, .{ .transparent = &.{0}, .w = 4, .h = 4 });
        return;
    }

    // _ = tic80.vbank(1);
    tdraw.set2bpp();
    const facing: tic80.Flip = if (obj.facing != 1) .horizontal else .no;
    self.game_object.game_state.draw_spr(self.spr, obj.x, obj.y, .{ .flip = facing, .transparent = &.{0} });
    // _ = tic80.vbank(0);
    _ = tic80.printf("{any}", .{self.game_object.speed_x}, 0, 0, .{});
}

fn riding_platform_check(ctx: *anyopaque, platform: GameObject.IsGameObject) bool {
    const self: *Player = @alignCast(@ptrCast(ctx));

    // TODO: jank
    return self.game_object.overlaps(platform, 0, 1);
}

fn riding_platform_set_velocity(ctx: *anyopaque, value: types.PointF) void {
    if (value.x == 0 and value.y == 0) return;

    const self: *Player = @alignCast(@ptrCast(ctx));
    if (self.t_platform_velocity_storage == 0 or value.y <= self.game_object.speed_y or types.abs(value.x) > types.abs(self.game_object.speed_x) or
        (std.math.sign(value.x) != std.math.sign(self.game_object.speed_x)))
    {
        self.t_platform_velocity_storage = 10;
        self.platform_velocity = value;
    }
}

fn riding_platform_moved(ctx: *anyopaque, delta: types.PointF) void {
    vtable.move(ctx, delta, move_args);
}

fn add_platform_velocity(self: *Player, play_sound: bool) bool {
    if (self.t_platform_velocity_storage > 0) {
        var add = self.platform_velocity;
        add.y = std.math.clamp(add.y, -30, 0);
        add.x = std.math.clamp(add.x, -50, 50);
        self.game_object.speed_x += add.x;
        self.game_object.speed_y += add.y;
        self.platform_velocity = .{ .x = 0, .y = 0 };
        self.t_platform_velocity_storage = 0;

        if (play_sound and (add.y <= 3 or add.x > 3)) {
            self.game_object.game_state.voice.play(6, .{ .volume = 8 });
            return true;
        }
    }
    return false;
}
