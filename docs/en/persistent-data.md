# Persistent data

**Persistent data** keeps one value per subject, usually a player account, under a name your
package defines: a profile, a number of visits, unlocked items. Values are checked against a
[schema](validation.md), missing values have a default, and other packages can read them.
Data is kept on disk like [stores](storage.md) and follows the same rules: saved across
restarts, never deleted when a package stops, written before the server stops.

## Example

<!-- example: tests/integration/packages/foundation-example-profiles/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Profiles",
})

local S = Foundation.Schema

local profile = context:DefineData(
    "profile",
    S.Record({
        nickname = S.String({ min = 1, max = 24 }),
        color = S.Optional(S.Enum({ "red", "green", "blue" }), "blue"),
    })
)
local visits = context:DefineData("visits", S.Integer({ min = 0 }), { default = 0 })

context:RegisterCommand({
    name = "profile",
    subcommands = {
        {
            name = "set",
            arguments = {
                { name = "account" },
                { name = "nickname", min = 1, max = 24 },
                { name = "color", type = "enum", values = { "red", "green", "blue" }, default = "blue" },
            },
            run = function(sender, args)
                profile:Set(args.account, { nickname = args.nickname, color = args.color }):Then(function()
                    sender:Reply("profile of " .. args.account .. " saved")
                end)
            end,
        },
        {
            name = "show",
            arguments = { { name = "account" } },
            run = function(sender, args)
                context:All({ profile:Get(args.account), visits:Get(args.account) }):Then(function(values)
                    local current, count = values[1], values[2]
                    if current == nil then
                        sender:Reply(args.account .. " has no profile, " .. count .. " visit(s)")
                        return
                    end
                    sender:Reply(string.format("%s (%s), %d visit(s)", current.nickname, current.color, count))
                end)
            end,
        },
    },
})

Player.Subscribe("Spawn", function(player)
    local account = player:GetAccountID()
    visits:Get(account):Then(function(count)
        return visits:Set(account, count + 1)
    end)
end)
```

In the server console:

```
profile set 76561198000000021 Alex green
[foundation] profile of 76561198000000021 saved
profile show 76561198000000021
[foundation] Alex (green), 0 visit(s)
```

## Defining data

`context:DefineData(name, schema, options)` returns a data key.

- `name` uses lowercase letters, digits, `_`, `-` and `.` (64 characters at most). The full
  name is `<package>:<name>`, for example `foundation-example-profiles:profile`; other
  packages use it to read the data.
- `schema` is a [schema](validation.md) built with `Foundation.Schema`.
- `options.default` is returned for subjects without a value. It must match the schema.
  Without it, the default is `nil`.

Each name can be defined once while the package runs. Defining it again after a restart or a
reload gives access to the values saved before.

## Subjects

A subject identifies who or what the value belongs to: a non-empty string of at most 128
characters, without control characters. Use the account id of players
(`player:GetAccountID()`), which stays the same across sessions and name changes. A player
command sender can be passed directly: its account id is used. The console is not a subject.

## Reading and writing

| Method | Resolves with |
| --- | --- |
| `key:Get(subject)` | The value, or a copy of the default when the subject has none |
| `key:Set(subject, value)` | `true` once the value is written |
| `key:Delete(subject)` | `true` if the subject had a value, `false` otherwise |

`Set` checks the value against the schema and raises at your line when it does not match:

```
[foundation:invalid_value] data:Set: argument #2 'value' is invalid: does not match the schema of 'foundation-example-profiles:profile': $.nickname: must have at least 1 characters
```

The checked value is stored, with the defaults of the schema filled in: the example above
stores `color = "blue"` when no color is given. `Get` returns a new table each time.

Operations run in the order they are made, so a `Get` made after a `Set` sees the new value.
`Get` then `Set`, as in the visit counter above, is fine for occasional changes; when several
changes of the same value can overlap, keep the current value in memory and write it with
`Set`.

## Reading another package's data

`context:ReadData("<package>:<name>")` gives read-only access to data defined by any package:

<!-- example: tests/integration/packages/foundation-example-nametags/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Name Tags",
})

local profiles = context:ReadData("foundation-example-profiles:profile")

context:RegisterCommand({
    name = "nametag",
    arguments = { { name = "account" } },
    run = function(sender, args)
        profiles:Get(args.account):Then(function(profile)
            if profile == nil then
                sender:Reply(args.account .. ": no name tag")
                return
            end
            sender:Reply(string.format("%s: [%s] %s", args.account, profile.color, profile.nickname))
        end)
    end,
})
```

```
nametag 76561198000000021
[foundation] 76561198000000021: [green] Alex
```

- `reader:Get(subject)` resolves with the stored value or `nil`. Defaults are known only to
  the package that defines the data.
- Readers have no `Set` or `Delete`: only the defining package changes its data.
- Reading works even when the defining package is stopped or not installed, and sees its
  writes in order.

## Limits

A package's persistent data counts as one store for the [quotas](storage.md#quotas): every
value of every name and subject adds its size (`<name>|<subject>` plus the JSON value).

## When your package stops

Using a data key after your package stopped raises `invalid_state`; readers in other packages
keep working. Nothing is deleted.

See the [reference](reference/storage.md#persistent-data) for every method and error.
