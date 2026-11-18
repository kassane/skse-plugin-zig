//! Zig interface for SKSE64's `skse64/PluginAPI.h` (SKSE 2.3.1, runtime 1.7.104).
//!
//! Each type mirrors its C++ declaration in layout: they are `extern struct`s so
//! field order and padding follow the Windows x64 ABI, and every C callback
//! (`T (*)(...)`) is an optional function pointer. C++ references in return
//! position are ABI pointers, so they are spelled `*anyopaque`.
//!
//! Cross-checked against the header by `plugin_api_layout.cpp` (static_assert on
//! size and every field offset) and by the tests at the bottom of this file.

const std = @import("std");

/// `typedef UInt32 PluginHandle` -- opaque, `kPluginHandle_Invalid` when bad.
pub const PluginHandle = u32;
pub const kPluginHandle_Invalid: PluginHandle = 0xFFFFFFFF;

/// `struct PluginInfo`
pub const PluginInfo = extern struct {
    pub const kInfoVersion: u32 = 1;

    infoVersion: u32,
    name: [*:0]const u8,
    version: u32,
};

/// Interface ids accepted by `SKSEInterface.QueryInterface`.
/// C spells these as an untyped `enum`, so they are `u32` constants here.
pub const InterfaceId = struct {
    pub const invalid: u32 = 0;
    pub const scaleform: u32 = 1;
    pub const papyrus: u32 = 2;
    pub const serialization: u32 = 3;
    pub const task: u32 = 4;
    pub const messaging: u32 = 5;
    pub const object: u32 = 6;
    pub const trampoline: u32 = 7;
    pub const max: u32 = 8;
};

/// `struct SKSEInterface`
pub const SKSEInterface = extern struct {
    skseVersion: u32,
    runtimeVersion: u32,
    editorVersion: u32,
    isEditor: u32,
    QueryInterface: ?*const fn (id: u32) callconv(.c) ?*anyopaque,
    GetPluginHandle: ?*const fn () callconv(.c) PluginHandle,
    GetReleaseIndex: ?*const fn () callconv(.c) u32,
    GetPluginInfo: ?*const fn (name: [*:0]const u8) callconv(.c) ?*const PluginInfo,
};

/// `struct SKSESerializationInterface`
pub const SKSESerializationInterface = extern struct {
    pub const kVersion: u32 = 4;
    pub const EventCallback = ?*const fn (intfc: *SKSESerializationInterface) callconv(.c) void;
    pub const FormDeleteCallback = ?*const fn (handle: u64) callconv(.c) void;

    version: u32,
    SetUniqueID: ?*const fn (plugin: PluginHandle, uid: u32) callconv(.c) void,
    SetRevertCallback: ?*const fn (plugin: PluginHandle, callback: EventCallback) callconv(.c) void,
    SetSaveCallback: ?*const fn (plugin: PluginHandle, callback: EventCallback) callconv(.c) void,
    SetLoadCallback: ?*const fn (plugin: PluginHandle, callback: EventCallback) callconv(.c) void,
    SetFormDeleteCallback: ?*const fn (plugin: PluginHandle, callback: FormDeleteCallback) callconv(.c) void,
    WriteRecord: ?*const fn (record_type: u32, version: u32, buf: ?*const anyopaque, length: u32) callconv(.c) bool,
    OpenRecord: ?*const fn (record_type: u32, version: u32) callconv(.c) bool,
    WriteRecordData: ?*const fn (buf: ?*const anyopaque, length: u32) callconv(.c) bool,
    GetNextRecordInfo: ?*const fn (record_type: *u32, version: *u32, length: *u32) callconv(.c) bool,
    ReadRecordData: ?*const fn (buf: ?*anyopaque, length: u32) callconv(.c) u32,
    ResolveHandle: ?*const fn (handle: u64, handle_out: *u64) callconv(.c) bool,
    ResolveFormId: ?*const fn (form_id: u32, form_id_out: *u32) callconv(.c) bool,
};

