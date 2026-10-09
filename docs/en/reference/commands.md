# API reference: commands

Availability: **server**. Introduced in 0.1.0 (API 0.1). Status: pre-release; the API may
change before 1.0.

Guide: [Commands](../commands.md). For administrators:
[Administration commands](../administration.md).

## `context:RegisterCommand(spec)`

Declares a command and returns a handle with `Release()` and `IsActive()`. The command is
removed when the package is disabled.

### Command fields

| Field | Type | Description |
| --- | --- | --- |
| `name` | string | `[a-z][a-z0-9_-]*`, at most 32 characters |
| `aliases` | array of strings, optional | Same rules as `name` |
| `description` | string, optional | Shown by `foundation help` |
| `description_key` | string, optional | Key of the package's catalogs, translated instead of `description` |
| `arguments` | array, optional | [Argument declarations](#argument-declarations) |
| `run` | function, optional | `run(sender, args, info)`; `info.path` is the array of command names, `info.line` the typed text |
| `subcommands` | array, optional | Command fields of the subcommands, nested up to 8 levels |
| `senders` | array, optional | `"player"`, `"console"` or both (default) |
| `cooldown` | integer, optional | Milliseconds between two uses by the same player |
| `audit` | boolean, optional | Record each use in the audit log |

A command needs `run` or `subcommands`. Names and aliases are unique among the subcommands of
a command. `foundation` cannot be used as a top-level name or alias.

Labels: every top-level name and alias is reachable as typed and as `<package>:<label>`.
When labels collide between packages, names go first in registration order, then aliases
where still free; the package that loses a label gets a warning. A label that becomes free
goes to the next package that declared it.

Raises `invalid_argument` for wrong field types, `invalid_value` for malformed names, unknown
fields, reserved or duplicate names, invalid arguments, sender lists or cooldowns,
`invalid_state` if a label is already used by another command of the same package or the
context is no longer active.

### Argument declarations

| Field | Type | Description |
| --- | --- | --- |
| `name` | string | `[a-z][a-z0-9_]*`, unique in the command; key of the value in `args` |
| `type` | string, optional | `"string"` (default), `"greedy"`, `"integer"`, `"number"`, `"boolean"`, `"enum"` or a package type `"<package>:<name>"` |
| `optional` | boolean, optional | The value is `nil` when missing |
| `default` | any, optional | Value when missing; makes the argument optional. Checked for built-in types |
| `description` | string, optional | Description of the argument |
| `min`, `max` | number, optional | Bounds for `integer` and `number`; length in characters for `string` and `greedy` |
| `values` | array of lowercase strings | Accepted words for `enum` (required for it) |

Required arguments come first; a `greedy` argument is last. A package type must be
registered when the command is declared.

Parsing rules:

- words are separated by spaces; `"..."` makes one argument, where `\"` and `\\` are escapes;
- `greedy` takes the rest of the line as typed, trailing spaces removed;
- `integer` accepts an optional sign and digits; `number` decimal notation without exponent;
- `boolean` accepts `true`, `yes`, `on`, `false`, `no`, `off`, case-insensitive;
- `enum` compares case-insensitively and gives the declared value.

Wrong input does not run the command: the sender receives the problem and the usage line.

## `context:RegisterArgumentType(name, definition)`

Registers an argument type usable by every package as `<package>:<name>`, and returns that
name. The type is removed when the package is disabled; commands that use it then answer
`<argument> could not be read`.

| `definition` field | Type | Description |
| --- | --- | --- |
| `parse` | function | `parse(text)` returns the value, or `nil` and a message for the sender |
| `suggest` | function, optional | `suggest(prefix)` returns an array of completions |

Both functions run guarded: an error is logged, and the sender gets
`<argument> could not be read`.

Raises `invalid_argument` for wrong types, `invalid_value` for a malformed name or an unknown
field, `invalid_state` if the type exists or the context is no longer active.

## Sender

| Method | Description |
| --- | --- |
| `sender:Reply(text)` | Sends `text` to the player's chat or to the console |
| `sender:GetKind()` | `"player"` or `"console"` |
| `sender:IsPlayer()`, `sender:IsConsole()` | |
| `sender:GetId()` | Player account id, `"console"` for the console |
| `sender:GetName()` | Player account name, `"console"` for the console |
| `sender:GetPlayer()` | Player object, `nil` for the console |
| `sender:GetLocale()` | `nil` in this version (server language) |

## Execution

For each typed command: parsing, sender kind (`senders`), cooldown, `foundation:command`
(cancellable), `run`, audit, `foundation:command_completed`. See
[Foundation's events](events.md#foundations-events).

- An error raised by `run` is logged as `command callback of <package> failed`; the sender
  gets a generic message. The cooldown does not start.
- Cooldowns are kept in memory per command and player, and never apply to the console.
- Audit entries use the action `<package>:command/<names joined by />`, the actor `console`
  or `player:<id>`, the outcome and `details.arguments` (non-scalar values as text; fields
  with secret-looking names masked).

## Errors

Wrong input is reported to the sender as an error value with code `command_usage` (category
`user`); its `message` is localized.
