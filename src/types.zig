pub const Point = struct { x: i32 = 0, y: i32 = 0 };

pub const Box = struct { x: i32, y: i32, w: i32, h: i32 };

pub const Direction = enum(u2) { up = 0, right = 1, down = 2, left = 3 };
