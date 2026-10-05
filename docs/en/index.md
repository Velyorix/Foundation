# Foundation documentation

Foundation is a server framework for nanos world. It is installed as a script package named
`foundation` and provides the infrastructure other packages build on: package lifecycle
and resource ownership, events, commands, a permission API, services, scheduling, guarded
client-server messaging, configuration, storage, localization, logging and diagnostics.

Foundation does not contain gameplay. A server keeps its own game-mode, and features such as
economy, ranks, homes, warps or shops are provided by separate packages that use Foundation.
Any of those packages can be replaced without modifying Foundation.

> Foundation is in early development (0.1.0, unreleased). Available today: package
> registration, lifecycle and resource tracking. These pages describe only what exists in the
> current version, and the API may change before 1.0.

*Version française : [Documentation Foundation](../fr/index.md)*

## Server administrators

- [Requirements](requirements.md)
- [Installation and updates](installation.md)
- [Compatibility](compatibility.md)
- [Logging](logging.md)

## Package developers

- [Package integration](package-integration.md)
- [Lifecycle](lifecycle.md)
- [API reference: Foundation and package contexts](reference/foundation.md)
