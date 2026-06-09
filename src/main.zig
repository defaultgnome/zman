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

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len > 1) {
        const task_name = try std.mem.join(arena, " ", args[1..]);
        try runTimer(io, arena, init.environ_map, task_name);
    } else {
        try listTasks(io, arena, init.environ_map);
    }
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
