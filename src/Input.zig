const Input = @This();

const tic80 = @import("tic80.zig");
const std = @import("std");

player: u2,
input_x: i2 = 0,
input_y: i2 = 0,
input_jump: bool = false,
input_jump_pressed: u4 = 0,
input_action: bool = false,
input_action_pressed: u4 = 0,
input_gun: bool = false,
input_gun_pressed: u4 = 0,
axis_x_value: i2 = 0,
axis_x_turned: bool = false,
axis_y_value: i2 = 0,
axis_y_turned: bool = false,

pub fn update(self: *Input) void {
    const player_idx: u8 = @as(u8, self.player) * 8;
    const prev_x = self.axis_x_value;
    const prev_y = self.axis_y_value;
    const left = tic80.btn(2 + player_idx);
    const right = tic80.btn(3 + player_idx);
    const up = tic80.btn(0 + player_idx);
    const down = tic80.btn(1 + player_idx);
    const jump = tic80.btn(4 + player_idx);
    const action = tic80.btn(5 + player_idx);
    const gun = tic80.btn(6 + player_idx);

    if (left) {
        if (right) {
            if (self.axis_x_turned) {
                self.axis_x_value = prev_x;
                self.input_x = prev_x;
            } else {
                self.axis_x_turned = true;
                self.axis_x_value = -prev_x;
                self.input_x = -prev_x;
            }
        } else {
            self.axis_x_turned = false;
            self.axis_x_value = -1;
            self.input_x = -1;
        }
    } else if (right) {
        self.axis_x_turned = false;
        self.axis_x_value = 1;
        self.input_x = 1;
    } else {
        self.axis_x_turned = false;
        self.axis_x_value = 0;
        self.input_x = 0;
    }
    if (up) {
        if (down) {
            if (self.axis_y_turned) {
                self.axis_y_value = prev_y;
                self.input_y = prev_y;
            } else {
                self.axis_y_turned = true;
                self.axis_y_value = -prev_y;
                self.input_y = -prev_y;
            }
        } else {
            self.axis_y_turned = false;
            self.axis_y_value = -1;
            self.input_y = -1;
        }
    } else if (down) {
        self.axis_y_turned = false;
        self.axis_y_value = 1;
        self.input_y = 1;
    } else {
        self.axis_y_turned = false;
        self.axis_y_value = 0;
        self.input_y = 0;
    }

    if (jump and !self.input_jump) {
        self.input_jump_pressed = 8;
    } else {
        if (jump) {
            if (self.input_jump_pressed > 0)
                self.input_jump_pressed -= 1;
        } else {
            self.input_jump_pressed = 0;
        }
    }
    self.input_jump = jump;

    if (action and !self.input_action) {
        self.input_action_pressed = 8;
    } else {
        if (action) {
            if (self.input_action_pressed > 0)
                self.input_action_pressed -= 1;
        } else {
            self.input_action_pressed = 0;
        }
    }
    self.input_action = action;

    if (gun and !self.input_gun) {
        self.input_gun_pressed = 8;
    } else {
        if (gun) {
            if (self.input_gun_pressed > 0)
                self.input_gun_pressed -= 1;
        } else {
            self.input_gun_pressed = 0;
        }
    }
    self.input_gun = gun;
}

pub fn consume_jump_press(self: *Input) bool {
    const res = self.input_jump_pressed > 0;
    self.input_jump_pressed = 0;
    return res;
}

pub fn consume_action_press(self: *Input) bool {
    const res = self.input_action_pressed > 0;
    self.input_action_pressed = 0;
    return res;
}

pub fn consume_gun_press(self: *Input) bool {
    const res = self.input_gun_pressed > 0;
    self.input_gun_pressed = 0;
    return res;
}
