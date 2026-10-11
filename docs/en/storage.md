# Storage

Foundation gives each package **stores**: places where it keeps values under string keys,
saved on disk and kept across restarts and package reloads. Values are any Lua data that can
be written as JSON: numbers, strings, booleans and tables. Every operation is asynchronous and
returns a [future](scheduling.md#futures).

For values tied to a player or another subject, with a schema and a default, use
[persistent data](persistent-data.md), which is built on stores.

## The data file

Everything is kept in one SQLite file, `foundation/data/foundation.db`, next to the server
executable. Foundation creates it on the first start and logs:

```
[foundation] INFO  foundation/storage: storage opened at foundation/data/foundation.db
```

- **Backups**: copy the file while the server is stopped.
- **Nothing is deleted** when a package stops, is reloaded or is removed from the server: its
  data waits in the file until the package is installed again. Only the package itself
  deletes its keys.
- When the server stops, Foundation writes every operation still waiting, including those
  made by packages while they stop, before closing the file.
- If the file cannot be opened (missing permissions, damaged file), the error is logged and
  every store refuses its operations with `storage_unavailable`; Foundation never falls back
  to keeping data in memory, where it would be lost.

The size of each store is limited, see [Quotas](#quotas).

## Example

<!-- example: tests/integration/packages/foundation-example-warps/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Warps",
})

-- Version 1 stored { x, y, z }; version 2 adds the map name.
local warps = context:Store("warps", {
    version = 2,
    migrations = {
        [1] = function(entries)
            for name, position in pairs(entries) do
                entries[name] = { map = "default", position = position }
            end
            return entries
        end,
    },
})

