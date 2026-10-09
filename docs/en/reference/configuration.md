# API reference: package settings

Availability: **server**. Introduced in 0.1.0 (API 0.1). Status: pre-release; the API may
change before 1.0.

Guide: [Package settings](../package-configuration.md). For administrators:
[Configuration](../configuration.md).

## `context:Config(spec)`

Declares the package settings, reads `foundation/config/<package>.toml` (creating it from the
defaults when it is missing) and returns a [settings object](#settings-object). Can be called
once per package registration.

`spec` fields:

| Field | Type | Description |
| --- | --- | --- |
| `fields` | array | Non-empty array of [field declarations](#field-declaration) |
| `version` | integer, optional | Current layout version, 1 or more. Default `1` |
| `migrations` | table, optional | `[n] = function(data) return data end` converts a version `n` file to version `n + 1` |

Unknown fields are refused.

### Field declaration

| Field | Type | Description |
| --- | --- | --- |
| `key` | string | `"name"` or `"section.name"`; each part starts with a letter or `_` and contains letters, digits and `_` |
| `schema` | schema | Built with [`Foundation.Schema`](validation.md#foundationschema) |
| `default` | string, number, boolean or array of those | Must pass `schema`. Required unless `schema` accepts `nil`. Tables with named keys are refused: they cannot be written to the file |
| `description` | string, optional | Comment written above the setting in a created file |
| `reload` | string, optional | `"restart"` (default) or `"hot"` |
| `secret` | boolean, optional | Hide the value in Foundation's logs |

A key cannot be declared twice, cannot be `config_version`, and a name cannot be used both
as a setting and as a section.

### Reading the file

- A missing file is created with the comments and defaults.
- A file without `config_version` is read as the current version.
- An older `config_version` is converted in memory with `migrations`, in order; the file is
  not rewritten and a warning is logged.
- The file is used only if it parses, its version is supported, every migration succeeds and
  every value passes its schema. Otherwise every problem is logged and the defaults are used.

Raises:

| Code | When |
| --- | --- |
| `invalid_argument` | `spec`, a field declaration or one of their fields has the wrong type |
| `invalid_value` | Unknown field, malformed or duplicate key, reserved key, default that does not pass its schema or is a table with named keys, invalid `version` or `reload` |
| `invalid_state` | The package already called `context:Config`, or its context is no longer active |

## Settings object

### `settings:Get(key)`

Returns the value of a declared setting (a copy for tables). `key` is written as in the
declaration. Raises `invalid_value` for an undeclared key.

### `settings:Values()`

Returns a copy of all values. Settings in a section are in a nested table:
`values.section.name`.

### `settings:GetPath()`

Returns the path of the file, relative to the server folder.

### `settings:OnChange(fn)`

Adds `fn(changed, values)`, called after a reload of the file changed at least one `"hot"`
setting. `changed` is the array of changed keys, `values` a copy of all values. A setting
declared `"restart"` keeps its value until the package starts again; a warning tells the
administrator to restart.

Files are reloaded by the `foundation reload-config` console command. Functions run in the
order they were added; an error in one is logged and the others still run.

`Get`, `Values` and `OnChange` raise `invalid_state` once the package is disabled.
