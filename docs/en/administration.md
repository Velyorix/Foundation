# Administration commands

Foundation adds a `foundation` command to the server console. In this version it can only be
used from the console, not by players.

| Command | Effect |
| --- | --- |
| `foundation version` | Shows the Foundation version and API version |
| `foundation help` | Lists every command with its usage and description |
| `foundation help <command>` | Describes one command: usage, aliases, subcommands |
| `foundation packages` | Lists the packages that use Foundation, with their version and state |
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
