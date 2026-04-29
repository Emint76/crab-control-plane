#!/usr/bin/env bash
set -u

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
else
  printf '%s\n' '{"status":"fail","target_type":null,"target_path":null,"approved_root":null,"violations":["python runtime not found; install python or python3"]}'
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd -P)"
export REPO_ROOT

exec "${PYTHON_BIN}" - "$@" <<'PY'
import json
import os
import sys
from pathlib import Path


def emit(payload, code):
    print(json.dumps(payload, indent=2, sort_keys=True))
    raise SystemExit(code)


def is_under(path, root):
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


args = sys.argv[1:]
values = {
    "target_type": None,
    "target_path": None,
    "approved_root": None,
}
violations = []

i = 0
while i < len(args):
    arg = args[i]
    if arg not in ("--target-type", "--target-path", "--approved-root"):
        violations.append(f"unknown argument: {arg}")
        i += 1
        continue

    if i + 1 >= len(args):
        violations.append(f"missing value for {arg}")
        i += 1
        continue

    key = arg[2:].replace("-", "_")
    if values[key] is not None:
        violations.append(f"duplicate argument: {arg}")
    values[key] = args[i + 1]
    i += 2

target_type = values["target_type"]
target_path_raw = values["target_path"]
approved_root_raw = values["approved_root"]

for key, raw in values.items():
    if raw is None:
        violations.append(f"missing required argument: --{key.replace('_', '-')}")
    elif raw == "":
        violations.append(f"empty value for --{key.replace('_', '-')}")

if target_type is not None and target_type not in ("workspace", "state"):
    violations.append("target_type must be workspace or state")

target_abs = bool(target_path_raw and os.path.isabs(target_path_raw))
approved_abs = bool(approved_root_raw and os.path.isabs(approved_root_raw))

if target_path_raw and not target_abs:
    violations.append("target_path must be absolute")
if approved_root_raw and not approved_abs:
    violations.append("approved_root must be absolute")

repo_root = Path(os.environ["REPO_ROOT"]).resolve(strict=True)
target_path = None
approved_root = None

if target_abs:
    target_path = Path(target_path_raw).resolve(strict=False)
    if not target_path.exists():
        violations.append("target_path does not exist")
    elif not target_path.is_dir():
        violations.append("target_path is not a directory")
    else:
        target_path = target_path.resolve(strict=True)

if approved_abs:
    approved_root = Path(approved_root_raw).resolve(strict=False)
    if not approved_root.exists():
        violations.append("approved_root does not exist")
    elif not approved_root.is_dir():
        violations.append("approved_root is not a directory")
    else:
        approved_root = approved_root.resolve(strict=True)

if target_path is not None and approved_root is not None:
    if target_path == approved_root:
        violations.append("target_path must not equal approved_root")
    elif not is_under(target_path, approved_root):
        violations.append("target_path must be under approved_root")

if target_path is not None:
    if target_path == repo_root:
        violations.append("target_path must not equal repo_root")
    elif is_under(target_path, repo_root):
        violations.append("target_path must be outside repo_root")

marker_verified = False
marker_file = None
if target_path is not None and target_path.exists() and target_path.is_dir():
    marker_file = target_path / ".crab-disposable-target.json"
    if not marker_file.exists():
        violations.append("disposable marker file is missing")
    elif not marker_file.is_file():
        violations.append("disposable marker path is not a file")
    else:
        try:
            marker = json.loads(marker_file.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            violations.append(f"disposable marker file is not valid JSON: {exc.msg}")
        else:
            expected_kind = {
                "workspace": "openclaw-workspace",
                "state": "openclaw-state",
            }.get(target_type)
            if expected_kind is not None and marker.get("kind") != expected_kind:
                violations.append(f"disposable marker kind must be {expected_kind}")
            if marker.get("disposable") is not True:
                violations.append("disposable marker disposable must be true")
            if expected_kind is not None and marker.get("kind") == expected_kind and marker.get("disposable") is True:
                marker_verified = True

if violations:
    emit(
        {
            "status": "fail",
            "target_type": target_type,
            "target_path": target_path_raw,
            "approved_root": approved_root_raw,
            "violations": violations,
        },
        1,
    )

emit(
    {
        "status": "pass",
        "target_type": target_type,
        "target_path": str(target_path),
        "approved_root": str(approved_root),
        "marker_file": str(marker_file),
        "under_approved_root": True,
        "outside_repo_root": True,
        "marker_verified": marker_verified,
        "violations": [],
    },
    0,
)
PY
