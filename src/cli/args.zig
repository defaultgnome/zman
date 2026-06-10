const std = @import("std");

pub const Command = enum {
    tui,
    help,
    version,
    config,
    start,
    list,
    delete,
    merge,
    show,
};

pub const Parsed = struct {
    command: Command,
    help_target: ?Command = null,
    positionals: []const []const u8,
    start_last: bool = false,
    start_git: bool = false,
    list_name_only: bool = false,
    delete_yes: bool = false,
};

fn isFlag(arg: []const u8) bool {
    return arg.len > 0 and arg[0] == '-';
}

fn isHelpFlag(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help");
}

pub fn parse(allocator: std.mem.Allocator, args: []const []const u8) !Parsed {
    if (args.len == 0) return .{ .command = .tui, .positionals = &.{} };

    const first = args[0];
    if (isHelpFlag(first)) return .{ .command = .help, .positionals = &.{} };

    const cmd = std.meta.stringToEnum(Command, first) orelse return error.UnknownCommand;

    for (args[1..]) |arg| {
        if (isHelpFlag(arg)) return .{ .command = .help, .help_target = cmd, .positionals = &.{} };
    }

    var parsed = Parsed{ .command = cmd, .positionals = &.{} };
    var positionals = std.ArrayList([]const u8).empty;
    errdefer positionals.deinit(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (!isFlag(arg)) {
            try positionals.append(allocator, arg);
            continue;
        }

        if (std.mem.eql(u8, arg, "--last")) {
            if (cmd != .start) return error.UnexpectedFlag;
            parsed.start_last = true;
        } else if (std.mem.eql(u8, arg, "--git")) {
            if (cmd != .start) return error.UnexpectedFlag;
            parsed.start_git = true;
        } else if (std.mem.eql(u8, arg, "--name-only")) {
            if (cmd != .list) return error.UnexpectedFlag;
            parsed.list_name_only = true;
        } else if (std.mem.eql(u8, arg, "-y")) {
            if (cmd != .delete) return error.UnexpectedFlag;
            parsed.delete_yes = true;
        } else return error.UnknownFlag;
    }

    parsed.positionals = try positionals.toOwnedSlice(allocator);
    return parsed;
}

pub fn freeParsed(allocator: std.mem.Allocator, parsed: *Parsed) void {
    allocator.free(parsed.positionals);
    parsed.positionals = &.{};
}

test parse {
    const p1 = try parse(std.testing.allocator, &.{});
    try std.testing.expect(p1.command == .tui);

    const p2 = try parse(std.testing.allocator, &.{ "start", "my-task" });
    defer freeParsed(std.testing.allocator, &p2);
    try std.testing.expect(p2.command == .start);
    try std.testing.expectEqualStrings("my-task", p2.positionals[0]);

    const p3 = try parse(std.testing.allocator, &.{ "delete", "-h" });
    try std.testing.expect(p3.command == .help);
    try std.testing.expect(p3.help_target.? == .delete);
}
