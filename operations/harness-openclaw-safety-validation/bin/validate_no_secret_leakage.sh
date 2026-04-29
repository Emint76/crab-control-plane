#!/usr/bin/env bash
set -u

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
else
  printf '%s\n' '{"status":"fail","evidence_dir":null,"files_scanned":0,"violations":[{"type":"runtime","path":null,"detail":"python runtime not found; install python or python3"}]}'
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd -P)"
export REPO_ROOT

exec "${PYTHON_BIN}" - "$@" <<'PY'
from __future__ import annotations

import fnmatch
import json
import os
import re
import sys
from pathlib import Path, PurePosixPath


APPROVED_ROOT = "operations/harness-openclaw-dryrun/runs"
FORBIDDEN_EXACT_FILENAMES = {
    ".env",
    ".env.local",
    ".env.production",
    "id_rsa",
    "id_ed25519",
}
FORBIDDEN_FILENAME_GLOBS = (
    "*.env",
    "*.pem",
    "*.key",
)
SECRET_PATTERNS = (
    ("private_key_block", re.compile(r"-----BEGIN PRIVATE KEY-----")),
    ("rsa_private_key_block", re.compile(r"-----BEGIN RSA PRIVATE KEY-----")),
    ("openssh_private_key_block", re.compile(r"-----BEGIN OPENSSH PRIVATE KEY-----")),
    ("openai_token_like", re.compile(r"sk-[A-Za-z0-9_-]{10,}")),
    ("github_pat_like", re.compile(r"ghp_[A-Za-z0-9A-Za-z_]{20,}")),
    ("github_fine_grained_pat_like", re.compile(r"github_pat_[A-Za-z0-9_]{20,}")),
    ("slack_token_like", re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}")),
    ("aws_access_key_like", re.compile(r"AKIA[0-9A-Z]{16}")),
)
KEY_VALUE_PATTERNS = (
    ("OPENAI_API_KEY", re.compile(r"OPENAI_API_KEY\s*=", re.IGNORECASE)),
    ("ANTHROPIC_API_KEY", re.compile(r"ANTHROPIC_API_KEY\s*=", re.IGNORECASE)),
    ("GITHUB_TOKEN", re.compile(r"GITHUB_TOKEN\s*=", re.IGNORECASE)),
    ("OAUTH_REFRESH_TOKEN", re.compile(r"OAUTH_REFRESH_TOKEN\s*=", re.IGNORECASE)),
    ("AWS_SECRET_ACCESS_KEY", re.compile(r"AWS_SECRET_ACCESS_KEY\s*=", re.IGNORECASE)),
)
HARMLESS_PLACEHOLDERS = ("<redacted>", "example", "placeholder")


def safe_evidence_display(raw: str | None) -> str | None:
    if raw is None:
        return None
    if os.path.isabs(raw) or re.match(r"^[A-Za-z]:[\\/]", raw) or "\\" in raw:
        return "<invalid-non-repo-relative-path>"
    return raw


def repo_ref(path: Path, repo_root: Path) -> str:
    return path.resolve(strict=False).relative_to(repo_root).as_posix()


def emit(status: str, evidence_dir: str | None, files_scanned: int, violations: list[dict[str, str | None]]) -> None:
    print(
        json.dumps(
            {
                "status": status,
                "evidence_dir": evidence_dir,
                "files_scanned": files_scanned,
                "violations": violations,
            },
            indent=2,
            sort_keys=True,
        )
    )
    raise SystemExit(0 if status == "pass" else 1)


def violation(kind: str, path: str | None, detail: str) -> dict[str, str | None]:
    return {
        "type": kind,
        "path": path,
        "detail": detail,
    }


args = sys.argv[1:]
evidence_dir_raw = None
violations: list[dict[str, str | None]] = []
files_scanned = 0

