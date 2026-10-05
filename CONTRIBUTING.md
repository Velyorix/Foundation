# Contributing to Foundation

Thanks for helping. This document covers what belongs in Foundation, how the repository is
organized, the tools and conventions used, and what a change needs before it can be merged.

## What belongs in Foundation

Foundation is infrastructure: lifecycle, ownership, events, commands, the permission API
and its minimal default provider, services, scheduling, guarded networking, configuration,
storage, metadata, registries, localization, logging and diagnostics.

Gameplay and administration features do not belong here: economy, jobs, guilds, quests,
homes, warps, teleport requests, shops, permission groups or ranks, chat formatting,
advanced admin interfaces. Propose them as separate packages. If such a package needs
something Foundation does not offer, open an issue describing the missing extension
point rather than the feature itself.

## Repository layout

| Path | Content |
| --- | --- |
| `package/` | The installable package (copied to `Packages/foundation/` on a server) |
| `package/Server/` | Server-only code |
| `package/Shared/` | Code loaded on server and clients; downloaded by every player |
| `package/Client/` | Client-only code; downloaded by every player |
| `tests/unit/` | Unit specs (`*_spec.lua`) run on standalone Lua 5.4 |
| `tests/support/` | Test runner, assertions and the `Package.Require` emulation |
| `tests/fixtures/` | Files used by unit specs |
| `tests/integration/` | Suites run on a real nanos world server |
| `tests/scripts/` | Tests for the Python tooling |
| `scripts/` | Development tooling (integration runner, repository checks) |
| `docs/en/`, `docs/fr/` | Public documentation, same pages in both languages |

## Tools

| Tool | Version | Used for |
| --- | --- | --- |
| Lua | 5.4 | Unit tests (`lua` or `lua5.4` on PATH) |
| StyLua | 2.5.2, built with Lua 5.4 support | Formatting |
| selene | 0.31.0, built with Lua 5.2–5.4 grammars | Linting |
| Python | 3.10 or newer | Integration runner and repository checks |
| nanos world server | 1.156 or newer | Integration tests |

StyLua and selene must be built with Lua 5.4 grammar support; the default crates.io
builds only parse Lua 5.1:

```bash
cargo install --locked stylua@2.5.2 --features lua54
```

```bash
cargo install --locked selene@0.31.0 --no-default-features --features "selene-lib/lua52,selene-lib/lua53,selene-lib/lua54,full_moon/lua52,full_moon/lua53,full_moon/lua54"
```

## Running the checks

From the repository root:

```bash
lua tests/run.lua
```

```bash
stylua --check package tests
```

```bash
selene package
```

```bash
selene --config tests/selene.toml tests
```

```bash
python scripts/check.py
```

```bash
python -m unittest discover -s tests/scripts -p "test_*.py"
```

`lua tests/run.lua keys scheduler` runs only the spec files whose path contains one of the
given words.

### Integration tests

Integration suites start a disposable copy of a nanos world server with the built-in blank
map, bound to `127.0.0.1` on free ports and unannounced. Your own server folder is only read,
never modified.

```bash
python scripts/integration.py --server-dir "/path/to/nanos-world/Server"
```

Set `NANOS_SERVER_DIR` instead of passing `--server-dir` if you run them often. Add
`--suite <name>` to run one suite, `--keep` to keep the temporary server folder
(`.tmp/integration/<suite>/`) after a passing run, `--tracy` to use the Tracy server build.

A suite is a script package in `tests/integration/packages/` that requires
`foundation-test-harness`, declared in `tests/integration/suites.json`. The harness runs
steps after the server `Start` event and stops the server when done:

```lua
local suite = FoundationTest.Suite("my-suite")

suite:Test("does something", function()
	FoundationTest.Equal(1 + 1, 2)
end)

suite:Run()
```

Behavior that needs a connected client (remote events, chat, player sessions) is covered
by the manual procedures listed in the pull request template until it can be automated.

## Coding conventions

Formatting is whatever StyLua produces; lint findings are errors.

