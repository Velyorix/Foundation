# Lifecycle

Every registered package has a state:

| State | Meaning |
| --- | --- |
| `initializing` | Registered; its `Index.lua` is running or has not received the server's `Load` event yet |
| `ready` | The server fired the package's `Load` event and all its ready hooks succeeded |
| `failed` | A ready hook raised an error or a required dependency stopped being active |
| `disabled` | The package was unloaded, or Foundation disabled it |

`context:GetState()` returns the current state; `context:IsActive()` is true while the package
is `initializing` or `ready`.

## Becoming ready

The server fires each package's `Load` event once its scripts have run. At server start this
happens after every package has loaded, before the server `Start` event. When a package is
reloaded at runtime, it happens right after its scripts run again.

On that event Foundation runs the package's `OnReady` hooks in the order they were added.
If one raises an error, the error is logged with its stack trace, the package becomes `failed`,
its disable hooks run and its resources are released.

## Shutting down

A package is disabled when:

- the server unloads it (`package unload`, `package reload`, server stop, map change);
- a package it lists in `depends` is disabled or fails;
- Foundation stops.

Disabling runs in this order:

1. packages that list this one in `depends` are disabled first;
2. its `OnDisable` hooks run, newest first, while its resources still exist;
3. its tracked resources are released, newest first.

Each step runs once even if several of these causes happen together. After that, every call on
the context raises an `invalid_state` error; a resource cannot be registered for a disabled
package.

## Tracked resources

`context:Track(kind, release)` ties something your package created to its lifecycle:
`release` runs once when the package is disabled.

This matters because Foundation can disable a package that the server keeps loaded, for
example when a dependency is reloaded or when Foundation stops. In that case, the event
subscriptions, timers and other native resources your package created keep running unless
you release them. Tracking them makes them stop together with the package.

A `release` function that raises an error is logged with its stack trace; the remaining
resources are still released.

## Dependencies

List in `depends` the Foundation packages your package cannot work without, and also add
them to `packages_requirements` in your `Package.toml` so the server loads them first.

- Registration fails if a listed package is not registered or not active.
- When a dependency is disabled or fails, your package is disabled before it.
- When a dependency is reloaded, your package stays disabled: the server does not reload it.
  Reload it as well, for example `package reload my-package`.

## Reloading

| Action | Supported | Effect |
| --- | --- | --- |
| `package reload my-package` | Yes | Your package is disabled, then registers again from a clean state |
| `package reload all`, server restart | Yes | Everything starts again in load order |
| `package reload foundation` | No | Every registered package is disabled. Foundation logs a warning listing them with the command that restores them. Packages keep references to the stopped Foundation until they are reloaded |
| `package hotreload foundation` | No | Not handled; restart the server |

## Server stop

When the server stops, Foundation disables packages newest first (dependents before their
dependencies), then logs `Foundation stopped`. This happens before the server unloads the
packages themselves, so use `OnDisable` rather than the native `Unload` event for work that
needs Foundation: by the time your `Unload` handler runs, Foundation may already be stopped.
