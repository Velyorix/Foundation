# Changelog

All notable changes to Foundation are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). API changes are listed under
their own heading inside each release.

## [Unreleased]

### Added

- Installable `foundation` script package.
- English and French documentation: introduction, requirements, installation, compatibility,
  package integration, lifecycle, logging, API reference.
- Structured console logging with masked secret fields and suppression of repeated warnings
  and errors.

### API

- `Foundation` global (read-only) with `VERSION`, `API_VERSION` (`0.1`) and
  `Register(package, manifest)`.
- Package contexts: `GetId`, `GetName`, `GetVersion`, `GetState`, `IsActive`, `OnReady`,
  `OnDisable`, `Track`.
- Package states `initializing`, `ready`, `failed`, `disabled`; dependents are disabled before
  their dependencies; all packages are disabled when Foundation stops.
- Errors raised as `[foundation:<code>] ...` with the codes `invalid_argument`,
  `invalid_value`, `invalid_state`, `incompatible_api`.
