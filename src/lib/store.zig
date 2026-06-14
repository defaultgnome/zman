const std = @import("std");
const Io = std.Io;
const time = @import("time.zig");
const pattern = @import("pattern.zig");
const config = @import("config.zig");

pub const TaskTimeEntry = time.TaskTimeEntry;
pub const store_filename = config.store_filename;
pub const unnamed_task_prefix = "unnamed-task-";

pub const TaskEntry = struct {
    name: []const u8,
    times: []TaskTimeEntry,
};

pub const Store = struct {
    tasks: []TaskEntry,
    last_task: ?[]const u8 = null,
};

const JsonStore = struct {
    tasks: []JsonTask = &.{},
    last_task: ?[]const u8 = null,
};

const JsonTask = struct {
    name: []const u8,
    times: []JsonTime = &.{},
};

const JsonTime = struct {
    start: ?i64 = null,
    end: ?i64 = null,
};

pub const StoreMut = struct {
    allocator: std.mem.Allocator,
    tasks: std.ArrayList(TaskMut),
    last_task: ?[]const u8 = null,

    pub const TaskMut = struct {
        name: []const u8,
        times: std.ArrayList(TaskTimeEntry),
    };

    pub fn deinit(self: *StoreMut) void {
        if (self.last_task) |lt| self.allocator.free(lt);
        for (self.tasks.items) |*task| {
            self.allocator.free(task.name);
            task.times.deinit(self.allocator);
        }
        self.tasks.deinit(self.allocator);
    }

    pub fn findTask(self: *StoreMut, name: []const u8) ?*TaskMut {
        for (self.tasks.items) |*task| {
            if (std.mem.eql(u8, task.name, name)) return task;
        }
        return null;
    }

    pub fn findOrCreateTask(self: *StoreMut, name: []const u8) !*TaskMut {
        if (self.findTask(name)) |task| return task;
        try self.tasks.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .times = std.ArrayList(TaskTimeEntry).empty,
        });
        return &self.tasks.items[self.tasks.items.len - 1];
    }

    pub fn setLastTask(self: *StoreMut, name: []const u8) !void {
        if (self.last_task) |lt| self.allocator.free(lt);
        self.last_task = try self.allocator.dupe(u8, name);
    }

    pub fn removeTask(self: *StoreMut, name: []const u8) bool {
        for (self.tasks.items, 0..) |*task, task_index| {
            if (!std.mem.eql(u8, task.name, name)) continue;
            self.allocator.free(task.name);
            task.times.deinit(self.allocator);
            _ = self.tasks.swapRemove(task_index);
            if (self.last_task) |lt| {
                if (std.mem.eql(u8, lt, name)) {
                    self.allocator.free(lt);
                    self.last_task = null;
                }
            }
            return true;
        }
        return false;
    }

    pub fn taskNamesMatching(self: *const StoreMut, pat: []const u8, out: *std.ArrayList([]const u8)) !void {
        for (self.tasks.items) |task| {
            if (pattern.matchesPattern(pat, task.name)) try out.append(self.allocator, task.name);
        }
    }

    pub fn mergeTasks(self: *StoreMut, from_name: []const u8, to_name: []const u8) !void {
        const from = self.findTask(from_name) orelse return error.TaskNotFound;
        const to = self.findTask(to_name) orelse return error.TaskNotFound;
        if (from == to) return error.SameTask;

        for (from.times.items) |from_time| {
            for (to.times.items) |to_time| {
                if (time.timesOverlap(from_time, to_time)) return error.TimeOverlap;
            }
        }

        for (from.times.items) |entry| try to.times.append(self.allocator, entry);
        _ = self.removeTask(from_name);
    }

    pub fn stopLastOpenEntry(self: *StoreMut, name: []const u8, end: i64) !void {
        const task = self.findTask(name) orelse return error.TaskNotFound;
        if (task.times.items.len == 0) return error.NoTimeEntries;
        const last = &task.times.items[task.times.items.len - 1];
        if (last.end != null) return error.TimeEntryAlreadyClosed;
        last.end = end;
    }

    pub fn addTimeEntry(self: *StoreMut, name: []const u8, entry: TaskTimeEntry) !void {
        const task = try self.findOrCreateTask(name);
        for (task.times.items) |existing| {
            if (time.timesOverlap(existing, entry)) return error.TimeOverlap;
        }
        try task.times.append(self.allocator, entry);
    }
};

pub fn nextUnnamedTaskName(store: *const StoreMut, allocator: std.mem.Allocator) ![]const u8 {
    var n: usize = 1;
    while (true) : (n += 1) {
        const candidate = try std.fmt.allocPrint(allocator, unnamed_task_prefix ++ "{d}", .{n});
        defer allocator.free(candidate);
        var taken = false;
        for (store.tasks.items) |task| {
            if (std.mem.eql(u8, task.name, candidate)) {
                taken = true;
                break;
            }
        }
        if (!taken) return try std.fmt.allocPrint(allocator, unnamed_task_prefix ++ "{d}", .{n});
    }
}

