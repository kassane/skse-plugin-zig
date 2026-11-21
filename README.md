# skse-plugin-zig (nolibc by default)

Zig bindings for the SKSE64 plugin API, with examples that build DLLs the game
loader accepts.

SKSE hands a plugin a small set of C structs: a version block, then function
pointers for messaging, tasks, Papyrus, serialization and trampolines. This
package ports those declarations to Zig as `extern struct`s, so field order and
padding follow the Windows x64 ABI.

### Requires

Built here with Zig `0.17.0` or master.

### How to use

Make project folder and open
```powershell
# inside project path
zig init -m
```
Add skse module in your `build.zig.zon`
```bash
zig fetch --save=skse git+https://github.com/kassane/skse-plugin-zig
```
Also, add `b.dependency("...")` in your `build.zig`, see [examples](./examples/).

> [!IMPORTANT]
> If need MSVC files (`libraries`/`includes`), check [xwin](https://github.com/Jake-Shadle/xwin/releases/latest) or [msvcup](https://github.com/marler8997/msvcup/releases/latest) to add in your `build.zig` like template-project [xwin-zig-test](https://github.com/kassane/xwin-zig-test).

## Build

```bash
zig build test                        # module tests
cd examples/basic && zig build        # zig-out/bin/skse-plugin-basic.dll
cd examples/report && zig build -Doptimize=ReleaseFast
cd examples/papyrus && zig build -Doptimize=ReleaseFast
```

More info, check [examples/README.md](./examples/README.md)

## License

See [LICENSE](./LICENSE)
