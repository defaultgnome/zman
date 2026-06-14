## TODO NOW
- [x] make all confirm `[y/n]` to `[Y/n]`, i.e. the default when enter is Yes
- [ ] add option to quit the `start` command with `ESC` key, on windows it will be the only option - reflect that in the text displayed
- [ ] add a new `stop` command that will close the last open time of the provided `<task-name>` - error out if last time entry is already close
- [ ] addd a new command, i don't have a good name so choose one, this command should help me set manually a time entry for a task, so i could say --from="11:00" --to="11:30" and it will add this entry. notes: error out if this is conflicting with current times (overlap), error if this is in the future. this should be smartish - meaning, "11:00" (24h format) mean today, but we can also add full fomart, add in this command sub `-h` help, the format supported

## TODO LATER
- [ ] add a 'lap' functionality while running and printing the the current time of `start`
  - meaning that if i type something, when running, and then submit with enter, it will take the now time as a clock-out and add the label (a new optional field for the entry), and immediatly also start a new clock-in in the same session
  - make sure to update the `show` table with the new optional label
- [ ] following the `lap` funcitonality, if we run `start` with `--follow-commit` (assert cwd is git), this will listen to git commit made, and auto label session. think about what does it mean, if we change branch, or do commit ops

## TODO - TUI
- [ ] amend entry time (missing clock-in / clock-out)
- [ ] amend entry label
- [ ] squash times, like a rebase in git
