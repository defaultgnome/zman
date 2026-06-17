//! CLI / TUI entry point for zman.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const posix = std.posix;

const zman = @import("zman");
const cli_args = @import("cli/args.zig");
const cli_errors = @import("cli/errors.zig");
const cli_output = @import("cli/output.zig");
const usage = @import("cli/usage.zig");
const timer_input = @import("cli/timer_input.zig");

var timer_stop_requested = std.atomic.Value(bool).init(false);

fn handleSigInt(_: posix.SIG) callconv(.c) void {
    timer_stop_requested.store(true, .seq_cst);
}

const App = struct {
    io: Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
};

pub fn main(init: std.process.Init) !void {
    var app = App{
        .io = init.io,
        .allocator = init.arena.allocator(),
        .environ = init.environ_map,
    };

    const raw_args = try init.minimal.args.toSlice(app.allocator);
    const cmd_args = if (raw_args.len > 1) raw_args[1..] else &.{};

    var parsed = cli_args.parse(app.allocator, cmd_args) catch |err| {
        try reportError(app.io, err);
        std.process.exit(1);
    };
    defer cli_args.freeParsed(app.allocator, &parsed);

    const dispatch = [_]struct { cmd: cli_args.Command, run: *const fn (*App, cli_args.Parsed) anyerror!void }{
        .{ .cmd = .tui, .run = runTui },
        .{ .cmd = .help, .run = runHelp },
        .{ .cmd = .version, .run = runVersion },
        .{ .cmd = .config, .run = runConfig },
        .{ .cmd = .start, .run = runStart },
        .{ .cmd = .stop, .run = runStop },
        .{ .cmd = .log, .run = runLog },
        .{ .cmd = .amend, .run = runAmend },
        .{ .cmd = .list, .run = runList },
        .{ .cmd = .delete, .run = runDelete },
        .{ .cmd = .merge, .run = runMerge },
        .{ .cmd = .show, .run = runShow },
    };

    for (dispatch) |entry| {
        if (entry.cmd == parsed.command) {
            entry.run(&app, parsed) catch |err| {
                try reportError(app.io, err);
                std.process.exit(1);
            };
            return;
        }
    }
}

fn runTui(app: *App, _: cli_args.Parsed) !void {
    var buf: [256]u8 = undefined;
    var w = Io.File.stdout().writer(app.io, &buf);
    try w.interface.writeAll("\x1b[2J\x1b[HTUI Coming Soon!\n");
    try w.interface.flush();
}

fn runHelp(app: *App, parsed: cli_args.Parsed) !void {
    const text = if (parsed.help_target) |target|
        usage.commandText(target) orelse usage.global_text
    else
        usage.global_text;

    var buf: [512]u8 = undefined;
    var w = Io.File.stdout().writer(app.io, &buf);
    try w.interface.writeAll(text);
    try w.interface.flush();
}

fn runVersion(app: *App, _: cli_args.Parsed) !void {
    var buf: [64]u8 = undefined;
    var w = Io.File.stdout().writer(app.io, &buf);
    try w.interface.print("{s}\n", .{zman.version});
    try w.interface.flush();
}

fn runConfig(app: *App, _: cli_args.Parsed) !void {
    const path = try zman.configFilePath(app.io, app.allocator, app.environ);
    defer app.allocator.free(path);

    var buf: [512]u8 = undefined;
    var w = Io.File.stdout().writer(app.io, &buf);
    try w.interface.print("{s}\n", .{path});
    try w.interface.flush();
}

fn runStart(app: *App, parsed: cli_args.Parsed) !void {
    if (parsed.start_last and parsed.start_git) return error.InvalidStartFlags;
    if (parsed.start_last and parsed.positionals.len > 0) return error.InvalidStartFlags;
    if (parsed.start_git and parsed.positionals.len > 0) return error.InvalidStartFlags;

    var config_dir = try zman.openConfigDir(app.io, app.allocator, app.environ);
    defer config_dir.close(app.io);

    var store = try zman.loadStoreMut(app.io, app.allocator, config_dir);
    defer store.deinit();

    const resolved = try resolveStartTaskName(app, &store, parsed);
    defer if (resolved.owned) app.allocator.free(resolved.name);

    try runTimer(app, config_dir, &store, resolved.name);
}

