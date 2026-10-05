# Installation and updates

## Install

1. Download the source of the repository (until the first release, there is no separate
   archive).
2. Copy its `package/` folder into your server's `Packages/` folder and rename it to
   `foundation`. The folder name is the package identifier and must be exactly
   `foundation`:

   ```
   NanosWorldServer.exe
   Config.toml
   Packages/
   └── foundation/
       ├── Package.toml
       └── Shared/
   ```

3. Load it. Either add it to the `packages` list in `Config.toml`:

   ```toml
   [game]
       packages = [
           "foundation",
       ]
   ```

   or rely on the packages that use it: a package that lists `foundation` in its
   `packages_requirements` makes the server load Foundation first.

4. Start the server and check the log for:

   ```
   [foundation] INFO  foundation/config: created foundation/config.toml with the default settings
   [foundation] INFO  foundation/core: Foundation 0.1.0 started (API 0.1, server)
   Package 'foundation' (0.1.0) loaded.
   ```

   On the first start, Foundation creates its settings file, `foundation/config.toml`, next to
   the server executable; later starts log `loaded foundation/config.toml` instead. See
   [Configuration](configuration.md).

## Update

Stop the server, replace the `Packages/foundation/` folder with the new version and start the
server again. The package folder contains no server data, so replacing it loses nothing:
settings are kept in the `foundation/` folder next to the server executable.

Read the [changelog](../../CHANGELOG.md) before updating: it lists changes that need action
from server owners or package developers.

## Remove

Remove `foundation` from `packages` in `Config.toml` and delete `Packages/foundation/`. Packages
that require Foundation will no longer load. Delete the `foundation/` folder next to the server
executable as well if you do not want to keep the settings.
