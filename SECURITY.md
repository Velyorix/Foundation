# Security policy

## Supported versions

Foundation has not had a stable release yet. Security fixes land on the `main` branch.
Once 1.0 is released, this section will list the release lines that receive fixes.

| Version | Supported |
| --- | --- |
| `main` (pre-release) | Yes |

## Reporting a vulnerability

Do not open a public issue for security problems.

Report privately through GitHub: open the repository's **Security** tab and choose
**Report a vulnerability**. Include:

- the Foundation version or commit;
- the nanos world server version and operating system;
- what an attacker can do and what they need (a connected client, a malicious package,
  server console access, ...);
- steps or a minimal package that reproduces the issue.

You will get an acknowledgement within 7 days. Fixes are developed privately and
published with a changelog entry under **Security** once a patched version is available.

## Scope

In scope:

- anything that lets a client bypass a server-side check made by Foundation (permissions,
  payload validation, rate limits);
- secrets or server-only data exposed through `Client/` or `Shared/` files;
- data loss or corruption caused by Foundation storage or migrations;
- crashes or stalls of the server triggered by client input handled by Foundation.

Out of scope:

- vulnerabilities in the nanos world engine itself (report them to the nanos world team);
- issues that require running arbitrary server-side packages: packages share one Lua
  process and Foundation does not sandbox them from each other;
- servers started with `--enable_unsafe_libs`, which Foundation does not require.
