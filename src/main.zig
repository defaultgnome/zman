//! main .exe tui/cli code for zman
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const posix = std.posix;

const zman = @import("zman");

var timer_stop_requested = std.atomic.Value(bool).init(false);

fn handleSigInt(_: posix.SIG) callconv(.c) void {
    timer_stop_requested.store(true, .seq_cst);
}

fn isFlag(arg: []const u8) bool {
    return arg.len > 0 and arg[0] == '-';
}

fn exitUnknownFlag(io: Io, flag: []const u8) noreturn {
    printCliError(io, "unknown flag: {s}", .{flag}) catch {};
    std.process.exit(1);
}

fn exitInvalidTaskName(io: Io, task_name: []const u8) noreturn {
    printCliError(io, "invalid task name: {s}", .{task_name}) catch {};
    std.process.exit(1);
}

fn ensureTaskNameArgs(io: Io, args: []const []const u8) void {
    for (args) |arg| {
        if (isFlag(arg)) exitInvalidTaskName(io, arg);
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len == 1) {
        try listTasks(io, arena, init.environ_map);
        return;
    }

    const first = args[1];
    if (std.mem.eql(u8, first, "--help") or std.mem.eql(u8, first, "-h")) {
        try printUsage(io);
        return;
    }

    if (std.mem.eql(u8, first, "--version")) {
        try printVersion(io);
        return;
    }

    if (std.mem.eql(u8, first, "--config")) {
        try printConfigPath(io, arena, init.environ_map);
        return;
    }

    if (std.mem.eql(u8, first, "-D")) {
        if (args.len < 3) {
            try printCliError(io, "missing task name for -D", .{});
            std.process.exit(1);
        }
        ensureTaskNameArgs(io, args[2..]);
        const task_name = try std.mem.join(arena, " ", args[2..]);
        try deleteTask(io, arena, init.environ_map, task_name);
        return;
    }

    if (isFlag(first)) exitUnknownFlag(io, first);

    ensureTaskNameArgs(io, args[1..]);
    const task_name = try std.mem.join(arena, " ", args[1..]);
    try runTimer(io, arena, init.environ_map, task_name);
}

const usage =
    \\Usage: zman [command] [options] [task-name]
    \\
    \\Commands:
    \\  zman                      List all tasks with total time
    \\  zman <task-name>          Start timer for task (Ctrl-C to stop)
    \\
    \\Options:
    \\  -h, --help                Show this help
    \\  --version                 Print version
    \\  --config                  Print config file path
    \\  -D <task-name>            Delete task (with confirmation)
    \\
;

fn printUsage(io: Io) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll(usage);
    try stdout.flush();
}

fn printVersion(io: Io) !void {
    var stdout_buffer: [64]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("{s}\n", .{zman.version});
    try stdout.flush();
}

fn printConfigPath(
    io: Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
) !void {
    const config_path = try zman.configFilePath(io, allocator, environ);
    defer allocator.free(config_path);

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("{s}\n", .{config_path});
    try stdout.flush();
}

fn printCliError(io: Io, comptime fmt: []const u8, args: anytype) !void {
    var stderr_buffer: [256]u8 = undefined;
    var stderr_writer = Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    try stderr.print("zman: ", .{});
    try stderr.print(fmt, args);
    try stderr.writeAll("\n");
    try stderr.flush();
}

fn confirmDelete(io: Io, task_name: []const u8) !bool {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Delete task '{s}'? [y/n] ", .{task_name});
    try stdout.flush();

    var stdin_buffer: [256]u8 = undefined;
    var stdin_reader = Io.File.stdin().reader(io, &stdin_buffer);
    const line = stdin_reader.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
        error.EndOfStream => return false,
        else => |e| return e,
    };

    const answer = std.mem.trim(u8, line, " \t\r");
    return answer.len > 0 and (answer[0] == 'y' or answer[0] == 'Y');
}

fn deleteTask(
    io: Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    task_name: []const u8,
) !void {
    if (!try confirmDelete(io, task_name)) return;

    var config_dir = try zman.openConfigDir(io, allocator, environ);
    defer config_dir.close(io);

    var store = try zman.loadStoreMut(io, allocator, config_dir);
    defer store.deinit();

    if (!store.removeTask(task_name)) {
        try printCliError(io, "task not found", .{});
        std.process.exit(1);
    }

    try zman.saveStoreMut(io, config_dir, &store, allocator);
}

fn listTasks(
    io: Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
) !void {
    var config_dir = try zman.openConfigDir(io, allocator, environ);
    defer config_dir.close(io);

    var store = try zman.loadStoreMut(io, allocator, config_dir);
    defer store.deinit();

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var name_width: usize = 4;
    for (store.tasks.items) |task| {
        name_width = @max(name_width, task.name.len);
    }

    for (store.tasks.items) |task| {
        var duration_buf: [32]u8 = undefined;
        const total = zman.taskTotalSeconds(task);
        const duration = zman.formatDurationSeconds(total, &duration_buf);
        try stdout.print("{s}", .{task.name});
        var pad_remaining = name_width - task.name.len;
        while (pad_remaining > 0) : (pad_remaining -= 1) try stdout.writeAll(" ");
        try stdout.print("  {s}\n", .{duration});
    }

    try stdout.flush();
}

fn runTimer(
    io: Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    task_name: []const u8,
) !void {
    var config_dir = try zman.openConfigDir(io, allocator, environ);
    defer config_dir.close(io);

    var store = try zman.loadStoreMut(io, allocator, config_dir);
    defer store.deinit();

    const task = try store.findOrCreateTask(task_name);
    const start = zman.unixNow(io);
    try task.times.append(allocator, .{ .start = start, .end = null });
    try zman.saveStoreMut(io, config_dir, &store, allocator);

    const time_index = task.times.items.len - 1;

    if (builtin.os.tag != .windows) {
        const act: posix.Sigaction = .{
            .handler = .{ .handler = handleSigInt },
            .mask = posix.sigemptyset(),
            .flags = posix.SA.RESTART,
        };
        posix.sigaction(.INT, &act, null);
    }

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const no_color = environ.get("NO_COLOR") != null and environ.get("NO_COLOR").?.len > 0;
    const clicolor_force = environ.get("CLICOLOR_FORCE") != null and environ.get("CLICOLOR_FORCE").?.len > 0;
    const terminal_mode = try Io.Terminal.Mode.detect(io, Io.File.stdout(), no_color, clicolor_force);
    var terminal: Io.Terminal = .{
        .writer = stdout,
        .mode = terminal_mode,
    };

    var first_draw = true;
    while (!timer_stop_requested.load(.seq_cst)) {
        const elapsed: u64 = @intCast(@max(zman.unixNow(io) - start, 0));
        var duration_buf: [32]u8 = undefined;
        const duration = zman.formatDurationSeconds(elapsed, &duration_buf);

        if (!first_draw) try stdout.writeAll("\x1b[2A");
        first_draw = false;

        try stdout.print("{s}\n", .{duration});
        try terminal.setColor(.bright_black);
        try stdout.print("press Ctrl-C to stop timer\n", .{});
        try terminal.setColor(.reset);
        try stdout.flush();

        try Io.sleep(io, Io.Duration.fromSeconds(1), .real);
    }

    const end = zman.unixNow(io);
    task.times.items[time_index].end = end;
    try zman.saveStoreMut(io, config_dir, &store, allocator);
    try stdout.writeAll("\n");
    try stdout.flush();
}
