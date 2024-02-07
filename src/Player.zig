const Player = @This();

const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const Input = @import("Input.zig");
const tic80 = @import("tic80.zig");
const std = @import("std");
const Bullet = @import("Bullet.zig");
const tdraw = @import("draw.zig");
const Allocator = std.mem.Allocator;

const State = enum { normal, death };

pub const vtable: GameObject.VTable = .{ .ptr_update = @ptrCast(&update), .ptr_draw = @ptrCast(&draw), .get_object = @ptrCast(&get_object), .destroy = @ptrCast(&destroy) };

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

pub fn create(allocator: Allocator, state: *GameState, x: i32, y: i32, input: *Input) !Player {
    var obj = GameObject.create(state, x, y);
    // obj.x += 4;
    // obj.y += 8;
    // ???
    obj.hit_x = 2;
    obj.hit_y = 2;
    obj.hit_w = 6;
    obj.hit_h = 6;
    obj.persistent = true;

    return .{ .game_object = obj, .input = input, .allocator = allocator };
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
    _ = self.input.consume_action_press();
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
    self.t_shoot_cooldown = 15;
    self.t_fire_pose = 8;
    self.fire_dir = dir;
    const x_offset: i32 =
        switch (dir) {
        .up, .down => -4,
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
}
pub fn jump(self: *Player) void {
    _ = self.input.consume_jump_press();
    self.state = .normal;
    self.game_object.speed_y = -4;
    self.var_jump_speed = -4;
    self.game_object.speed_x += @as(f32, @floatFromInt(self.input.input_x)) * 0.2;
    self.t_var_jump = 4;
    self.t_jump_grace = 0;
    self.auto_var_jump = false;
    _ = vtable.move_y(self, @floatFromInt(self.jump_grace_y - self.game_object.y), null);
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
}

pub fn die(self: *Player) void {
    self.state = .death;
    self.t_death = 0;
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
    var sliding = false;
    switch (self.state) {
        .normal => {
            if (self.input.input_x != 0) {
                self.game_object.facing = self.input.input_x;
            }

            var target: f32 = 0;
            var accel: f32 = 0.2;
            if (std.math.sign(self.game_object.speed_x) * self.game_object.speed_x > 2 and self.input.input_x == @as(i2, @intFromFloat(std.math.sign(self.game_object.speed_x)))) {
                target = 1;
                accel = 0.05;
            } else if (on_ground) {
                target = 1;
                accel = 0.4;
            } else if (self.input.input_x != 0) {
                target = 1;
                accel = 0.2;
            }
            self.game_object.speed_x = approach(self.game_object.speed_x, @as(f32, @floatFromInt(self.input.input_x)) * target, accel);

            if (!on_ground) {
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
            if (self.input.input_action_pressed > 0) {
                if (self.t_shoot_cooldown == 0) {
                    self.shoot();
                }
            }
        },
        .death => {
            self.t_death += 1;
            return;
        },
    }
    _ = vtable.move_x(self, self.game_object.speed_x, @ptrCast(&on_collide_x));
    _ = vtable.move_y(self, self.game_object.speed_y, @ptrCast(&on_collide_y));

    if (self.t_fire_pose > 0) {
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
        const frame = @divFloor(self.game_object.game_state.time, 8);
        self.spr = 513 + @as(i32, @intCast(frame % 4));
    } else {
        self.spr = 512;
    }
}
pub fn on_collide_x(self: *Player, moved: i32, target: i32) bool {
    return GameObject.on_collide_x(&self.game_object, moved, target);
}
pub fn on_collide_y(self: *Player, moved: i32, target: i32) bool {
    self.t_var_jump = 0;
    return GameObject.on_collide_y(&self.game_object, moved, target);
}

pub fn pallete(player: u2) void {
    switch (player) {
        0 => {
            tic80.PALETTE_MAP.color1 = 2;
        },
        1 => {
            tic80.PALETTE_MAP.color1 = 3;
        },
        2 => {
            tic80.PALETTE_MAP.color1 = 5;
        },
        3 => {
            tic80.PALETTE_MAP.color1 = 9;
        },
    }
    tic80.PALETTE_MAP.color2 = tic80.PALETTE_MAP.color1 + 1;
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
}
pub fn draw(self: *Player) void {
    const obj = self.get_object();
    if (self.state == .death) {
        // fx...
        const frame: i32 = self.t_death;
        if (frame > 7) {
            self.reset();
            self.game_object.game_state.loaded_level.reset() catch unreachable;
            return;
        }
        tdraw.set1bpp();
        self.game_object.game_state.draw_spr(1280 + (frame * 4), obj.x - 13, obj.y - 13, .{ .transparent = &.{0}, .w = 4, .h = 4 });
        tdraw.set4bpp();
        return;
    }

    // _ = tic80.vbank(1);
    tdraw.set2bpp();
    pallete(self.input.player);
    const facing: tic80.Flip = if (obj.facing != 1) .horizontal else .no;
    self.game_object.game_state.draw_spr(self.spr, obj.x, obj.y, .{ .flip = facing, .transparent = &.{0} });
    // _ = tic80.vbank(0);
    tdraw.set4bpp();
    reset_pallete();
}
