const math = @This();

const std = @import("std");

pub const Point = struct {
    x: i32 = 0,
    y: i32 = 0,
    pub fn add(self: Point, other: Point) Point {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }
    pub fn times(self: Point, scalar: i32) Point {
        return .{ .x = self.x * scalar, .y = self.y * scalar };
    }
    pub fn as_float(self: Point) PointF {
        return .{ .x = @floatFromInt(self.x), .y = @floatFromInt(self.y) };
    }
    pub fn to_radians(self: Point) f32 {
        return self.as_float().to_radians();
    }
};

pub const PointF = struct {
    x: f32 = 0,
    y: f32 = 0,
    pub fn add(self: PointF, other: PointF) PointF {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }
    pub fn minus(self: PointF, other: PointF) PointF {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }
    pub fn times(self: PointF, scalar: f32) PointF {
        return .{ .x = self.x * scalar, .y = self.y * scalar };
    }
    pub fn as_int(self: PointF) Point {
        return .{ .x = @intFromFloat(self.x), .y = @intFromFloat(self.y) };
    }
    pub fn min(left: PointF, right: PointF) PointF {
        return .{ .x = @min(left.x, right.x), .y = @min(left.y, right.y) };
    }
    pub fn max(left: PointF, right: PointF) PointF {
        return .{ .x = @max(left.x, right.x), .y = @max(left.y, right.y) };
    }
    pub fn from_radians(angle: f32) PointF {
        const x = @cos(angle);
        const y = -@sin(angle);
        return .{ .x = x, .y = y };
    }
    pub fn normalized(self: PointF) PointF {
        const len = self.length();
        // panics (?) on divide by 0
        return .{ .x = self.x / len, .y = self.y / len };
    }
    pub fn to_radians(self: PointF) f32 {
        return std.math.atan2(-self.y, self.x);
    }
    pub fn length_squared(self: PointF) f32 {
        return std.math.pow(f32, self.x, 2) + std.math.pow(f32, self.y, 2);
    }
    pub fn length(self: PointF) f32 {
        return std.math.sqrt(self.length_squared());
    }
    pub fn distance_squared(self: PointF, other: PointF) f32 {
        return std.math.pow(f32, self.x - other.x, 2) + std.math.pow(f32, self.y - other.y, 2);
    }
    pub fn distance(self: PointF, other: PointF) f32 {
        return std.math.sqrt(self.distance_squared(other));
    }

    pub fn dot(self: PointF, other: PointF) f32 {
        return (self.x * other.x) + (self.y * other.y);
    }

    pub fn with_x(self: PointF, x: f32) PointF {
        return .{ .x = x, .y = self.y };
    }
    pub fn with_y(self: PointF, y: f32) PointF {
        return .{ .x = self.x, .y = y };
    }

    pub fn approach(self: PointF, speed_x: f32, speed_y: f32, target: PointF) PointF {
        return .{ .x = math.approach(self.x, target.x, speed_x), .y = math.approach(self.y, target.y, speed_y) };
    }

    pub fn lerp(left: PointF, right: PointF, t: f32) PointF {
        return .{ .x = math.lerp(left.x, right.x, t), .y = math.lerp(left.y, right.y, t) };
    }

    pub fn cross(self: PointF, other: PointF) f32 {
        return (self.x * other.y) - (self.y * other.x);
    }

    pub fn trunc(self: PointF) PointF {
        return .{ .x = @trunc(self.x), .y = @trunc(self.y) };
    }
    pub fn floor(self: PointF) PointF {
        return .{ .x = @floor(self.x), .y = @floor(self.y) };
    }

    pub fn element_divide(self: PointF, other: PointF) PointF {
        return .{ .x = self.x / other.x, .y = self.y / other.y };
    }
    pub fn element_times(self: PointF, other: PointF) PointF {
        return .{ .x = self.x * other.x, .y = self.y * other.y };
    }
};

pub fn approach(x: anytype, target: anytype, max_delta: anytype) @TypeOf(x, target, max_delta) {
    return if (x < target) @min(x + max_delta, target) else @max(x - max_delta, target);
}

pub fn sine_in_out(t: f32) f32 {
    return -(std.math.cos(std.math.pi * t) - 1) / 2;
}
pub fn lerp(min: f32, max: f32, t: f32) f32 {
    return (1 - t) * min + t * max;
}

// Digital input direction
pub const DigitalDir = struct {
    x: i2,
    y: i2,

    pub fn as_point(self: DigitalDir) Point {
        return .{ .x = self.x, .y = self.y };
    }
};
pub const CardinalDir = enum(u2) {
    up,
    right,
    down,
    left,

    pub fn as_princible(self: CardinalDir) PrincibleWind {
        // could be represented as a `@enumFromInt(@intFromEnum(self) * 2)` but NO! sinner
        return switch (self) {
            .up => .up,
            .right => .right,
            .down => .down,
            .left => .left,
        };
    }

    pub fn x(self: CardinalDir) i2 {
        return switch (self) {
            .up, .down => 0,
            .left => -1,
            .right => 1,
        };
    }
    pub fn y(self: CardinalDir) i2 {
        return switch (self) {
            .left, .right => 0,
            .up => -1,
            .down => 1,
        };
    }
    pub fn digital_dir(self: CardinalDir) DigitalDir {
        return .{ .x = self.x(), .y = self.y() };
    }
};

// don't @ me wikipedia told me so
pub const PrincibleWind = enum(u3) {
    up,
    up_right,
    right,
    down_right,
    down,
    down_left,
    left,
    up_left,

    pub fn cardinal_bias_horz(self: PrincibleWind) CardinalDir {
        return switch (self) {
            .up => .up,
            .up_right, .right, .down_right => .right,
            .down => .down,
            .down_left, .left, .up_left => .left,
        };
    }
    pub fn cardinal_bias_vert(self: PrincibleWind) CardinalDir {
        return switch (self) {
            .up_left, .up, .up_right => .up,
            .right => .right,
            .down_right, .down, .down_left => .down,
            .left => .left,
        };
    }
    pub fn x(self: PrincibleWind) i2 {
        return switch (self) {
            .up, .down => 0,
            .up_right, .right, .down_right => 1,
            .down_left, .left, .up_left => -1,
        };
    }
    pub fn y(self: PrincibleWind) i2 {
        return switch (self) {
            .left, .right => 0,
            .up_left, .up, .up_right => -1,
            .down_right, .down, .down_left => 1,
        };
    }
    pub fn digital_dir(self: PrincibleWind) DigitalDir {
        return .{ .x = self.x(), .y = self.y() };
    }
};
