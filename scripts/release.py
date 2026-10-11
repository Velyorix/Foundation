#!/usr/bin/env python3
"""Builds the release files of Foundation from a commit.

Usage:
  python scripts/release.py version --nightly YYYYMMDD
  python scripts/release.py build VERSION [--ref REF] [--out DIR]

`build` writes foundation-<version>.zip (a `foundation/` folder ready for `Packages/`),
SHA256SUMS and release-notes.md. Versions are X.Y.Z, X.Y.Z-rc.N, X.Y.Z-beta.N or
X.Y.Z-nightly.YYYYMMDD[.N], and X.Y.Z must be the version in package/Package.toml.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import re
import subprocess
import sys
import tarfile
import time
import zipfile
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "Velyorix/Foundation"

VERSION_PATTERN = re.compile(
    r"(?P<base>(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))"
    r"(?:-(?:(?P<channel>rc|beta)\.(?P<number>[1-9]\d*)|nightly\.(?P<date>\d{8})(?:\.(?P<serial>[2-9]|[1-9]\d+))?))?"
)

CHANNELS = {
    "stable": ("Stable", "Recommended for servers with players."),
    "rc": ("Release candidate", "The next stable version, published for a last round of testing."),
    "beta": ("Beta", "New features that may still change. Use it on test servers."),
    "nightly": ("Nightly", "Built automatically from the development branch. Expect breaking changes."),
}


class ReleaseError(Exception):
    pass


@dataclass(frozen=True)
class Version:
    text: str
    base: str
    channel: str

    @property
    def prerelease(self) -> bool:
        return self.channel != "stable"


def parse_version(text: str) -> Version:
    match = VERSION_PATTERN.fullmatch(text)
    if not match:
        raise ReleaseError(
            f"'{text}' is not a release version (X.Y.Z, X.Y.Z-rc.N, X.Y.Z-beta.N or X.Y.Z-nightly.YYYYMMDD[.N])"
        )
    if match.group("date"):
        try:
            time.strptime(match.group("date"), "%Y%m%d")
        except ValueError as error:
            raise ReleaseError(f"'{text}' has an invalid date") from error
        channel = "nightly"
    else:
        channel = match.group("channel") or "stable"
    return Version(text, match.group("base"), channel)


def git(*args: str) -> bytes:
    completed = subprocess.run(["git", *args], cwd=REPO_ROOT, capture_output=True, check=False)
    if completed.returncode != 0:
        raise ReleaseError(f"git {' '.join(args)} failed: {completed.stderr.decode(errors='replace').strip()}")
    return completed.stdout


def manifest_field(text: str, name: str) -> str:
    match = re.search(rf'^\s*{name}\s*=\s*"([^"]*)"', text, re.MULTILINE)
    if not match:
        raise ReleaseError(f"package/Package.toml has no {name}")
    return match.group(1)


def nightly_version(base: str, date: str, tags: set[str]) -> str:
    version = f"{base}-nightly.{date}"
    serial = 2
    while f"v{version}" in tags:
        version = f"{base}-nightly.{date}.{serial}"
        serial += 1
    return version


def changelog_section(text: str, heading: str) -> str | None:
    lines = text.splitlines()
    start = next((i for i, line in enumerate(lines) if line.startswith(f"## [{heading}]")), None)
    if start is None:
        return None
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## [")), len(lines))
    body = "\n".join(lines[start + 1 : end]).strip()
    return body or None


def release_changes(changelog: str, version: Version) -> str:
    section = changelog_section(changelog, version.base)
    if section is None and version.prerelease:
        section = changelog_section(changelog, "Unreleased")
    if section is None:
        expected = f"[{version.base}]" if not version.prerelease else f"[{version.base}] or [Unreleased]"
        raise ReleaseError(f"CHANGELOG.md has no {expected} section with content")
    return section


def stamp(path: str, data: bytes, version: str) -> bytes:
    if path == "Package.toml":
        text, count = re.subn(r'^(\s*version\s*=\s*)"[^"]*"', rf'\g<1>"{version}"', data.decode(), count=1, flags=re.M)
    elif path == "Shared/foundation/version.lua":
        text, count = re.subn(r'PRODUCT = "[^"]*"', f'PRODUCT = "{version}"', data.decode(), count=1)
    else:
        return data
    if count != 1:
        raise ReleaseError(f"could not write the version into {path}")
    return text.encode()


def package_files(ref: str) -> dict[str, bytes]:
    files: dict[str, bytes] = {}
    with tarfile.open(fileobj=io.BytesIO(git("archive", "--format=tar", ref, "package")), mode="r:") as archive:
        for member in archive.getmembers():
            if member.isfile():
                extracted = archive.extractfile(member)
                assert extracted is not None
                files[member.name.removeprefix("package/")] = extracted.read()
    if "Package.toml" not in files:
        raise ReleaseError(f"{ref} has no package/Package.toml")
    return files


def write_archive(path: Path, files: dict[str, bytes], timestamp: int) -> None:
    date = time.gmtime(max(timestamp, 315532800))[:6]
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name in sorted(files):
            info = zipfile.ZipInfo(f"foundation/{name}", date_time=date)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, files[name])


def release_notes(version: Version, commit: str, nanos_minimum: str, changes: str) -> str:
    label, description = CHANNELS[version.channel]
    archive = f"foundation-{version.text}.zip"
    docs = f"https://github.com/{REPOSITORY}/blob/v{version.text}/docs"
    return f"""**{label}** build of Foundation {version.text}, from commit {commit[:12]}. {description}

