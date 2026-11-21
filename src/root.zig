//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const builtin = @import("builtin");
const w = std.os.windows;

pub const plugin_api = @import("plugin_api.zig");
pub const game = @import("game.zig");
pub const papyrus = @import("papyrus_function.zig");

// SKSE LoadLibrary's the DLL and there is no console behind it, so an example
// points std.log at a file beside itself:
//     pub const std_options: std.Options = .{ .logFn = logFn };
//     openLog("name.log");
//
// CreateFileW rather than std.Io: Zig's Windows path goes to NtCreateFile and
// so skips the CreateFileW hook MO2's usvfs installs to redirect writes out of
// an enabled mod folder. Every entry point is guarded, because the package
// also builds for the host in `zig build test` and calling into kernel32 there
// is a link error.
var log_handle: ?w.HANDLE = null;
var logging = false;

const SystemTime = extern struct {
    year: u16,
    month: u16,
    day_of_week: u16,
    day: u16,
    hour: u16,
    minute: u16,
    second: u16,
    milliseconds: u16,
};

extern "kernel32" fn GetModuleHandleExW(dw_flags: u32, lp_module_name: *const anyopaque, ph_module: *w.HMODULE) callconv(.winapi) c_int;
// A null module handle asks for the path of the executable, which is the
// second place the log is tried.
extern "kernel32" fn GetModuleFileNameW(h_module: ?w.HMODULE, lp_filename: [*]u16, n_size: u32) callconv(.winapi) u32;
extern "kernel32" fn GetLocalTime(lp_system_time: *SystemTime) callconv(.winapi) void;
extern "kernel32" fn CreateFileW(lp_file_name: [*:0]const u16, dw_desired_access: u32, dw_share_mode: u32, lp_security_attributes: ?*anyopaque, dw_creation_disposition: u32, dw_flags_and_attributes: u32, h_template_file: ?w.HANDLE) callconv(.winapi) w.HANDLE;
extern "kernel32" fn SetFilePointerEx(h_file: w.HANDLE, li_distance_to_move: i64, lp_new_file_pointer: ?*i64, dw_move_method: u32) callconv(.winapi) c_int;
extern "kernel32" fn WriteFile(h_file: w.HANDLE, lp_buffer: [*]const u8, n_number_of_bytes_to_write: u32, lp_number_of_bytes_written: ?*u32, lp_overlapped: ?*anyopaque) callconv(.winapi) c_int;

const from_address: u32 = 0x4;
const unchanged_refcount: u32 = 0x2;
const generic_write: u32 = 0x40000000;
const file_share_read: u32 = 0x1;
const file_share_write: u32 = 0x2;
const create_always: u32 = 2;
const file_attribute_normal: u32 = 0x80;
const file_end: u32 = 2;

/// Path of `module`, or of the executable when it is null, as a null
/// terminated wide string inside `out`.
fn pathW(module: ?w.HMODULE, out: []u16) ?[:0]const u16 {
    const len = GetModuleFileNameW(module, out.ptr, @intCast(out.len));
    if (len == 0 or len >= out.len) return null;
    return out[0..len :0];
}

/// Path of the DLL this code is compiled into, so the log lands next to it and
/// MO2's VFS puts it in `overwrite/`. A static is used rather than
/// `@returnAddress()`, which inlining would resolve to the caller's module.
fn modulePathW(out: []u16) ?[:0]const u16 {
    var module: w.HMODULE = undefined;
    const address: *const anyopaque = @ptrCast(&log_handle);
    if (GetModuleHandleExW(from_address | unchanged_refcount, address, &module) == 0) return null;
    return pathW(module, out);
}

/// `dir\stem` derived from `path`, null terminated for CreateFileW.
fn reportPath(path: []const u16, comptime stem: [:0]const u16, out: []u16) ?[:0]const u16 {
    var sep: usize = path.len;
    while (sep > 0 and path[sep - 1] != '\\') sep -= 1;
    if (sep == 0) return null;
    sep -= 1; // index of the final backslash

    if (sep + 1 + stem.len + 1 > out.len) return null;
    @memcpy(out[0..sep], path[0..sep]);
    out[sep] = '\\';
    @memcpy(out[sep + 1 .. sep + 1 + stem.len], stem);
    out[sep + 1 + stem.len] = 0;
    return out[0 .. sep + 1 + stem.len :0];
}

fn tryOpen(path: ?[:0]const u16) bool {
    const p = path orelse return false;
    const f = CreateFileW(
        p,
        generic_write,
        file_share_read | file_share_write,
        null,
        create_always,
        file_attribute_normal,
        null,
    );
    if (f == w.INVALID_HANDLE_VALUE) return false;
    log_handle = f;
    logging = true;
    return true;
}

/// Opens `stem` beside the DLL, falling back to the executable's folder.
pub fn openLog(comptime stem: [:0]const u16) void {
    if (builtin.os.tag != .windows) return;
    var path_w: [1024]u16 = undefined;
    var file_w: [1024]u16 = undefined;

    if (modulePathW(&path_w)) |dll_path| {
        if (tryOpen(reportPath(dll_path, stem, &file_w))) return;
    }
    if (pathW(null, &path_w)) |exe_path| {
        if (tryOpen(reportPath(exe_path, stem, &file_w))) return;
    }
}

/// Writes the local date and time into `buf`, returning how much it used.
fn writeStamp(buf: []u8) usize {
    var st: SystemTime = undefined;
    GetLocalTime(&st);
    const stamp = std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} ", .{
        st.year,
        st.month,
        st.day,
        st.hour,
        st.minute,
        st.second,
    }) catch return 0;
    return stamp.len;
}

pub fn log(comptime fmt: []const u8, args: anytype) void {
    if (builtin.os.tag != .windows) return;
    if (!logging) return;
    const f = log_handle orelse return;
    var buf: [1024]u8 = undefined;
    const stamp_len = writeStamp(&buf);
    const rest = std.fmt.bufPrint(buf[stamp_len..], fmt, args) catch return;
    const line = buf[0 .. stamp_len + rest.len];
    _ = SetFilePointerEx(f, 0, null, file_end);
    var written: u32 = 0;
    if (WriteFile(f, line.ptr, @intCast(line.len), &written, null) == 0) logging = false;
}

/// `std.Options.logFn` for an example that has called `openLog`.
pub fn logFn(comptime message_level: std.log.Level, comptime scope: @EnumLiteral(), comptime format: []const u8, args: anytype) void {
    log("{s} {s}: ", .{ @tagName(message_level), @tagName(scope) });
    log(format ++ "\n", args);
}

// Pull in the tests of every re-exported declaration. Without this,
// `zig build test` reports 1/1 instead of 4/4.
test {
    std.testing.refAllDecls(@This());
    _ = plugin_api;
    _ = game;
    _ = papyrus;
}
