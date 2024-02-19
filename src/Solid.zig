const GameObject = @import("GameObject.zig");
const std = @import("std");
const tic = @import("tic80.zig");

const MovetoForeachData = struct {
    self: GameObject.IsGameObject,
    delta_x: f32,
    delta_y: f32,
};
fn moveto_foreach(args: *anyopaque, actor: GameObject.IsGameObject) void {
    const data: *MovetoForeachData = @alignCast(@ptrCast(args));
    const self = data.self;
    const obj = self.obj();

    if (actor.as_rider()) |rider| {
        if (rider.riding_platform_check(self)) {
            obj.solid = false;
            rider.riding_platform_set_velocity(.{ .x = obj.speed_x, .y = obj.speed_y });
            rider.riding_platform_moved(.{ .x = data.delta_x, .y = data.delta_y });
            obj.solid = true;
        }
    }
}
pub fn move_to(self: GameObject.IsGameObject, x: i32, y: i32) void {
    const obj = self.obj();
    const delta_x: f32 = @floatFromInt(x - obj.x);
    const delta_y: f32 = @floatFromInt(y - obj.y);

    if (std.math.pow(f32, delta_x, 2) + std.math.pow(f32, delta_y, 2) > 0.001) {
        var data: MovetoForeachData = .{ .self = self, .delta_x = delta_x, .delta_y = delta_y };
        obj.game_state.forall_objects(@ptrCast(&data), &moveto_foreach);

        obj.remainder_x += delta_x;
        const mx: i32 = @intFromFloat(@floor(obj.remainder_x + 0.5));
        obj.remainder_x -= @floatFromInt(mx);
        obj.x += mx;

        obj.remainder_y += delta_y;
        const my: i32 = @intFromFloat(@floor(obj.remainder_y + 0.5));
        obj.remainder_y -= @floatFromInt(my);
        obj.y += my;
    }
}
