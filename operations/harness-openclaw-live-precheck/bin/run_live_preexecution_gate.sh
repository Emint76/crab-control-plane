#!/usr/bin/env bash
set -u
set -o pipefail

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_PRECHECK_PYTHON_BIN:-python}"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_PRECHECK_PYTHON_BIN:-python3}"
else
  echo "FAIL python runtime not found; set LIVE_PRECHECK_PYTHON_BIN or install python/python3" >&2
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
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class GateCliError(Exception):
    pass


repo_root = Path(sys.argv[1]).resolve(strict=True)
args = sys.argv[2:]
gate_root = repo_root / "operations" / "harness-openclaw-live-precheck"
runs_root = gate_root / "runs"
schemas_root = gate_root / "schemas"

allowed_args = {
    "--selector-file": "selector",
    "--approval-file": "approval",
    "--rollback-file": "rollback",
    "--run-id": "run_id",
}
values: dict[str, str | None] = {value: None for value in allowed_args.values()}

schema_refs = {
    "selector": schemas_root / "live_target_selector.schema.json",
    "approval": schemas_root / "operator_approval_record.schema.json",
    "rollback": schemas_root / "rollback_handoff_record.schema.json",
}

secret_key_terms = {
    "secret",
    "token",
    "password",
    "apikey",
    "api_key",
    "oauth",
    "credential",
    "private_key",
    "session_cookie",
}


def fail(message: str) -> None:
    raise GateCliError(message)


def usage() -> None:
    print(
        "usage: run_live_preexecution_gate.sh "
        "--selector-file <ABSOLUTE_PATH_OUTSIDE_GIT> "
        "--approval-file <ABSOLUTE_PATH_OUTSIDE_GIT> "
        "--rollback-file <ABSOLUTE_PATH_OUTSIDE_GIT> "
        "--run-id <SAFE_RUN_ID>",
        file=sys.stderr,
    )


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


def validate_run_id(value: str) -> None:
    if value == "":
        fail("invalid --run-id: empty")
    if value != value.strip():
        fail("invalid --run-id: leading or trailing whitespace")
    if value in {".", ".."}:
        fail("invalid --run-id: . and .. are not allowed")
    if value.startswith("/") or re.match(r"^[A-Za-z]:[\\/]", value):
        fail("invalid --run-id: absolute paths are not allowed")
    if "/" in value or "\\" in value:
        fail("invalid --run-id: traversal and path separators are not allowed")
    if not re.fullmatch(r"[A-Za-z0-9._-]+", value):
        fail("invalid --run-id: must match ^[A-Za-z0-9._-]+$")


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def canonical_run_dir(run_id: str) -> str:
    return f"operations/harness-openclaw-live-precheck/runs/{run_id}"


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def load_json_file(path: Path) -> tuple[Any | None, str | None]:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig")), None
    except (OSError, json.JSONDecodeError) as exc:
        return None, str(exc)


def path_is_inside_repo(path: Path) -> bool:
    try:
        path.relative_to(repo_root)
    except ValueError:
        return False
    return True


def validate_input_files() -> tuple[dict[str, Any], dict[str, Path]]:
    results: dict[str, Any] = {
        "status": "pass",
        "validation_only": True,
        "live_runtime_apply": False,
        "inputs": {},
        "violations": [],
    }
    resolved_paths: dict[str, Path] = {}

    for label in ("selector", "approval", "rollback"):
        raw = str(values[label])
        item: dict[str, Any] = {
            "provided": bool(raw),
            "absolute_path": False,
            "exists": False,
            "file": False,
            "outside_repo": False,
            "git_tracked_repo_path": False,
            "status": "fail",
        }

        if raw == "" or raw != raw.strip():
            results["violations"].append(f"{label}_path_empty_or_whitespace")
            results["inputs"][label] = item
            continue

        path = Path(raw)
        item["absolute_path"] = path.is_absolute()
        if not item["absolute_path"]:
            results["violations"].append(f"{label}_path_not_absolute")
            results["inputs"][label] = item
            continue

        try:
            resolved = path.resolve(strict=True)
        except OSError:
            results["violations"].append(f"{label}_path_missing")
            results["inputs"][label] = item
            continue

        item["exists"] = resolved.exists()
        item["file"] = resolved.is_file()
        item["outside_repo"] = not path_is_inside_repo(resolved)
        item["git_tracked_repo_path"] = path_is_inside_repo(resolved)

        if not item["file"]:
            results["violations"].append(f"{label}_path_not_file")
        if not item["outside_repo"]:
            results["violations"].append(f"{label}_path_inside_repo")

        if item["absolute_path"] and item["file"] and item["outside_repo"]:
            item["status"] = "pass"
            resolved_paths[label] = resolved

        results["inputs"][label] = item

    if results["violations"]:
        results["status"] = "fail"

    return results, resolved_paths


