# zman

A small timer utility to track how much time you spend on tasks.

> Pre-v1 — the CLI may change between releases.

## Install

Have `zig` v0.16.0 installed

```sh
git clone https://github.com/defaultgnome/zman
cd zman
zig build
# copy zig-out/bin/zman somewhere on your PATH
```

Config is stored at the path printed by `zman config` (typically `~/Library/Application Support/zman.json` on macOS).

## Usage

```sh
zman --help                  # list commands
zman <command> -h            # help for a specific command
```

### Commands

| Command | Description |
|---------|-------------|
| `zman` | Open full-screen TUI (coming soon) |
| `zman version` | Print version |
| `zman config` | Print config file path |
| `zman start [name]` | Start a timer; Ctrl-C or Esc to stop (Esc only on Windows) |
| `zman stop <name>` | Close the last open time entry for a task |
| `zman log <name>` | Add a manual clock-in/clock-out entry |
| `zman amend <name> <id>` | Edit or remove an existing time entry |
| `zman list` | List tasks with total time |
| `zman delete <pattern>` | Delete tasks matching a glob pattern |
| `zman merge <from> <to>` | Merge time entries from one task into another |
| `zman rename <name> <new>` | Rename a task |
| `zman show <name>` | Print full clock-in/clock-out log for a task |

### `zman start`

```sh
zman start my-task           # named task
zman start                   # auto-named (unnamed-task-1, unnamed-task-2, …)
zman start --last            # restart the last started task
zman start --git             # use current git branch as task name
```

On Unix, press **Ctrl-C** or **Esc** to stop. On Windows, press **Esc**.

`--last` and `--git` cannot be combined with a task name. See `zman start -h`.

### `zman stop`

Closes the last open clock-out for the given task using the current time. Errors if the task has no entries or the last entry is already closed.

```sh
zman stop my-task
zman stop --git             # use current git branch as task name
```

`<task-name>` and `--git` cannot be combined. See `zman stop -h`.

### `zman log`

Adds a manual clock-in/clock-out entry. Aborts if the range overlaps an existing entry or is in the future.

```sh
zman log my-task --from=09:00 --to=11:30
zman log my-task --from="2026-06-10 09:00" --to="2026-06-10T11:30"
zman log --git --from=09:00 --to=11:30
```

`<task-name>` and `--git` cannot be combined. See `zman log -h`.

**Time formats** (local time):

| Format | Example |
|--------|---------|
| `HH:MM` | today at 09:00 |
| `HH:MM:SS` | today at 09:00:00 |
| `YYYY-MM-DD HH:MM` | full date and time |
| `YYYY-MM-DD HH:MM:SS` | full date and time |
| `YYYY-MM-DDTHH:MM` | ISO-style date and time |
| `YYYY-MM-DDTHH:MM:SS` | ISO-style date and time |

See `zman log -h`.

### `zman amend`

Edits or removes an existing time entry. `<id>` is the row index shown by `zman show` (`0` is the first entry).

```sh
zman amend my-task 0 --from=09:15          # change clock-in
zman amend my-task 0 --to=11:45            # change clock-out
zman amend my-task 0 --from=+0:15          # shift clock-in forward 15 minutes
zman amend my-task 0 --to=-0:30            # shift clock-out back 30 minutes
zman amend my-task 0 --drop                # remove the entry
zman amend --git 0 --from=09:15            # amend entry on current git branch task
```

Accepts the same absolute time formats as `zman log`, plus **relative offsets** from the entry's current value: `+H:MM`, `-H:MM`, `+H:MM:SS`, `-H:MM:SS`.

`--drop` cannot be combined with `--from` or `--to`. At least one of `--from`, `--to`, or `--drop` is required. `<task-name>` and `--git` cannot be combined. See `zman amend -h`.

### `zman list`

```sh
zman list                    # name + total time, aligned
zman list --name-only        # one task name per line (useful for scripting)
```

### `zman delete`

Deletes all tasks whose name matches a **glob pattern** (`*` matches any substring). The confirmation prompt defaults to **yes** — press Enter to proceed.

```sh
zman delete "old-feature*"   # delete tasks starting with old-feature
zman delete "*"              # delete every task (prompts for confirmation)
zman delete "*" -y           # delete all, skip confirmation
```

See `zman delete -h`.

### `zman merge`

Moves all time entries from `<from>` into `<to>`, then removes `<from>`. Aborts with no changes if any time ranges overlap.

```sh
zman merge old-name new-name
```

On success, prints the merged result (same format as `zman show`).

### `zman rename`

Renames an existing task. Errors if the task is not found or the new name is already in use.

```sh
zman rename old-name new-name
zman rename --git new-name        # rename to current git branch name
```

Note: `--git` cannot be used here as target name.

### `zman show`

Prints a summary line (total time, date range, day count) and a table of every entry with a `#` index, clock-in, clock-out, and duration. Open entries show `N/A` for clock-out and duration.

```sh
zman show my-task
zman show --git             # show task named after current git branch
```

Example output:

```
Task: my-task
Total: 2h 30m  ·  2026-06-10 → 2026-06-14  ·  3 days

#  Clock-in            Clock-out           Duration
0  2026-06-10 09:00    2026-06-10 11:00    2h 0m
1  2026-06-14 08:00    N/A                 N/A
```

Use the `#` column as the `<id>` for `zman amend`.

## fzf recipes

With [fzf](https://github.com/junegunn/fzf) installed:

```sh
# fuzzy-pick a task to inspect
zman show "$(zman list --name-only | fzf)"

# show or stop the task for the current git branch
zman show --git
zman stop --git

# fuzzy-pick a task to stop
zman stop "$(zman list --name-only | fzf)"

# fuzzy-pick a task to delete
zman delete "$(zman list --name-only | fzf)"

# fuzzy-pick from/to for a merge
zman merge \
  "$(zman list --name-only | fzf --prompt="from: ")" \
  "$(zman list --name-only | fzf --prompt="to: ")"
```

## Development

```sh
zig build test
```

## Changes

### v0.7.0

- **Added** `--git` on `stop`, `log`, `show`, and `amend` — use the current git branch name instead of `<task-name>`

### v0.6.1

- **Fixed** `zman rename --git` — now works in worktrees, and sub directories.

### v0.6.0

- **Added** `zman rename` — rename a task to a new name or to the current git branch (`--git`)

### v0.5.0

- **Added** `zman amend` — edit clock-in/clock-out on an existing entry, apply relative time offsets, or drop an entry by index

### v0.4.0

- **Added** `#` index column to `zman show` output (used as entry id for `zman amend`)
- **Added** date range and day count to the `zman show` summary line

### v0.3.0

- **Added** `zman stop` — close the last open time entry without running a live timer
- **Added** `zman log` — insert a manual clock-in/clock-out range
- **Added** Esc as a stop key during `zman start` (Unix: Ctrl-C or Esc; Windows: Esc)

### v0.2.0

- **Fixed** delete confirmation prompt defaults to yes when Enter is pressed (`[Y/n]`)
