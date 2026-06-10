## TODO NOW
- [ ] add a 'lap' functionality while running and printing the the current time of `start`
  - meaning that if i type something, when running, and then submit with enter, it will take the now time as a clock-out and add the label (a new optional field for the entry), and immediatly also start a new clock-in in the same session
  - make sure to update the `show` table with the new optional label
- [ ] following the `lap` funcitonality, if we run `start` with `--follow-commit` (assert cwd is git), this will listen to git commit made, and auto label session. think about what does it mean, if we change branch, or do commit ops

## TODO LATER with TUI
- [ ] amend entry time (missing clock-in / clock-out)
- [ ] amend entry label
- [ ] squash times, like a rebase in git
