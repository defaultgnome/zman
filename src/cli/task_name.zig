const std = @import("std");
const Io = std.Io;

const zman = @import("zman");
const cli_args = @import("args.zig");

pub const Resolved = struct {
    name: []const u8,
    owned: bool,
};

pub fn freeResolved(allocator: std.mem.Allocator, resolved: *Resolved) void {
    if (resolved.owned) allocator.free(resolved.name);
}

/// Resolves a required single task name from `<task-name>` or `--git`.
pub fn resolveRequired(io: Io, allocator: std.mem.Allocator, parsed: cli_args.Parsed) !Resolved {
    if (parsed.task_git and parsed.positionals.len > 0) return error.InvalidTaskNameFlags;
    if (parsed.task_git) {
        return .{ .name = try zman.gitBranchName(io, allocator), .owned = true };
    }
    if (parsed.positionals.len != 1) return error.MissingTaskName;
    return .{ .name = parsed.positionals[0], .owned = false };
}

pub const AmendResolved = struct {
    task: Resolved,
    time_id: usize,
};

/// Resolves the task name for `amend`: `<task-name> <time-id>` or `--git <time-id>`.
pub fn resolveAmend(io: Io, allocator: std.mem.Allocator, parsed: cli_args.Parsed) !AmendResolved {
    if (parsed.task_git) {
        if (parsed.positionals.len != 1) return error.MissingAmendArgs;
        const time_id = std.fmt.parseInt(usize, parsed.positionals[0], 10) catch return error.InvalidTimeEntryId;
        return .{
            .task = .{ .name = try zman.gitBranchName(io, allocator), .owned = true },
            .time_id = time_id,
        };
    }
    if (parsed.positionals.len != 2) return error.MissingAmendArgs;
    const time_id = std.fmt.parseInt(usize, parsed.positionals[1], 10) catch return error.InvalidTimeEntryId;
    return .{
        .task = .{ .name = parsed.positionals[0], .owned = false },
        .time_id = time_id,
    };
}