fn runStop(app: *App, parsed: cli_args.Parsed) !void {
    if (parsed.positionals.len != 1) return error.MissingTaskName;

    var config_dir = try zman.openConfigDir(app.io, app.allocator, app.environ);
    defer config_dir.close(app.io);

    var store = try zman.loadStoreMut(app.io, app.allocator, config_dir);
    defer store.deinit();

    const task_name = parsed.positionals[0];
    try store.stopLastOpenEntry(task_name, zman.unixNow(app.io));
    try store.setLastTask(task_name);
    try zman.saveStoreMut(app.io, config_dir, &store, app.allocator);
}

fn runLog(app: *App, parsed: cli_args.Parsed) !void {
    if (parsed.positionals.len != 1) return error.MissingTaskName;
    const from_text = parsed.from orelse return error.MissingLogFrom;
    const to_text = parsed.to orelse return error.MissingLogTo;

    const now = zman.unixNow(app.io);
    const from_epoch = try zman.parseTimeSpecifier(from_text, now);
    const to_epoch = try zman.parseTimeSpecifier(to_text, now);

    if (from_epoch >= to_epoch) return error.InvalidLogRange;
    if (from_epoch > now or to_epoch > now) return error.FutureTime;

    var config_dir = try zman.openConfigDir(app.io, app.allocator, app.environ);
    defer config_dir.close(app.io);

    var store = try zman.loadStoreMut(app.io, app.allocator, config_dir);
    defer store.deinit();

    const task_name = parsed.positionals[0];
    try store.addTimeEntry(task_name, .{ .start = from_epoch, .end = to_epoch });
    try store.setLastTask(task_name);
    try zman.saveStoreMut(app.io, config_dir, &store, app.allocator);
}

fn runAmend(app: *App, parsed: cli_args.Parsed) !void {
    if (parsed.positionals.len != 2) return error.MissingAmendArgs;

    const task_name = parsed.positionals[0];
    const time_id = std.fmt.parseInt(usize, parsed.positionals[1], 10) catch return error.InvalidTimeEntryId;

    if (parsed.amend_drop and (parsed.from != null or parsed.to != null)) return error.InvalidAmendFlags;
    if (!parsed.amend_drop and parsed.from == null and parsed.to == null) return error.MissingAmendTime;

    var config_dir = try zman.openConfigDir(app.io, app.allocator, app.environ);
    defer config_dir.close(app.io);

    var store = try zman.loadStoreMut(app.io, app.allocator, config_dir);
    defer store.deinit();

    if (parsed.amend_drop) {
        try store.removeTimeEntryAt(task_name, time_id);
        try store.setLastTask(task_name);
        try zman.saveStoreMut(app.io, config_dir, &store, app.allocator);
        return;
    }

    const task = store.findTask(task_name) orelse return error.TaskNotFound;
    if (time_id >= task.times.items.len) return error.TimeEntryNotFound;

    const existing = task.times.items[time_id];
    const now = zman.unixNow(app.io);

    const new_start: ?i64 = if (parsed.from) |text|
        try zman.parseAmendTimeSpecifier(text, now, existing.start)
    else
        existing.start;

    const new_end: ?i64 = if (parsed.to) |text|
        try zman.parseAmendTimeSpecifier(text, now, existing.end)
    else
        existing.end;

    if (new_start != null and new_end != null and new_start.? >= new_end.?) return error.InvalidLogRange;
    if (new_start) |start| if (start > now) return error.FutureTime;
    if (new_end) |end| if (end > now) return error.FutureTime;

    try store.setTimeEntryAt(task_name, time_id, .{ .start = new_start, .end = new_end });
    try store.setLastTask(task_name);
    try zman.saveStoreMut(app.io, config_dir, &store, app.allocator);
}

const ResolvedTaskName = struct { name: []const u8, owned: bool };

fn resolveStartTaskName(app: *App, store: *zman.StoreMut, parsed: cli_args.Parsed) !ResolvedTaskName {
    if (parsed.start_last) {
        const last = store.last_task orelse return error.NoLastTask;
        return .{ .name = last, .owned = false };
    }
    if (parsed.start_git) {
        return .{ .name = try zman.gitBranchName(app.io, app.allocator), .owned = true };
    }
    if (parsed.positionals.len > 0) {
        return .{ .name = try std.mem.join(app.allocator, " ", parsed.positionals), .owned = true };
    }
    return .{ .name = try zman.nextUnnamedTaskName(store, app.allocator), .owned = true };
}

