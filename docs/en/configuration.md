# Configuration

Foundation and the packages that use it keep their settings in TOML files inside a
`foundation/` folder, next to the server executable:

```
NanosWorldServer.exe
Config.toml
foundation/
├── config.toml                 Foundation's own settings
└── config/
    └── my-package.toml         settings of the package my-package
```

You never have to create these files. When one is missing, it is written with the default
values and a comment above each setting.

## Foundation settings

`foundation/config.toml`, as created on the first start:

<!-- example: tests/integration/packages/foundation-docs-examples-test/expected/config.toml -->
```toml
# Foundation configuration.
# Read when Foundation starts. Delete this file to recreate it with the default values.

# Format version of this file. Do not change it.
config_version = 1

# Language of Foundation's own messages, for example 'en' or 'fr'. Languages without a translation use English.
language = "en"

[log]
# Minimum level of Foundation's log lines: 'debug', 'info', 'warning' or 'error'.
level = "info"

# Parts of Foundation whose debug lines are written even when the level is above 'debug', for example ['config'].
debug_categories = []

[commands]
# Chat messages starting with '/' that are not commands: 'reply' answers "unknown command" and hides the message, 'pass' leaves them to other packages.
unknown_in_chat = "reply"
```

| Setting | Values | Default | Effect |
| --- | --- | --- | --- |
| `language` | Locale code: `en`, `fr`, or a regional code such as `fr_CA` | `"en"` | Language of Foundation's log messages and the default language of package translations (see [Localization](localization.md)). Foundation ships English and French; other languages fall back to English. |
| `log.level` | `"debug"`, `"info"`, `"warning"`, `"error"` | `"info"` | Lines below this level are not written. See [Logging](logging.md). |
| `log.debug_categories` | List of domains, for example `["config"]` | `[]` | Domains (the part after `/` in a log line) whose debug lines are written whatever `log.level` is. |
| `commands.unknown_in_chat` | `"reply"`, `"pass"` | `"reply"` | Chat messages starting with `/` that are not commands: `reply` answers "unknown command" and hides the message; `pass` lets other packages handle it, for example a package with its own chat commands. |

This file is always created in English. Changing `language` changes the messages, not the
comments already in the file.

## Package settings

A package that declares settings gets its own file, `foundation/config/<package>.toml`, where
`<package>` is the package folder name. The comments in the file describe each setting; the
package documentation tells you more. The first lines are written in the server language, the
comments of each setting are provided by the package. For example:

<!-- example: tests/integration/packages/foundation-docs-examples-test/expected/foundation-example-rewards.toml -->
```toml
# Settings of Daily Rewards (foundation-example-rewards).
# Read when the package starts. Delete this file to recreate it with the default values.

# Format version of this file. Do not change it.
config_version = 1

# Give a reward on the first join of each day.
enabled = true

[reward]
# Amount of money given.
amount = 250

# Message shown with the reward.
message = "Here is your daily reward!"
```

## When changes apply

- `foundation/config.toml` is read when Foundation starts.
- A package file is read when that package starts.

After editing files, type `foundation reload-config` in the server console: every file is read
again and the answer tells, for each one, what changed (see
[Administration commands](administration.md#reloading-the-configuration)). All of
Foundation's settings apply at once. A package decides which of its settings can change
while it runs; the others wait for a restart, and the answer lists them.

Do not use `package reload foundation`: every package that uses Foundation would stop working
until it is reloaded too.

## Editing safely

- Settings you remove from a file use their default value. Unknown settings are refused.
- Values are checked when the file is read. If anything is wrong (TOML syntax, wrong type, value
  out of range, unknown setting), **the whole file is ignored** and the defaults are used. Each
  problem is logged with the setting it concerns:

  ```
  [foundation] ERROR my-package/config: foundation/config/my-package.toml is invalid (1 problem(s))
  [foundation] ERROR my-package/config: foundation/config/my-package.toml: $.motd: must have at most 32 characters
  [foundation] ERROR my-package/config: foundation/config/my-package.toml is not used; Foundation runs with the default settings until the file is fixed
  ```

  Foundation never rewrites a file that exists, so your comments and layout are kept. Fix
  the file and restart.
- Delete a file to get a fresh copy with the defaults on the next start.
- Values of settings that a package marks as secret (passwords, tokens) are replaced with
  `***` in Foundation's log lines.

## Format versions

`config_version` identifies the layout of the file. When an update of Foundation or of a
package changes the layout, the old file keeps working: it is converted in memory when it is
read, and Foundation logs:

```
[foundation] WARN  my-package/config: foundation/config/my-package.toml uses config_version 1; it was converted to version 2 in memory. Update the file to stop this message
```

To update the file, delete it so it is recreated, then copy your values back. A file with a
`config_version` newer than the installed version supports is ignored, and the defaults are
used.