context:RegisterCommand({
    name = "warp",
    subcommands = {
        {
            name = "set",
            arguments = {
                { name = "name", min = 1, max = 32 },
                { name = "x", type = "number" },
                { name = "y", type = "number" },
                { name = "z", type = "number" },
            },
            run = function(sender, args)
                warps
                    :Set(args.name, { map = "default", position = { args.x, args.y, args.z } })
                    :Then(function()
                        sender:Reply("warp " .. args.name .. " saved")
                    end)
                    :Catch(function(err)
                        sender:Reply("warp not saved: " .. err.message)
                    end)
            end,
        },
        {
            name = "show",
            arguments = { { name = "name" } },
            run = function(sender, args)
                warps:Get(args.name):Then(function(warp)
                    if warp == nil then
                        sender:Reply("no warp named " .. args.name)
                        return
                    end
                    local x, y, z = table.unpack(warp.position)
                    sender:Reply(string.format("%s: %g %g %g on %s", args.name, x, y, z, warp.map))
                end)
            end,
        },
        {
            name = "list",
            run = function(sender)
                warps:Keys():Then(function(names)
                    sender:Reply(#names .. " warp(s): " .. table.concat(names, ", "))
                end)
            end,
        },
        {
            name = "delete",
            arguments = { { name = "name" } },
            run = function(sender, args)
                warps:Delete(args.name):Then(function(existed)
                    sender:Reply(existed and ("warp " .. args.name .. " deleted") or ("no warp named " .. args.name))
                end)
            end,
        },
    },
})
```

In the server console:

```
warp set arena 1200.5 -40 100
[foundation] warp arena saved
warp show arena
[foundation] arena: 1200.5 -40 100 on default
warp list
[foundation] 1 warp(s): arena
```

The warps are still there after a restart.

## Opening a store

`context:Store(name, options)` returns a store of your package.

- Without `name`, you get the package's main store. With a name (lowercase letters, digits,
  `_` and `-`), you get a separate store, for example one per kind of data.
- Calling it again with the same name returns the same store.
- `options` declares a [version and migrations](#versions-and-migrations); leave it out for
  an unversioned store.

The store can be used at once: operations made while it reads its keys from the disk wait
and run in order.

## Reading and writing

| Method | Resolves with |
| --- | --- |
| `store:Get(key)` | The value, or `nil` when the key does not exist |
| `store:Set(key, value)` | `true` once the value is written |
| `store:Delete(key)` | `true` if the key existed, `false` otherwise |
| `store:Keys(prefix, limit)` | The keys starting with `prefix` (all keys without it), sorted, at most `limit` (10000 at most) |
| `store:Batch(operations)` | `true` once all the operations are written |

- Keys are non-empty strings of at most 256 characters, without control characters. Use
  prefixes to group them, such as `homes/76561198000000001/house`, then list one group with
  `Keys`.
- `Set` refuses `nil` (use `Delete`) and values that cannot be written as JSON: functions,
  userdata, numbers that are not finite, tables that refer to themselves, tables mixing a list
  and named fields, tables nested more than 32 levels, or values whose JSON is larger than 1 MB
  (1048576 bytes). These are programming errors: the call raises at your line.
- Integers stay integers and decimal numbers stay decimal numbers.
- `Get` returns a new table each time: changing it changes nothing in the store until you call
  `Set`.
- Operations of a package run in the order they are made: a `Get` made after a `Set` sees the
  new value, even before the `Set` future resolves.
- When a `Set`, `Delete` or `Batch` future resolves, the change is on disk.

`store:Batch(operations)` applies several changes together: either all of them are written or
none.

```lua
store:Batch({
    { op = "set", key = "kits/starter", value = { "pistol", "bandage" } },
    { op = "delete", key = "kits/old" },
})
```

`store:Usage()` answers at once with `{ count, bytes, max_keys, max_bytes }`, and
`store:GetName()` with the name of the store (`<package>` or `<package>/<name>`).

## Failures

Futures are rejected with an [error value](reference/foundation.md#errors):

| Code | When |
| --- | --- |
| `storage_quota` | The write would make the store exceed its [quota](#quotas); nothing is written |
| `storage_failed` | The disk refused the operation; the store is left as it was before the call |
| `storage_unavailable` | The data file could not be opened, or the store could not read its keys or migrate its data |
| `storage_corrupt` | The stored text of this key is not valid JSON (the file was changed by hand) |

## When your package stops

Using a store after your package stopped raises `invalid_state`. Writes made before, including
those made in `context:OnDisable`, are still written. When the package starts again,
`context:Store` gives access to the same data.

## Versions and migrations

When the shape of your values changes between two versions of your package, declare a version
and the functions that convert the old data:

```lua
local warps = context:Store("warps", {
    version = 2,
    migrations = {
        [1] = function(entries)
            -- convert version 1 to version 2
            return entries
        end,
    },
})
```

- `version` is an integer, 1 or more. A store opened without `options` is unversioned.
- `migrations[n]` converts version `n` to version `n + 1`. Every step from 1 to `version - 1`
  must be present.
- A migration receives every entry of the store as a table `{ [key] = value }` and returns the
  table of entries of the next version. It can change, add or remove entries.
- Foundation runs the missing steps when the store opens, then writes the changed entries and
  the new version in one transaction, and logs
  `migrated 'foundation-example-warps/warps' from version 1 to 2 (3 change(s))`.
- Data saved before you added a version counts as version 1. A new, empty store just records
  the declared version.

If a migration raises an error or returns something that cannot be stored, if the stored data
is newer than the declared version (an older package was installed over a newer one), or if
the result cannot be written, **nothing is changed** in the file: the error is logged, the
store refuses every operation, and your package goes to the `failed` state (see
[Lifecycle](lifecycle.md)). Fix the package, or install the newer version again, and restart it.

## Quotas

Each store has two limits, set by the server owner in
[`foundation/config.toml`](configuration.md#foundation-settings):

| Setting | Default |
| --- | --- |
| `storage.max_bytes_per_package` | 50 MB: sum of the lengths of every key and its JSON value |
| `storage.max_keys_per_package` | 100000 keys |

They apply to each store separately: a package's main store, each named store and its
[persistent data](persistent-data.md) each have their own count. A write that would go over a
limit is rejected with `storage_quota`; writes that make the store smaller are always accepted.
Changes to the limits apply after `foundation reload-config`.

See the [reference](reference/storage.md) for every method and error.
