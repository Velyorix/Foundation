# Logging

Foundation writes to the server console and log file (`.logs/NanosWorldCore.log`) with one
line per record:

```
[foundation] <LEVEL> <owner>/<domain>: <message> <field>=<value> ...
```

- `LEVEL` is `DEBUG`, `INFO `, `WARN ` or `ERROR`.
- `owner` is the package the record is about (`foundation` for Foundation itself), `domain`
  the part of Foundation that wrote it.
- Fields are sorted by name. Values containing spaces, quotes or `=` are quoted.
- An error caused by a package callback is followed by its stack trace.

Warnings and errors are written with the server's warning and error output, so the server
also prints its own stack lines after them and tags them `S_WARN` and `S_ERR` in the log file.

## Lines to expect

| Line | When |
| --- | --- |
| `Foundation 0.1.0 started (API 0.1, server)` | Foundation finished starting |
| `registered my-package 1.0.0 (API 0.1)` | A package called `Foundation.Register` |
| `my-package is ready` | Its `Load` event ran and its ready hooks succeeded |
| `my-package failed: <reason>` | A ready hook failed or a dependency stopped |
| `my-package disabled: <reason>` | The package was unloaded or disabled |
| `<kind> callback of my-package failed` | A function supplied by the package raised an error |
| `Foundation was unloaded while ...` | Foundation was reloaded alone; follow the command in the message |
| `Foundation stopped` | Foundation finished shutting down |
| `created foundation/config/my-package.toml with the default settings` | A configuration file was missing and has been written |
| `loaded foundation/config/my-package.toml` | A configuration file was read and accepted |
| `foundation/config/my-package.toml is not used; ...` | The file is invalid; the lines before it list the problems (see [Configuration](configuration.md#editing-safely)) |
| `missing translation for 'my-package:some.key'` | A package asked for a text that none of its catalogs contains (logged once per key) |
| `repeating task of my-package stopped after 3 consecutive failures` | A repeating task failed several times in a row and was stopped |
| `/spawn of warps is already used by homes; it is available as /warps:spawn` | Two packages declared the same command name |
| `command callback of my-package failed` | A command raised an error; the player got a short message |

## Level and language

The `[log]` section of `foundation/config.toml` sets the minimum level (`info` by default)
and the domains whose debug lines are always written. The `language` setting chooses the
language of the messages: English (`en`) and French (`fr`) are available, other languages use
English. Lines written while `foundation/config.toml` itself is read are in English. See
[Configuration](configuration.md).

These settings apply to the lines written by Foundation, whichever package they are about. They
do not change the server's own `log_level`.

## Secrets

Field values whose name contains `password`, `passwd`, `secret`, `token`, `credential`,
`authorization`, `connection_string`, `api_key` or `apikey` are replaced with `***`.

## Repeated messages

When the same warning or error line is written several times within 10 seconds, only the first
one is printed. The next time it appears after that window, Foundation first prints
`previous message repeated N more times`. Informational lines are never suppressed.
