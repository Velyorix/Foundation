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

### `Foundation.Keys` and `Foundation.Schema`

See [Keys and schemas](validation.md).

### `Foundation.Capabilities`

See [Services and capabilities](services.md#foundationcapabilitieshasname-version).

## Package context

Returned by `Foundation.Register`. Methods are called with `:`. This page describes the
lifecycle methods; the context also provides:

| Methods | Reference |
| --- | --- |
| `RegisterCatalog`, `Translate` | [Localization](localization.md) |
| `Config` | [Package settings](configuration.md) |
| `NextTick`, `Delay`, `Repeat`, `Debounce`, `Throttle`, `Future`, `All` | [Timers and futures](scheduling.md) |
| `DefineEvent`, `Emit`, `Listen` | [Events](events.md) |
| `RegisterCommand`, `RegisterArgumentType` | [Commands](commands.md) |
| `ProvideService`, `GetService`, `GetServices`, `OnService` | [Services and capabilities](services.md) |

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

Foundation reports two kinds of errors.

**Wrong calls** (a programming error in the calling code) are raised as strings, at the line
of the call:

```
[foundation:<code>] <function>: <explanation>
```

| Code | Meaning |
| --- | --- |
| `invalid_argument` | An argument has the wrong type |
| `invalid_value` | An argument has the right type but an unusable value |
| `invalid_state` | The call is not possible in the current state |
| `incompatible_api` | The package requires an API version this Foundation does not provide |

**Expected failures** (invalid input, a timeout) are returned, not raised: the function returns
`nil` and an error value, or a future is rejected with one. An error value is a table:

| Field | Description |
| --- | --- |
| `code` | Stable identifier, see below |
| `category` | `"developer"`, `"user"`, `"configuration"` or `"infrastructure"` |
| `message` | Explanation in the server language |
| `params` | Values used in the message |
| `details` | Extra data for some codes, for example the problems of `validation_failed` |
| `cause` | Original error, when this one wraps another |

`tostring(err)` gives `[foundation:<code>] <message>`. Compare `err.code`, never the message,
which depends on the language.

| Code | Category | Returned by |
| --- | --- | --- |
| `invalid_key` | user | [`Foundation.Keys.Parse`](validation.md#foundationkeysparsetext-default_namespace) |
| `validation_failed` | user | [`Foundation.Schema.Validate`](validation.md#foundationschemavalidateschema-value-limits) |
| `async_failed` | developer | A [future](scheduling.md#futures) whose executor or handler raised an error |
| `timeout` | infrastructure | [`future:Timeout`](scheduling.md#future-methods) |
| `command_usage` | user | Wrong command input, reported to the [sender](commands.md#errors) |
