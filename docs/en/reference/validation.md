# API reference: keys and schemas

Availability: **server**. Introduced in 0.1.0 (API 0.1). Status: pre-release; the API may
change before 1.0.

Guide: [Keys and validation](../validation.md).

## `Foundation.Keys`

Read-only table.

### `Foundation.Keys.Parse(text, default_namespace)`

Normalizes `text` into a key `<namespace>:<path>`.

| Parameter | Type | Description |
| --- | --- | --- |
| `text` | any | Text to parse. Converted to lowercase |
| `default_namespace` | string, optional | Namespace used when `text` has none |

Returns `key, namespace, path`, or `nil, err` with `err.code == "invalid_key"` when `text` is
not a string or not a valid key.

Rules:

- namespace: `a`-`z`, `0`-`9`, `_`, `-`, `.`; 1 to 64 characters;
- path: the same characters and `/`; not empty, no `/` at the start or end, no `//`;
- whole key: at most 128 characters.

Raises `invalid_argument` if `default_namespace` is not a string.

### `Foundation.Keys.Split(key)`

Returns `namespace, path` of a key returned by `Parse`. Do not use it on unchecked text.

### `Foundation.Keys.IsReserved(namespace)`

Returns `true` for namespaces reserved for Foundation (`foundation`).

## `Foundation.Schema`

Read-only table. Builders return a schema, which can be reused and shared; do not modify it.

Builders raise `invalid_argument` or `invalid_value` when their options are wrong (unknown
option, wrong type, `min` greater than `max`, infinite bound).

### `Foundation.Schema.String(options)`

| Option | Type | Description |
| --- | --- | --- |
| `min` | integer, optional | Minimum length in characters (UTF-8) |
| `max` | integer, optional | Maximum length in characters |
| `pattern` | string, optional | Lua pattern the text must match (`string.find`); anchor it with `^` and `$` to match the whole text |

Text that is not valid UTF-8 is refused.

### `Foundation.Schema.Number(options)` / `Foundation.Schema.Integer(options)`

Options `min` and `max` (numbers, inclusive). `NaN` and infinite values are refused. `Integer`
accepts numbers without a fractional part, including floats such as `3.0`.

### `Foundation.Schema.Boolean()`

### `Foundation.Schema.Any()`

Accepts any value except `nil`. The value is not copied.

### `Foundation.Schema.Enum(values)`

`values`: non-empty array. Accepts a value equal to one of them.

### `Foundation.Schema.Optional(schema, default)`

Accepts `nil`, replaced by a copy of `default` (which may be `nil`), or what `schema` accepts.

### `Foundation.Schema.Record(fields, options)`

`fields`: table mapping field names (strings) to schemas. Fields are checked in alphabetical
order.

| Option | Values | Description |
| --- | --- | --- |
| `extra` | `"reject"` (default), `"strip"`, `"allow"` | What to do with fields not in `fields`: refuse them, leave them out of the result, or copy them unchecked |

### `Foundation.Schema.List(schema, options)`

Accepts a sequence (keys `1` to `n`, no gaps) whose items match `schema`. Options `min`,
`max`: number of items.

### `Foundation.Schema.Map(key_schema, value_schema, options)`

Accepts a table whose keys match `key_schema` and values match `value_schema`. Option `max`:
number of entries.

### `Foundation.Schema.Custom(key, fn)`

| Parameter | Type | Description |
| --- | --- | --- |
| `key` | string | Name of the check, a key with an explicit namespace (`"my-package:even"`) |
| `fn` | function | `fn(value)` returns `true`, or `false` and a message |

If `fn` raises an error, the value is refused with `check '<key>' failed` and the error is
logged for the namespace of `key`. The value is not copied.

### `Foundation.Schema.Validate(schema, value, limits)`

Returns a validated copy of `value` with defaults applied, or `nil, err` with
`err.code == "validation_failed"`.

| `limits` field | Default | Description |
| --- | --- | --- |
| `max_depth` | 16 | Maximum nesting depth |
| `max_items` | 10000 | Maximum number of values checked; validation stops beyond it |
| `max_problems` | 20 | Maximum number of problems listed |

On failure:

- `err.message`: number of problems and the first one;
- `err.details.count`: total number of problems;
- `err.details.problems`: array of `{ path, reason, params, message }`; `path` is `$` for the
  value, `$.field`, `$[1]` or `$["key"]` below it; `message` is `"<path>: <reason text>"` in
  the server language; `reason` is a stable identifier of the problem kind.

Values are never converted: validate after converting text to numbers or booleans.

Raises `invalid_argument` if `schema` is not a schema, `invalid_value` for an unknown limit.

### `Foundation.Schema.IsSchema(value)`

Returns `true` if `value` was built by `Foundation.Schema`.
