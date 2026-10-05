# Changelog

All notable changes to Foundation are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). API changes are listed under
their own heading inside each release.

## [Unreleased]

### Added

- Installable `foundation` script package.
- English and French documentation: introduction, requirements, installation, compatibility,
  configuration, package integration, lifecycle, package settings, localization, keys and
  validation, timers and futures, logging, API reference.
- Structured console logging with masked secret fields and suppression of repeated warnings
  and errors.
- `foundation/config.toml`, created with commented defaults on first start: server language
  (`language`, English and French messages), log level and debug categories. Invalid files are
  ignored with every problem logged, and the defaults are used.
- Per-package settings files in `foundation/config/<package>.toml`.

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