/// `struct SKSETaskInterface`
pub const SKSETaskInterface = extern struct {
    pub const kInterfaceVersion: u32 = 2;

    interfaceVersion: u32,
    AddTask: ?*const fn (task: *anyopaque) callconv(.c) void,
    AddUITask: ?*const fn (task: *anyopaque) callconv(.c) void,
};

/// `struct SKSEPapyrusInterface`
pub const SKSEPapyrusInterface = extern struct {
    pub const kInterfaceVersion: u32 = 1;
    /// `typedef bool (* RegisterFunctions)(VMClassRegistry * registry)`
    pub const RegisterFunctions = ?*const fn (registry: *anyopaque) callconv(.c) bool;

    interfaceVersion: u32,
    Register: ?*const fn (callback: RegisterFunctions) callconv(.c) bool,
};

/// `struct SKSEMessagingInterface`, whose nested `struct Message` is the unit
/// of inter-plugin traffic.
pub const SKSEMessagingInterface = extern struct {
    pub const kInterfaceVersion: u32 = 2;

    pub const Message = extern struct {
        sender: [*:0]const u8,
        type: u32,
        dataLen: u32,
        data: ?*anyopaque,
    };

    pub const EventCallback = ?*const fn (msg: *Message) callconv(.c) void;

    /// SKSE messages, matching the header's `kMessage_*` enum in order.
    pub const MessageId = struct {
        pub const PostLoad: u32 = 0;
        pub const PostPostLoad: u32 = 1;
        pub const PreLoadGame: u32 = 2;
        pub const PostLoadGame: u32 = 3;
        pub const SaveGame: u32 = 4;
        pub const DeleteGame: u32 = 5;
        pub const InputLoaded: u32 = 6;
        pub const NewGame: u32 = 7;
        pub const DataLoaded: u32 = 8;
    };

    /// `kDispatcher_*` ids for `GetEventDispatcher`.
    pub const DispatcherId = struct {
        pub const ModEvent: u32 = 0;
        pub const CameraEvent: u32 = 1;
        pub const CrosshairEvent: u32 = 2;
        pub const ActionEvent: u32 = 3;
        pub const NiNodeUpdateEvent: u32 = 4;
    };

    interfaceVersion: u32,
    RegisterListener: ?*const fn (listener: PluginHandle, sender: [*:0]const u8, handler: EventCallback) callconv(.c) bool,
    Dispatch: ?*const fn (
        sender: PluginHandle,
        message_type: u32,
        data: ?*anyopaque,
        data_len: u32,
        receiver: ?[*:0]const u8,
    ) callconv(.c) bool,
    GetEventDispatcher: ?*const fn (dispatcher_id: u32) callconv(.c) ?*anyopaque,
};

/// `struct SKSEObjectInterface`. The header returns C++ references; a reference
/// is a pointer at the ABI level, and a reference cannot be null.
pub const SKSEObjectInterface = extern struct {
    pub const kInterfaceVersion: u32 = 1;

    interfaceVersion: u32,
    GetDelayFunctorManager: ?*const fn () callconv(.c) *anyopaque,
    GetObjectRegistry: ?*const fn () callconv(.c) *anyopaque,
    GetPersistentObjectStorage: ?*const fn () callconv(.c) *anyopaque,
};

/// `struct SKSETrampolineInterface`
pub const SKSETrampolineInterface = extern struct {
    pub const kInterfaceVersion: u32 = 1;

    interfaceVersion: u32,
    AllocateFromBranchPool: ?*const fn (plugin: PluginHandle, size: usize) callconv(.c) ?*anyopaque,
    AllocateFromLocalPool: ?*const fn (plugin: PluginHandle, size: usize) callconv(.c) ?*anyopaque,
};

