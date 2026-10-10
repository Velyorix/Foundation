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
  capabilities, logging, API reference.
- Structured console logging with masked secret fields and suppression of repeated warnings
  and errors.
- `foundation/config.toml`, created with commented defaults on first start: server language
  (`language`, English and French messages), log level and debug categories. Invalid files are
  ignored with every problem logged, and the defaults are used.
- Per-package settings files in `foundation/config/<package>.toml`.
- Console commands `foundation version`, `foundation help`, `foundation packages`,
  `foundation services` (providers, consumers, missing services, capabilities) and
  `foundation reload-config` (reloads every configuration file without restarting; audited).
- Commands typed in the server console and in the chat (`/` prefix) run package commands;
  `commands.unknown_in_chat` chooses whether unknown `/` messages are answered or left to other
  packages.

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
