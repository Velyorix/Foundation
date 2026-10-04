#!/usr/bin/env python3
"""Repository consistency checks for Foundation.

Checks:
  docs-parity       docs/en and docs/fr contain the same pages
  links             relative links and heading anchors in public Markdown resolve
  public-wording    public documents do not reference internal material
  unsafe-lua        shipped Lua does not use functions the server disables by default
  client-secrets    Client/ and Shared/ files contain no credentials or database access
  secrets           no private keys or provider tokens anywhere in the repository
  todo-markers      shipped code contains no TODO/FIXME/XXX/HACK markers
  versions          Package.toml, version.lua and CHANGELOG.md agree

Usage: python scripts/check.py [--only NAME ...] [--root PATH]
Exit status is 1 when any check reports a problem.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections.abc import Callable, Iterable
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

SKIPPED_DIRS = {".git", ".tmp", "dist", ".idea", "internal-docs", "__pycache__", "node_modules"}
TEXT_SUFFIXES = {".lua", ".md", ".toml", ".yml", ".yaml", ".json", ".py", ".txt", ".cfg", ".ini"}

PUBLIC_MARKDOWN_ROOT_FILES = ["README.md", "CONTRIBUTING.md", "SECURITY.md", "CHANGELOG.md"]

FORBIDDEN_PUBLIC_WORDING = [
    (re.compile(r"\broadmap(\.md)?\b", re.IGNORECASE), "reference to the internal roadmap"),
    (re.compile(r"\bCDC\b"), "reference to the specification document"),
    (re.compile(r"cahier des charges", re.IGNORECASE), "reference to the specification document"),
    (re.compile(r"internal-docs|engineering/", re.IGNORECASE), "link to internal engineering material"),
    (re.compile(r"\bADR(s)?\b"), "reference to internal decision records"),
    (re.compile(r"\bClaude\b|\bChatGPT\b|\bLLM\b"), "reference to an AI assistant"),
    (re.compile(r"\b(generated|written)\s+(by|with)\s+(an\s+)?AI\b", re.IGNORECASE), "AI generation statement"),
]

UNSAFE_LUA = [
    (re.compile(r"(?<![\w.:])io\s*\."), "io library (disabled on servers by default)"),
    (re.compile(r"(?<![\w.:])os\s*\.\s*(execute|rename|remove|exit|getenv|tmpname|setlocale)\b"), "os function disabled on servers by default"),
    (re.compile(r"(?<![\w.:])(dofile|loadfile)\s*\("), "dofile/loadfile (disabled on servers by default)"),
    (re.compile(r"(?<![\w.:])require\s*[\(\"']"), "require (use Package.Require)"),
    (re.compile(r"(?<![\w.:])package\s*\."), "package library (use Package.Require)"),
]

CLIENT_SECRET_PATTERNS = [
    (re.compile(r"\b(password|passwd|pass|token|secret|api[_-]?key|connection[_-]?string)\b\s*=\s*[\"'][^\"']+[\"']", re.IGNORECASE), "credential-like assignment"),
    (re.compile(r"(?<![\w.:])Database\s*\("), "database access from a client-visible file"),
    (re.compile(r"DatabaseEngine\s*\."), "database access from a client-visible file"),
]

SECRET_PATTERNS = [
    (re.compile(r"-----BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----"), "private key"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "AWS access key id"),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,}\b"), "GitHub token"),
    (re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}\b"), "Slack token"),
    (re.compile(r"\bsk-[A-Za-z0-9]{32,}\b"), "API secret key"),
]

TODO_MARKER = re.compile(r"\b(TODO|FIXME|XXX|HACK)\b")

Problem = str


def iter_files(root: Path, base: Path | None = None) -> Iterable[Path]:
    start = base or root
    if not start.exists():
        return
    for path in sorted(start.rglob("*")):
        if any(part in SKIPPED_DIRS for part in path.relative_to(root).parts):
            continue
        if path.is_file():
            yield path


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def rel(root: Path, path: Path) -> str:
    return path.relative_to(root).as_posix()


def strip_lua_comments(line: str) -> str:
    """Removes a trailing `--` comment that is not inside a string literal."""
    quote = None
    index = 0
    while index < len(line):
        char = line[index]
        if quote:
            if char == "\\":
                index += 2
                continue
            if char == quote:
                quote = None
        elif char in ("'", '"'):
            quote = char
        elif line.startswith("--", index):
            return line[:index]
        index += 1
    return line


def lua_code_only(line: str) -> str:
    """Removes the comment and blanks string literal contents, keeping the quotes."""
    result = []
    quote = None
    index = 0
    code = strip_lua_comments(line)
    while index < len(code):
        char = code[index]
        if quote:
            if char == "\\":
                index += 2
                continue
            if char == quote:
                quote = None
                result.append(char)
        else:
            if char in ("'", '"'):
                quote = char
            result.append(char)
        index += 1
    return "".join(result)


def public_markdown_files(root: Path) -> list[Path]:
    files = [root / name for name in PUBLIC_MARKDOWN_ROOT_FILES if (root / name).is_file()]
    files += [path for path in iter_files(root, root / "docs") if path.suffix == ".md"]
    files += [path for path in iter_files(root, root / ".github") if path.suffix == ".md"]
    return files


def check_docs_parity(root: Path) -> list[Problem]:
    en_root, fr_root = root / "docs" / "en", root / "docs" / "fr"
    if not en_root.exists() and not fr_root.exists():
        return []
    en = {rel(en_root, path) for path in iter_files(root, en_root) if path.suffix == ".md"}
    fr = {rel(fr_root, path) for path in iter_files(root, fr_root) if path.suffix == ".md"}
    problems = [f"docs/fr/{page} is missing (exists in docs/en)" for page in sorted(en - fr)]
    problems += [f"docs/en/{page} is missing (exists in docs/fr)" for page in sorted(fr - en)]
    return problems


def github_slug(heading: str) -> str:
    text = re.sub(r"`([^`]*)`", r"\1", heading.strip().lower())
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def heading_anchors(text: str) -> set[str]:
    anchors: set[str] = set()
    counts: dict[str, int] = {}
    in_fence = False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        match = re.match(r"^#{1,6}\s+(.*?)\s*#*\s*$", line)
        if match:
            slug = github_slug(match.group(1))
            count = counts.get(slug, 0)
            anchors.add(slug if count == 0 else f"{slug}-{count}")
            counts[slug] = count + 1
    return anchors


LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")


def check_links(root: Path) -> list[Problem]:
    problems: list[Problem] = []
    for path in public_markdown_files(root):
        text = read_text(path)
        in_fence = False
        for number, line in enumerate(text.splitlines(), start=1):
            if line.lstrip().startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            for target in LINK.findall(line):
                if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.IGNORECASE):
                    continue
                file_part, _, anchor = target.partition("#")
                destination = (path.parent / file_part).resolve() if file_part else path
                where = f"{rel(root, path)}:{number}"
                if not destination.exists():
                    problems.append(f"{where}: broken link to '{target}'")
                    continue
                if anchor and destination.suffix == ".md" and anchor not in heading_anchors(read_text(destination)):
                    problems.append(f"{where}: missing anchor '#{anchor}' in {rel(root, destination)}")
    return problems


def check_public_wording(root: Path) -> list[Problem]:
    problems: list[Problem] = []
    for path in public_markdown_files(root):
        for number, line in enumerate(read_text(path).splitlines(), start=1):
            for pattern, reason in FORBIDDEN_PUBLIC_WORDING:
                if pattern.search(line):
                    problems.append(f"{rel(root, path)}:{number}: {reason}: {line.strip()[:120]}")
    return problems


def lua_files(root: Path, *parts: str) -> list[Path]:
    return [path for path in iter_files(root, root.joinpath(*parts)) if path.suffix == ".lua"]


def check_unsafe_lua(root: Path) -> list[Problem]:
    problems: list[Problem] = []
    for path in lua_files(root, "package"):
        for number, line in enumerate(read_text(path).splitlines(), start=1):
            code = lua_code_only(line)
            for pattern, reason in UNSAFE_LUA:
                if pattern.search(code):
                    problems.append(f"{rel(root, path)}:{number}: {reason}")
    return problems


def check_client_secrets(root: Path) -> list[Problem]:
    problems: list[Problem] = []
    for side in ("Client", "Shared"):
        for path in iter_files(root, root / "package" / side):
            if path.suffix not in TEXT_SUFFIXES:
                continue
            for number, line in enumerate(read_text(path).splitlines(), start=1):
                code = strip_lua_comments(line) if path.suffix == ".lua" else line
                for pattern, reason in CLIENT_SECRET_PATTERNS:
                    if pattern.search(code):
                        problems.append(f"{rel(root, path)}:{number}: {reason} (file is downloaded by players)")
    return problems


def check_secrets(root: Path) -> list[Problem]:
    problems: list[Problem] = []
    for path in iter_files(root):
        if path.suffix not in TEXT_SUFFIXES and path.name not in {".gitignore", ".gitattributes", ".editorconfig"}:
            continue
        if path.resolve() == Path(__file__).resolve():
            continue
        for number, line in enumerate(read_text(path).splitlines(), start=1):
            for pattern, reason in SECRET_PATTERNS:
                if pattern.search(line):
                    problems.append(f"{rel(root, path)}:{number}: possible {reason}")
    return problems


def check_todo_markers(root: Path) -> list[Problem]:
    problems: list[Problem] = []
    for path in iter_files(root, root / "package"):
        if path.suffix not in TEXT_SUFFIXES:
            continue
        for number, line in enumerate(read_text(path).splitlines(), start=1):
            if TODO_MARKER.search(line):
                problems.append(f"{rel(root, path)}:{number}: unresolved marker in shipped code")
    return problems


def check_versions(root: Path) -> list[Problem]:
    problems: list[Problem] = []
    manifest = root / "package" / "Package.toml"
    version_module = root / "package" / "Shared" / "foundation" / "version.lua"
    changelog = root / "CHANGELOG.md"
    manifest_match = re.search(r'^\s*version\s*=\s*"([^"]+)"', read_text(manifest), re.MULTILINE) if manifest.is_file() else None
    module_match = re.search(r'PRODUCT\s*=\s*"([^"]+)"', read_text(version_module)) if version_module.is_file() else None
    if not manifest_match:
        problems.append("package/Package.toml: [meta] version not found")
    if not module_match:
        problems.append("package/Shared/foundation/version.lua: PRODUCT not found")
    if manifest_match and module_match and manifest_match.group(1) != module_match.group(1):
        problems.append(f"version mismatch: Package.toml {manifest_match.group(1)} vs version.lua {module_match.group(1)}")
    if manifest_match and not re.fullmatch(r"\d+\.\d+\.\d+", manifest_match.group(1)):
        problems.append(f"package/Package.toml: version '{manifest_match.group(1)}' is not X.Y.Z")
    if not changelog.is_file():
        problems.append("CHANGELOG.md is missing")
    elif manifest_match:
        text = read_text(changelog)
        released = f"## [{manifest_match.group(1)}]" in text
        if not released and "## [Unreleased]" not in text:
            problems.append(f"CHANGELOG.md has neither an [Unreleased] nor a [{manifest_match.group(1)}] section")
    return problems


CHECKS: dict[str, Callable[[Path], list[Problem]]] = {
    "docs-parity": check_docs_parity,
    "links": check_links,
    "public-wording": check_public_wording,
    "unsafe-lua": check_unsafe_lua,
    "client-secrets": check_client_secrets,
    "secrets": check_secrets,
    "todo-markers": check_todo_markers,
    "versions": check_versions,
}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Foundation repository checks")
    parser.add_argument("--only", action="append", choices=sorted(CHECKS), help="run only this check (repeatable)")
    parser.add_argument("--root", type=Path, default=REPO_ROOT, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)

    failed = False
    for name in args.only or list(CHECKS):
        problems = CHECKS[name](args.root.resolve())
        if problems:
            failed = True
            print(f"{name}: {len(problems)} problem(s)")
            for problem in problems:
                print(f"  {problem}")
        else:
            print(f"{name}: ok")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