pub fn loadStoreMut(io: Io, allocator: std.mem.Allocator, config_dir: Io.Dir) !StoreMut {
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

    if (parsed.value.last_task) |lt| store.last_task = try allocator.dupe(u8, lt);

    for (parsed.value.tasks) |json_task| {
        var times = std.ArrayList(TaskTimeEntry).empty;
        errdefer times.deinit(allocator);
        for (json_task.times) |json_time| {
            try times.append(allocator, .{ .start = json_time.start, .end = json_time.end });
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

    var json_writer: std.json.Stringify = .{ .writer = &out.writer, .options = .{} };

    try json_writer.beginObject();
    if (store.last_task) |lt| {
        try json_writer.objectField("last_task");
        try json_writer.write(lt);
    }
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
            if (entry.start) |start| {
                try json_writer.objectField("start");
                try json_writer.write(start);
            }
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

test "removeTask" {
    var store = StoreMut{
        .allocator = std.testing.allocator,
        .tasks = std.ArrayList(StoreMut.TaskMut).empty,
    };
    defer store.deinit();

    try store.tasks.append(std.testing.allocator, .{
        .name = try std.testing.allocator.dupe(u8, "keep"),
        .times = std.ArrayList(TaskTimeEntry).empty,
    });
    try store.tasks.append(std.testing.allocator, .{
        .name = try std.testing.allocator.dupe(u8, "drop"),
        .times = std.ArrayList(TaskTimeEntry).empty,
    });

    try std.testing.expect(store.removeTask("drop"));
    try std.testing.expectEqual(@as(usize, 1), store.tasks.items.len);
    try std.testing.expectEqualStrings("keep", store.tasks.items[0].name);
}

test "mergeTasks" {
    var store = StoreMut{
        .allocator = std.testing.allocator,
        .tasks = std.ArrayList(StoreMut.TaskMut).empty,
    };
    defer store.deinit();

    var from_times = std.ArrayList(TaskTimeEntry).empty;
    try from_times.append(std.testing.allocator, .{ .start = 0, .end = 100 });
    try store.tasks.append(std.testing.allocator, .{
        .name = try std.testing.allocator.dupe(u8, "from"),
        .times = from_times,
    });

    var to_times = std.ArrayList(TaskTimeEntry).empty;
    try to_times.append(std.testing.allocator, .{ .start = 200, .end = 300 });
    try store.tasks.append(std.testing.allocator, .{
        .name = try std.testing.allocator.dupe(u8, "to"),
        .times = to_times,
    });

    try store.mergeTasks("from", "to");
    try std.testing.expectEqual(@as(usize, 1), store.tasks.items.len);
    try std.testing.expectEqual(@as(usize, 2), store.tasks.items[0].times.items.len);
}

test "mergeTasksOverlap" {
    var store = StoreMut{
        .allocator = std.testing.allocator,
        .tasks = std.ArrayList(StoreMut.TaskMut).empty,
    };
    defer store.deinit();

    var from_times = std.ArrayList(TaskTimeEntry).empty;
    try from_times.append(std.testing.allocator, .{ .start = 50, .end = 150 });
    try store.tasks.append(std.testing.allocator, .{
        .name = try std.testing.allocator.dupe(u8, "from"),
        .times = from_times,
    });

    var to_times = std.ArrayList(TaskTimeEntry).empty;
    try to_times.append(std.testing.allocator, .{ .start = 100, .end = 200 });
    try store.tasks.append(std.testing.allocator, .{
        .name = try std.testing.allocator.dupe(u8, "to"),
        .times = to_times,
    });

    try std.testing.expectError(error.TimeOverlap, store.mergeTasks("from", "to"));
    try std.testing.expectEqual(@as(usize, 2), store.tasks.items.len);
}

test nextUnnamedTaskName {
    var store = StoreMut{
        .allocator = std.testing.allocator,
        .tasks = std.ArrayList(StoreMut.TaskMut).empty,
    };
    defer store.deinit();

    const n1 = try nextUnnamedTaskName(&store, std.testing.allocator);
    defer std.testing.allocator.free(n1);
    try std.testing.expectEqualStrings("unnamed-task-1", n1);

    try store.tasks.append(std.testing.allocator, .{
        .name = try std.testing.allocator.dupe(u8, "unnamed-task-1"),
        .times = std.ArrayList(TaskTimeEntry).empty,
    });

    const n2 = try nextUnnamedTaskName(&store, std.testing.allocator);
    defer std.testing.allocator.free(n2);
    try std.testing.expectEqualStrings("unnamed-task-2", n2);
}