**Naming.** Public API members use PascalCase, like the nanos world API
(`Package.Require`, `player:GetName()`). Local variables and functions use
`snake_case`. Module tables and classes use PascalCase. Constants use `UPPER_SNAKE_CASE`.
Methods on objects are called with `:`; functions on static tables with `.`.

**Modules.** Each file returns a table or a constructor and creates no globals. Requiring
a file only defines things; state lives in objects created during bootstrap. The only
global Foundation creates is `Foundation`, exported once.

**Public and internal code.** The public API is what is reachable from the `Foundation`
global and documented in `docs/`. Everything else is internal, whatever its file path,
and may change at any time.

**Server, Shared, Client.** Server-authoritative logic, credentials and anything
players must not read stay in `package/Server/`. `Shared/` and `Client/` are downloaded by
every player. `scripts/check.py` rejects credential-like values and database access in
those folders.

**Engine APIs.** Use only APIs present in the official nanos world scripting reference for
the supported server version. Functions the server disables by default (`io`,
`os.execute`, `dofile`, `require`, ...) are rejected by `scripts/check.py`; use
`Package.Require`, `File` and `Database` instead.

**Errors.** Programming errors (bad arguments, wrong state) raise a string error at level 2
formatted as `[foundation:<code>] <API>: <explanation>`. Expected failures (permission
denied, invalid external input, missing optional service, I/O failure) return `nil, err`
with a structured error value. Do not mix both styles for the same condition.

**Callbacks.** Code supplied by other packages is always invoked under `xpcall` with a
traceback, so an error is logged with its trace, attributed to the owning package and never
propagates into Foundation's own dispatch.

**Ownership.** Every registration made on behalf of a package records that package as
owner and provides a release function. Releasing twice must be harmless. Persistent data is
never deleted because a package unloads.

**Text.** User-visible and administrator-visible text comes from localization catalogs,
never from string literals in functional modules. English and French catalogs change
together. Log messages for developers follow the same rule.

**Performance.** No work on every tick unless a feature cannot exist without it. No scans
over all players or entities where an event or an index works. No blocking I/O on paths
that run during gameplay.

**Comments** explain decisions and non-obvious constraints, not what the next line does.

## Tests

- Pure logic gets unit specs in `tests/unit/`, mirroring the module path.
- Behavior that depends on the engine (load order, unload, timers, files, database) gets an
  integration test; a fake engine in unit tests does not prove engine behavior.
- Bug fixes come with a test that fails without the fix.
- Benchmarks go next to the code they measure and record the environment they ran in.

## Documentation

- Every public API change updates the English and French reference pages in the same
  change. `scripts/check.py` fails when a page exists in one language only.
- Examples must use the real API, state whether they are server, client or shared code, and
  be exercised by a test or an integration suite. Put a complete example in a package under
  `tests/integration/packages/`, run it from a suite, and precede the code block in the page
  with `<!-- example: <path to the file> -->`: `scripts/check.py` then fails whenever the page
  and the tested file differ.
- Public pages stand on their own: no references to internal planning material.
- Write for server administrators and package developers: direct, specific, no filler.

## Commits and branches

Commits follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):
`type(scope): summary`, imperative mood, at most 72 characters in the summary.

- Types: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `chore`, `ci`.
- Scopes name the subsystem: `runtime`, `events`, `commands`, `permissions`, `services`,
  `scheduler`, `network`, `config`, `storage`, `i18n`, `log`, `diagnostics`, `package`,
  `integration`, `docs`, `repo`.
- A breaking change to a public API adds `!` after the scope and a `BREAKING CHANGE:` footer
  describing the migration.

One commit, one purpose: do not mix a refactor with a feature or unrelated fixes.

Branches are named `<type>/<short-topic>`, for example `feat/command-cooldowns` or
`fix/scheduler-cancel-twice`.

## Pull requests

Fill in the pull request template. A pull request is ready when the checks above pass,
documentation and the changelog are updated, and the description lists the tests that were
actually run.
