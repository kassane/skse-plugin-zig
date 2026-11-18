# skse-plugin-zig (nolibc by default)

Zig bindings for the SKSE64 plugin API, with an example that builds a DLL the
game loader will accept.

SKSE hands a plugin a small set of C structs: a version block, then function
pointers for messaging, tasks, Papyrus, serialization and trampolines. This
package ports those declarations to Zig as `extern struct`s, so field order and
padding follow the Windows x64 ABI.

### Requires

Built here with Zig `0.17.0` or master.

## What actually changed between SKSE versions

The port came from SKSE 2.3.1, which targets runtime 1.7.104. Two older header
sets were checked against it: SKSE 2.0.20 for runtime 1.5.97, and 2.2.6-gog for
runtime 1.6.1179 GOG.

All eight ported structs are byte identical across the three. Between the
2.0.20 and 2.3.1 headers 127 lines differ, but only one removed line is code
and only 27 added lines are:

- `PluginAPI.h` drops `typedef bool(*_SKSEPlugin_Query)(...)`. The 2.0.20
  loader needs that export and skips the plugin without it:
  `if (plugin.query && plugin.load)`. The 2.2.6 and 2.3.1 loaders never look
  for it.
- `PluginAPI.h` gains `SKSEPluginVersionData`, the struct behind the
  `SKSEPlugin_Version` export. The 2.3.1 loader reads it out of the PE resource
  section before running any plugin code.

A plugin aiming at all three runtimes exports `SKSEPlugin_Query`,
`SKSEPlugin_Version` and `SKSEPlugin_Load`.

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

## Build

```bash
zig build test                        # module tests
cd examples/basic && zig build        # zig-out/bin/sksePlugin.dll
cd examples/report && zig build -Doptimize=ReleaseFast
```

## License

See [LICENSE](./LICENSE)
