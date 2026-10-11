# Changelog

All notable changes to Foundation are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). API changes are listed under
their own heading inside each release.

## [Unreleased]

### Added

- Installable `foundation` script package.
- English and French documentation: introduction, requirements, installation, compatibility,
  configuration, administration commands, package integration, lifecycle, package settings,
  localization, keys and validation, timers and futures, events, commands, services and
  capabilities, permissions, storage, persistent data, logging, API reference.
- Structured console logging with masked secret fields and suppression of repeated warnings
  and errors.
- `foundation/config.toml`, created with commented defaults on first start: server language
  (`language`, English and French messages), log level and debug categories. Invalid files are
  ignored with every problem logged, and the defaults are used.
- Per-package settings files in `foundation/config/<package>.toml`.
- Commands `foundation version`, `foundation help`, `foundation packages`,
  `foundation services` (providers, consumers, missing services, capabilities),
  `foundation reload-config` (reloads every configuration file without restarting; audited),
  `foundation op add|remove|list` and `foundation permissions check|list`. Each is behind a
  `foundation.command.*` permission; the console can use all of them.
- Operators kept in `foundation/operators.json`; a damaged file gives no operator and is never
  overwritten.
- Commands typed in the server console and in the chat (`/` prefix) run package commands;
  `commands.unknown_in_chat` chooses whether unknown `/` messages are answered or left to other
  packages.
- Storage in `foundation/data/foundation.db` (SQLite), created on first start. Package data is
  never deleted when a package stops or is removed, and pending writes are written before the
  server stops. Quotas per store in `foundation/config.toml` (`[storage]`
  `max_bytes_per_package`, `max_keys_per_package`), applied after `foundation reload-config`.

### API

- `Foundation` global (read-only) with `VERSION`, `API_VERSION` (`0.1`) and
  `Register(package, manifest)`.
- Package contexts: `GetId`, `GetName`, `GetVersion`, `GetState`, `IsActive`, `OnReady`,
  `OnDisable`, `Track`.
- Package states `initializing`, `ready`, `failed`, `disabled`; dependents are disabled before
  their dependencies; all packages are disabled when Foundation stops.
- Errors raised as `[foundation:<code>] ...` with the codes `invalid_argument`,
  `invalid_value`, `invalid_state`, `incompatible_api`.
- Error values returned for expected failures (`code`, `category`, `message`, `params`,
  `details`, `cause`) with the codes `invalid_key`, `validation_failed`, `async_failed`,
  `timeout`.
- `Foundation.Keys`: `Parse`, `Split`, `IsReserved`.
- `Foundation.Schema`: `String`, `Number`, `Integer`, `Boolean`, `Any`, `Enum`, `Optional`,
  `Record`, `List`, `Map`, `Custom`, `Validate`, `IsSchema`.
- Localization: `context:RegisterCatalog`, `context:Translate`, with plural forms (English and
  French rules) and language fallback.
- Package settings: `context:Config` and the settings object (`Get`, `Values`, `GetPath`,
  `OnChange`), with versioned layouts and migrations.
- Timers owned by the package: `context:NextTick`, `Delay`, `Repeat`, `Debounce`, `Throttle`.
- Futures: `context:Future`, `context:All`, and `Then`, `Catch`, `Finally`, `Timeout`,
  `Cancel`.
- Events: `context:DefineEvent`, `context:Emit`, `context:Listen`, with priorities
  (`lowest` to `monitor`), cancellation and fields listeners may change.
- Foundation events: `foundation:package_ready`, `package_failed`, `package_disabled`,
  `config_reloaded`, `command` (cancellable), `command_completed`.
- Commands: `context:RegisterCommand` (aliases, subcommands, typed arguments, sender kinds,
  cooldowns, audit) and `context:RegisterArgumentType`; senders with `Reply`, `GetKind`,
  `GetId`, `GetName`, `GetPlayer`; error code `command_usage`.
- Services: `context:ProvideService` (contract versions, priorities, explicit replacement),
  `GetService`, `GetServices`, `OnService`; returned services stop working when their
  provider stops. Manifest field `services` (required services block the ready state and fail
  the package when lost; optional ones are declarative).
- Capabilities: manifest field `capabilities`, `Foundation.Capabilities.Has` and `Providers`.
- Foundation events: `foundation:service_available`, `service_unavailable`,
  `capability_available`, `capability_unavailable`.
- Permissions: `context:DeclarePermission` (defaults `everyone`, `nobody`, `operators`,
  `non_operators`, deprecation), `context:AttachPermission` (temporary allow/deny, deny wins),
  `Foundation.Permissions.Has`, `Explain`, `Get`, `List`; command field `permission`.
- Permission provider contract `foundation:permission_provider` 1.x (`Check(account, node)`).
- `Foundation.Operators.IsOperator` and `List`; events `foundation:operator_added` and
  `operator_removed`.
- Stores: `context:Store(name, { version, migrations })` with `Get`, `Set`, `Delete`, `Keys`,
  `Batch` (all or nothing), `Usage`, `GetName`; JSON values; versioned data with migrations
  applied in one transaction, which fail the package without changing the data.
- Persistent data: `context:DefineData(name, schema, { default })` with `Get`, `Set`,
  `Delete` per subject (account id or player sender), validated against the schema;
  `context:ReadData("<package>:<name>")` for read-only access from any package.
- Error codes `storage_unavailable`, `storage_failed`, `storage_corrupt`, `storage_quota`.
