const std = @import("std");
const builtin = @import("builtin");
const skse = @import("skse");
const pa = skse.plugin_api;
const w = std.os.windows;

// Once SKSE has LoadLibrary'd this DLL there is no console behind stderr, so
// std.log is pointed at the report file instead of defaultLog's stderr.
pub const std_options: std.Options = .{ .log_level = .info, .logFn = logFn };

const plugin_name: [:0]const u8 = "skse-plugin-zig-report";
const plugin_version_number: u32 = 0x01000000;
const report_name_w = std.unicode.utf8ToUtf16LeStringLiteral("skse-plugin-zig-report.log");

// Declared for every runtime this plugin will accept. SKSE 2.0.20 reads
// SKSEPlugin_Query and never looks at SKSEPlugin_Version; 2.2.6 and 2.3.1 do
// the reverse. Exporting all three covers both.
var version_block = pa.versionData(.{
    .name = plugin_name,
    .plugin_version = plugin_version_number,
    .author = "skse-plugin-zig",
    .compatible = &.{
        pa.RUNTIME_VERSION_1_5_97,
        pa.RUNTIME_VERSION_1_6_1179_GOG,
        pa.RUNTIME_VERSION_1_7_104,
    },
});

var handle: pa.PluginHandle = pa.kPluginHandle_Invalid;
var get_plugin_info: ?*const fn ([*:0]const u8) callconv(.c) ?*const pa.PluginInfo = null;
var logging = false;
var log_file: ?w.HANDLE = null;

const InterfaceProbe = struct { id: u32, name: []const u8 };
const interfaces = [_]InterfaceProbe{
    .{ .id = pa.InterfaceId.scaleform, .name = "scaleform" },
    .{ .id = pa.InterfaceId.papyrus, .name = "papyrus" },
    .{ .id = pa.InterfaceId.serialization, .name = "serialization" },
    .{ .id = pa.InterfaceId.task, .name = "task" },
    .{ .id = pa.InterfaceId.messaging, .name = "messaging" },
    .{ .id = pa.InterfaceId.object, .name = "object" },
    .{ .id = pa.InterfaceId.trampoline, .name = "trampoline" },
};

// Names as SKSE knows them, which for most plugins is the DLL name without
// ".dll". A wrong name just logs "not reported", so the list is safe to grow.
const probe_names = [_][:0]const u8{
    plugin_name,
    "JContainers64",
    "PapyrusUtil",
    "ConsoleUtilSSE",
    "MCMHelper",
    "EngineFixes",
    "SkyrimNet",
    "SexLabUtil",
};

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

extern "kernel32" fn GetModuleHandleExW(
    dw_flags: u32,
    lp_module_name: *const anyopaque,
    ph_module: *w.HMODULE,
) callconv(.winapi) c_int;

// A null module handle asks for the path of the executable, which is the
// second place the report is tried.
extern "kernel32" fn GetModuleFileNameW(
    h_module: ?w.HMODULE,
    lp_filename: [*]u16,
    n_size: u32,
) callconv(.winapi) u32;

extern "kernel32" fn GetLocalTime(lp_system_time: *SystemTime) callconv(.winapi) void;

extern "kernel32" fn CreateFileW(
    lp_file_name: [*:0]const u16,
    dw_desired_access: u32,
    dw_share_mode: u32,
    lp_security_attributes: ?*anyopaque,
    dw_creation_disposition: u32,
    dw_flags_and_attributes: u32,
    h_template_file: ?w.HANDLE,
) callconv(.winapi) w.HANDLE;

extern "kernel32" fn SetFilePointerEx(
    h_file: w.HANDLE,
    li_distance_to_move: i64,
    lp_new_file_pointer: ?*i64,
    dw_move_method: u32,
) callconv(.winapi) c_int;

extern "kernel32" fn WriteFile(
    h_file: w.HANDLE,
    lp_buffer: [*]const u8,
    n_number_of_bytes_to_write: u32,
    lp_number_of_bytes_written: ?*u32,
    lp_overlapped: ?*anyopaque,
) callconv(.winapi) c_int;

const generic_write: u32 = 0x40000000;
const file_share_read: u32 = 0x1;
const file_share_write: u32 = 0x2;
const create_always: u32 = 2;
const file_attribute_normal: u32 = 0x80;
const file_end: u32 = 2;

/// Path of `module`, or of the executable when it is null, as a null
/// terminated wide string inside `out`.
fn pathW(module: ?w.HMODULE, out: []u16) ?[:0]const u16 {
    if (builtin.os.tag != .windows) return null;
    const len = GetModuleFileNameW(module, out.ptr, @intCast(out.len));
    if (len == 0 or len >= out.len) return null;
    return out[0..len :0];
}

/// Path of the DLL this code is running in, so the report lands next to it
/// and MO2's VFS puts it in `overwrite/`.
fn modulePathW(out: []u16) ?[:0]const u16 {
    const from_address: u32 = 0x4;
    const unchanged_refcount: u32 = 0x2;
    const caller: *const anyopaque = @ptrCast(&onLoad);

    var module: w.HMODULE = undefined;
    if (GetModuleHandleExW(from_address | unchanged_refcount, caller, &module) == 0) return null;
    return pathW(module, out);
}

