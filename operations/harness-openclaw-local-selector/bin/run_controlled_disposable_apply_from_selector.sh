#!/usr/bin/env bash
set -u
set -o pipefail

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
else
  echo "FAIL python runtime not found; install python or python3" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd -P)"

cd "${REPO_ROOT}" || {
  echo "FAIL missing repo root" >&2
  exit 1
}

exec "${PYTHON_BIN}" - "${REPO_ROOT}" "$@" <<'PY'
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any


class SelectorError(Exception):
    pass


repo_root = Path(sys.argv[1]).resolve(strict=True)
args = sys.argv[2:]

allowed_args = {
    "--selector-file": "selector_file",
    "--dry-run-run-dir": "dry_run_run_dir",
    "--run-id": "run_id",
}
values: dict[str, str | None] = {key: None for key in allowed_args.values()}

schema_ref = "operations/harness-openclaw-local-selector/schemas/disposable_target_selector.schema.json"
apply_ref = "operations/harness-openclaw-disposable-apply/bin/run_controlled_disposable_apply.sh"


def fail(message: str) -> None:
    raise SelectorError(message)


def parse_args() -> None:
    index = 0
    while index < len(args):
        arg = args[index]
        if arg not in allowed_args:
            fail(f"unknown argument: {arg}")
        if index + 1 >= len(args):
            fail(f"missing value for {arg}")
        key = allowed_args[arg]
        if values[key] is not None:
            fail(f"duplicate argument: {arg}")
        values[key] = args[index + 1]
        index += 2

    for arg, key in allowed_args.items():
        if values[key] is None:
            fail(f"missing required argument: {arg}")


def load_json(path: Path, label: str) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"unable to read {label}: {exc}")


def validate_selector_path(raw: str) -> Path:
    if raw == "" or raw != raw.strip():
        fail("--selector-file must be a nonempty absolute path")
    selector_path = Path(raw)
    if not selector_path.is_absolute():
        fail("--selector-file must be absolute")
    if not selector_path.is_file():
        fail("--selector-file must be an existing file")
    resolved = selector_path.resolve(strict=True)
    try:
        resolved.relative_to(repo_root)
    except ValueError:
        return resolved
    fail("--selector-file must be outside the repository root")


def validate_selector_schema(selector: Any) -> None:
    try:
        import jsonschema
    except ImportError:
        fail("jsonschema is required; install operations/harness-phase2/requirements.txt")

    schema_path = repo_root / schema_ref
    schema = load_json(schema_path, schema_ref)
    jsonschema.Draft202012Validator.check_schema(schema)
    validator = jsonschema.Draft202012Validator(schema)
    violations = sorted(validator.iter_errors(selector), key=lambda item: list(item.path))
    if violations:
        first = violations[0]
        location = "/".join(str(part) for part in first.path) or "<root>"
        fail(f"selector schema validation failed at {location}: {first.message}")


def main() -> int:
    parse_args()
    selector_path = validate_selector_path(str(values["selector_file"]))
    selector = load_json(selector_path, "--selector-file")
    validate_selector_schema(selector)

    completed = subprocess.run(
        [
            "bash",
            apply_ref,
            "--dry-run-run-dir",
            str(values["dry_run_run_dir"]),
            "--workspace-target",
            str(selector["workspace_target"]),
            "--workspace-approved-root",
            str(selector["workspace_approved_root"]),
            "--state-target",
            str(selector["state_target"]),
            "--state-approved-root",
            str(selector["state_approved_root"]),
            "--approval-label",
            str(selector["approval_label"]),
            "--run-id",
            str(values["run_id"]),
        ],
        cwd=repo_root,
        check=False,
    )
    return completed.returncode


try:
    raise SystemExit(main())
except SelectorError as exc:
    print(f"FAIL {exc}", file=sys.stderr)
    raise SystemExit(1)
except Exception as exc:
    print(f"FAIL unexpected local selector error: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
