# Package integration

A package uses Foundation by registering with it from its server code. Registration gives the
package a **context**: the object through which Foundation knows what the package owns and
when it starts and stops.

Foundation currently runs on the server only. Everything on this page is server code
(`Server/` folder).

## Declare the dependency

List `foundation` in your `Package.toml` so the server always loads it before your package:

```toml
[script]
    packages_requirements = [
        "foundation",
    ]
```

## Register

Call `Foundation.Register` at the top level of your `Server/Index.lua`, passing your package's
own `Package` object and a manifest:

<!-- example: tests/integration/packages/foundation-example-greeter/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Greeter",
})

local function on_ping(player_name)
    Console.Log("pong for %s", player_name)
end

Events.Subscribe("greeter:ping", on_ping)
context:Track("event_listener", function()
    Events.Unsubscribe("greeter:ping", on_ping)
end)

context:OnReady(function()
    Console.Log("Greeter is ready")
end)

context:OnDisable(function()
    Console.Log("Greeter is shutting down")
end)
```

Foundation reads your package identifier from `Package.GetName()`, which is your package
folder name. You cannot register on behalf of another package by changing the manifest.

Register while `Index.lua` runs, not later from a timer or an event: Foundation marks the
package ready when the server fires its `Load` event, which only happens once, right after
your scripts have run. A package registered later stays in the `initializing` state.

## Manifest

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `api` | string | yes | Foundation API version your code is written for, `"<major>"` or `"<major>.<minor>"` |
| `name` | string | no | Display name. Defaults to the `title` of your `Package.toml` |
| `version` | string | no | Your package version. Defaults to the `version` of your `Package.toml` |
| `author` | string | no | Author or organization |
| `id` | string | no | Must equal your package folder name if present; catches copied manifests |
| `depends` | array of package names | no | Foundation packages that must be registered before yours (see [Lifecycle](lifecycle.md#dependencies)) |
| `soft_depends` | array of package names | no | Packages your code can use when present; not required |
| `services` | array | no | Services your package requires or can use, see [Services](services.md#requiring-a-service) |
| `capabilities` | array | no | Capabilities your package declares, see [Capabilities](services.md#capabilities) |

Any other field is rejected, so a misspelled field fails at startup instead of being ignored.

## API version

`Foundation.API_VERSION` is the version of the contract between Foundation and packages. It is
separate from the product version (`Foundation.VERSION`).

- Before 1.0, your `api` must match exactly (`"0.1"` works only with API 0.1), because
  pre-release versions may change the API.
- From 1.0 on, the major must match and your minor must not be higher than Foundation's:
  `"1"`, `"1.0"` and `"1.2"` all work with API 1.2; `"1.3"` and `"2.0"` do not.

An incompatible version stops your package with:

```
[foundation:incompatible_api] my-package requires Foundation API 0.2; this server runs API 0.1
```

## When registration fails

Registration errors are raised at the line of your `Foundation.Register` call, so the server
log shows your file and line. The causes are:

- invalid manifest (unknown field, wrong type, `id` not matching the folder name);
- incompatible `api`;
- a package listed in `depends` is not registered or not active;
- the package is already registered (for example `Foundation.Register` called twice);
- Foundation itself is not running.

See the [reference](reference/foundation.md) for the exact error codes.
