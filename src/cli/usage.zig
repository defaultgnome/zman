const cli_args = @import("args.zig");

pub const global_text =
    \\Usage: zman [command] [args]
    \\
    \\Commands:
    \\  (none)          Open full-screen TUI (coming soon)
    \\  version         Print version
    \\  config          Print config file path
    \\  start           Start a timer (Ctrl-C to stop)
    \\  list            List all tasks with total time
    \\  delete          Delete tasks matching a glob pattern
    \\  merge           Merge one task's times into another
    \\  show            Print full time log for a task
    \\
    \\Run 'zman <command> -h' for command-specific help.
    \\
;

pub fn commandText(cmd: cli_args.Command) ?[]const u8 {
    return switch (cmd) {
        .start => start_text,
        .list => list_text,
        .delete => delete_text,
        .merge => merge_text,
        .show => show_text,
        else => null,
    };
}

const start_text =
    \\Usage: zman start [task-name] [options]
    \\
    \\Start a timer for the given task. Press Ctrl-C to stop.
    \\If no task name is given, an auto-generated name is used.
    \\
    \\Options:
    \\  --last          Restart the last started task
    \\  --git           Use the current git branch name as the task name
    \\
;

const list_text =
    \\Usage: zman list [options]
    \\
    \\List all tasks and their total tracked time.
    \\
    \\Options:
    \\  --name-only     Print task names only (one per line)
    \\
;

const delete_text =
    \\Usage: zman delete <pattern> [options]
    \\
    \\Delete all tasks whose name matches the glob pattern.
    \\Use '*' to match every task. Patterns support '*' wildcards
    \\(e.g. 'feat*' matches 'feat-auth', 'feature-x').
    \\
    \\A confirmation prompt is shown unless -y is passed.
    \\
    \\Options:
    \\  -y              Skip confirmation and delete immediately
    \\
;

const merge_text =
    \\Usage: zman merge <from> <to>
    \\
    \\Move all time entries from <from> into <to>, then delete <from>.
    \\Aborts without changes if any time ranges overlap.
    \\
;

const show_text =
    \\Usage: zman show <task-name>
    \\
    \\Print a human-readable log of all clock-in/clock-out entries
    \\for the given task.
    \\
;
