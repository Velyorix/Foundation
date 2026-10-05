# Foundation

Foundation is a server framework for [nanos world](https://nanos-world.com). It runs as a
regular script package and gives other packages a common platform: package lifecycle and
resource ownership, events, commands, permissions, services, scheduling, guarded
networking, configuration, storage, localization, logging and diagnostics.

Foundation does not ship gameplay. Economy, jobs, ranks, homes, warps, shops and similar
features belong in separate packages built on top of it, so that servers can combine them
freely and replace any of them without touching the platform.

> **Status:** early development (0.1.0, unreleased). Package registration, lifecycle and
> resource tracking are available; the rest of the API is being implemented and nothing is
> stable before 1.0.

## Requirements

- nanos world server 1.156 or newer
- No C module and no `--enable_unsafe_libs` flag

## Installation

Copy the `package/` folder of this repository to your server as `Packages/foundation`, then
either add `foundation` to `packages` in `Config.toml` or list it in the
`packages_requirements` of the packages that use it.

Full instructions: [English](docs/en/installation.md) · [Français](docs/fr/installation.md)

## Documentation

- [English documentation](docs/en/index.md)
- [Documentation en français](docs/fr/index.md)

## Development

Contributions follow [CONTRIBUTING.md](CONTRIBUTING.md). The usual local checks:

```bash
lua tests/run.lua
stylua --check package tests
selene package
python scripts/check.py
```

Security issues: see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
