#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PHASE2_ROOT}/../.." && pwd)"

if [[ "$#" -ne 2 ]]; then
  echo "usage: $0 <schema> <json-file>" >&2
  exit 2
fi

PYTHON_BIN="${PHASE2_PYTHON_BIN:-python}"
if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  echo "FAIL python runtime not found: ${PYTHON_BIN}" >&2
  exit 1
fi

"${PYTHON_BIN}" - "${REPO_ROOT}" "$1" "$2" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator


def resolve_schema(repo_root: Path, schema_arg: str) -> Path:
    candidate = Path(schema_arg)
    if candidate.is_absolute():
        return candidate

    repo_relative = repo_root / candidate
    if repo_relative.is_file():
        return repo_relative

    return repo_root / "control-plane" / "contracts" / "schemas" / schema_arg


def resolve_json(repo_root: Path, json_arg: str) -> Path:
    candidate = Path(json_arg)
    if candidate.is_absolute():
        return candidate
    return repo_root / candidate


def load_json(path: Path) -> object:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def main() -> int:
    repo_root = Path(sys.argv[1]).resolve()
    schema_path = resolve_schema(repo_root, sys.argv[2])
    json_path = resolve_json(repo_root, sys.argv[3])

    try:
        schema = load_json(schema_path)
        if not isinstance(schema, dict):
            raise ValueError("schema top-level JSON value must be an object")
        Draft202012Validator.check_schema(schema)
        payload = load_json(json_path)
        errors = sorted(Draft202012Validator(schema).iter_errors(payload), key=lambda error: list(error.path))
        if errors:
            first = errors[0]
            path = ".".join(str(part) for part in first.path) or "<root>"
            raise ValueError(f"{path}: {first.message}")
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL schema validation: {json_path.as_posix()} against {schema_path.as_posix()}: {exc}", file=sys.stderr)
        return 1

    print(f"PASS schema validation: {json_path.as_posix()} against {schema_path.as_posix()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
