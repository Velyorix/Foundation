#!/usr/bin/env python3
"""Run Foundation integration suites on disposable nanos world servers.

Each suite gets a fresh server folder under .tmp/integration/<suite>/ containing a
copy of the server binaries, the Foundation package and the suite's test packages.
The server is started with command-line overrides only (no Config.toml edits), bound
to 127.0.0.1 on free ports, unannounced, with the built-in blank map. The suite stops
the server itself; the runner then reads the result lines from the server log.

Usage:
    python scripts/integration.py --server-dir "C:/path/to/Server" [--suite smoke] [--keep]

The server folder can also be given through the NANOS_SERVER_DIR environment variable.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import shutil
import socket
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PACKAGE_DIR = REPO_ROOT / "package"
TEST_PACKAGES_DIR = REPO_ROOT / "tests" / "integration" / "packages"
SUITES_FILE = REPO_ROOT / "tests" / "integration" / "suites.json"
WORK_ROOT = REPO_ROOT / ".tmp" / "integration"

# Server folder entries that must not be copied into a disposable server.
SKIPPED_SERVER_ENTRIES = {"Packages", "Assets", "Config.toml", ".logs", ".sentry-native", "foundation"}

RESULT_LINE = re.compile(r"\[FOUNDATION-TEST\] (?P<suite>\S+) (?P<kind>PASS|FAIL|DONE)(?: (?P<rest>.*))?$")
# ERROR: engine and Lua runtime errors; S_ERR: lines written with Console.Error by scripts.
ENGINE_ERROR = re.compile(r"^\S+ \S+\s+(ERROR|S_ERR)\s+(?P<message>.*)$")
LUA_ERROR = re.compile(r"Lua Error", re.IGNORECASE)


@dataclass
class SuiteResult:
    name: str
    passed: list[str] = field(default_factory=list)
    failed: list[tuple[str, str]] = field(default_factory=list)
    done: bool = False
    engine_errors: list[str] = field(default_factory=list)
    missing_log_lines: list[str] = field(default_factory=list)
    timed_out: bool = False
    exit_code: int | None = None
    log_path: Path | None = None

    @property
    def ok(self) -> bool:
        return (
            self.done
            and bool(self.passed)
            and not self.failed
            and not self.engine_errors
            and not self.missing_log_lines
            and not self.timed_out
        )


def load_suites() -> dict:
    with SUITES_FILE.open(encoding="utf-8") as handle:
        return json.load(handle)


def server_executable(server_dir: Path, tracy: bool) -> list[str]:
    if os.name == "nt":
        name = "NanosWorldServerTracy.exe" if tracy else "NanosWorldServer.exe"
        return [str(server_dir / name)]
    command = [str(server_dir / "NanosWorldServer.sh")]
    if tracy:
        command.append("--tracy")
    return command


# Candidate ports sit below the OS dynamic range: on Windows, Hyper-V and WSL reserve
# blocks of the dynamic range for UDP, so ephemeral TCP ports are often unusable there.
PORT_RANGE = (20000, 29998)


def port_is_free(port: int) -> bool:
    for kind in (socket.SOCK_STREAM, socket.SOCK_DGRAM):
        try:
            with socket.socket(socket.AF_INET, kind) as check:
                check.bind(("127.0.0.1", port))
        except OSError:
            return False
    return True


def free_port_pair() -> int:
    """Returns a port P such that P and P+1 are free for TCP and UDP right now."""
    for _ in range(200):
        port = random.randint(*PORT_RANGE)
        if port_is_free(port) and port_is_free(port + 1):
            return port
    raise RuntimeError(f"no two consecutive free ports found in {PORT_RANGE[0]}-{PORT_RANGE[1] + 1}")


def prepare_server(server_dir: Path, work_dir: Path, packages: list[str]) -> None:
    if work_dir.exists():
        shutil.rmtree(work_dir)
    work_dir.mkdir(parents=True)
    for entry in server_dir.iterdir():
        if entry.name in SKIPPED_SERVER_ENTRIES:
            continue
        target = work_dir / entry.name
        if entry.is_dir():
            shutil.copytree(entry, target)
        else:
            shutil.copy2(entry, target)
    packages_dir = work_dir / "Packages"
    packages_dir.mkdir()
    for name in packages:
        source = PACKAGE_DIR if name == "foundation" else TEST_PACKAGES_DIR / name
        if not (source / "Package.toml").is_file():
            raise FileNotFoundError(f"package '{name}' not found at {source}")
        shutil.copytree(source, packages_dir / name)


def parse_log(
    result: SuiteResult, log_path: Path, allowed_errors: list[str], expected_lines: list[str] | None = None
) -> None:
    """Fills `result` from the server log.

    allowed_errors  regexes for engine error lines the suite triggers on purpose
    expected_lines  regexes that must each match at least one log line
    """
    allowed = [re.compile(pattern) for pattern in allowed_errors]
    expected = {pattern: re.compile(pattern) for pattern in expected_lines or []}
    seen: set[str] = set()
    result.log_path = log_path
    if not log_path.is_file():
        result.engine_errors.append(f"server log not found: {log_path}")
        return
    for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        for pattern, compiled in expected.items():
            if pattern not in seen and compiled.search(line):
                seen.add(pattern)
        match = RESULT_LINE.search(line)
        if match and match.group("suite") == result.name:
            kind, rest = match.group("kind"), match.group("rest") or ""
            if kind == "PASS":
                result.passed.append(rest)
            elif kind == "FAIL":
                name, _, reason = rest.partition(" :: ")
                result.failed.append((name, reason))
            else:
                result.done = True
            continue
        error = ENGINE_ERROR.match(line)
        if (error or LUA_ERROR.search(line)) and not any(pattern.search(line) for pattern in allowed):
            result.engine_errors.append(line.strip())
    result.missing_log_lines = [pattern for pattern in expected if pattern not in seen]


def run_suite(name: str, suite: dict, server_dir: Path, tracy: bool, keep: bool) -> SuiteResult:
    work_dir = WORK_ROOT / name
    prepare_server(server_dir, work_dir, suite["packages"])
    port = free_port_pair()
    command = server_executable(work_dir, tracy) + [
        "--ip", "127.0.0.1",
        "--map", "default-blank-map",
        "--packages", ",".join(suite["packages"]),
        "--port", str(port),
        "--query_port", str(port + 1),
        "--announce", "0",
        "--max_players", "1",
        "--async_log", "0",
        "--log_level", "2",
    ]
    result = SuiteResult(name=name)
    with (work_dir / "server-stdout.txt").open("wb") as stdout:
        process = subprocess.Popen(command, cwd=work_dir, stdout=stdout, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        try:
            result.exit_code = process.wait(timeout=suite.get("timeout_seconds", 90))
        except subprocess.TimeoutExpired:
            result.timed_out = True
            process.kill()
            process.wait()
    parse_log(
        result,
        work_dir / ".logs" / "NanosWorldCore.log",
        suite.get("allowed_errors", []),
        suite.get("expected_log_lines", []),
    )
    if result.ok and not keep:
        shutil.rmtree(work_dir, ignore_errors=True)
    return result


def report(result: SuiteResult) -> None:
    status = "ok" if result.ok else "FAILED"
    print(f"suite {result.name}: {status}")
    for name in result.passed:
        print(f"  ok    {name}")
    for name, reason in result.failed:
        print(f"  FAIL  {name}\n        {reason}")
    if result.timed_out:
        print("  server did not stop before the timeout")
    if not result.done and not result.timed_out:
        print("  suite did not report DONE")
    if not result.passed and result.done:
        print("  suite reported no passing test")
    for line in result.engine_errors:
        print(f"  engine error: {line}")
    for pattern in result.missing_log_lines:
        print(f"  expected log line not found: {pattern}")
    if not result.ok and result.log_path:
        print(f"  log: {result.log_path}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--server-dir", default=os.environ.get("NANOS_SERVER_DIR"), help="nanos world server folder")
    parser.add_argument("--suite", action="append", help="suite to run (repeatable); default: all")
    parser.add_argument("--tracy", action="store_true", help="use the Tracy-enabled server build")
    parser.add_argument("--keep", action="store_true", help="keep the disposable server folder after a passing run")
    parser.add_argument("--list", action="store_true", help="list suites and exit")
    args = parser.parse_args(argv)

    suites = load_suites()
    if args.list:
        for name, suite in suites.items():
            print(f"{name}: {suite.get('description', '')}")
        return 0
    if not args.server_dir:
        parser.error("--server-dir or NANOS_SERVER_DIR is required")
    server_dir = Path(args.server_dir)
    executable = Path(server_executable(server_dir, args.tracy)[0])
    if not executable.is_file():
        parser.error(f"server executable not found: {executable}")

    selected = args.suite or list(suites)
    unknown = [name for name in selected if name not in suites]
    if unknown:
        parser.error(f"unknown suite(s): {', '.join(unknown)}")

    all_ok = True
    for name in selected:
        result = run_suite(name, suites[name], server_dir, args.tracy, args.keep)
        report(result)
        all_ok = all_ok and result.ok
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
