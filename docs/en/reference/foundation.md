# API reference: Foundation and package contexts

Availability: **server**. Introduced in 0.1.0 (API 0.1). Status: pre-release; the API may
change before 1.0.

## `Foundation`

Global table exported by the `foundation` package. It is read-only: assigning a field raises
`invalid_state`.

### `Foundation.VERSION`

String. Product version of the installed Foundation, for example `"0.1.0"`.

### `Foundation.API_VERSION`

String. API contract version, `"<major>.<minor>"`, for example `"0.1"`. Use it in logs or
diagnostics; in your manifest, write the version your code was written for instead, so an
incompatible Foundation is detected.

### `Foundation.Register(package, manifest)`

Registers the calling package and returns its [context](#package-context).

| Parameter | Type | Description |
| --- | --- | --- |
| `package` | table | Your package's `Package` object |
| `manifest` | table | See [manifest fields](../package-integration.md#manifest) |

Call it once, at the top level of `Server/Index.lua`.

Raises, at the caller's line:

| Code | When |
| --- | --- |
| `invalid_argument` | `package` or `manifest` has the wrong type, or a manifest field has the wrong type |
| `invalid_value` | Unknown manifest field, malformed `api`, `id` different from the folder name, invalid package name in `depends` or `soft_depends` |
| `incompatible_api` | `manifest.api` is not compatible with `Foundation.API_VERSION` |
| `invalid_state` | Already registered; a `depends` entry is missing or inactive; Foundation is not running |

## Package context

Returned by `Foundation.Register`. Methods are called with `:`.

### `context:GetId()`

Returns the package identifier (package folder name).

### `context:GetName()`

Returns the display name: `manifest.name`, otherwise the package title.

### `context:GetVersion()`

Returns `manifest.version`, otherwise the version from `Package.toml`.

### `context:GetState()`

Returns `"initializing"`, `"ready"`, `"failed"` or `"disabled"`. See [Lifecycle](../lifecycle.md).

### `context:IsActive()`

Returns `true` while the state is `initializing` or `ready` and the context belongs to the
current registration of the package.

### `context:OnReady(hook)`

Adds a function called once when the package becomes ready, with the context as argument.
Hooks run in the order they were added. If a hook raises an error, the package becomes `failed`.

Raises `invalid_argument` if `hook` is not a function, `invalid_state` if the package is no
longer `initializing`.

### `context:OnDisable(hook)`

Adds a function called once when the package is disabled or fails, with the context as
argument. Hooks run newest first, before tracked resources are released. An error in a hook
is logged; the other hooks still run.

Raises `invalid_argument` if `hook` is not a function, `invalid_state` if the context is no
longer active.

### `context:Track(kind, release, info)`

Ties a resource to the package. `release` is called once, with the returned handle, when the
package is disabled or fails, or when you call `handle:Release()`.

| Parameter | Type | Description |
| --- | --- | --- |
| `kind` | string | Short label shown in diagnostics, for example `"event_listener"` |
| `release` | function | Undoes whatever created the resource |
| `info` | table, optional | Extra values for diagnostics (copied) |

Returns a handle with:

- `handle:Release()`: runs `release` now; returns `true` the first time, `false` afterwards;
- `handle:IsActive()`: `true` until the resource has been released.

Raises `invalid_argument` or `invalid_value` for bad arguments, `invalid_state` if the context
is no longer active.

## Errors

Errors caused by a wrong call are raised as strings:

```
[foundation:<code>] <function>: <explanation>
```

| Code | Meaning |
| --- | --- |
| `invalid_argument` | An argument has the wrong type |
| `invalid_value` | An argument has the right type but an unusable value |
| `invalid_state` | The call is not possible in the current state |
| `incompatible_api` | The package requires an API version this Foundation does not provide |
