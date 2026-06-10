## TODO NOW
- [ ] maybe restructure CLI interface (start, version, config, instead of flags)
  - ok lets have a command structure: `zman <command> <params>`, so:
  - [ ] `zman version` - print version
  - [ ] `zman config` - print config path
  - [ ] `zman start [task-name]` - start a timer with provided name, if not provided call it `unamed-task-<n>` (one not used)
    - [ ] `zman start --last` - start last started timer (last is presisted in zman.json)
    - [ ] `zman start --git` - use cwd git branch name as task name - throw error in case not in git repo
  - [ ] `zman list` - list all tasks and time, can pass `--name-only` to print a list of the tasks name
  - [ ] `zman delete <task-name-pattern>` - delete all tasks that match pattern - delete all if using `*`, print list of will be deleted tasks, and ask for y/n confirmation, passing `-y` will auto accept and not ask for confirmation.
  - [ ] `zman merge <task-name-from> <task-name-to>` - merge times of `from` to `to`, deleting the `from` task, in case of conflicting times (overlaps) abort action and do nothing
  - [ ] `zman show <task-name>` - print full log of times for task - should be human readable
  - [ ] `zman` - open zman as a full screen TUI - currently only display "coming soon"
  - [ ] `zman --help` or `zman -h` - print help

## TODO LATER with TUI
- [ ] amend time
