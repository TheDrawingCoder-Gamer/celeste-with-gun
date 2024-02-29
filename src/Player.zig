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
const rider_vtable: GameObject.IRide.VTable = .{ .riding_platform_check = &riding_platform_check, .riding_platform_set_velocity = &riding_platform_set_velocity };

fn as_rider(ctx: *anyopaque) GameObject.IRide {
    return .{ .ctx = ctx, .table = &rider_vtable };
}

const MAX_FALL_SPEED = 2;
const MAX_FAST_FALL_SPEED = 2.6;
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
dashes: u8 = 1,
max_dashes: u8 = 1,
host: bool = false,
// doesn't affect hitbox, only used for detecting wave and hyper dashes
crouching: bool = false,
down_dash: bool = false,
t_recharge: u8 = 0,
recharging: bool = false,
t_platform_velocity_storage: u8 = 0,
platform_velocity: types.PointF = .{ .x = 0, .y = 0 },
fully_riding: bool = false,
skull_offset: types.Point = .{ .x = 0, .y = 0 },
last_velocity: types.PointF = .{},
char_sliding: bool = false,
last_accel: types.PointF = .{},
follow_thru_accel: types.PointF = .{},
t_accel_follow_thru: u8 = 0,

pub fn create(allocator: Allocator, state: *GameState, x: i32, y: i32, input: *Input, voice: *Voice) !*Player {
    var obj = GameObject.create(state, x, y);
    // obj.x += 4;
    // obj.y += 8;
    // ???
    obj.hit_x = 2;
    obj.hit_y = 2;
    obj.hit_w = 5;
    obj.hit_h = 6;
    obj.hurtbox = .{ .x = 2, .y = 2, .w = 4, .h = 5 };
    obj.persistent = true;
    obj.special_type = .player;
    obj.is_actor = true;
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
    const x_dir = if (self.input.input_y == 0 and self.input.input_x == 0) self.game_object.facing else self.input.input_x;
    self.shoot_dir(x_dir, self.input.input_y, -1);

    tic80.sfx(3, .{ .duration = 10, .volume = 5 });
}
fn shoot_dir(self: *Player, x: i2, y: i2, ttl: i32) void {
    const dir: Bullet.Direction = blk: {
        if (y == -1) {
            break :blk if (x < 0)
                .up_left
            else if (x > 0)
                .up_right
            else
                .up;
        }
        if (y > 0) {
            break :blk if (x < 0)
                .down_left
            else if (x > 0)
                .down_right
            else
                .down;
        }
        break :blk if (x == -1) .left else .right;
    };
    self.t_shoot_cooldown = 6;
    self.t_fire_pose = 8;
    self.fire_dir = dir;
    const x_offset: i32 =
        switch (dir) {
        .left, .up_left, .down_left => -8,
        else => 0,
    };
    _ = Bullet.create(self.allocator, self.game_object.game_state, self.game_object.x + x_offset, self.game_object.y, self.input.player, dir, ttl) catch |err| {
        switch (err) {
            error.TooMany => {},
            error.OutOfMemory => {
                tic80.trace("oom?");
            },
        }
        return;
    };
}
fn raw_jump(self: *Player, play_sound: bool) bool {
    _ = self.input.consume_jump_press();
    self.state = .normal;
    self.game_object.speed_y = -3;
    self.var_jump_speed = -3;
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
    if (recover) {
        self.refill_dashes();
    }
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
    if (recover) {
        self.refill_dashes();
    }
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
    self.dashes -= 1;
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
    self.shoot_dir(x_dir, self.input.input_y, 30);
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
    self.last_accel = self.game_object.velocity().minus(self.last_velocity);
    self.last_velocity = self.game_object.velocity();
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
            const fast_fall: f32 = if (self.input.input_y == 1) MAX_FAST_FALL_SPEED else MAX_FALL_SPEED;
            if (self.input.input_x != 0) {
                sliding = self.game_object.check_solid(self.input.input_x, 0);
            }
            const slide_penalty: f32 = if (sliding) 1 else 0;
            const max_fall = fast_fall - slide_penalty;

            if (std.math.sign(self.game_object.speed_y) * self.game_object.speed_y < 0.2 and self.input.input_jump) {
                self.game_object.speed_y = @min(self.game_object.speed_y + 0.2, max_fall);
            } else {
                self.game_object.speed_y = @min(self.game_object.speed_y + 0.8, max_fall);
            }
            if (!on_ground) {
                self.recharging = false;
                self.t_recharge = 0;
            } else {
                if (self.dashes < self.max_dashes and self.t_recharge == 0) {
                    if (self.recharging) {
                        self.recharging = false;
                        self.refill_dashes();
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
                        if (self.dashes > 0)
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
    // hack
    _ = vtable.move_y(self, self.game_object.speed_y * gravity_multiplier, @ptrCast(&on_collide_y));
    _ = vtable.move_x(self, self.game_object.speed_x, @ptrCast(&on_collide_x));

    // sprite
    self.char_sliding = false;
    self.skull_offset = .{};
    if (self.state == .dash) {
        self.spr = 538;
    } else if (self.t_fire_pose > 0) {
        self.spr = switch (self.fire_dir) {
            .right, .left => 527,
            .up_left, .up_right => 530,
            .down_left, .down_right => 531,
            .up => 528,
            .down => 529,
        };
    } else if (!on_ground) {
        if (sliding) {
            self.char_sliding = true;
            self.spr = 522;
        } else {
            if (self.game_object.speed_y > 0) {
                self.spr = 517;
            } else {
                self.spr = 515;
            }
        }
    } else {
        if (self.crouching) {
            self.skull_offset.y = 2;
        }
        if (self.input.input_x != 0) {
            if (self.crouching) {
                const frame: i32 = @intCast(@divFloor(self.game_object.game_state.time, 9) % 3);
                if (frame == 1) {
                    self.skull_offset.y = 1;
                }
                self.spr = 560 + frame;
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
        if (obj.hazard != .none and self.game_object.hurtboxes_touch(o, args.ox, args.oy)) {
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
            if (@as(i2, @intCast(std.math.sign(target))) == self.input.input_x and self.corner_correct(self.input.input_x, 2, 2, .{ .only_sign = -1, .func = &correction_func })) {
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

pub fn on_collide_y(self: *Player, moved: i32, target: i32) bool {
    if (target < 0 and self.corner_correct(0, -1, 2, .{ .only_sign = 1, .func = &correction_func })) {
        return false;
    }
    if (self.state == .dash and self.corner_correct(0, std.math.sign(target), 4, .{ .only_sign = 0, .func = &correction_func })) {
        return false;
    }

    if (target < 0) {
        self.t_accel_follow_thru = 1;
    }

    const res = GameObject.on_collide_y(&self.game_object, moved, target);
    // bonk!
    if (self.state == .dash) {
        const shockwave_ttl = 5;
        self.shoot_dir(-1, 0, shockwave_ttl);
        self.shoot_dir(1, 0, shockwave_ttl);
    }
    return res;
}

pub inline fn pallete(player: u2) void {
    dash_palette(player, 1, false);
}

pub fn dash_palette(player: u2, dash_n: u8, recharging: bool) void {
    const baseColor: u4 = switch (player) {
        0 => switch (dash_n) {
            0 => 9,
            2 => 5,
            else => 2,
        },
        1 => 3,
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

pub fn sniff_zone(self: *const Player) types.Box {
    return .{
        .x = self.game_object.x - 2,
        .y = self.game_object.y - 1,
        .w = 10,
        .h = 10,
    };
}

fn clamp_mag_high(x: i32, magnitude: i32) i32 {
    if (x < 0) {
        return @max(x, -magnitude);
    }
    return @min(x, magnitude);
}
pub fn draw(self: *Player) void {
    const obj = self.get_object();
    dash_palette(self.input.player, self.dashes, self.recharging);
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

    tdraw.set2bpp();
    const facing: tic80.Flip = if ((obj.facing != 1) != (self.char_sliding)) .horizontal else .no;
    if (self.state == .dash or self.dashes == 0) {
        var skull_offset_y: i32 = 0;
        if (self.recharging) {
            skull_offset_y = 3;
            skull_offset_y -= self.t_recharge / 3;
        }
        self.game_object.game_state.draw_spr(553, obj.x, obj.y + skull_offset_y, .{ .flip = facing, .transparent = &.{0} });
        return;
    }
    const accel = obj.velocity().minus(self.last_velocity);
    const len2 = accel.length_squared();
    const last_len2 = self.last_accel.length_squared();
    if (len2 > 1.0 and (len2 > last_len2 or self.t_accel_follow_thru <= 0)) {
        self.t_accel_follow_thru = 6;
        self.follow_thru_accel = accel;
    }
    if (self.t_accel_follow_thru > 0) {
        self.t_accel_follow_thru -= 1;
    }
    //const skull_offset_x: i32 = clamp_mag_high(-@as(i32, @intFromFloat(obj.speed_x / 1.5)), 5) + self.skull_offset.x;
    const skull_offset_y: i32 = self.skull_offset.y +
        if (self.t_accel_follow_thru > 0)
        clamp_mag_high(@as(i32, @intFromFloat(-self.follow_thru_accel.y)), 2)
    else
        0;
    self.game_object.game_state.draw_spr(553, obj.x, obj.y + skull_offset_y, .{ .flip = facing, .transparent = &.{0} });

    // _ = tic80.vbank(1);
    self.game_object.game_state.draw_spr(self.spr, obj.x, obj.y, .{ .flip = facing, .transparent = &.{0} });
    // _ = tic80.vbank(0);
}

fn riding_platform_check(ctx: *anyopaque, platform: GameObject.IsGameObject) bool {
    const self: *Player = @alignCast(@ptrCast(ctx));
    const obj = platform.obj();

    if (obj.overlaps_box(0, 0, self.sniff_zone())) {
        if (self.game_object.overlaps(platform, 0, 0)) {
            return false;
        }
        if (self.game_object.overlaps(platform, 0, 1)) {
            self.fully_riding = true;
            return true;
        }
    }

    return false;
}

fn riding_platform_set_velocity(ctx: *anyopaque, value: types.PointF) void {
    if (value.x == 0 and value.y == 0) return;

    const self: *Player = @alignCast(@ptrCast(ctx));
    if (self.t_platform_velocity_storage == 0 or value.y <= self.platform_velocity.y or types.abs(value.x) > types.abs(self.platform_velocity.x) or
        (std.math.sign(value.x) != std.math.sign(self.platform_velocity.x)))
    {
        self.t_platform_velocity_storage = 10;
        self.platform_velocity = value;
    }
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

        if (play_sound and (add.y <= -3 or types.abs(add.x) > 3)) {
            self.game_object.game_state.voice.play(6, .{ .volume = 8 });
            return true;
        }
    }
    return false;
}

pub fn as_table(self: *Player) GameObject.IsGameObject {
    return .{ .ptr = self, .table = vtable };
}

pub inline fn refill_dashes(self: *Player) void {
    self.dashes = self.max_dashes;
}
