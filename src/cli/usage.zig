const cli_args = @import("args.zig");

pub const global_text =
    \\Usage: zman [command] [args]
    \\
    \\Commands:
    \\  (none)          Open full-screen TUI (coming soon)
    \\  version         Print version
    \\  config          Print config file path
    \\  start           Start a timer (Ctrl-C or Esc to stop)
    \\  stop            Close the last open time entry for a task
    \\  log             Add a manual clock-in/clock-out entry
    \\  amend           Edit or remove an existing time entry
    \\  list            List all tasks with total time
    \\  delete          Delete tasks matching a glob pattern
    \\  merge           Merge one task's times into another
    \\  rename          Rename a task
    \\  show            Print full time log for a task
    \\
    \\Run 'zman <command> -h' for command-specific help.
    \\
;

pub fn commandText(cmd: cli_args.Command) ?[]const u8 {
    return switch (cmd) {
        .start => start_text,
        .stop => stop_text,
        .log => log_text,
        .amend => amend_text,
        .list => list_text,
        .delete => delete_text,
        .merge => merge_text,
        .rename => rename_text,
        .show => show_text,
        else => null,
    };
}

const start_text =
    \\Usage: zman start [task-name] [options]
    \\
    \\Start a timer for the given task.
    \\On Unix, press Ctrl-C or Esc to stop. On Windows, press Esc.
    \\If no task name is given, an auto-generated name is used.
    \\
    \\Options:
    \\  --last          Restart the last started task
    \\  --git           Use the current git branch name as the task name
    \\
;

const stop_text =
    \\Usage: zman stop <task-name>
    \\
    \\Close the last open clock-out for the given task using the current time.
    \\Errors if the task has no entries or the last entry is already closed.
    \\
;

const log_text =
    \\Usage: zman log <task-name> --from=<time> --to=<time>
    \\
    \\Add a manual clock-in/clock-out entry for a task.
    \\Aborts if the range overlaps an existing entry or is in the future.
    \\
    \\Time formats (local time):
    \\  HH:MM                   today at the given time
    \\  HH:MM:SS                today at the given time
    \\  YYYY-MM-DD HH:MM        full date and time
    \\  YYYY-MM-DD HH:MM:SS     full date and time
    \\  YYYY-MM-DDTHH:MM        ISO-style date and time
    \\  YYYY-MM-DDTHH:MM:SS     ISO-style date and time
    \\
    \\Options:
    \\  --from=<time>   Clock-in time (required)
    \\  --to=<time>     Clock-out time (required)
    \\
;

const amend_text =
    \\Usage: zman amend <task-name> <time-id> [options]
    \\
    \\Edit or remove an existing time entry. <time-id> is the row index
    \\shown by 'zman show' (0 is the first entry).
    \\
    \\Time formats (local time):
    \\  HH:MM                   today at the given time
    \\  HH:MM:SS                today at the given time
    \\  YYYY-MM-DD HH:MM        full date and time
    \\  YYYY-MM-DD HH:MM:SS     full date and time
    \\  YYYY-MM-DDTHH:MM        ISO-style date and time
    \\  YYYY-MM-DDTHH:MM:SS     ISO-style date and time
    \\
    \\Relative offsets (from the entry's current clock-in or clock-out):
    \\  +H:MM                   add hours and minutes
    \\  -H:MM                   subtract hours and minutes
    \\  +H:MM:SS / -H:MM:SS     add or subtract with seconds
    \\
    \\Options:
    \\  --from=<time>   New clock-in time (optional)
    \\  --to=<time>     New clock-out time (optional)
    \\  --drop          Remove the entry
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

const rename_text =
    \\Usage: zman rename <task-name> <new-name>
    \\   or: zman rename <task-name> --git
    \\
    \\Rename an existing task. Errors if the task is not found or the
    \\new name is already in use.
    \\
    \\Options:
    \\  --git           Use the current git branch name as the new name
    \\
;

const show_text =
    \\Usage: zman show <task-name>
    \\
    \\Print a human-readable log of all clock-in/clock-out entries
    \\for the given task. Times are shown in your local timezone.
    \\
;