def validate_schemas(payloads: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "status": "pass",
        "validation_only": True,
        "live_runtime_apply": False,
        "records": {},
        "violations": [],
    }

    try:
        import jsonschema
    except ImportError:
        result["status"] = "fail"
        result["violations"].append(
            "jsonschema is required; install operations/harness-phase2/requirements.txt"
        )
        return result

    for label, schema_path in schema_refs.items():
        item = {"status": "pass", "schema": schema_path.name, "violations": []}
        payload = payloads.get(label)
        if payload is None:
            item["status"] = "fail"
            item["violations"].append("input_not_loaded")
        else:
            schema = json.loads(schema_path.read_text(encoding="utf-8-sig"))
            jsonschema.Draft202012Validator.check_schema(schema)
            validator = jsonschema.Draft202012Validator(schema)
            errors = sorted(validator.iter_errors(payload), key=lambda error: list(error.path))
            for error in errors:
                location = "/".join(str(part) for part in error.path) or "<root>"
                item["violations"].append(f"{location}: {error.message}")
            if item["violations"]:
                item["status"] = "fail"

        if item["status"] != "pass":
            result["status"] = "fail"
            result["violations"].append(f"{label}_schema_failed")
        result["records"][label] = item

    return result


def contains_parent_reference(path_text: str) -> bool:
    parts = re.split(r"[\\/]+", path_text)
    return any(part == ".." for part in parts)


def normalized_path_identity(path_text: str) -> str:
    return str(Path(path_text).resolve(strict=False))


def root_obviously_disposable(path_text: str) -> bool:
    lowered_parts = [part.lower() for part in re.split(r"[\\/]+", path_text)]
    return any("disposable" in part for part in lowered_parts)


def validate_cross_binding(payloads: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "status": "pass",
        "validation_only": True,
        "live_runtime_apply": False,
        "checks": {},
        "violations": [],
    }

    selector = payloads.get("selector")
    approval = payloads.get("approval")
    rollback = payloads.get("rollback")

    if not all(isinstance(item, dict) for item in (selector, approval, rollback)):
        result["status"] = "fail"
        result["violations"].append("records_not_loaded")
        return result

    checks = result["checks"]
    checks["approval_target_matches_selector"] = (
        approval.get("target_instance_label") == selector.get("target_instance_label")
    )
    checks["rollback_target_matches_selector"] = (
        rollback.get("target_instance_label") == selector.get("target_instance_label")
    )
    checks["approval_selector_matches_selector"] = (
        approval.get("selector_label") == selector.get("selector_label")
    )
    checks["approval_execution_matches_rollback"] = (
        approval.get("execution_label") == rollback.get("execution_label")
    )
    checks["selector_target_class_live"] = selector.get("target_class") == "live"
    checks["selector_is_not_disposable"] = selector.get("is_disposable") is False

    roots = {
        "workspace_root": str(selector.get("workspace_root", "")),
        "state_root": str(selector.get("state_root", "")),
        "runtime_root": str(selector.get("runtime_root", "")),
    }
    normalized_roots = {key: normalized_path_identity(value) for key, value in roots.items()}
    checks["selector_roots_pairwise_distinct"] = len(set(normalized_roots.values())) == 3
    checks["selector_roots_do_not_contain_parent_reference"] = not any(
        contains_parent_reference(value) for value in roots.values()
    )
    checks["selector_roots_outside_repo"] = not any(
        path_is_inside_repo(Path(value).resolve(strict=False)) for value in roots.values()
    )
    checks["selector_roots_not_obviously_disposable"] = not any(
        root_obviously_disposable(value) for value in roots.values()
    )

    for key, passed in checks.items():
        if not passed:
            result["violations"].append(key)

    if result["violations"]:
        result["status"] = "fail"

    return result


def secret_key_match(key: str) -> bool:
    lowered = key.lower()
    compact = lowered.replace("-", "_")
    collapsed = compact.replace("_", "")
    for term in secret_key_terms:
        term_compact = term.replace("-", "_")
        term_collapsed = term_compact.replace("_", "")
        if term_compact in compact or term_collapsed in collapsed:
            return True
    return False


