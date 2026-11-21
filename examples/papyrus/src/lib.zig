const std = @import("std");
const skse = @import("skse");
const pa = skse.plugin_api;
const papyrus = skse.papyrus;
const vm = papyrus.vm;
const value = papyrus.value;

// SKSE LoadLibrary's this DLL with no console behind stderr, so std.log goes to
// the file beside it instead of defaultLog's stderr.
pub const std_options: std.Options = .{ .log_level = .info, .logFn = skse.logFn };

const log = skse.log;
const console = skse.console;

/// Log a result to the plugin log and the `~` console.
fn emit(comptime fmt: []const u8, args: anytype) void {
    log(fmt, args);
    console.print(fmt, args);
}

const plugin_name: [:0]const u8 = "skse-plugin-zig-papyrus";
const plugin_version_number: u32 = 0x01000000;
const log_name_w = std.unicode.utf8ToUtf16LeStringLiteral("skse-plugin-zig-papyrus.log");

// The ScriptName the caller script declares.
const script_name: [:0]const u8 = "ZigExampleCaller";

var version_block = pa.versionData(.{
    .name = plugin_name,
    .plugin_version = plugin_version_number,
    .author = "skse-plugin-zig",
    .compatible = &.{pa.RUNTIME_VERSION_1_7_104},
});

fn sum(args: [*]const value.VMValue, count: u32, machine: *vm.VirtualMachine, result: *value.VMValue) callconv(.c) void {
    _ = count;
    _ = machine;
    const total = args[0].data.int + args[1].data.int;
    result.setInt(total);
    emit("Sum({d}, {d}) = {d}\n", .{ args[0].data.int, args[1].data.int, total });
}

// Zero parameters: the game's table ctor leaves a null table.
var ticks: u32 = 0;

fn tick(args: [*]const value.VMValue, count: u32, machine: *vm.VirtualMachine, result: *value.VMValue) callconv(.c) void {
    _ = args;
    _ = count;
    _ = machine;
    ticks += 1;
    result.setInt(@bitCast(ticks));
    emit("Tick() = {d}\n", .{ticks});
}

fn scale(args: [*]const value.VMValue, count: u32, machine: *vm.VirtualMachine, result: *value.VMValue) callconv(.c) void {
    _ = count;
    _ = machine;
    const scaled = args[0].data.float * args[1].data.float;
    result.setFloat(scaled);
    emit("Scale({d}, {d}) = {d}\n", .{ args[0].data.float, args[1].data.float, scaled });
}

fn isEven(args: [*]const value.VMValue, count: u32, machine: *vm.VirtualMachine, result: *value.VMValue) callconv(.c) void {
    _ = count;
    _ = machine;
    const even = @rem(args[0].data.int, 2) == 0;
    result.setBool(even);
    emit("IsEven({d}) = {s}\n", .{ args[0].data.int, if (even) "true" else "false" });
}

/// `Int[] Range(Int n)`: an int array filled 1..n. `CreateArray` writes only
/// the `Array*`, so the cell is built here as `{int_array, pointer}`; `assign`
/// the result, `reset` the creator's reference.
fn range(args: [*]const value.VMValue, count: u32, machine: *vm.VirtualMachine, result: *value.VMValue) callconv(.c) void {
    _ = count;
    const length = args[0].data.int;
    const size: u32 = if (length < 0) 0 else @intCast(length);

    var array_ptr: ?*anyopaque = null;
    const element_type = value.TypeInfo{ .raw = @backingInt(value.Type.int) };
    if (!machine.createArray(&element_type, size, &array_ptr) or array_ptr == null) {
        result.setNone();
        emit("Range({d}) = none\n", .{length});
        return;
    }

    const array: *value.Array = @ptrCast(@alignCast(array_ptr.?));
    var total: i32 = 0;
    const elements = array.elements();
    for (0..array.size) |i| {
        elements[i].setInt(@intCast(i + 1));
        total += elements[i].data.int;
    }
    var cell: value.VMValue = .{ .type = value.arrayOf(.int), .data = .{ .pointer = array_ptr } };
    value.assign(result, &cell);
    value.reset(&cell);
    emit("Range({d}) = {d} elements, sum {d}\n", .{ length, array.size, total });
}

