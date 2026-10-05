# Keys and validation

Two tools for data your package does not control: **keys** give names a namespace so that two
packages never use the same identifier by accident, and **schemas** check the shape of a value
(configuration, data from storage, values sent by players) before your code uses it.

Both are available as `Foundation.Keys` and `Foundation.Schema` once Foundation is loaded.

## Example

A package that lets other code define kits validates each definition, and names each kit with
a key in its own namespace:

<!-- example: tests/integration/packages/foundation-example-kits/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Kits",
})

local S = Foundation.Schema

local Kit = S.Record({
    name = S.String({ min = 1, max = 32 }),
    items = S.List(S.String({ min = 1 }), { min = 1, max = 10 }),
    cooldown = S.Optional(S.Integer({ min = 0 }), 300),
})

local kits = {}

local function define_kit(id, definition)
    local key, key_error = Foundation.Keys.Parse(id, context:GetId())
    if not key then
        return nil, key_error
    end
    local kit, err = S.Validate(Kit, definition)
    if not kit then
        return nil, err
    end
    kits[key] = kit
    return key
end

local key = define_kit("starter", { name = "Starter", items = { "pistol", "bandage" } })
Console.Log("defined %s, cooldown %d s", key, kits[key].cooldown)

local _, err = define_kit("builder", { name = "", items = { "hammer", 42 } })
Console.Log("rejected: %s", err.message)
for _, problem in ipairs(err.details.problems) do
    Console.Log("- %s", problem.message)
end

local _, key_error = define_kit("Bad Kit", { name = "Bad", items = { "stick" } })
Console.Log("rejected: %s", key_error.message)
```

Output (the package folder is `foundation-example-kits`):

```
defined foundation-example-kits:starter, cooldown 300 s
rejected: invalid value (2 problem(s)): $.items[2]: expected string, got integer
- $.items[2]: expected string, got integer
- $.name: must have at least 1 characters
rejected: 'Bad Kit' is not a valid key: expected '<namespace>:<path>' with lowercase letters, digits, '_', '-', '.' and, in the path, '/'
```

## Keys

A key is `<namespace>:<path>`, for example `my-shop:items/apple`:

- the namespace is usually your package identifier (`context:GetId()`); `foundation` is
  reserved for Foundation itself;
- the namespace may contain lowercase letters, digits, `_`, `-` and `.` (64 characters at most);
- the path may also contain `/`, but not at its start or end, and not twice in a row;
- the whole key is at most 128 characters.

`Foundation.Keys.Parse` converts text to lowercase, adds the default namespace when the text
has none, and returns the key, or `nil` and an error for text that cannot be a key. Use it for
text that comes from players, files or other packages.

## Schemas

A schema describes the value you expect. Build it once, at load time, and reuse it:

| Builder | Accepts |
| --- | --- |
| `S.String({ min, max, pattern })` | Text; lengths count characters, not bytes; `pattern` is a Lua pattern |
| `S.Number({ min, max })` | Finite number |
| `S.Integer({ min, max })` | Number without a fractional part |
| `S.Boolean()` | `true` or `false` |
| `S.Enum({ ... })` | One of the listed values |
| `S.Any()` | Any value except `nil` |
| `S.Optional(schema, default)` | `nil` (replaced by `default`) or a value accepted by `schema` |
| `S.Record({ field = schema, ... }, { extra })` | Table with named fields |
| `S.List(schema, { min, max })` | Sequence `{ a, b, c }` without gaps |
| `S.Map(key_schema, value_schema, { max })` | Table used as a dictionary |
| `S.Custom(key, fn)` | Whatever `fn` accepts |

`S.Validate(schema, value)` returns a **copy** of the value with defaults filled in, or `nil`
and an error. The original value is never modified, and the copy contains only what the schema
allows, so you can keep it safely. Values accepted by `S.Any` or `S.Custom` are the exception:
they are returned as they are, not copied.

Validation never converts values: the text `"5"` is not an integer. Convert first (for
example with `tonumber`), then validate.

### When validation fails

The error lists every problem, each with the place in the value where it was found (`$` is the
value itself, `$.items[2]` the second item of its `items` field):

```lua
local value, err = S.Validate(schema, input)
if not value then
    for _, problem in ipairs(err.details.problems) do
        Console.Warn(problem.message)
    end
end
```

Messages are in the server language. At most 20 problems are listed (`err.details.count` gives
the total).

### Records

Fields not listed in the record are refused by default. Pass `{ extra = "strip" }` to drop
them from the copy instead, or `{ extra = "allow" }` to keep them unchecked.

A field is required unless its schema is wrapped in `S.Optional`.

### Custom checks

`S.Custom` names a check with a key and calls your function with the value. Return `true`
to accept it, or `false` and a message to refuse it:

```lua
local Even = S.Custom("my-package:even", function(value)
    if math.type(value) == "integer" and value % 2 == 0 then
        return true
    end
    return false, "must be an even integer"
end)
```

If the function raises an error, the value is refused with `check 'my-package:even' failed` and
the error is logged for the namespace of the key. The error text itself is not put in the
problem message, which may be shown to players.

### Limits

Validation stops at 16 levels of nesting and 10,000 values, so a hostile value cannot make it
run for long. Pass different limits as the third argument of `S.Validate`. See the
[reference](reference/validation.md).
