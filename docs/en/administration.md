# Administration commands

Foundation adds a `foundation` command, typed in the server console or, with the matching
permission, in the chat (`/foundation ...`). The console can use every subcommand; players
need the permission listed in [Who can use them](#who-can-use-them).

| Command | Effect |
| --- | --- |
| `foundation version` | Shows the Foundation version and API version |
| `foundation help` | Lists every command with its usage and description |
| `foundation help <command>` | Describes one command: usage, aliases, subcommands |
| `foundation packages` | Lists the packages that use Foundation, with their version and state |
| `foundation services` | Lists services, their providers, the packages that need them, and capabilities |
| `foundation reload-config` | Reloads every configuration file without restarting |
| `foundation op add <account> [name]` | Makes an account an operator |
| `foundation op remove <account>` | Removes an operator |
| `foundation op list` | Lists operators |
| `foundation permissions check <account> <permission>` | Tells whether an account has a permission, and why |
| `foundation permissions list [package]` | Lists declared permissions |

Typing `foundation` alone lists the subcommands.

## Examples

```
> foundation help buy
buy <item> [amount] - Buy an item

> foundation packages
Packages (2):
shop 1.0.0 - ready
loyalty 1.0.0 - failed: a ready hook of 'loyalty' failed
```

Usage lines show required arguments as `<name>`, optional ones as `[name]`, and arguments
that take the rest of the line as `<name...>`.

Package states are `initializing`, `ready`, `failed` (with the reason) and `disabled`. See
[Lifecycle](lifecycle.md).

Answers are written in the server language (`language` setting); the examples above are in
English.

## Services

`foundation services` shows which package provides each service and which packages need it.
`MISSING` marks a need that no provider satisfies, the usual reason why a package failed to
start:

```
> foundation services
Services (2):
chat:format
  no provider
  used if present by: shop (any version, MISSING)
economy:bank
  provided by: coins 1.2 (priority 10), gems 1.0 (priority 0)
  required by: shop (1.1), auction (2, MISSING)
Capabilities (1):
  chat:emotes: chat-plus 2.1
```

Providers are listed in the order they are chosen. To fix a missing service, install a package
that provides it in a compatible version, or remove the package that requires it. See
[Services and capabilities](services.md).

## Reloading the configuration

`foundation reload-config` reads `foundation/config.toml` and every package settings file
again, and answers one line per file:

```
> foundation reload-config
foundation/config.toml: no change
foundation/config/shop.toml: 1 setting changed
foundation/config/shop.toml: restart the server to apply port
```

- Settings that a package declares as reloadable apply at once, and the package is told.
  The others keep their value until the next restart; the answer lists them.
- A file with an error is refused as a whole: the current settings stay in use, and the
  problems are in the log (see [Configuration](configuration.md#editing-safely)).
- Each reload is recorded in the audit log, `foundation/audit/audit-<date>.log`.

Foundation's own settings (`language`, `[log]`, `[commands]`) all apply at once.

## Who can use them

| Permission | Default | Commands |
| --- | --- | --- |
| `foundation.command.version` | everyone | `foundation version` |
| `foundation.command.help` | everyone | `foundation help` |
| `foundation.command.packages` | operators | `foundation packages` |
| `foundation.command.services` | operators | `foundation services` |
| `foundation.command.reload-config` | operators | `foundation reload-config` |
| `foundation.command.op` | operators | `foundation op ...` |
| `foundation.command.permissions` | operators | `foundation permissions ...` |

A permission package can give these permissions to other accounts. See
[Permissions](permissions.md).

## Operators

Operators have every permission whose default is `operators`, including the ones above. They
are identified by account id, so the list also applies to players who are offline.

```
> foundation op add 76561198000000001 Alex
76561198000000001 is now an operator
> foundation op list
Operators (1):
  76561198000000001 Alex (added by console)
> foundation op remove 76561198000000001
76561198000000001 is no longer an operator
```

The optional name is only a reminder for administrators. Each change is recorded in the audit
log with the account that made it.

The list is kept in `foundation/operators.json`; back it up with the rest of the
`foundation/` folder. Change it with `foundation op` rather than by hand. If the file cannot be
read, Foundation logs why, nobody is an operator, and `foundation op` refuses changes until the
file is fixed or deleted; the file itself is never overwritten.

## Checking permissions

`foundation permissions check` shows the decision and where it comes from:

```
> foundation permissions check 76561198000000009 arena.manage
arena.manage for 76561198000000009: allowed (attachment from arena)
  declared by arena, default: operators
  Start matches and appoint referees
```

The source is `console`, `attachment from <package>` (a temporary grant or refusal made by a
package), `provider <package>` (a permission package) or `declared default`.