fn runList(app: *App, parsed: cli_args.Parsed) !void {
    var config_dir = try zman.openConfigDir(app.io, app.allocator, app.environ);
    defer config_dir.close(app.io);

    var store = try zman.loadStoreMut(app.io, app.allocator, config_dir);
    defer store.deinit();

    var buf: [512]u8 = undefined;
    var w = Io.File.stdout().writer(app.io, &buf);

    if (parsed.list_name_only) {
        for (store.tasks.items) |task| try w.interface.print("{s}\n", .{task.name});
        try w.interface.flush();
        return;
    }

    var name_width: usize = 4;
    for (store.tasks.items) |task| name_width = @max(name_width, task.name.len);

    for (store.tasks.items) |task| {
        var duration_buf: [32]u8 = undefined;
        const total = zman.taskTotalSeconds(task.times.items);
        const duration = zman.formatDurationSeconds(total, &duration_buf);
        try w.interface.print("{s}", .{task.name});
        var pad = name_width - task.name.len;
        while (pad > 0) : (pad -= 1) try w.interface.writeAll(" ");
        try w.interface.print("  {s}\n", .{duration});
    }
    try w.interface.flush();
}

fn runDelete(app: *App, parsed: cli_args.Parsed) !void {
    if (parsed.positionals.len != 1) return error.MissingPattern;

    var config_dir = try zman.openConfigDir(app.io, app.allocator, app.environ);
    defer config_dir.close(app.io);

    var store = try zman.loadStoreMut(app.io, app.allocator, config_dir);
    defer store.deinit();

    var matches = std.ArrayList([]const u8).empty;
    defer matches.deinit(app.allocator);
    try store.taskNamesMatching(parsed.positionals[0], &matches);

    if (matches.items.len == 0) return error.NoMatchingTasks;

    if (!parsed.delete_yes) {
        var buf: [256]u8 = undefined;
        var w = Io.File.stdout().writer(app.io, &buf);
        try w.interface.writeAll("Will delete:\n");
        for (matches.items) |name| try w.interface.print("  {s}\n", .{name});
        try w.interface.writeAll("Proceed? [Y/n] ");
        try w.interface.flush();
        if (!try readYes(app.io)) return;
    }

    for (matches.items) |name| _ = store.removeTask(name);
    try zman.saveStoreMut(app.io, config_dir, &store, app.allocator);
}

fn runMerge(app: *App, parsed: cli_args.Parsed) !void {
    if (parsed.positionals.len != 2) return error.MissingMergeArgs;

    const from_name = parsed.positionals[0];
    const to_name = parsed.positionals[1];

    var config_dir = try zman.openConfigDir(app.io, app.allocator, app.environ);
    defer config_dir.close(app.io);

    var store = try zman.loadStoreMut(app.io, app.allocator, config_dir);
    defer store.deinit();

    try store.mergeTasks(from_name, to_name);
    try zman.saveStoreMut(app.io, config_dir, &store, app.allocator);

    const task = store.findTask(to_name).?;

    var buf: [512]u8 = undefined;
    var w = Io.File.stdout().writer(app.io, &buf);
    try w.interface.print("task {s} has been merged to {s}:\n\n", .{ from_name, to_name });
    try cli_output.printTaskLog(&w.interface, task.*);
    try w.interface.flush();
}

fn runShow(app: *App, parsed: cli_args.Parsed) !void {
    if (parsed.positionals.len != 1) return error.MissingTaskName;

    var config_dir = try zman.openConfigDir(app.io, app.allocator, app.environ);
    defer config_dir.close(app.io);

    var store = try zman.loadStoreMut(app.io, app.allocator, config_dir);
    defer store.deinit();

    const task = store.findTask(parsed.positionals[0]) orelse return error.TaskNotFound;

    var buf: [512]u8 = undefined;
    var w = Io.File.stdout().writer(app.io, &buf);
    try cli_output.printTaskLog(&w.interface, task.*);
    try w.interface.flush();
}

