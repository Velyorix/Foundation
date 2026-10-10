# API reference: permissions and operators

Availability: **server**. Introduced in 0.1.0 (API 0.1). Status: pre-release; the API may
change before 1.0.

Guide: [Permissions](../permissions.md). For administrators:
[Administration commands](../administration.md#operators).

## Nodes and subjects

A node is two or more dot-separated segments of `a`-`z`, `0`-`9`, `_` and `-`, 128 characters
at most. Nodes are compared in lowercase. A subject is a command sender or an account id
(non-empty string); console senders have every permission.

## `context:DeclarePermission(node, definition)`

Declares a permission owned by the package and returns the node in lowercase. The declaration
is removed when the package is disabled.

| `definition` field | Type | Description |
| --- | --- | --- |
| `description` | string, optional | Shown to administrators |
| `default` | string, optional | `"everyone"`, `"nobody"`, `"operators"` (default) or `"non_operators"` |
| `deprecated` | `true` or string, optional | Marks the permission as deprecated; the string explains what to use instead |

Raises `invalid_argument` for wrong types, `invalid_value` for a malformed node, a node that
does not start with `<package>.`, an unknown field or default, `invalid_state` if the node is
already declared or the context is no longer active.

## `context:AttachPermission(subject, node, value, options)`

Gives (`value = true`) or removes (`false`) a permission for one account. Returns a handle with
`Release()` and `IsActive()`; the attachment is removed with the handle or when the package is
disabled.

| Option | Type | Description |
| --- | --- | --- |
| `duration` | integer | Milliseconds after which the attachment no longer applies |

When attachments of several packages apply to the same account and node, `false` wins.

Raises `invalid_argument` for wrong types, `invalid_value` for a console subject, a malformed
node, an unknown option or a duration of 0 or less, `invalid_state` if the context is no longer
active.

## `Foundation.Permissions.Has(subject, node)`

Returns whether the subject has the permission. Decision order: console, attachments, provider,
declaration default (`operators` for an undeclared node). The first check of a deprecated node
logs a warning.

Raises `invalid_argument` for an invalid subject or a non-string node, `invalid_value` for a
malformed node.

## `Foundation.Permissions.Explain(subject, node)`

Returns `{ allowed = <boolean>, source = <string>, package = <string or nil> }`. `source` is
`"console"`, `"attachment"`, `"provider"` or `"default"`; `package` names the package behind an
attachment or the provider. Same errors as `Has`.

## `Foundation.Permissions.Get(node)`

Returns `{ node, owner, description, default, deprecated }` for a declared node, or `nil`.

## `Foundation.Permissions.List(package)`

Returns the declarations, sorted by node, optionally only those of `package`.

## Provider contract

Service `foundation:permission_provider`, contract version `1.x`, provided with
[`context:ProvideService`](services.md#contextprovideservicename-version-implementation-options).

| Method | Description |
| --- | --- |
| `provider:Check(account, node)` | Returns `true`, `false`, or `nil` when it has no answer |

`node` is lowercase. The best provider (highest priority) is asked on every check that no
attachment decided. An error raised by `Check` is logged as
`permission_provider callback of <package> failed`; an answer other than `true`, `false` or
`nil` is logged once; both count as no answer. Each change of provider is logged and recorded in
the audit log as `foundation:permissions/provider`.

## `Foundation.Operators.IsOperator(subject)`

Returns whether the account is an operator. Console senders count as operators. Raises
`invalid_argument` for an invalid subject.

## `Foundation.Operators.List()`

Returns `{ id, name, added_by, added_at }` for each operator, sorted by account id. `added_by` is
`"console"` or `"player:<account id>"`; `added_at` is a Unix time in seconds.

## Events

| Event | Fields |
| --- | --- |
| `foundation:operator_added` | `account`, `name` (or `nil`), `by` |
| `foundation:operator_removed` | `account`, `name` (or `nil`), `by` |

## Foundation's permissions

| Node | Default | Allows |
| --- | --- | --- |
| `foundation.command.version` | everyone | `foundation version` |
| `foundation.command.help` | everyone | `foundation help` |
| `foundation.command.packages` | operators | `foundation packages` |
| `foundation.command.services` | operators | `foundation services` |
| `foundation.command.reload-config` | operators | `foundation reload-config` |
| `foundation.command.op` | operators | `foundation op` |
| `foundation.command.permissions` | operators | `foundation permissions` |