/// `dir\report.log` derived from `path`, null terminated for CreateFileW.
fn reportPath(path: []const u16, out: []u16) ?[:0]const u16 {
    var sep: usize = path.len;
    while (sep > 0 and path[sep - 1] != '\\') sep -= 1;
    if (sep == 0) return null;
    sep -= 1; // index of the final backslash

    const stem = report_name_w;
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
    log_file = f;
    logging = true;
    return true;
}

// CreateFileW is used rather than std.Io, whose Windows path goes straight
// to NtCreateFile and so skips the hook MO2's VFS uses to redirect writes
// out of an enabled mod folder.
fn openLog() void {
    var path_w: [1024]u16 = undefined;
    var file_w: [1024]u16 = undefined;

    if (modulePathW(&path_w)) |dll_path| {
        if (tryOpen(reportPath(dll_path, &file_w))) return;
    }
    if (pathW(null, &path_w)) |exe_path| {
        if (tryOpen(reportPath(exe_path, &file_w))) return;
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

fn log(comptime fmt: []const u8, args: anytype) void {
    if (!logging) return;
    const f = log_file orelse return;
    var buf: [1024]u8 = undefined;
    const stamp_len = writeStamp(&buf);
    const rest = std.fmt.bufPrint(buf[stamp_len..], fmt, args) catch return;
    const line = buf[0 .. stamp_len + rest.len];
    _ = SetFilePointerEx(f, 0, null, file_end);
    var written: u32 = 0;
    if (WriteFile(f, line.ptr, @intCast(line.len), &written, null) == 0) logging = false;
}

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    log("{s} {s}: ", .{ @tagName(message_level), @tagName(scope) });
    log(format ++ "\n", args);
}

fn messageIdName(message_type: u32) []const u8 {
    const Id = pa.SKSEMessagingInterface.MessageId;
    return switch (message_type) {
        Id.PostLoad => "PostLoad",
        Id.PostPostLoad => "PostPostLoad",
        Id.PreLoadGame => "PreLoadGame",
        Id.PostLoadGame => "PostLoadGame",
        Id.SaveGame => "SaveGame",
        Id.DeleteGame => "DeleteGame",
        Id.InputLoaded => "InputLoaded",
        Id.NewGame => "NewGame",
        Id.DataLoaded => "DataLoaded",
        else => "unknown",
    };
}

fn onSkseMessage(msg: *pa.SKSEMessagingInterface.Message) callconv(.c) void {
    log("msg {s} from {s} type={d} len={d}\n", .{
        messageIdName(msg.type),
        std.mem.span(msg.sender),
        msg.type,
        msg.dataLen,
    });

    if (msg.type != pa.SKSEMessagingInterface.MessageId.PostLoad) return;
    const query_info = get_plugin_info orelse return;
    for (probe_names) |name| {
        if (query_info(name)) |info| {
            log("  {s}: present, version 0x{X:0>8}\n", .{ name, info.version });
        } else {
            log("  {s}: not reported by SKSE\n", .{name});
        }
    }
}

/// `bool SKSEPlugin_Query(const SKSEInterface*, PluginInfo*)`, required by
/// SKSE 2.0.20 and ignored by everything newer.
fn onQuery(skse_intfc: *const pa.SKSEInterface, info: *pa.PluginInfo) callconv(.c) bool {
    _ = skse_intfc;
    info.infoVersion = pa.PluginInfo.kInfoVersion;
    info.name = plugin_name;
    info.version = plugin_version_number;
    return true;
}

fn onLoad(skse_intfc: *const pa.SKSEInterface) callconv(.c) bool {
    const get_handle = skse_intfc.GetPluginHandle orelse return false;
    const query_interface = skse_intfc.QueryInterface orelse return false;
    handle = get_handle();

    openLog();

    const release_index = if (skse_intfc.GetReleaseIndex) |get_index| get_index() else 0;
    log("load skse=0x{X:0>8} runtime=0x{X:0>8} release={d} editor={d}\n", .{
        skse_intfc.skseVersion,
        skse_intfc.runtimeVersion,
        release_index,
        skse_intfc.isEditor,
    });

    get_plugin_info = skse_intfc.GetPluginInfo;

    var have_messaging = false;
    for (interfaces) |probe| {
        const available = query_interface(probe.id) != null;
        log("interface {s} id={d} {s}\n", .{ probe.name, probe.id, if (available) "ok" else "absent" });
        if (probe.id == pa.InterfaceId.messaging) have_messaging = available;
    }
    if (!have_messaging) return false;

    const messaging: *pa.SKSEMessagingInterface = @ptrCast(@alignCast(query_interface(pa.InterfaceId.messaging).?));
    const register = messaging.RegisterListener orelse return false;
    const registered = register(handle, "SKSE", &onSkseMessage);
    log("listener on SKSE: {s}\n", .{if (registered) "registered" else "refused"});
    return registered;
}

comptime {
    @export(&version_block, .{ .name = "SKSEPlugin_Version" });
    @export(&onQuery, .{ .name = "SKSEPlugin_Query" });
    @export(&onLoad, .{ .name = "SKSEPlugin_Load" });
}
