# API reference: events

Availability: **server**. Introduced in 0.1.0 (API 0.1). Status: pre-release; the API may
change before 1.0.

Guide: [Events](../events.md).

## `context:DefineEvent(name, definition)`

Defines an event owned by the package and returns its full name.

| Parameter | Type | Description |
| --- | --- | --- |
| `name` | string | `"<name>"` or `"<package>:<name>"`, a [key](validation.md#foundationkeysparsetext-default_namespace) in the package's namespace |
| `definition` | table, optional | See below |

| `definition` field | Type | Description |
| --- | --- | --- |
| `fields` | table, optional | Field name → [schema](validation.md#foundationschema) |
| `mutable` | array, optional | Fields listeners may change; each must be in `fields` |
| `cancellable` | boolean, optional | Whether listeners may cancel the event. Default `false` |

The event is removed, with every listener on it, when the package is disabled.

Raises `invalid_argument` for wrong types, `invalid_value` for a malformed name, a name
outside the package namespace, an unknown definition field or a `mutable` entry that is not a
field, `invalid_state` if the event is already defined or the context is no longer active.

## `context:Emit(name, payload)`

Runs the listeners of an event defined by the package and returns the [event](#event-object)
once they all ran.

| Parameter | Type | Description |
| --- | --- | --- |
| `name` | string | Name used in `DefineEvent`, with or without the namespace |
| `payload` | table, optional | Field values; validated with the field schemas (defaults of `Optional` schemas apply) |

Listeners run by priority (`lowest`, `low`, `normal`, `high`, `highest`, `monitor`), then in the
order they were added. Listeners added during the dispatch wait for the next one; listeners
removed during it are skipped. An error in a listener is logged
(`event_listener callback of <package> failed`) and the dispatch continues. Events emitted
from listeners may nest up to 16 levels.

Raises `invalid_value` if the event is not defined by the package or the payload does not
match the definition, `invalid_state` when nesting goes deeper than 16 levels or the context
is no longer active.

## `context:Listen(name, fn, options)`

Calls `fn(event)` each time the event is emitted. Returns a handle with `Release()` and
`IsActive()`, like [`context:Track`](foundation.md#contexttrackkind-release-info).

| Parameter | Type | Description |
| --- | --- | --- |
| `name` | string | Full event name; without a namespace, the package's own |
| `fn` | function | Listener |
| `options` | table, optional | See below |

| Option | Type | Description |
| --- | --- | --- |
| `priority` | string | `"lowest"`, `"low"`, `"normal"` (default), `"high"`, `"highest"` or `"monitor"` |
| `ignore_cancelled` | boolean | Skip the listener while the event is cancelled. Default `false` |

Raises `invalid_argument` for wrong types, `invalid_value` if the event is not defined or an
option is unknown or invalid, `invalid_state` if the same function already listens to this
event for the package or the context is no longer active.

## Event object

| Method | Description |
| --- | --- |
| `event:GetName()` | Full event name |
| `event:Get(field)` | Value of a field (tables are copied). Raises `invalid_value` for an undeclared field |
| `event:GetData()` | Copy of all field values |
| `event:IsCancellable()` | Whether the definition allows cancelling |
| `event:IsCancelled()` | Current cancellation state |
| `event:Set(field, value)` | Changes a `mutable` field; the value is validated with its schema |
| `event:Cancel()` | Same as `SetCancelled(true)` |
| `event:SetCancelled(cancelled)` | Cancels the event or restores it |

`Set`, `Cancel` and `SetCancelled` only work inside a listener whose priority is not
`monitor`, while the event is dispatched; otherwise they raise `invalid_state`. `Set` raises
`invalid_value` for a field that is not `mutable` or a value that does not match its schema;
`Cancel` and `SetCancelled` raise `invalid_state` for an event that is not cancellable.

## Foundation's events

Defined in the reserved `foundation` namespace, emitted by Foundation only. Only
`foundation:command` is cancellable.

| Event | Fields |
| --- | --- |
| `foundation:package_ready` | `package` (string), `version` (string or `nil`) |
| `foundation:package_failed` | `package`, `version`, `message` (localized reason) |
| `foundation:package_disabled` | `package`, `version`, `reason`: `"unload"`, `"dependency_disabled"`, `"dependency_failed"` or `"foundation_stopping"` |
| `foundation:config_reloaded` | `package` (`"foundation"` for Foundation's own file), `path`, `changed` and `pending` (arrays of setting keys) |
| `foundation:command` | `command` (path, `"home set"`), `owner` (package), `sender` (`"console"` or `"player"`), `name` (sender name), `arguments` (table by argument name) |
| `foundation:command_completed` | The fields of `foundation:command` and `outcome`: `"success"` or `"failure"` |
| `foundation:service_available`, `service_unavailable` | See [Services](services.md#events) |
| `foundation:capability_available`, `capability_unavailable` | See [Services](services.md#events) |

`package_disabled` is emitted for dependents before their dependency. `config_reloaded` is
emitted once per file that reloaded without error, after the package's `OnChange` functions.
