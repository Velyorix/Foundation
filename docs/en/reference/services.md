# API reference: services and capabilities

Availability: **server**. Introduced in 0.1.0 (API 0.1). Status: pre-release; the API may
change before 1.0.

Guide: [Services and capabilities](../services.md).

## Versions

A provider declares `"<major>.<minor>"`. A consumer asks for `"<major>"` (same major, any minor),
`"<major>.<minor>"` (same major, minor at least the one asked) or `nil` (any version).

## `context:ProvideService(name, version, implementation, options)`

Adds a provider and returns a handle with `Release()` and `IsActive()`. The provider is removed
when the package is disabled.

| Parameter | Type | Description |
| --- | --- | --- |
| `name` | string | Service key; without a namespace, the package's own |
| `version` | string | `"<major>.<minor>"` |
| `implementation` | table | Fields and methods of the service |
| `options` | table, optional | See below |

| Option | Type | Description |
| --- | --- | --- |
| `priority` | integer | From -1000000 to 1000000. Default 0. The highest is selected |
| `replace` | boolean | Replace this package's provider of the same service |

Raises `invalid_argument` for wrong types, `invalid_value` for a malformed name or version, an
unknown option or a priority out of range, `invalid_state` when another package provides the
same service and major version with the same priority, when the package already provides the
service and `replace` is not set, or when the context is no longer active.

## `context:GetService(name, version)`

Returns `service, info` for the best compatible provider (highest priority, then first
registered), or `nil`.

- `service`: proxy of the implementation. Methods called with `:` run on the implementation
  itself; fields are read through. Assigning a field raises `invalid_state`. Any use after the
  provider is removed raises `invalid_state` naming the service and its provider.
- `info`: `{ service = <proxy>, provider = <package>, version = <string>, priority = <integer> }`.

Raises `invalid_value` for a malformed name or version, `invalid_state` if the context is no
longer active.

## `context:GetServices(name, version)`

Returns the array of `info` tables of every compatible provider, best first.

## `context:OnService(name, version, fn)`

Calls `fn(service, info)` at once when a compatible provider exists, then each time the best
compatible provider changes; `fn(nil)` when none is left. A replacement made with
`replace = true` is reported once. Returns a handle with `Release()` and `IsActive()`; the
watch stops when the package is disabled. `fn` runs guarded: an error is logged as
`service_watcher callback of <package> failed`.

Raises `invalid_argument` if `fn` is not a function, `invalid_value` for a malformed name or
version, `invalid_state` if the context is no longer active.

## Manifest `services`

Array of `{ name, version, optional }`:

| Field | Type | Description |
| --- | --- | --- |
| `name` | string | Service key with an explicit namespace |
| `version` | string, optional | Accepted versions, as for `GetService` |
| `optional` | boolean, optional | `true` for a service the package can work without |

When the package becomes ready, each required service must have a compatible provider;
otherwise the package fails (`'<package>' requires the service '<name>' (...), which no
package provides`). When the last compatible provider of a required service is removed while
the package is ready, the package fails. Entries are unique per name.

## Manifest `capabilities`

Array of `"<namespace>:<name>"` or `{ name = "<namespace>:<name>", version = "<major>.<minor>" }`.
Names are unique in the list; the `foundation` namespace is reserved. A capability is available
while the package is `ready`.

A capability with the name of a provided service is accepted with a warning: use distinct
names.

## `Foundation.Capabilities.Has(name, version)`

Returns `true` if a ready package declares a compatible capability. A capability declared
without a version only matches requests without a version.

## `Foundation.Capabilities.Providers(name, version)`

Returns the array of `{ package, version }` of the ready packages that declare a compatible
capability, in the order they became ready.

Both raise `invalid_value` for a name without a namespace or a malformed version.

## Events

| Event | Fields |
| --- | --- |
| `foundation:service_available` | `service`, `provider`, `version`, `priority` |
| `foundation:service_unavailable` | `service`, `provider`, `version`, `priority` |
| `foundation:capability_available` | `capability`, `package`, `version` (or `nil`) |
| `foundation:capability_unavailable` | `capability`, `package`, `version` (or `nil`) |

Not cancellable. A replacement emits `service_unavailable` for the old provider, then
`service_available` for the new one.