## Install

1. Download `{archive}` and extract it into the `Packages/` folder of your server. It
   contains a `foundation/` folder.
2. Add `foundation` to `packages` in `Config.toml`, or list it in the
   `packages_requirements` of the packages that use it.

Requires a nanos world server {nanos_minimum} or newer.
Guide: [English]({docs}/en/installation.md) · [Français]({docs}/fr/installation.md)

## Changes

{changes}

## Verify the download

`SHA256SUMS` lists the checksum of the archive. Its build provenance can be checked with:

```
gh attestation verify {archive} --repo {REPOSITORY}
```
"""


def build(version_text: str, ref: str, out: Path) -> list[Path]:
    version = parse_version(version_text)
    files = package_files(ref)
    manifest = files["Package.toml"].decode()
    manifest_version = manifest_field(manifest, "version")
    if version.base != manifest_version:
        raise ReleaseError(f"version {version.text} does not match {manifest_version} in package/Package.toml of {ref}")
    changes = release_changes(git("show", f"{ref}:CHANGELOG.md").decode(), version)
    commit = git("rev-parse", f"{ref}^{{commit}}").decode().strip()
    timestamp = int(git("show", "-s", "--format=%ct", commit).decode().strip())

    stamped = {name: stamp(name, data, version.text) for name, data in files.items()}
    out.mkdir(parents=True, exist_ok=True)
    archive = out / f"foundation-{version.text}.zip"
    write_archive(archive, stamped, timestamp)
    checksums = out / "SHA256SUMS"
    checksums.write_text(f"{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n", encoding="utf-8")
    notes = out / "release-notes.md"
    notes.write_text(
        release_notes(version, commit, manifest_field(manifest, "compatibility_version"), changes), encoding="utf-8"
    )
    return [archive, checksums, notes]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    version_parser = commands.add_parser("version", help="print the next nightly version")
    version_parser.add_argument("--nightly", required=True, metavar="YYYYMMDD")
    build_parser = commands.add_parser("build", help="write the release files")
    build_parser.add_argument("version")
    build_parser.add_argument("--ref", default="HEAD", help="commit, branch or tag to build (default HEAD)")
    build_parser.add_argument("--out", default=str(REPO_ROOT / "dist"), help="output folder (default dist/)")
    args = parser.parse_args(argv)

    try:
        if args.command == "version":
            base = manifest_field((REPO_ROOT / "package" / "Package.toml").read_text(encoding="utf-8"), "version")
            version = nightly_version(base, args.nightly, set(git("tag", "--list", "v*").decode().split()))
            parse_version(version)
            print(version)
        else:
            for path in build(args.version, args.ref, Path(args.out)):
                print(path)
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
