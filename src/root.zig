//! Shared lib module, like that tommorow we can create a GUI if we want
const std = @import("std");
const Io = std.Io;
const known_folders = @import("known_folders");

pub const store_filename = "zman.json";

pub const TaskTimeEntry = struct {
    start: i64,
    end: ?i64 = null,
};

pub const TaskEntry = struct {
    name: []const u8,
    times: []TaskTimeEntry,
};

pub const Store = struct {
    tasks: []TaskEntry,
};

const JsonStore = struct {
    tasks: []JsonTask = &.{},
};

const JsonTask = struct {
    name: []const u8,
    times: []JsonTime = &.{},
};

const JsonTime = struct {
    start: i64,
    end: ?i64 = null,
};

pub const StoreMut = struct {
    allocator: std.mem.Allocator,
    tasks: std.ArrayList(TaskMut),

    pub const TaskMut = struct {
        name: []const u8,
        times: std.ArrayList(TaskTimeEntry),
    };

    pub fn deinit(self: *StoreMut) void {
        for (self.tasks.items) |*task| {
            self.allocator.free(task.name);
            task.times.deinit(self.allocator);
        }
        self.tasks.deinit(self.allocator);
    }

    pub fn findOrCreateTask(self: *StoreMut, name: []const u8) !*TaskMut {
        for (self.tasks.items) |*task| {
            if (std.mem.eql(u8, task.name, name)) return task;
        }
        try self.tasks.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .times = std.ArrayList(TaskTimeEntry).empty,
        });
        return &self.tasks.items[self.tasks.items.len - 1];
    }
};

pub fn unixNow(io: Io) i64 {
    const ts = Io.Timestamp.now(io, .real);
    return @intCast(@divTrunc(ts.nanoseconds, std.time.ns_per_s));
}

pub fn formatDurationSeconds(seconds: u64, buf: *[32]u8) []const u8 {
    const hours = seconds / std.time.s_per_hour;
    const minutes = (seconds % std.time.s_per_hour) / std.time.s_per_min;
    const secs = seconds % std.time.s_per_min;
    return std.fmt.bufPrint(buf, "{d}:{d:0>2}:{d:0>2}", .{ hours, minutes, secs }) catch unreachable;
}

pub fn taskTotalSeconds(task: StoreMut.TaskMut) u64 {
    var total: u64 = 0;
    for (task.times.items) |entry| {
        if (entry.end) |end| {
            if (end >= entry.start) total += @intCast(end - entry.start);
        }
    }
    return total;
}

pub fn openConfigDir(
    io: Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
) !Io.Dir {
    const config_path = try known_folders.getPath(io, allocator, environ, .local_configuration) orelse {
        return error.ConfigFolderUnavailable;
    };
    defer allocator.free(config_path);

    return try Io.Dir.cwd().createDirPathOpen(io, config_path, .{});
}

pub fn loadStoreMut(
    io: Io,
    allocator: std.mem.Allocator,
    config_dir: Io.Dir,
) !StoreMut {
    var store = StoreMut{
        .allocator = allocator,
        .tasks = std.ArrayList(StoreMut.TaskMut).empty,
    };
    errdefer store.deinit();

    const contents = config_dir.readFileAlloc(io, store_filename, allocator, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return store,
        else => |e| return e,
    };
    defer allocator.free(contents);

    const parsed = try std.json.parseFromSlice(JsonStore, allocator, contents, .{});
    defer parsed.deinit();

    for (parsed.value.tasks) |json_task| {
        var times = std.ArrayList(TaskTimeEntry).empty;
        errdefer times.deinit(allocator);

        for (json_task.times) |json_time| {
            try times.append(allocator, .{
                .start = json_time.start,
                .end = json_time.end,
            });
        }

        try store.tasks.append(allocator, .{
            .name = try allocator.dupe(u8, json_task.name),
            .times = times,
        });
    }

    return store;
}

pub fn saveStoreMut(io: Io, config_dir: Io.Dir, store: *const StoreMut, allocator: std.mem.Allocator) !void {
    var out = Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    var json_writer: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{},
    };

    try json_writer.beginObject();
    try json_writer.objectField("tasks");
    try json_writer.beginArray();
    for (store.tasks.items) |task| {
        try json_writer.beginObject();
        try json_writer.objectField("name");
        try json_writer.write(task.name);
        try json_writer.objectField("times");
        try json_writer.beginArray();
        for (task.times.items) |entry| {
            try json_writer.beginObject();
            try json_writer.objectField("start");
            try json_writer.write(entry.start);
            if (entry.end) |end| {
                try json_writer.objectField("end");
                try json_writer.write(end);
            }
            try json_writer.endObject();
        }
        try json_writer.endArray();
        try json_writer.endObject();
    }
    try json_writer.endArray();
    try json_writer.endObject();

    const data = try out.toOwnedSlice();
    defer allocator.free(data);

    try config_dir.writeFile(io, .{
        .sub_path = store_filename,
        .data = data,
        .flags = .{ .truncate = true },
    });
}

test formatDurationSeconds {
    var buf: [32]u8 = undefined;

    try std.testing.expectEqualStrings("0:00:01", formatDurationSeconds(1, &buf));
    try std.testing.expectEqualStrings("1:02:03", formatDurationSeconds(3723, &buf));
    try std.testing.expectEqualStrings("25:00:00", formatDurationSeconds(25 * std.time.s_per_hour, &buf));
}

test taskTotalSeconds {
    var times = std.ArrayList(TaskTimeEntry).empty;
    defer times.deinit(std.testing.allocator);
    try times.append(std.testing.allocator, .{ .start = 100, .end = 160 });
    try times.append(std.testing.allocator, .{ .start = 200, .end = null });
    try times.append(std.testing.allocator, .{ .start = 300, .end = 450 });

    const task = StoreMut.TaskMut{
        .name = "work",
        .times = times,
    };
    try std.testing.expectEqual(@as(u64, 210), taskTotalSeconds(task));
}
