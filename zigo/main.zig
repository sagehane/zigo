// SPDX-FileCopyrightText: 2023 Sage Hane <sage@sagehane.com>
//
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");
const assert = std.debug.assert;

const game = @import("game.zig");
pub const Game = game.Game;
pub const DefaultGame = game.DefaultGame;
pub const defaultGame = game.evenGame;

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
    empty = 0,
    black = 1,
    white = 2,

    pub inline fn isColour(self: Point) bool {
        return self != .empty;
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
        };
    }
};

pub const Vec2 = packed struct(u16) { x: u8, y: u8 };
