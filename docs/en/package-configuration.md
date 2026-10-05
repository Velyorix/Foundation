# Package settings

`context:Config(spec)` gives your package a settings file that server administrators edit:
`foundation/config/<package>.toml`. Foundation creates it with your defaults and comments,
reads it, validates every value with the schema you give, and returns the result.

## Example

<!-- example: tests/integration/packages/foundation-example-rewards/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Daily Rewards",
})

local S = Foundation.Schema

local settings = context:Config({
    fields = {
        {
            key = "enabled",
            schema = S.Boolean(),
            default = true,
            description = "Give a reward on the first join of each day.",
            reload = "hot",
        },
        {
            key = "reward.amount",
            schema = S.Integer({ min = 1, max = 100000 }),
            default = 250,
            description = "Amount of money given.",
            reload = "hot",
        },
        {
            key = "reward.message",
            schema = S.String({ min = 1, max = 120 }),
            default = "Here is your daily reward!",
            description = "Message shown with the reward.",
        },
    },
})

local function describe()
    if not settings:Get("enabled") then
        return "daily rewards are disabled"
    end
    return string.format("daily reward: %d (%s)", settings:Get("reward.amount"), settings:Get("reward.message"))
end

Console.Log(describe())

settings:OnChange(function()
    Console.Log(describe())
end)
```

The first start creates `foundation/config/foundation-example-rewards.toml`, shown in
[Configuration](configuration.md#package-settings), and logs:

```
[foundation] INFO  foundation-example-rewards/config: created foundation/config/foundation-example-rewards.toml with the default settings
daily reward: 250 (Here is your daily reward!)
```

## Fields

Each entry of `fields` declares one setting:

| Field | Required | Meaning |
| --- | --- | --- |
| `key` | yes | `name`, or `section.name` to put the setting under `[section]` in the file. Letters, digits and `_` |
| `schema` | yes | A [schema](validation.md#schemas) the value must match |
| `default` | yes, unless the schema accepts `nil` | Value used when the setting is absent; written to the created file. It must match `schema` |
| `description` | no | Comment written above the setting in the created file |
| `reload` | no | `"restart"` (default) or `"hot"`, see [Reloading](#reloading) |
| `secret` | no | `true` for passwords, tokens and other secrets: the value is replaced with `***` in Foundation's logs |

Fields appear in the file in the order you declare them, settings without a section first.
`config_version` is reserved.

Settings can be strings, numbers, booleans, or arrays of those (`S.List`).

## Reading values

- `settings:Get(key)` returns one value, with the same key as in `fields`
  (`"reward.amount"`). Tables are returned as copies. An undeclared key raises an error, so a
  typo is found the first time the code runs.
- `settings:Values()` returns a copy of all values, sections as nested tables:
  `values.reward.amount`.
- `settings:GetPath()` returns the file path, for messages to administrators.

`context:Config` can be called once per package. Call it while your `Index.lua` runs, so an
invalid file is reported at startup.

## When the file is invalid

Your package always receives usable values. If the file cannot be read or a value does not
match its schema, Foundation logs every problem for the administrator and your package runs
with the defaults. You do not need to handle that case.

## Reloading

The file is read when `context:Config` is called: at server start, and when your package is
reloaded. `reload` declares how a setting may change while your package keeps running:

- `"restart"`: never; a new value is only used after a restart. Use it for settings read
  once (a database path, a port).
- `"hot"`: the new value replaces the old one, and the functions registered with
  `settings:OnChange(fn)` run with the list of changed keys and all values:
  `fn(changed, values)`.

Foundation 0.1.0 does not reload configuration files while packages run, so `OnChange`
functions are not called in this version. Declaring `reload` and `OnChange` now lets your
package support it without changes.

## Changing the layout

When a new version of your package renames, moves or converts settings, increase `version` and
give a migration from each older version:

```lua
local settings = context:Config({
    version = 2,
    migrations = {
        [1] = function(data)
            data.reward = { amount = data.reward_amount }
            data.reward_amount = nil
            return data
        end,
    },
    fields = {
        { key = "reward.amount", schema = S.Integer({ min = 1 }), default = 250 },
    },
})
```

A migration receives the file content as a table and returns the converted table.
`migrations[1]` converts version 1 to version 2, `migrations[2]` version 2 to 3, and so on.
Files are converted in memory only; Foundation never rewrites the administrator's file. See
the [reference](reference/configuration.md).
