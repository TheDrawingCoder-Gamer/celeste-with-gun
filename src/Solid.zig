const GameObject = @import("GameObject.zig");
const std = @import("std");
const tic = @import("common").tic;
const PointF = @import("types.zig").PointF;

pub fn move_to(self: GameObject.IsGameObject, x: i32, y: i32) void {
    move_to_point(self, .{ .x = @floatFromInt(x), .y = @floatFromInt(y) });
}

pub fn move_to_point(self: GameObject.IsGameObject, point: PointF) void {
    move_to_point_with_speed(self, point, self.obj().velocity());
}

pub fn move_to_point_with_speed(self: GameObject.IsGameObject, point: PointF, speed: PointF) void {
    return move_by_with_speed(self, point.minus(self.obj().point()), speed);
}
pub fn move_by_with_speed(self: GameObject.IsGameObject, delta: PointF, speed: PointF) void {
    const obj = self.obj();
    obj.remainder_x += delta.x;
    obj.remainder_y += delta.y;

    const move_x: i32 = @intFromFloat(@round(obj.remainder_x));
    const move_y: i32 = @intFromFloat(@round(obj.remainder_y));

    if (move_x != 0 or move_y != 0) {
        obj.solid = false;
        const left = move_x < 0;
        const right = move_x > 0;
        const up = move_y < 0;
        const down = move_y > 0;
        const our_hitbox = obj.world_hitbox().offset(move_x, move_y);
        {
            var it = obj.game_state.objects.first;
            while (it) |node| : (it = node.next) {
                const actor = node.data;
                if (!actor.obj().is_actor) continue;
                const rider = actor.as_rider();
                // if this breaks check riding platform check for anything solid related!
                const was_riding = if (rider) |r| r.riding_platform_check(self) else false;
                if (left or right) {
                    // use move_x move_y to prevent sadness
                    if (obj.overlaps(actor, move_x, 0)) {
                        // Push
                        const their_hitbox = actor.obj().world_hitbox();
                        const movement = if (left) our_hitbox.x - their_hitbox.right() else our_hitbox.right() - their_hitbox.x;
                        if (actor.move_x(@floatFromInt(movement), null)) {
                            actor.squish();
                        }
                    } else if (was_riding) {
                        _ = actor.move_x(@floatFromInt(move_x), null);
                    }
                }
                if (up or down) {
                    // use move_x move_y to prevent sadness
                    if (obj.overlaps(actor, 0, move_y)) {
                        // Push
                        const their_hitbox = actor.obj().world_hitbox();
                        const movement = if (up) our_hitbox.y - their_hitbox.bottom() - 1 else our_hitbox.bottom() - their_hitbox.y;
                        if (actor.move_y(@floatFromInt(movement), null)) {
                            actor.squish();
                        }
                    } else if (was_riding) {
                        _ = actor.move_y(@floatFromInt(move_y), null);
                    }
                }
                if (was_riding) {
                    rider.?.riding_platform_set_velocity(speed);
                }
            }
        }

        obj.solid = true;

        if (left or right) {
            obj.remainder_x -= @floatFromInt(move_x);
            obj.x += move_x;
        }
        if (up or down) {
            obj.remainder_y -= @floatFromInt(move_y);
            obj.y += move_y;
        }
    }
}

pub fn move_to_point_once(self: GameObject.IsGameObject, point: PointF) void {
    move_to_point_with_speed(self, point, point.add(self.obj().point().times(-1)));
}
pub fn move_by(self: GameObject.IsGameObject, delta: PointF) void {
    move_by_with_speed(self, delta, delta);
}