def iter_secret_key_violations(value: Any, prefix: str) -> list[str]:
    violations: list[str] = []
    if isinstance(value, dict):
        for key, item in value.items():
            key_text = str(key)
            child_prefix = f"{prefix}.{key_text}" if prefix else key_text
            if secret_key_match(key_text):
                violations.append(child_prefix)
            violations.extend(iter_secret_key_violations(item, child_prefix))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            violations.extend(iter_secret_key_violations(item, f"{prefix}[{index}]"))
    return violations


def validate_non_secret_inputs(payloads: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "status": "pass",
        "validation_only": True,
        "live_runtime_apply": False,
        "secret_like_key_paths": [],
        "forbidden_key_terms": sorted(secret_key_terms),
    }

    for label, payload in payloads.items():
        if payload is not None:
            result["secret_like_key_paths"].extend(iter_secret_key_violations(payload, label))

    if result["secret_like_key_paths"]:
        result["status"] = "fail"
    elif len(payloads) != 3 or any(payloads.get(label) is None for label in ("selector", "approval", "rollback")):
        result["status"] = "fail"
        result["secret_like_key_paths"] = []
        result["skipped_reason"] = "input_not_loaded"

    return result


def gate_meta(run_id: str) -> dict[str, Any]:
    return {
        "gate_kind": "live-preexecution-gate",
        "run_id": run_id,
        "canonical_run_dir": canonical_run_dir(run_id),
        "validation_only": True,
        "live_runtime_apply": False,
        "live_wrapper": False,
        "crab_approved": False,
        "approval_granted": False,
        "rollback_executed": False,
        "secret_handling_implementation": False,
        "evidence_storage_implementation": False,
        "broader_local_overlay_reading": False,
        "created_at": now_utc(),
    }


def gate_report(
    input_result: dict[str, Any],
    schema_result: dict[str, Any],
    cross_result: dict[str, Any],
    non_secret_result: dict[str, Any],
) -> dict[str, Any]:
    statuses = {
        "input_location_validation": input_result["status"],
        "schema_validation": schema_result["status"],
        "cross_binding_validation": cross_result["status"],
        "non_secret_input_validation": non_secret_result["status"],
    }
    overall_status = "pass" if all(value == "pass" for value in statuses.values()) else "fail"
    return {
        "overall_status": overall_status,
        **statuses,
        "validation_only": True,
        "live_runtime_apply": False,
        "live_wrapper": False,
        "crab_approved": False,
        "approval_granted": False,
        "rollback_executed": False,
    }


def main() -> int:
    parse_args()
    run_id = str(values["run_id"])
    validate_run_id(run_id)

    run_dir = runs_root / run_id
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)
    write_json(run_dir / "gate_meta.json", gate_meta(run_id))

    input_result, resolved_paths = validate_input_files()
    write_json(checks_dir / "input_file_validation.json", input_result)

    payloads: dict[str, Any] = {"selector": None, "approval": None, "rollback": None}
    if input_result["status"] == "pass":
        for label, path in resolved_paths.items():
            payload, error = load_json_file(path)
            payloads[label] = payload
            if error is not None:
                input_result["status"] = "fail"
                input_result["violations"].append(f"{label}_json_unreadable")
                input_result["inputs"][label]["status"] = "fail"
        write_json(checks_dir / "input_file_validation.json", input_result)

    schema_result = validate_schemas(payloads)
    non_secret_result = validate_non_secret_inputs(payloads)
    cross_result = validate_cross_binding(payloads)
    report = gate_report(input_result, schema_result, cross_result, non_secret_result)
    exit_code = 0 if report["overall_status"] == "pass" else 1

    write_json(checks_dir / "schema_validation.json", schema_result)
    write_json(checks_dir / "cross_binding_validation.json", cross_result)
    write_json(checks_dir / "non_secret_input_validation.json", non_secret_result)
    write_json(run_dir / "gate_report.json", report)
    write_text(run_dir / "exit_code", f"{exit_code}\n")

    if exit_code == 0:
        print(f"PASS live pre-execution gate: {run_id}")
    else:
        print(f"FAIL live pre-execution gate: {run_id}", file=sys.stderr)
    return exit_code


try:
    raise SystemExit(main())
except GateCliError as exc:
    print(f"FAIL {exc}", file=sys.stderr)
    usage()
    raise SystemExit(1)
except Exception as exc:
    print(f"FAIL unexpected live pre-execution gate error: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
