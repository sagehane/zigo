// SPDX-FileCopyrightText: 2023 Sage Hane <sage@sagehane.com>
//
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");
const zigo = @import("zigo");
const Game = zigo.Game;

pub fn main() !void {
    const stdin = std.io.getStdIn().reader();
    const stderr = std.io.getStdErr().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit() == .leak)
            std.debug.print("Leak detected!\n", .{});
    }
    const allocator = gpa.allocator();

    var buffer: [std.mem.page_size]u8 = undefined;

    var game = try zigo.defaultGame(allocator);
    defer game.deinit();

    while (game.winner == .undecided) {
        try stderr.print("{s}'s turn: ", .{colourToString(game.player)});
        const len = try stdin.read(&buffer);

        try handleInput(&game, buffer[0..len], stderr);
    }

    try game.board.printAscii(game.board.points, stderr);
    const msg = switch (game.winner) {
        .black => "Black won the game!",
        .white => "White won the game!",
        .draw => "The game ended in a draw!",
        else => unreachable,
    };
    try stderr.print("\n\n{s}\n", .{msg});
    try printScores(game, game.board.getScores(), stderr);
}

fn colourToString(colour: zigo.Colour) []const u8 {
    return switch (colour) {
        .black => "Black",
        .white => "White",
    };
}

fn printScores(game: Game, scores: [2]u16, writer: anytype) !void {
    try writer.print("Black: {}\nWhite: {} (+{} komi)\n", .{
        scores[0],
        scores[1],
        game.getKomi(),
    });
}

fn handleInput(game: *Game, input: []const u8, writer: anytype) !void {
    const trimmed = std.mem.trim(u8, input, "\x0a ");

    const help_message =
        \\  Commands:
        \\    help                  Print this message
        \\    print                 Print the state of the board
        \\    territory             Show the territory of both players
        \\    pass                  Pass the turn to the other player
        \\    play [A..Z][1..26]    Make a play at a given coord, such as "b2"
        \\    forfeit               Forfeit the game
    ;

    if (std.mem.eql(u8, trimmed, "help")) {
        try writer.print(help_message, .{});
    } else if (std.mem.eql(u8, trimmed, "print")) {
        try writer.writeAll("\n\n");
        try game.board.printAscii(game.board.points, writer);
    } else if (std.mem.eql(u8, trimmed, "territory")) {
        try writer.writeAll("\n\n");
        const scores = game.board.getScores();
        try game.board.printAscii(game.board.copy, writer);
        try writer.writeAll("\n");
        try printScores(game.*, scores, writer);
    } else if (std.mem.eql(u8, trimmed, "pass")) {
        game.pass();
    } else if (std.mem.eql(u8, trimmed, "forfeit")) {
        game.forfeit(game.player);
    } else if (std.mem.startsWith(u8, trimmed, "play ")) {
        const arg = std.mem.trim(u8, trimmed["play ".len..], " ");

        if (std.fmt.parseInt(u8, arg[1..], 10)) |y| {
            const coord = .{ .x = std.ascii.toUpper(arg[0]) - 'A', .y = y - 1 };

            if (!game.board.inRange(coord))
                try writer.writeAll("\nInvalid coordinates!\n")
            else {
                game.play(coord) catch |err| {
                    const msg = switch (err) {
                        error.AlreadyOccupied => "\nThe coordinate is already occupied!\n",
                        error.BoardRepetition => "\nBoard repetition detected!\n",
                        error.OutOfMemory => @panic("\nOut of memory!\n"),
                    };
                    try writer.writeAll(msg);
                };
            }
        } else |_| try writer.writeAll("\nInvalid coordinates!\n");
    } else try writer.writeAll("Invalid command, type \"help\" for a list of commands");

    try writer.writeAll("\n\n");
}
