# Administration commands

Foundation adds a `foundation` command to the server console. In this version it can only be
used from the console, not by players.

| Command | Effect |
| --- | --- |
| `foundation version` | Shows the Foundation version and API version |
| `foundation help` | Lists every command with its usage and description |
| `foundation help <command>` | Describes one command: usage, aliases, subcommands |
| `foundation packages` | Lists the packages that use Foundation, with their version and state |
| `foundation services` | Lists services, their providers, the packages that need them, and capabilities |
| `foundation reload-config` | Reloads every configuration file without restarting |

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