i = 0
while i < len(args):
    arg = args[i]
    if arg != "--evidence-dir":
        violations.append(violation("argument", None, f"unknown argument: {arg}"))
        i += 1
        continue
    if i + 1 >= len(args):
        violations.append(violation("argument", None, "missing value for --evidence-dir"))
        i += 1
        continue
    if evidence_dir_raw is not None:
        violations.append(violation("argument", None, "duplicate argument: --evidence-dir"))
    evidence_dir_raw = args[i + 1]
    i += 2

evidence_display = safe_evidence_display(evidence_dir_raw)
repo_root = Path(os.environ["REPO_ROOT"]).resolve(strict=True)

if evidence_dir_raw is None:
    violations.append(violation("argument", None, "missing required argument: --evidence-dir"))
elif evidence_dir_raw == "":
    violations.append(violation("argument", evidence_display, "evidence_dir must not be empty"))
elif evidence_dir_raw != evidence_dir_raw.strip():
    violations.append(violation("argument", evidence_display, "evidence_dir must not have leading or trailing whitespace"))
elif os.path.isabs(evidence_dir_raw) or re.match(r"^[A-Za-z]:[\\/]", evidence_dir_raw):
    violations.append(violation("argument", evidence_display, "evidence_dir must be repo-relative"))
elif "\\" in evidence_dir_raw:
    violations.append(violation("argument", evidence_display, "evidence_dir must use POSIX separators"))
else:
    pure_path = PurePosixPath(evidence_dir_raw)
    if ".." in pure_path.parts:
        violations.append(violation("argument", evidence_display, "evidence_dir must not contain ../ traversal"))
    elif not pure_path.as_posix().startswith(f"{APPROVED_ROOT}/"):
        violations.append(violation("argument", evidence_display, f"evidence_dir must be under {APPROVED_ROOT}/"))
    else:
        approved_root_parts = PurePosixPath(APPROVED_ROOT).parts
        relative_parts = pure_path.parts[len(approved_root_parts):]
        if len(relative_parts) != 1:
            violations.append(violation("argument", evidence_display, f"evidence_dir must identify one dry-run directory under {APPROVED_ROOT}/"))

evidence_path: Path | None = None
if evidence_dir_raw and not violations:
    evidence_path = (repo_root / Path(*PurePosixPath(evidence_dir_raw).parts)).resolve(strict=False)
    approved_root_path = (repo_root / APPROVED_ROOT).resolve(strict=False)
    try:
        evidence_path.relative_to(approved_root_path)
    except ValueError:
        violations.append(violation("argument", evidence_display, f"evidence_dir must be under {APPROVED_ROOT}/"))
    if not violations:
        if not evidence_path.exists():
            violations.append(violation("argument", evidence_display, "evidence_dir does not exist"))
        elif not evidence_path.is_dir():
            violations.append(violation("argument", evidence_display, "evidence_dir is not a directory"))

if violations:
    emit("fail", evidence_display, files_scanned, violations)

assert evidence_path is not None

for path in sorted(item for item in evidence_path.rglob("*") if item.is_file()):
    files_scanned += 1
    relative_path = repo_ref(path, repo_root)
    name = path.name
    if name in FORBIDDEN_EXACT_FILENAMES or any(fnmatch.fnmatch(name, pattern) for pattern in FORBIDDEN_FILENAME_GLOBS):
        violations.append(violation("forbidden_filename", relative_path, f"forbidden secret-like filename: {name}"))

    try:
        text = path.read_bytes().decode("utf-8")
    except (OSError, UnicodeDecodeError):
        continue

    for line_number, line in enumerate(text.splitlines(), start=1):
        lower_line = line.lower()
        harmless = any(token in lower_line for token in HARMLESS_PLACEHOLDERS)

        for detail, pattern in SECRET_PATTERNS:
            if pattern.search(line) and not harmless:
                violations.append(violation("secret_pattern", relative_path, f"{detail} on line {line_number}"))

        for detail, pattern in KEY_VALUE_PATTERNS:
            if pattern.search(line) and not harmless:
                violations.append(violation("secret_pattern", relative_path, f"{detail} assignment on line {line_number}"))

if violations:
    emit("fail", evidence_display, files_scanned, violations)

emit("pass", evidence_display, files_scanned, [])
PY
