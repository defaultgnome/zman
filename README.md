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
| `zman start [name]` | Start a timer; Ctrl-C to stop |
| `zman list` | List tasks with total time |
| `zman delete <pattern>` | Delete tasks matching a glob pattern |
| `zman merge <from> <to>` | Merge time entries from one task into another |
| `zman show <name>` | Print full clock-in/clock-out log for a task |

### `zman start`

```sh
zman start my-task           # named task
zman start                   # auto-named (unnamed-task-1, unnamed-task-2, …)
zman start --last            # restart the last started task
zman start --git             # use current git branch as task name
```

`--last` and `--git` cannot be combined with a task name. See `zman start -h`.

### `zman list`

```sh
zman list                    # name + total time, aligned
zman list --name-only        # one task name per line (useful for scripting)
```

### `zman delete`

Deletes all tasks whose name matches a **glob pattern** (`*` matches any substring).

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

### `zman show`

Prints a table of clock-in, clock-out, and duration for every entry. Open entries show `N/A` for clock-out and duration.

```sh
zman show my-task
```

## fzf recipes

With [fzf](https://github.com/junegunn/fzf) installed:

```sh
# fuzzy-pick a task to inspect
zman show "$(zman list --name-only | fzf)"

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
