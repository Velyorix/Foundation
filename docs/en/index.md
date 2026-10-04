# Foundation documentation

Foundation is a server framework for nanos world. It is installed as a script package named
`foundation` and provides the infrastructure other packages build on: package lifecycle
and resource ownership, events, commands, a permission API, services, scheduling, guarded
client-server messaging, configuration, storage, localization, logging and diagnostics.

Foundation does not contain gameplay. A server keeps its own game-mode, and features such as
economy, ranks, homes, warps or shops are provided by separate packages that use Foundation.
Any of those packages can be replaced without modifying Foundation.

> Foundation is in early development (0.1.0, unreleased). The package installs and loads, but
> the public API is not available yet. These pages describe only what exists in the current
> version.

*Version française : [Documentation Foundation](../fr/index.md)*

## Server administrators

- [Requirements](requirements.md)
- [Installation and updates](installation.md)
- [Compatibility](compatibility.md)

## Package developers

The developer guides and API reference are added as each part of the API becomes available.
Start with [Requirements](requirements.md) and [Installation and updates](installation.md) to
set up a development server.
