# Compatibility

## nanos world versions

| Foundation | Minimum nanos world | Tested with | Status | Notes |
| --- | --- | --- | --- | --- |
| 0.1.0 (unreleased) | 1.156 | 1.156.0 on Windows | In development | Linux not tested yet |

"Tested with" means the automated integration suites passed on that server version.

## Known incompatibilities

None known.

## Versioning

Foundation uses [Semantic Versioning](https://semver.org/). Before 1.0.0, any minor release
may change the API. From 1.0.0 on:

- patch releases fix bugs and never break documented behavior;
- minor releases add features without breaking existing ones;
- major releases may remove APIs that were deprecated in an earlier release, with a migration
  guide.

## Release channels

Every release is published on the
[releases page](https://github.com/Velyorix/Foundation/releases) with its archive,
`foundation-<version>.zip`, and a `SHA256SUMS` file. Its version tells the channel:

| Channel | Version and tag | Use |
| --- | --- | --- |
| Stable | `1.2.0`, tag `v1.2.0` | Recommended for servers with players |
| Release candidate | `1.2.0-rc.1`, tag `v1.2.0-rc.1` | The next stable version, published for a last round of testing |
| Beta | `1.2.0-beta.1`, tag `v1.2.0-beta.1` | New features that may still change. Use it on test servers |
| Nightly | `1.2.0-nightly.20261011`, tag `v1.2.0-nightly.20261011` | Built automatically from the development branch when it changed. Expect breaking changes |

Release candidates, betas and nightlies are marked as pre-releases. A pre-release carries the
number of the version it leads to: `1.2.0-beta.1` comes before `1.2.0`. `foundation version`
shows the full version of the installed build.

To check a download, compare its SHA-256 checksum with `SHA256SUMS`, or verify where it was
built with the [GitHub CLI](https://cli.github.com/):

```
gh attestation verify foundation-<version>.zip --repo Velyorix/Foundation
```
