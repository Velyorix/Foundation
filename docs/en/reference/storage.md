# API reference: storage and persistent data

Availability: **server**. Introduced in 0.1.0 (API 0.1). Status: pre-release; the API may
change before 1.0.

Guides: [Storage](../storage.md), [Persistent data](../persistent-data.md).

## Stores

### `context:Store(name, options)`

Returns the store `<package>` (without `name`) or `<package>/<name>`. The same name returns the
same store while the package runs. The store is released when the package is disabled; its
data is kept.

| Parameter | Type | Description |
| --- | --- | --- |
| `name` | string, optional | Lowercase letters, digits, `_` and `-` |
| `options` | table, optional | See below; without it the store is unversioned |

| Option | Type | Description |
| --- | --- | --- |
| `version` | integer | Version of the data, 1 or more. Required when `options` is given |
| `migrations` | table, optional | Functions; `migrations[n]` converts version `n` to `n + 1`. Required for every `n` from 1 to `version - 1` |

A migration receives `{ [key] = value }` with every entry of the store and returns the entries
of the next version, under the same rules as `Set`. Its errors are logged as
`store_migration callback of <package> failed`.

Raises `invalid_argument` for wrong types, `invalid_value` for a malformed name, an unknown
option, a version below 1 or a missing migration, `invalid_state` when the store is already open
with another version or the context is no longer active.

### Store methods

Every method except `Usage` and `GetName` returns a [future](scheduling.md#futures) owned by the
package. All of them raise `invalid_state` once the package has stopped.

| Method | Resolves with |
| --- | --- |
| `store:Get(key)` | The value, or `nil` |
| `store:Set(key, value)` | `true` |
| `store:Delete(key)` | `true` if the key existed, otherwise `false` |
| `store:Keys(prefix, limit)` | Sorted array of the keys starting with `prefix` (default `""`), at most `limit` (default and maximum 10000) |
| `store:Batch(operations)` | `true`; the operations are written together or not at all |
| `store:Usage()` | Returns at once `{ count, bytes, max_keys, max_bytes }` |
| `store:GetName()` | Returns at once `"<package>"` or `"<package>/<name>"` |

- `key`: non-empty string of at most 256 characters, without control characters.
- `value`: anything the JSON encoder accepts: `boolean`, finite `number`, `string`, and tables
  that are either sequences or tables with string keys, at most 32 levels deep, without cycles.
  The JSON text is at most 1048576 bytes. Integers and decimal numbers are kept apart.
- `operations`: array of `{ op = "set", key = ..., value = ... }` and
  `{ op = "delete", key = ... }`. An empty array resolves at once.

Raises `invalid_argument` for wrong types or a `nil` value, `invalid_value` for an invalid key,
an invalid operation or a value the encoder refuses.

Rejections:

| Code | Category | When |
| --- | --- | --- |
| `storage_quota` | developer | A write would exceed `max_keys` or `max_bytes`; `params` has `namespace`, `max_keys`, `max_bytes` |
| `storage_failed` | infrastructure | The database refused the operation; `cause` holds its message. The store's counts and cache are restored |
| `storage_unavailable` | infrastructure | No database, or the store could not read its keys or migrate its data |
| `storage_corrupt` | infrastructure | The stored text is not valid JSON; `params` has `namespace` and `key` |

### Sizes and quotas

A key's size is the length of the key plus the length of its JSON text, in bytes. `bytes` is
the sum for the store and `count` its number of keys. A write is rejected when it raises
`count` above `max_keys` or `bytes` above `max_bytes`
(`storage.max_keys_per_package` and `storage.max_bytes_per_package` in
[`foundation/config.toml`](../configuration.md#foundation-settings)). Limits apply to each
store separately.

## Persistent data

### `context:DefineData(name, schema, options)`

Defines `<package>:<name>` and returns its data key.

| Parameter | Type | Description |
| --- | --- | --- |
| `name` | string | Lowercase letters, digits, `_`, `-` and `.`; 64 characters at most |
| `schema` | schema | Built with [`Foundation.Schema`](validation.md#foundationschema) |
| `options` | table, optional | `default`: value returned for subjects without one; must match `schema` |

Raises `invalid_argument` for wrong types, `invalid_value` for a malformed name, an unknown
option or a default that does not match, `invalid_state` when the name is already defined by
the package or the context is no longer active.

### Data key methods

| Method | Description |
| --- | --- |
| `key:GetName()` | `"<package>:<name>"` |
| `key:Get(subject)` | Future resolved with the value, or a copy of the default |
| `key:Set(subject, value)` | Future resolved with `true`. Stores the value returned by [`Foundation.Schema.Validate`](validation.md#foundationschemavalidateschema-value-limits) |
| `key:Delete(subject)` | Future resolved with `true` if the subject had a value |

- `subject`: non-empty string of at most 128 characters without control characters, or a
  player [command sender](commands.md#sender) (its account id).

Raises `invalid_value` for an invalid subject or a value that does not match the schema
(`params.reason` names the first problem) or that the JSON encoder refuses, `invalid_state`
once the package has stopped. Futures are rejected like store futures.

### `context:ReadData(key)`

Returns a read-only reader for `<package>:<name>`, defined by any package, now or later.

| Method | Description |
| --- | --- |
| `reader:GetName()` | `"<package>:<name>"` |
| `reader:Get(subject)` | Future owned by the reading package, resolved with the stored value or `nil` |

The reader keeps working while the defining package is stopped. Raises `invalid_value` when
`key` is not a namespaced key; `reader:Get` raises `invalid_value` for an invalid subject.

## Logged messages

| Message | Level |
| --- | --- |
| `storage opened at <path>` | info |
| `storage could not be opened at <path> (...)` | error |
| `the keys of '<store>' could not be read (...)` | error |
| `migrated '<store>' from version <n> to <m> (<k> change(s))` | info |
| `the data of '<store>' could not be migrated from version <n> (...); nothing was changed` | error |
| `the data of '<store>' is version <n>, newer than version <m> declared by its package; it is left untouched` | error |
| `wrote <n> pending storage operation(s) before stopping` | info |

These messages are written in the server language; they are quoted here in English.
