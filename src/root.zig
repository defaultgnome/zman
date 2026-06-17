//! Shared lib module — core logic for CLI, TUI, or future GUI.
const time = @import("lib/time.zig");
const store = @import("lib/store.zig");
const config = @import("lib/config.zig");
const pattern = @import("lib/pattern.zig");
const git = @import("lib/git.zig");

const build_options = @import("build_options");

pub const version = build_options.version;

pub const TaskTimeEntry = time.TaskTimeEntry;
pub const TaskEntry = store.TaskEntry;
pub const Store = store.Store;
pub const StoreMut = store.StoreMut;
pub const store_filename = store.store_filename;

pub const na_label = time.na_label;
pub const unnamed_task_prefix = store.unnamed_task_prefix;

pub const unixNow = time.unixNow;
pub const formatDurationSeconds = time.formatDurationSeconds;
pub const formatTimestamp = time.formatTimestamp;
pub const formatTimestampOpt = time.formatTimestampOpt;
pub const timesOverlap = time.timesOverlap;
pub const taskTotalSeconds = time.taskTotalSeconds;
pub const TaskDateRange = time.TaskDateRange;
pub const taskDateRange = time.taskDateRange;
pub const taskDateRangeDayCount = time.taskDateRangeDayCount;
pub const formatDate = time.formatDate;
pub const parseTimeSpecifier = time.parseTimeSpecifier;
pub const parseAmendTimeSpecifier = time.parseAmendTimeSpecifier;

pub const matchesPattern = pattern.matchesPattern;
pub const gitBranchName = git.gitBranchName;

pub const configDirPath = config.configDirPath;
pub const configFilePath = config.configFilePath;
pub const openConfigDir = config.openConfigDir;

pub const loadStoreMut = store.loadStoreMut;
pub const saveStoreMut = store.saveStoreMut;
pub const nextUnnamedTaskName = store.nextUnnamedTaskName;