/// `struct PluginVersionData` -- exported as `SKSEPlugin_Version` so SKSE can
/// decide compatibility without running any plugin code. Layout is exact:
/// `supportEmail` is 252 bytes, not 256, and there is no padding anywhere, so
/// the whole struct is 848 bytes.
pub const PluginVersionData = extern struct {
    pub const kVersion: u32 = 1;

    /// `kVersionIndependent_*`
    pub const Independence = struct {
        pub const address_library_post_ae: u32 = 1 << 0;
        pub const signatures: u32 = 1 << 1;
        pub const structs_post_629: u32 = 1 << 2;
    };
    /// `kVersionIndependentEx_*`
    pub const IndependenceEx = struct {
        pub const no_struct_use: u32 = 1 << 0;
        pub const address_library_v5: u32 = 1 << 1;
    };

    dataVersion: u32,
    pluginVersion: u32,
    name: [256]u8,
    author: [256]u8,
    supportEmail: [252]u8,
    versionIndependenceEx: u32,
    versionIndependence: u32,
    compatibleVersions: [16]u32,
    seVersionRequired: u32,

    pub const max_compatible: usize = 16;
};

/// Build the `SKSEPlugin_Version` value. Runs at comptime when called from a
/// `var` initializer, which is how the export below is meant to be used.
pub fn versionData(comptime opts: VersionDataOptions) PluginVersionData {
    if (opts.name.len >= 256) @compileError("plugin name must fit in 256 bytes");
    if (opts.author.len >= 256) @compileError("author must fit in 256 bytes");
    if (opts.support_email.len >= 252) @compileError("support email must fit in 252 bytes");
    if (opts.compatible.len > PluginVersionData.max_compatible) {
        @compileError("at most 16 compatible runtime versions");
    }

    var v: PluginVersionData = .{
        .dataVersion = PluginVersionData.kVersion,
        .pluginVersion = opts.plugin_version,
        .name = undefined,
        .author = undefined,
        .supportEmail = undefined,
        .versionIndependenceEx = opts.version_independence_ex,
        .versionIndependence = opts.version_independence,
        .compatibleVersions = undefined,
        .seVersionRequired = opts.se_version_required,
    };
    @memset(&v.name, 0);
    @memset(&v.author, 0);
    @memset(&v.supportEmail, 0);
    @memset(&v.compatibleVersions, 0);
    @memcpy(v.name[0..opts.name.len], opts.name);
    @memcpy(v.author[0..opts.author.len], opts.author);
    @memcpy(v.supportEmail[0..opts.support_email.len], opts.support_email);
    for (opts.compatible, 0..) |runtime_version, i| {
        v.compatibleVersions[i] = runtime_version;
    }
    return v;
}

pub const VersionDataOptions = struct {
    name: [:0]const u8,
    plugin_version: u32,
    author: [:0]const u8 = "",
    support_email: [:0]const u8 = "",
    version_independence_ex: u32 = 0,
    version_independence: u32 = 0,
    compatible: []const u32 = &.{},
    se_version_required: u32 = 0,
};

/// `typedef bool(*_SKSEPlugin_Load)(const SKSEInterface * skse);`
/// Export a function of this shape as `SKSEPlugin_Load`.
pub const PluginLoad = ?*const fn (skse: *const SKSEInterface) callconv(.c) bool;

// ---- version helpers, ported from skse64_common/skse_version.h ----

/// `MAKE_EXE_VERSION_EX(major, minor, build, sub)`
pub fn makeExeVersionEx(major: u8, minor: u8, build: u12, sub: u4) u32 {
    return (@as(u32, major & 0xFF) << 24) |
        (@as(u32, minor & 0xFF) << 16) |
        (@as(u32, build & 0xFFF) << 4) |
        @as(u32, sub & 0xF);
}

/// `MAKE_EXE_VERSION(major, minor, build)`
pub fn makeExeVersion(major: u8, minor: u8, build: u12) u32 {
    return makeExeVersionEx(major, minor, build, 0);
}

