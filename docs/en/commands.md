# Commands

A package declares its commands once; Foundation reads what players type in the chat and
what administrators type in the server console, checks the arguments, and calls the
package's function with converted values. The `buy` command of the
[events example](events.md#example) is a complete example.

## Declaring a command

```lua
context:RegisterCommand({
    name = "home",
    aliases = { "h" },
    description = "Teleport to one of your homes",
    arguments = { { name = "name", default = "home" } },
    run = function(sender, args)
        sender:Reply("Teleporting to " .. args.name)
    end,
    subcommands = {
        {
            name = "set",
            arguments = { { name = "name" }, { name = "note", type = "greedy", optional = true } },
            senders = { "player" },
            cooldown = 5000,
            run = set_home,
        },
    },
})
```

| Field | Meaning |
| --- | --- |
| `name` | The command, `home` above. Lowercase letters, digits, `_` and `-`, starting with a letter, 32 characters at most |
| `aliases` | Other names for the same command |
| `description` | Text shown by `foundation help`. Or `description_key`: a key of your [catalogs](localization.md), translated |
| `arguments` | The values the command expects, see [Arguments](#arguments) |
| `run` | `run(sender, args, info)`, called with the converted arguments by name |
| `subcommands` | Commands under this one (`home set`), declared with the same fields |
| `senders` | `{ "player" }` or `{ "console" }` to accept only one kind of sender; both by default |
| `cooldown` | Milliseconds a player must wait before using the command again |
| `audit` | `true` to record each use in the [audit log](#audit) |

A command needs `run`, `subcommands`, or both. A word that is not a subcommand is passed as an
argument.

`RegisterCommand` returns a handle: `handle:Release()` removes the command. Commands are
removed when your package stops.

## Names and conflicts

Players type `/home`, administrators type `home` in the console. The command is always also
reachable as `<package>:<name>`, here `/homes:home` for a package named `homes`.

When two packages declare the same name, the first one loaded keeps it and the second one
gets a warning:

```
[foundation] WARN  warps/commands: /spawn of warps is already used by homes; it is available as /warps:spawn
```

A command name takes priority over an alias of another package. A name freed by a stopped
package goes to the next one. The name `foundation` is reserved for Foundation's
[administration commands](administration.md).

## Arguments

Each argument has a `name` and a `type`:

| Type | Accepts | Options |
| --- | --- | --- |
| `string` (default) | One word, or several in double quotes: `"golden apple"` | `min`, `max` (length) |
| `greedy` | The rest of the line, as typed. Must be the last argument | `min`, `max` (length) |
| `integer` | Whole numbers: `5`, `-3` | `min`, `max` |
| `number` | Decimal numbers: `2.5` | `min`, `max` |
| `boolean` | `true`/`false`, `yes`/`no`, `on`/`off` | |
| `enum` | One of `values`, case-insensitive | `values` (lowercase strings) |

An argument is optional when it has a `default` or `optional = true` (its value is then `nil`
when missing). Optional arguments come after required ones. Inside quotes, `\"` is a quote and
`\\` a backslash.

When the input is wrong, the sender gets the problem and the usage line, and `run` is not
called:

```
<item> must be one of apple, sword
Usage: buy <item> [amount]
```

### Your own argument types

`context:RegisterArgumentType(name, definition)` creates a type that every package can use as
`<package>:<name>`:

```lua
context:RegisterArgumentType("colour", {
    parse = function(text)
        local colours = { red = "#f00", green = "#0f0" }
        local value = colours[text:lower()]
        if not value then
            return nil, "unknown colour '" .. text .. "'"
        end
        return value
    end,
    suggest = function(prefix)
        return { "red", "green" }
    end,
})
```

`parse` returns the value, or `nil` and a message for the sender. `suggest` returns the
completions for what the player started typing. If either function raises an error, or the
package that registered the type has stopped, the sender gets `<name> could not be read` and
the error is logged.

## Senders

`run` receives the sender:

- `sender:Reply(text)` answers in the chat (players) or the console;
- `sender:GetKind()` returns `"player"` or `"console"`; `IsPlayer()`, `IsConsole()`;
- `sender:GetName()`, `sender:GetId()` (account id for players);
- `sender:GetPlayer()` returns the player object, `nil` for the console.

Cooldowns count per player and never apply to the console. They start only when `run`
completes without error, and are reset when the server restarts.

## What happens when a command is typed

1. The line is split and the arguments are checked.
2. The sender kind is checked (`senders`), then the cooldown.
3. `foundation:command` is emitted. A listener can cancel it, for example to block commands
   for a muted player; the command then does not run.
4. `run` is called. If it raises an error, the sender gets a short message and the error is
   logged with your package name.
5. With `audit = true`, the use is recorded.
6. `foundation:command_completed` is emitted with the outcome.

See [Events](events.md#foundations-events) for both events.

## Chat and console

- **Chat**: messages starting with `/` are commands; they are not shown to other players.
  A `/` message that is not a command is answered "unknown command" and hidden, unless the
  server sets `commands.unknown_in_chat = "pass"` (see [Configuration](configuration.md)).
- **Console**: command names are case-sensitive; type them in lowercase. Each command name is
  registered with the server console when its package declares it. The server cannot remove a
  console command: after a package stops, its names answer "unknown command".

## Audit

With `audit = true`, each use is written to the audit log
(`foundation/audit/audit-<date>.log`, one JSON line per use) with the action
`<package>:command/<path>`, the sender (`console` or `player:<id>`), the outcome and the
arguments. Arguments whose name looks like a secret (`password`, `token`, ...) are masked. The
typed line itself is not recorded.

See the [reference](reference/commands.md) for every field, method and error.
