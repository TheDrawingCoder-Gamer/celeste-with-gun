const GameObject = @import("GameObject.zig");
const std = @import("std");
const tic = @import("tic80.zig");
const PointF = @import("types.zig").PointF;

pub fn move_to(self: GameObject.IsGameObject, x: i32, y: i32) void {
    move_to_point(self, .{ .x = @floatFromInt(x), .y = @floatFromInt(y) });
}

pub fn move_to_point(self: GameObject.IsGameObject, point: PointF) void {
    move_to_point_with_speed(self, point, self.obj().velocity());
}
pub fn move_to_point_with_speed(self: GameObject.IsGameObject, point: PointF, speed: PointF) void {
    const obj = self.obj();
    const delta = point.add(obj.point().times(-1));

    if (delta.length_squared() > 0.001) {
        {
            var it = obj.game_state.objects.first;
            while (it) |node| : (it = node.next) {
                const actor = node.data;
                if (actor.as_rider()) |rider| {
                    if (rider.riding_platform_check(self)) {
                        obj.solid = false;
                        rider.riding_platform_set_velocity(speed);
                        rider.riding_platform_moved(delta);
                        obj.solid = true;
                    }
                }
            }
        }

        obj.move_raw(delta);
    }
}

pub fn move_to_point_once(self: GameObject.IsGameObject, point: PointF) void {
    move_to_point_with_speed(self, point, point.add(self.obj().point().times(-1)));
}
pub fn move_by(self: GameObject.IsGameObject, delta: PointF) void {
    const obj = self.obj();
    if (delta.length_squared() > 0.001) {
        {
            var it = obj.game_state.objects.first;
            while (it) |node| : (it = node.next) {
                const actor = node.data;
                if (actor.as_rider()) |rider| {
                    if (rider.riding_platform_check(self)) {
                        obj.solid = false;
                        rider.riding_platform_set_velocity(delta);
                        rider.riding_platform_moved(delta);
                        obj.solid = true;
                    }
                }
            }
        }

        obj.move_raw(delta);
    }
}
