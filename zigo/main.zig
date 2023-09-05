// SPDX-FileCopyrightText: 2023 Sage Hane <sage@sagehane.com>
//
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");
const assert = std.debug.assert;

pub const Game = @import("Game.zig");
pub const defaultGame = Game.evenGame;

test {
    std.testing.refAllDecls(@This());
}

pub const Colour = enum(u1) {
    black,
    white,

    pub inline fn getOpposite(self: Colour) Colour {
        return @enumFromInt(@intFromEnum(self) +% 1);
    }

    pub inline fn toPoint(self: Colour) Point {
        return @enumFromInt(@as(u2, @intFromEnum(self)) + 1);
    }
};

pub const Point = enum(u2) {
    empty = 0b00,
    black = 0b01,
    white = 0b10,
    // Meaningless in regular play, used for territory counting
    debug = 0b11,

    pub inline fn isColour(self: Point) bool {
        return self != .empty and self != .debug;
    }

    pub inline fn getOpposite(self: Point) Point {
        assert(self.isColour());
        return @enumFromInt(~@intFromEnum(self));
    }

    pub inline fn toColour(self: Point) Colour {
        assert(self.isColour());
        return @enumFromInt(@intFromEnum(self) - 1);
    }

    pub fn toChar(self: Point) u8 {
        return switch (self) {
            .empty => '.',
            .black => 'B',
            .white => 'W',
            .debug => '?',
        };
    }
};

pub const Vec2 = packed struct(u16) { x: u8, y: u8 };
