const std = @import("std");

// SKSE module
const skse = @import("skse");
const pa = skse.plugin_api;

/// SKSE reads this export to decide compatibility without running plugin code.
var plugin_version = pa.versionData(.{
    .name = "zig-skseplugin-basic",
    .plugin_version = 0x01000000,
    .author = "zig-skseplugin example",
    .compatible = &.{pa.RUNTIME_VERSION_1_7_104},
});

/// `typedef bool(*_SKSEPlugin_Load)(const SKSEInterface * skse);`
fn onLoad(skse_intfc: *const pa.SKSEInterface) callconv(.c) bool {
    // Real plugins call skse_intfc.GetPluginHandle.?.() here once and save it.
    _ = skse_intfc;
    return true;
}

comptime {
    @export(&plugin_version, .{ .name = "SKSEPlugin_Version" });
    @export(&onLoad, .{ .name = "SKSEPlugin_Load" });
}
