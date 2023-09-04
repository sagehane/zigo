// SPDX-FileCopyrightText: 2023 Sage Hane <sage@sagehane.com>
//
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");
const Allocator = std.mem.Allocator;

const zigo = @import("main.zig");
const Colour = zigo.Colour;
const Point = zigo.Point;
const Vec2 = zigo.Vec2;

const Board = @import("board.zig").Board;

pub const DefaultGame = Game(.{ .x = 19, .y = 19 });

pub fn evenGame(allocator: Allocator) error{OutOfMemory}!DefaultGame {
    return try DefaultGame.init(allocator, 7);
}

const MoveError = error{
    AlreadyOccupied,
    BoardRepetition,
    OutOfMemory,
};

// TODO: Make the dimensions configurable at runtime.
pub fn Game(comptime dimensions: Vec2) type {
    const BoardType = Board(dimensions);

    return struct {
        const Self = @This();

        /// Needed to detect board repetition.
        const History = struct {
            const prefix_len = 4;
            const IndexSize = u16;
            // TODO: Consider using std.SegmentedList?
            const List = std.ArrayList([prefix_len]IndexSize);
            const initial_item = [1]IndexSize{0} ** prefix_len;

            list: List,

            fn init(allocator: Allocator, board: BoardType, player: Colour) error{OutOfMemory}!History {
                var history = History{ .list = List.init(allocator) };
                history.list.append(initial_item) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    unreachable;
                };
                history.insert(board, player.getOpposite()) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    unreachable;
                };
                return history;
            }

            fn deinit(self: History) void {
                self.list.deinit();
            }

            fn insert(self: *History, board: BoardType, player: Colour) error{ BoardRepetition, OutOfMemory }!void {
                var index: IndexSize = 0;

                // Keep iterating on the board and adding entries.
                for (board.points) |point| {
                    const i = @intFromEnum(point);

                    const item_ptr = &self.list.items[index][i];
                    if (item_ptr.* == 0) {
                        item_ptr.* = @intCast(self.list.items.len);
                        try self.list.append(initial_item);
                    }

                    index = self.list.items[index][i];
                }

                // Note, this uses 0 and 1 for black and white.
                const i = @intFromEnum(player);
                const item_ptr = &self.list.items[index][i];

                if (item_ptr.* != 0) return error.BoardRepetition;
                item_ptr.* = std.math.maxInt(IndexSize);
            }
        };

        board: BoardType = .{},
        history: History,
        player: Colour = .black,
        // TODO: Consider signed integer.
        komi: u16 = 0,
        winner: ?Point = null,

        pub fn init(allocator: Allocator, komi: u16) error{OutOfMemory}!Self {
            return Self{ .history = try History.init(allocator, .{}, .black), .komi = komi };
        }

        pub fn deinit(self: *Self) void {
            self.history.deinit();
        }

        pub fn play(self: *Self, coord: Vec2) MoveError!void {
            var board_copy = self.board;
            try board_copy.placeStone(coord, self.player);
            try self.insertHistory(board_copy);
            self.board = board_copy;
            self.player = self.player.getOpposite();
        }

        /// The game ends when passing results in a move repetition.
        /// `.empty` represents a draw.
        pub fn pass(self: *Self) void {
            self.insertHistory(self.board) catch return {
                var scores = self.board.getScores();
                scores[1] +|= self.getKomi();

                if (scores[0] == scores[1])
                    self.winner = .empty
                else if (scores[0] > scores[1])
                    self.winner = .black
                else
                    self.winner = .white;
            };
            self.player = self.player.getOpposite();
        }

        pub inline fn forfeit(self: *Self, forfeiter: Colour) void {
            self.winner = forfeiter.getOpposite().toPoint();
        }

        pub inline fn getKomi(self: Self) u16 {
            return self.komi;
        }

        pub inline fn getDimensions() Vec2 {
            return dimensions;
        }

        fn insertHistory(self: *Self, board: BoardType) error{ BoardRepetition, OutOfMemory }!void {
            try self.history.insert(board, self.player);
        }
    };
}
