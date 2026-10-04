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
