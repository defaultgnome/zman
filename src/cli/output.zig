const std = @import("std");
const zman = @import("zman");

pub fn printTaskLog(writer: anytype, task: zman.StoreMut.TaskMut) !void {
    try writer.print("Task: {s}\n", .{task.name});
    try printTaskSummary(writer, task);
    try writer.writeAll("\n");

    const col_idx = "#";
    const col_start = "Clock-in";
    const col_end = "Clock-out";
    const col_dur = "Duration";

    var idx_w: usize = col_idx.len;
    var start_w: usize = col_start.len;
    var end_w: usize = col_end.len;
    var dur_w: usize = col_dur.len;

    if (task.times.items.len > 0) {
        var idx_buf: [16]u8 = undefined;
        const max_idx = std.fmt.bufPrint(&idx_buf, "{d}", .{task.times.items.len - 1}) catch unreachable;
        idx_w = @max(idx_w, max_idx.len);
    }

    for (task.times.items) |entry| {
        var start_buf: [32]u8 = undefined;
        var end_buf: [32]u8 = undefined;
        var dur_buf: [32]u8 = undefined;
        start_w = @max(start_w, entryDisplayStart(entry, &start_buf).len);
        end_w = @max(end_w, entryDisplayEnd(entry, &end_buf).len);
        dur_w = @max(dur_w, entryDisplayDuration(entry, &dur_buf).len);
    }

    try printRow(writer, idx_w, start_w, end_w, dur_w, col_idx, col_start, col_end, col_dur);

    for (task.times.items, 0..) |entry, i| {
        var idx_buf: [16]u8 = undefined;
        var start_buf: [32]u8 = undefined;
        var end_buf: [32]u8 = undefined;
        var dur_buf: [32]u8 = undefined;
        const idx = std.fmt.bufPrint(&idx_buf, "{d}", .{i}) catch unreachable;
        try printRow(
            writer,
            idx_w,
            start_w,
            end_w,
            dur_w,
            idx,
            entryDisplayStart(entry, &start_buf),
            entryDisplayEnd(entry, &end_buf),
            entryDisplayDuration(entry, &dur_buf),
        );
    }
}

fn printTaskSummary(writer: anytype, task: zman.StoreMut.TaskMut) !void {
    var total_buf: [32]u8 = undefined;
    const total = zman.formatDurationSeconds(zman.taskTotalSeconds(task.times.items), &total_buf);

    const range = zman.taskDateRange(task.times.items);
    const range_start = range.start orelse {
        try writer.print("Total: {s}\n", .{total});
        return;
    };
    const range_end = range.end orelse {
        try writer.print("Total: {s}\n", .{total});
        return;
    };

    var start_date_buf: [16]u8 = undefined;
    var end_date_buf: [16]u8 = undefined;
    const start_date = zman.formatDate(range_start, &start_date_buf);
    const end_date = zman.formatDate(range_end, &end_date_buf);
    const day_count = zman.taskDateRangeDayCount(range) orelse 0;
    const day_label: []const u8 = if (day_count == 1) "day" else "days";

    try writer.print("Total: {s}  ·  {s} → {s}  ·  {d} {s}\n", .{
        total,
        start_date,
        end_date,
        day_count,
        day_label,
    });
}

fn entryDisplayStart(entry: zman.TaskTimeEntry, buf: *[32]u8) []const u8 {
    return zman.formatTimestampOpt(entry.start, buf);
}

fn entryDisplayEnd(entry: zman.TaskTimeEntry, buf: *[32]u8) []const u8 {
    return zman.formatTimestampOpt(entry.end, buf);
}

fn entryDisplayDuration(entry: zman.TaskTimeEntry, buf: *[32]u8) []const u8 {
    if (entry.start) |start| {
        if (entry.end) |end| {
            const secs: u64 = if (end >= start) @intCast(end - start) else 0;
            return zman.formatDurationSeconds(secs, buf);
        }
    }
    return zman.na_label;
}

fn printRow(
    writer: anytype,
    idx_w: usize,
    start_w: usize,
    end_w: usize,
    dur_w: usize,
    idx: []const u8,
    start: []const u8,
    end: []const u8,
    dur: []const u8,
) !void {
    try padPrint(writer, idx, idx_w);
    try writer.writeAll("  ");
    try padPrint(writer, start, start_w);
    try writer.writeAll("  ");
    try padPrint(writer, end, end_w);
    try writer.writeAll("  ");
    try padPrint(writer, dur, dur_w);
    try writer.writeAll("\n");
}

fn padPrint(writer: anytype, text: []const u8, width: usize) !void {
    try writer.writeAll(text);
    var pad = width - text.len;
    while (pad > 0) : (pad -= 1) try writer.writeAll(" ");
}
