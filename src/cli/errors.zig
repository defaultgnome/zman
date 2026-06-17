const std = @import("std");

pub const Formatted = struct {
    message: []const u8,
    hint: ?[]const u8 = null,
};

pub fn format(err: anyerror) Formatted {
    return switch (err) {
        error.UnknownCommand => .{
            .message = "unknown command",
            .hint = "Run 'zman --help' for available commands.",
        },
        error.UnknownFlag => .{
            .message = "unknown flag",
            .hint = "Run 'zman <command> -h' for command-specific options.",
        },
        error.UnexpectedFlag => .{
            .message = "flag not valid for this command",
            .hint = "Run 'zman <command> -h' for command-specific options.",
        },
        error.InvalidStartFlags => .{
            .message = "incompatible start options",
            .hint = "Use only one of: a task name, --last, or --git. Run 'zman start -h'.",
        },
        error.NoLastTask => .{
            .message = "no previous task to restart",
            .hint = "Start a task first with 'zman start <name>'.",
        },
        error.NotGitRepo => .{
            .message = "not inside a git repository",
            .hint = "Run from a directory with a .git folder, or pass a task name instead.",
        },
        error.MissingPattern => .{
            .message = "missing delete pattern",
            .hint = "Usage: zman delete <pattern>. Use '*' to match all tasks. Run 'zman delete -h'.",
        },
        error.NoMatchingTasks => .{
            .message = "no tasks match the pattern",
            .hint = "Check the pattern or run 'zman list' to see task names.",
        },
        error.MissingMergeArgs => .{
            .message = "missing merge arguments",
            .hint = "Usage: zman merge <from> <to>. Run 'zman merge -h'.",
        },
        error.MissingTaskName => .{
            .message = "missing task name",
            .hint = "Usage: zman show <task-name>. Run 'zman show -h'.",
        },
        error.TaskNotFound => .{
            .message = "task not found",
            .hint = "Run 'zman list' to see existing tasks.",
        },
        error.TimeOverlap => .{
            .message = "cannot merge: time ranges overlap",
            .hint = "Resolve overlapping entries before merging.",
        },
        error.SameTask => .{
            .message = "cannot merge a task into itself",
            .hint = "Provide two different task names.",
        },
        error.MissingLogFrom => .{
            .message = "missing --from time",
            .hint = "Usage: zman log <task-name> --from=<time> --to=<time>. Run 'zman log -h'.",
        },
        error.MissingLogTo => .{
            .message = "missing --to time",
            .hint = "Usage: zman log <task-name> --from=<time> --to=<time>. Run 'zman log -h'.",
        },
        error.MissingAmendArgs => .{
            .message = "missing amend arguments",
            .hint = "Usage: zman amend <task-name> <time-id>. Run 'zman amend -h'.",
        },
        error.MissingAmendTime => .{
            .message = "missing amend option",
            .hint = "Pass --from, --to, and/or --drop. Run 'zman amend -h'.",
        },
        error.InvalidAmendFlags => .{
            .message = "--drop cannot be combined with --from or --to",
            .hint = "Use --drop alone to remove an entry. Run 'zman amend -h'.",
        },
        error.InvalidTimeEntryId => .{
            .message = "invalid time entry id",
            .hint = "Use the row index from 'zman show' (0 is the first entry).",
        },
        error.TimeEntryNotFound => .{
            .message = "time entry not found",
            .hint = "Check the index with 'zman show <task-name>'.",
        },
        error.MissingAmendBase => .{
            .message = "relative time requires an existing clock-in or clock-out",
            .hint = "Set an absolute time, or amend the field that already has a value.",
        },
        error.MissingFlagValue => .{
            .message = "flag requires a value",
            .hint = "Run 'zman <command> -h' for command-specific options.",
        },
        error.InvalidTimeFormat => .{
            .message = "invalid time format",
            .hint = "Use HH:MM, HH:MM:SS, YYYY-MM-DD HH:MM, or YYYY-MM-DDTHH:MM:SS. Run 'zman log -h'.",
        },
        error.InvalidLogRange => .{
            .message = "--from must be before --to",
            .hint = "Provide a valid time range. Run 'zman log -h'.",
        },
        error.FutureTime => .{
            .message = "time cannot be in the future",
            .hint = "Use a clock-in/out time that is not later than now.",
        },
        error.NoTimeEntries => .{
            .message = "task has no time entries",
            .hint = "Start or log time for this task first.",
        },
        error.TimeEntryAlreadyClosed => .{
            .message = "last time entry is already closed",
            .hint = "Use 'zman start' to begin a new open entry.",
        },
        error.ConfigFolderUnavailable => .{
            .message = "could not resolve config directory",
            .hint = "Check that your home directory and XDG paths are accessible.",
        },
        else => .{ .message = @errorName(err) },
    };
}

test format {
    const f = format(error.NoLastTask);
    try std.testing.expectEqualStrings("no previous task to restart", f.message);
    try std.testing.expect(f.hint != null);
}
