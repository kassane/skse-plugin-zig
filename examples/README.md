## The installed plugin

`examples/report` builds `skse-plugin-zig-report.dll`, installed to
`Mods/skse-plugin-zig/SKSE/Plugins/`. On load it records the SKSE and runtime
versions, asks `QueryInterface` for all seven interfaces, registers a listener
on `"SKSE"`, and appends every message with a timestamp. On `PostLoad` it runs
`GetPluginInfo` over a list of plugin names, so the report shows which of them
SKSE actually reports.

The report is written beside the DLL, which under MO2 means
`Mods/skse-plugin-zig/SKSE/Plugins/` or `overwrite/SKSE/Plugins/` depending on
where the VFS sends the write, and falls back to the game folder if that open
fails. stderr is not an option: once SKSE has loaded the DLL there is no
console behind it, so `std.log` is redirected through `std_options.logFn`.

## The Papyrus example

`examples/papyrus` builds `skse-plugin-zig-papyrus.dll`, installed beside the
report plugin. It registers four global natives on a script class
(`ZigExampleCaller.Sum`, `Tick`, `Scale`, `IsEven`) through SKSE's Papyrus
interface, building each one as a `NativeFunction` object on the heap and
patching the vtable pointer. `src/papyrus_function.zig` carries that, and
`src/papyrus_vm.zig` the frame layout the arguments come out of.

`scripts/ZigExampleCaller.psc` declares them and calls them from `OnInit`, so
`APS ZigExampleCaller Run` in the console (with a reference selected) runs the
batch. Each native writes its result twice: to the plugin log beside the DLL,
and to the `~` screen through the engine's `ConsoleLog` singleton
(`src/console.zig`, RVAs taken from the 1.7.104 address library). Vanilla
Papyrus cannot print to the console, so the plugin does it instead of pulling
in ConsoleUtil Extended.