/// SKSE's `RegisterFunctions` callback; the pointer it hands over is the VM.
fn registerNatives(registry: *anyopaque) callconv(.c) bool {
    const machine: *vm.VirtualMachine = @ptrCast(@alignCast(registry));

    const natives = [_]struct { signature: papyrus.Signature, callback: papyrus.Callback }{
        .{
            .signature = .{ .class = script_name, .name = "Sum", .params = &.{ .int, .int }, .ret = .int },
            .callback = &sum,
        },
        .{
            .signature = .{ .class = script_name, .name = "Tick", .ret = .int },
            .callback = &tick,
        },
        .{
            .signature = .{ .class = script_name, .name = "Scale", .params = &.{ .float, .float }, .ret = .float },
            .callback = &scale,
        },
        .{
            .signature = .{ .class = script_name, .name = "IsEven", .params = &.{.int}, .ret = .boolean },
            .callback = &isEven,
        },
        .{
            .signature = .{ .class = script_name, .name = "Range", .params = &.{.int}, .ret = value.arrayOf(.int) },
            .callback = &range,
        },
    };

    for (natives) |native| {
        if (papyrus.register(machine, native.signature, native.callback)) {
            log("registered {s}.{s}\n", .{ script_name, native.signature.name });
        } else |err| {
            log("register {s}: {s}\n", .{ native.signature.name, @errorName(err) });
            return false;
        }
    }
    return true;
}

/// `SKSEPlugin_Query`: required by SKSE 2.0.20, ignored by newer.
fn onQuery(skse_intfc: *const pa.SKSEInterface, info: *pa.PluginInfo) callconv(.c) bool {
    _ = skse_intfc;
    info.infoVersion = pa.PluginInfo.kInfoVersion;
    info.name = plugin_name;
    info.version = plugin_version_number;
    return true;
}

/// Preload runs before Load (SKSE 2.2.7+); record it so the log proves ordering.
var preloaded = false;

fn onPreload(skse_intfc: *const pa.SKSEInterface) callconv(.c) bool {
    _ = skse_intfc;
    preloaded = true;
    return true;
}

fn onLoad(skse_intfc: *const pa.SKSEInterface) callconv(.c) bool {
    const query_interface = skse_intfc.QueryInterface orelse return false;

    skse.openLog(log_name_w);
    log("preload ran before load: {s}\n", .{if (preloaded) "yes" else "no"});

    // The RVAs are the 1.7.104 image's; the Creation Kit is a different image.
    if (skse_intfc.isEditor != 0) {
        log("skipping: editor runtime\n", .{});
        return true;
    }
    if (skse_intfc.runtimeVersion != pa.RUNTIME_VERSION_1_7_104) {
        log("skipping: runtime 0x{X:0>8} is not 1.7.104\n", .{skse_intfc.runtimeVersion});
        return true;
    }

    const interface = query_interface(@backingInt(pa.InterfaceId.papyrus)) orelse {
        log("papyrus interface absent\n", .{});
        return false;
    };
    const papyrus_intfc: *pa.SKSEPapyrusInterface = @ptrCast(@alignCast(interface));
    if (papyrus_intfc.interfaceVersion != pa.SKSEPapyrusInterface.kInterfaceVersion) {
        log("papyrus interface version {d} refused\n", .{papyrus_intfc.interfaceVersion});
        return false;
    }

    const register = papyrus_intfc.Register orelse return false;
    const registered = register(&registerNatives);
    log("Register: {s}\n", .{if (registered) "accepted" else "refused"});
    return registered;
}

comptime {
    @export(&version_block, .{ .name = "SKSEPlugin_Version" });
    @export(&onQuery, .{ .name = "SKSEPlugin_Query" });
    @export(&onPreload, .{ .name = "SKSEPlugin_Preload" });
    @export(&onLoad, .{ .name = "SKSEPlugin_Load" });
}
