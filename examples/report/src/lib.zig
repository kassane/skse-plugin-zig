const std = @import("std");
const skse = @import("skse");
const pa = skse.plugin_api;

// Once SKSE has LoadLibrary'd this DLL there is no console behind stderr, so
// std.log is pointed at the report file instead of defaultLog's stderr.
pub const std_options: std.Options = .{ .log_level = .info, .logFn = skse.logFn };

const log = skse.log;

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

const InterfaceProbe = struct { id: pa.InterfaceId, name: []const u8 };
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

fn messageIdName(message_type: u32) []const u8 {
    const Id = pa.SKSEMessagingInterface.MessageId;
    // SKSE only ever sends the ids the header declares, but `@backingInt` on
    // an out of range value is undefined, so the prongs match on the integer
    // and an unknown id still prints as unknown.
    return switch (message_type) {
        @backingInt(Id.PostLoad) => "PostLoad",
        @backingInt(Id.PostPostLoad) => "PostPostLoad",
        @backingInt(Id.PreLoadGame) => "PreLoadGame",
        @backingInt(Id.PostLoadGame) => "PostLoadGame",
        @backingInt(Id.SaveGame) => "SaveGame",
        @backingInt(Id.DeleteGame) => "DeleteGame",
        @backingInt(Id.InputLoaded) => "InputLoaded",
        @backingInt(Id.NewGame) => "NewGame",
        @backingInt(Id.DataLoaded) => "DataLoaded",
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

    if (msg.type != @backingInt(pa.SKSEMessagingInterface.MessageId.PostLoad)) return;
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

    skse.openLog(report_name_w);

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
        const available = query_interface(@backingInt(probe.id)) != null;
        log("interface {s} id={d} {s}\n", .{ probe.name, @backingInt(probe.id), if (available) "ok" else "absent" });
        if (probe.id == .messaging) have_messaging = available;
    }
    if (!have_messaging) return false;

    const messaging: *pa.SKSEMessagingInterface = @ptrCast(@alignCast(query_interface(@backingInt(pa.InterfaceId.messaging)).?));
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
