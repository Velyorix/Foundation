# Requirements

## Server

| Requirement | Value |
| --- | --- |
| nanos world server | 1.156 or newer |
| Operating system | Any platform supported by the nanos world server. Tested on Windows; Linux is not tested yet |
| Server flags | None. Foundation does not need `--enable_unsafe_libs` |
| Native modules | None. Foundation is written entirely in Lua |

Foundation runs alongside any game-mode. It is a `script` package, so it does not replace the
`game_mode` set in `Config.toml`.

## Players

Players need nothing beyond the nanos world client. Like any package, the files in
Foundation's `Shared/` folder are downloaded by clients when they join; they contain no
server data or credentials.

## Package developers

- nanos world server 1.156 or newer for testing.
- Packages that use Foundation declare it as a requirement so that it is always loaded first:

```toml
# Package.toml of your package
[script]
    packages_requirements = [
        "foundation",
    ]
```

See [Compatibility](compatibility.md) for tested versions.
