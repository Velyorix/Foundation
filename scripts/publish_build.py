#!/usr/bin/env python3
"""Registers a published release with the Foundation website (CI ingestion API).

Usage: python scripts/publish_build.py TAG --dist DIR [--site URL]

DIR holds the files of the GitHub release (foundation-<version>.zip and SHA256SUMS). Reads
FOUNDATION_CI_TOKEN and FOUNDATION_CI_SECRET, and GITHUB_REPOSITORY, GITHUB_WORKFLOW,
GITHUB_RUN_ID and GITHUB_SERVER_URL for the provenance. Running it again for the same tag is
harmless: the site returns the build it already has.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import release

DEFAULT_SITE = "https://foundationnw.dev"
REGISTER_PATH = "/api/ci/v1/builds"
# The default Python-urllib agent is refused by the website's firewall.
USER_AGENT = "Foundation-CI/1.0 (+https://github.com/Velyorix/Foundation)"


class PublishError(Exception):
    pass


def signature(secret: str, timestamp: str, nonce: str, method: str, path: str, body: bytes) -> str:
    payload = "\n".join([timestamp, nonce, method.upper(), "/" + path.lstrip("/"), hashlib.sha256(body).hexdigest()])
    return hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()


def build_number(tag: str, tags_by_creation: list[str]) -> int:
    releases = [name for name in tags_by_creation if release.VERSION_PATTERN.fullmatch(name.removeprefix("v"))]
    if tag not in releases:
        raise PublishError(f"{tag} is not a release tag of this repository")
    return releases.index(tag) + 1


def artifact(path: Path, kind: str) -> dict:
    data = path.read_bytes()
    return {"kind": kind, "filename": path.name, "platform": "any", "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def registration(tag: str, dist: Path, number: int, environment: dict[str, str]) -> dict:
    version = release.parse_version(tag.removeprefix("v"))
    archive = dist / f"foundation-{version.text}.zip"
    checksums = dist / "SHA256SUMS"
    for path in (archive, checksums):
        if not path.is_file():
            raise PublishError(f"{path} is missing")
    ref = f"refs/tags/{tag}"
    manifest = release.manifest_field(release.git("show", f"{ref}:package/Package.toml").decode(), "compatibility_version")
    repository = environment["GITHUB_REPOSITORY"]
    run_id = environment["GITHUB_RUN_ID"]
    return {
        "product": "foundation",
        "version": version.text,
        "build_number": number,
        "channel": version.channel,
        "commit": release.git("rev-parse", f"{ref}^{{commit}}").decode().strip(),
        "ref": ref,
        "built_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "nanos_world": {"minimum": manifest},
        "changelog": release.release_changes(release.git("show", f"{ref}:CHANGELOG.md").decode(), version),
        "provenance": {
            "provider": "github-actions",
            "repository": repository,
            "workflow": environment["GITHUB_WORKFLOW"],
            "run_id": run_id,
            "run_url": f"{environment.get('GITHUB_SERVER_URL', 'https://github.com')}/{repository}/actions/runs/{run_id}",
        },
        "artifacts": [artifact(archive, "archive"), artifact(checksums, "checksums")],
    }


class Client:
    def __init__(self, site: str, token: str, secret: str):
        self.site = site.rstrip("/")
        self.token = token
        self.secret = secret

    def call(self, method: str, url: str, payload: dict | None = None) -> tuple[int, dict]:
        body = json.dumps(payload).encode() if payload is not None else b""
        timestamp = str(int(time.time()))
        nonce = secrets.token_hex(16)
        path = urllib.parse.urlsplit(url).path
        request = urllib.request.Request(url, data=body, method=method)
        request.add_header("User-Agent", USER_AGENT)
        request.add_header("Authorization", f"Bearer {self.token}")
        request.add_header("Accept", "application/json")
        request.add_header("Content-Type", "application/json")
        request.add_header("X-Foundation-Timestamp", timestamp)
        request.add_header("X-Foundation-Nonce", nonce)
        request.add_header("X-Foundation-Signature", signature(self.secret, timestamp, nonce, method, path, body))
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.status, json.loads(response.read() or b"{}")
        except urllib.error.HTTPError as error:
            text = error.read().decode(errors="replace")
            try:
                return error.code, json.loads(text)
            except json.JSONDecodeError:
                raise PublishError(f"{method} {path} answered {error.code}: {text[:500]}") from error

    def upload(self, target: dict, path: Path) -> None:
        request = urllib.request.Request(target["url"], data=path.read_bytes(), method="PUT")
        request.add_header("User-Agent", USER_AGENT)
        for name, value in (target.get("headers") or {}).items():
            request.add_header(name, value if isinstance(value, str) else ", ".join(value))
        try:
            with urllib.request.urlopen(request, timeout=300):
                pass
        except urllib.error.HTTPError as error:
            raise PublishError(f"upload of {path.name} answered {error.code}") from error


def publish(client: Client, build: dict, dist: Path) -> str:
    status, answer = client.call("POST", client.site + REGISTER_PATH, build)
    if status == 409 and answer.get("error") == "build_exists":
        existing = answer.get("build", {})
        if existing.get("status") in ("verifying", "available"):
            return f"build {existing.get('id')} is already {existing.get('status')}"
        raise PublishError(f"the site already has build {build['build_number']} in state {existing.get('status')}")
    if status not in (200, 201):
        raise PublishError(f"registration answered {status}: {json.dumps(answer)[:1000]}")
    for target in answer["uploads"]:
        client.upload(target, dist / target["filename"])
    status, completed = client.call("POST", answer["complete_url"])
    if status not in (200, 202):
        raise PublishError(f"completion answered {status}: {json.dumps(completed)[:1000]}")
    return f"build {completed.get('id')} is {completed.get('status')}"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("tag")
    parser.add_argument("--dist", required=True, help="folder with the release files")
    parser.add_argument("--site", default=os.environ.get("FOUNDATION_SITE_URL") or DEFAULT_SITE)
    args = parser.parse_args(argv)

    try:
        missing = [name for name in ("FOUNDATION_CI_TOKEN", "FOUNDATION_CI_SECRET", "GITHUB_REPOSITORY", "GITHUB_WORKFLOW", "GITHUB_RUN_ID") if not os.environ.get(name)]
        if missing:
            raise PublishError(f"missing environment variables: {', '.join(missing)}")
        tags = release.git("tag", "--list", "v*", "--sort=creatordate").decode().split()
        build = registration(args.tag, Path(args.dist), build_number(args.tag, tags), dict(os.environ))
        client = Client(args.site, os.environ["FOUNDATION_CI_TOKEN"], os.environ["FOUNDATION_CI_SECRET"])
        print(f"{args.tag} (build {build['build_number']}, {build['channel']}): {publish(client, build, Path(args.dist))}")
    except (PublishError, release.ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
