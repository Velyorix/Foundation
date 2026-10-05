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

Messages are currently written in English.

## Secrets

Field values whose name contains `password`, `passwd`, `secret`, `token`, `credential`,
`authorization`, `connection_string`, `api_key` or `apikey` are replaced with `***`.

## Repeated messages

When the same warning or error line is written several times within 10 seconds, only the first
one is printed. The next time it appears after that window, Foundation first prints
`previous message repeated N more times`. Informational lines are never suppressed.