pub fn exeVersionMajor(v: u32) u8 {
    return @truncate((v & 0xFF000000) >> 24);
}
pub fn exeVersionMinor(v: u32) u8 {
    return @truncate((v & 0x00FF0000) >> 16);
}
pub fn exeVersionBuild(v: u32) u12 {
    return @truncate((v & 0x0000FFF0) >> 4);
}
pub fn exeVersionSub(v: u32) u4 {
    return @truncate(v & 0x0000000F);
}

/// The runtime this install runs: 1.7.104 (`RUNTIME_VERSION_1_7_104`, 0x01070680).
pub const RUNTIME_VERSION_1_7_104: u32 = makeExeVersion(1, 7, 104);
/// `SKSE_VERSION_RELEASEIDX` for SKSE 2.3.1.
pub const SKSE_VERSION_RELEASEIDX: u32 = 75;

/// 1.5.97, the last SE runtime, loaded by SKSE 2.0.20 (`0x01050610`).
pub const RUNTIME_VERSION_1_5_97: u32 = makeExeVersion(1, 5, 97);
/// 1.6.1179 GOG (`0x010649B1`). The sub-release is the store id: 0 is Steam,
/// 1 is GOG, and SKSE compares a plugin's compatibility list against it as
/// reported by the runtime, so the wrong sub-release never matches.
pub const RUNTIME_VERSION_1_6_1179_GOG: u32 = makeExeVersionEx(1, 6, 1179, 1);

test "exe version round trip" {
    try std.testing.expectEqual(@as(u32, 0x01070680), RUNTIME_VERSION_1_7_104);
    try std.testing.expectEqual(@as(u32, 0x01050610), RUNTIME_VERSION_1_5_97);
    try std.testing.expectEqual(@as(u32, 0x010649B1), RUNTIME_VERSION_1_6_1179_GOG);
    // Sub-release 0 of the same build is the Steam one and must not collide.
    try std.testing.expect(RUNTIME_VERSION_1_6_1179_GOG != makeExeVersionEx(1, 6, 1179, 0));
    try std.testing.expectEqual(@as(u8, 1), exeVersionMajor(RUNTIME_VERSION_1_7_104));
    try std.testing.expectEqual(@as(u8, 7), exeVersionMinor(RUNTIME_VERSION_1_7_104));
    try std.testing.expectEqual(@as(u12, 104), exeVersionBuild(RUNTIME_VERSION_1_7_104));
    try std.testing.expectEqual(@as(u4, 0), exeVersionSub(RUNTIME_VERSION_1_7_104));
}