fn runTimer(app: *App, config_dir: Io.Dir, store: *zman.StoreMut, task_name: []const u8) !void {
    timer_stop_requested.store(false, .seq_cst);

    const task = try store.findOrCreateTask(task_name);
    const start = zman.unixNow(app.io);
    try task.times.append(app.allocator, .{ .start = start, .end = null });
    try store.setLastTask(task_name);
    try zman.saveStoreMut(app.io, config_dir, store, app.allocator);

    const time_index = task.times.items.len - 1;

    if (builtin.os.tag != .windows) {
        const act: posix.Sigaction = .{
            .handler = .{ .handler = handleSigInt },
            .mask = posix.sigemptyset(),
            .flags = posix.SA.RESTART,
        };
        posix.sigaction(.INT, &act, null);
    }

    var stdin_mode: ?timer_input.TimerInput = timer_input.TimerInput.init() catch null;
    defer if (stdin_mode) |*mode| mode.deinit();

    var buf: [256]u8 = undefined;
    var w = Io.File.stdout().writer(app.io, &buf);

    const no_color = app.environ.get("NO_COLOR") != null and app.environ.get("NO_COLOR").?.len > 0;
    const clicolor_force = app.environ.get("CLICOLOR_FORCE") != null and app.environ.get("CLICOLOR_FORCE").?.len > 0;
    const terminal_mode = try Io.Terminal.Mode.detect(app.io, Io.File.stdout(), no_color, clicolor_force);
    var terminal: Io.Terminal = .{ .writer = &w.interface, .mode = terminal_mode };

    const stop_hint = if (builtin.os.tag == .windows)
        "press Esc to stop timer\n"
    else
        "press Ctrl-C or Esc to stop timer\n";

    var first_draw = true;
    while (!timer_stop_requested.load(.seq_cst)) {
        if (stdin_mode) |mode| {
            if (mode.escapePressed()) {
                timer_stop_requested.store(true, .seq_cst);
                break;
            }
        }

        const elapsed: u64 = @intCast(@max(zman.unixNow(app.io) - start, 0));
        var duration_buf: [32]u8 = undefined;
        const duration = zman.formatDurationSeconds(elapsed, &duration_buf);

        // NOTE: here we only clear 3 lines, so if you add more, update
        if (!first_draw) try w.interface.writeAll("\x1b[3A");
        first_draw = false;

        try w.interface.print("{s}\n", .{task.name});
        try w.interface.print("{s}\n", .{duration});
        try terminal.setColor(.bright_black);
        try w.interface.writeAll(stop_hint);
        try terminal.setColor(.reset);
        try w.interface.flush();

        try Io.sleep(app.io, Io.Duration.fromSeconds(1), .real);
    }

    const end = zman.unixNow(app.io);
    try recordTimerStop(app, task, time_index, end);
    try zman.saveStoreMut(app.io, config_dir, store, app.allocator);
    try w.interface.writeAll("\n");
    try w.interface.flush();
}

fn recordTimerStop(app: *App, task: *zman.StoreMut.TaskMut, time_index: usize, end: i64) !void {
    if (time_index >= task.times.items.len) {
        try printWarning(app.io, "timer entry is missing; recording clock-out without clock-in", .{});
        try task.times.append(app.allocator, .{ .start = null, .end = end });
        return;
    }

    const entry = &task.times.items[time_index];
    if (entry.start == null) {
        try printWarning(app.io, "timer entry has no clock-in; recording clock-out without clock-in", .{});
        try task.times.append(app.allocator, .{ .start = null, .end = end });
        return;
    }

    if (entry.end != null) {
        try printWarning(app.io, "timer entry already has a clock-out; recording clock-out without clock-in", .{});
        try task.times.append(app.allocator, .{ .start = null, .end = end });
        return;
    }

    entry.end = end;
}

fn readYes(io: Io) !bool {
    var stdin_buf: [256]u8 = undefined;
    var reader = Io.File.stdin().reader(io, &stdin_buf);
    const line = reader.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
        error.EndOfStream => return false,
        else => |e| return e,
    };
    const answer = std.mem.trim(u8, line, " \t\r");
    if (answer.len == 0) return true;
    return answer[0] == 'y' or answer[0] == 'Y';
}

fn reportError(io: Io, err: anyerror) !void {
    const formatted = cli_errors.format(err);
    try printCliMessage(io, .stderr, "error: {s}", .{formatted.message});
    if (formatted.hint) |hint| try printCliMessage(io, .stderr, "hint: {s}", .{hint});
}

fn printWarning(io: Io, comptime fmt: []const u8, args: anytype) !void {
    try printCliMessage(io, .stderr, "warning: " ++ fmt, args);
}

fn printCliMessage(io: Io, stream: enum { stdout, stderr }, comptime fmt: []const u8, args: anytype) !void {
    var buf: [256]u8 = undefined;
    var w = switch (stream) {
        .stdout => Io.File.stdout().writer(io, &buf),
        .stderr => Io.File.stderr().writer(io, &buf),
    };
    try w.interface.print(fmt, args);
    try w.interface.writeAll("\n");
    try w.interface.flush();
}
