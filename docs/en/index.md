# Foundation documentation

Foundation is a server framework for nanos world. It is installed as a script package named
`foundation` and provides the infrastructure other packages build on: package lifecycle
and resource ownership, events, commands, a permission API, services, scheduling, guarded
client-server messaging, configuration, storage, localization, logging and diagnostics.

Foundation does not contain gameplay. A server keeps its own game-mode, and features such as
economy, ranks, homes, warps or shops are provided by separate packages that use Foundation.
Any of those packages can be replaced without modifying Foundation.

> Foundation is in early development (0.1.0, unreleased). Available today: package
> registration, lifecycle and resource tracking, configuration files, localization, keys and
> validation, timers and futures, events, commands with console and chat input. These pages
> describe only what exists in the current version, and the API may change before 1.0.

*Version française : [Documentation Foundation](../fr/index.md)*

## Server administrators

- [Requirements](requirements.md)
- [Installation and updates](installation.md)
- [Compatibility](compatibility.md)
- [Configuration](configuration.md)
- [Administration commands](administration.md)
- [Logging](logging.md)

## Package developers

- [Package integration](package-integration.md)
- [Lifecycle](lifecycle.md)
- [Package settings](package-configuration.md)
- [Localization](localization.md)
- [Keys and validation](validation.md)
- [Timers and asynchronous work](scheduling.md)
- [Events](events.md)
- [Commands](commands.md)

API reference:

- [Foundation and package contexts](reference/foundation.md)
- [Package settings](reference/configuration.md)
- [Localization](reference/localization.md)
- [Keys and schemas](reference/validation.md)
- [Timers and futures](reference/scheduling.md)
- [Events](reference/events.md)
- [Commands](reference/commands.md)