test "C++ layout cross-check (generated from plugin_api_layout.cpp)" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(PluginInfo));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(SKSEInterface));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(SKSEMessagingInterface));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(SKSEMessagingInterface.Message));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(SKSEObjectInterface));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(SKSEPapyrusInterface));
    try std.testing.expectEqual(@as(usize, 848), @sizeOf(PluginVersionData));
    try std.testing.expectEqual(@as(usize, 104), @sizeOf(SKSESerializationInterface));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(SKSETaskInterface));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(SKSETrampolineInterface));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(PluginInfo, "infoVersion"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(PluginInfo, "name"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PluginInfo, "version"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(SKSEInterface, "GetPluginHandle"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(SKSEInterface, "GetPluginInfo"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(SKSEInterface, "GetReleaseIndex"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(SKSEInterface, "QueryInterface"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(SKSEInterface, "editorVersion"));
    try std.testing.expectEqual(@as(usize, 12), @offsetOf(SKSEInterface, "isEditor"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(SKSEInterface, "runtimeVersion"));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(SKSEInterface, "skseVersion"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(SKSEMessagingInterface, "Dispatch"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(SKSEMessagingInterface, "GetEventDispatcher"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(SKSEMessagingInterface, "RegisterListener"));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(SKSEMessagingInterface, "interfaceVersion"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(SKSEMessagingInterface.Message, "data"));
    try std.testing.expectEqual(@as(usize, 12), @offsetOf(SKSEMessagingInterface.Message, "dataLen"));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(SKSEMessagingInterface.Message, "sender"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(SKSEMessagingInterface.Message, "type"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(SKSEObjectInterface, "GetDelayFunctorManager"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(SKSEObjectInterface, "GetObjectRegistry"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(SKSEObjectInterface, "GetPersistentObjectStorage"));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(SKSEObjectInterface, "interfaceVersion"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(SKSEPapyrusInterface, "Register"));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(SKSEPapyrusInterface, "interfaceVersion"));
    try std.testing.expectEqual(@as(usize, 264), @offsetOf(PluginVersionData, "author"));
    try std.testing.expectEqual(@as(usize, 780), @offsetOf(PluginVersionData, "compatibleVersions"));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(PluginVersionData, "dataVersion"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(PluginVersionData, "name"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(PluginVersionData, "pluginVersion"));
    try std.testing.expectEqual(@as(usize, 844), @offsetOf(PluginVersionData, "seVersionRequired"));
    try std.testing.expectEqual(@as(usize, 520), @offsetOf(PluginVersionData, "supportEmail"));
    try std.testing.expectEqual(@as(usize, 776), @offsetOf(PluginVersionData, "versionIndependence"));
    try std.testing.expectEqual(@as(usize, 772), @offsetOf(PluginVersionData, "versionIndependenceEx"));
    try std.testing.expectEqual(@as(usize, 72), @offsetOf(SKSESerializationInterface, "GetNextRecordInfo"));
    try std.testing.expectEqual(@as(usize, 56), @offsetOf(SKSESerializationInterface, "OpenRecord"));
    try std.testing.expectEqual(@as(usize, 80), @offsetOf(SKSESerializationInterface, "ReadRecordData"));
    try std.testing.expectEqual(@as(usize, 96), @offsetOf(SKSESerializationInterface, "ResolveFormId"));
    try std.testing.expectEqual(@as(usize, 88), @offsetOf(SKSESerializationInterface, "ResolveHandle"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(SKSESerializationInterface, "SetFormDeleteCallback"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(SKSESerializationInterface, "SetLoadCallback"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(SKSESerializationInterface, "SetRevertCallback"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(SKSESerializationInterface, "SetSaveCallback"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(SKSESerializationInterface, "SetUniqueID"));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(SKSESerializationInterface, "WriteRecord"));
    try std.testing.expectEqual(@as(usize, 64), @offsetOf(SKSESerializationInterface, "WriteRecordData"));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(SKSESerializationInterface, "version"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(SKSETaskInterface, "AddTask"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(SKSETaskInterface, "AddUITask"));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(SKSETaskInterface, "interfaceVersion"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(SKSETrampolineInterface, "AllocateFromBranchPool"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(SKSETrampolineInterface, "AllocateFromLocalPool"));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(SKSETrampolineInterface, "interfaceVersion"));

    try std.testing.expectEqual(@as(u32, 0x01070680), RUNTIME_VERSION_1_7_104);
    try std.testing.expectEqual(@as(u32, 75), SKSE_VERSION_RELEASEIDX);
    try std.testing.expectEqual(@as(u32, 4294967295), kPluginHandle_Invalid);
    try std.testing.expectEqual(@as(u32, 8), InterfaceId.max);
}

test "versionData fills the fixed buffers" {
    const v = versionData(.{
        .name = "zig-skseplugin",
        .plugin_version = 0x01000000,
        .author = "tester",
        .compatible = &.{RUNTIME_VERSION_1_7_104},
    });
    try std.testing.expectEqualStrings("zig-skseplugin", std.mem.sliceTo(&v.name, 0));
    try std.testing.expectEqualStrings("tester", std.mem.sliceTo(&v.author, 0));
    try std.testing.expectEqual(@as(u8, 0), v.supportEmail[0]);
    try std.testing.expectEqual(RUNTIME_VERSION_1_7_104, v.compatibleVersions[0]);
    try std.testing.expectEqual(@as(u32, 0), v.compatibleVersions[1]);
}
