#!/usr/bin/env bash
set -u
set -o pipefail

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_WRAPPER_PREFLIGHT_PYTHON_BIN:-python}"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_WRAPPER_PREFLIGHT_PYTHON_BIN:-python3}"
else
  echo "FAIL python runtime not found; set LIVE_WRAPPER_PREFLIGHT_PYTHON_BIN or install python/python3" >&2
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


class WrapperPreflightError(Exception):
    pass


repo_root = Path(sys.argv[1]).resolve(strict=True)
args = sys.argv[2:]
surface_root = repo_root / "operations" / "harness-openclaw-live-wrapper"
runs_root = surface_root / "runs"
intake_runs_root = repo_root / "operations" / "harness-openclaw-live-wrapper-intake" / "runs"

allowed_args = {
    "--wrapper-intake-run-dir": "wrapper_intake_run_dir",
    "--run-id": "run_id",
}
values: dict[str, str | None] = {value: None for value in allowed_args.values()}


def fail(message: str) -> None:
    raise WrapperPreflightError(message)


def usage() -> None:
    print(
        "usage: run_live_wrapper_preflight.sh "
        "--wrapper-intake-run-dir <REPO_LOCAL_RUN_DIR> "
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
    return f"operations/harness-openclaw-live-wrapper/runs/{run_id}"


def repo_rel(path: Path) -> str:
    return path.relative_to(repo_root).as_posix()


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


def resolve_repo_local_run_dir(raw: str, approved_root: Path) -> tuple[Path | None, dict[str, Any]]:
    result: dict[str, Any] = {
        "provided": bool(raw),
        "path": raw,
        "absolute_or_repo_relative": False,
        "exists": False,
        "directory": False,
        "under_approved_root": False,
        "direct_child": False,
        "status": "pass",
        "violations": [],
    }
    if raw == "" or raw != raw.strip():
        result["violations"].append("wrapper_intake_path_empty_or_whitespace")
        result["status"] = "fail"
        return None, result

    raw_path = Path(raw)
    path = raw_path if raw_path.is_absolute() else repo_root / raw_path
    result["absolute_or_repo_relative"] = True
    resolved = path.resolve(strict=False)

    try:
        rel = resolved.relative_to(approved_root.resolve(strict=True))
        result["under_approved_root"] = True
        result["direct_child"] = len(rel.parts) == 1
    except (OSError, ValueError):
        result["violations"].append("wrapper_intake_run_dir_not_under_approved_root")

    if not result["direct_child"]:
        if "wrapper_intake_run_dir_not_under_approved_root" not in result["violations"]:
            result["violations"].append("wrapper_intake_run_dir_not_direct_child")

    result["exists"] = resolved.exists()
    result["directory"] = resolved.is_dir()
    if not result["exists"]:
        result["violations"].append("wrapper_intake_run_dir_missing")
    elif not result["directory"]:
        result["violations"].append("wrapper_intake_run_dir_not_directory")

    if result["violations"]:
        result["status"] = "fail"
        return None, result
    result["path"] = repo_rel(resolved)
    return resolved, result


def require_json(path: Path, result: dict[str, Any], key: str) -> Any | None:
    payload, error = load_json_file(path)
    result["files"][key] = {
        "path": repo_rel(path),
        "exists": path.is_file(),
        "readable_json": error is None,
        "error": error,
    }
    if error is not None:
        result["violations"].append(f"{key}_unreadable")
        result["status"] = "fail"
        return None
    return payload


def check_exact(result: dict[str, Any], name: str, actual: Any, expected: Any) -> None:
    passed = actual == expected
    result["checks"][name] = {
        "expected": expected,
        "actual": actual,
        "status": "pass" if passed else "fail",
    }
    if not passed:
        result["violations"].append(name)
        result["status"] = "fail"


def wrapper_meta(run_id: str) -> dict[str, Any]:
    return {
        "surface_kind": "live-wrapper-preflight",
        "run_id": run_id,
        "canonical_run_dir": canonical_run_dir(run_id),
        "preflight_only": True,
        "live_runtime_apply": False,
        "live_wrapper": False,
        "crab_approved": False,
        "approval_granting": False,
        "rollback_execution": False,
        "real_secret_loading": False,
        "broader_local_overlay_reading": False,
        "target_mutation": False,
        "created_at": now_utc(),
    }


def validate_wrapper_intake(raw: str) -> tuple[dict[str, Any], dict[str, Any] | None]:
    result: dict[str, Any] = {
        "status": "pass",
        "preflight_only": True,
        "live_runtime_apply": False,
        "root_validation": {},
        "files": {},
        "checks": {},
        "violations": [],
    }
    run_dir, root_result = resolve_repo_local_run_dir(raw, intake_runs_root)
    result["root_validation"] = root_result
    if run_dir is None:
        result["status"] = "fail"
        result["violations"].extend(root_result["violations"])
        return result, None

    report = require_json(run_dir / "wrapper_intake_report.json", result, "wrapper_intake_report")
    meta = require_json(run_dir / "wrapper_intake_meta.json", result, "wrapper_intake_meta")
    bundle = require_json(run_dir / "execution_input_bundle.json", result, "execution_input_bundle")
    input_refs = require_json(run_dir / "input_refs.json", result, "input_refs")
    non_secret_check = require_json(
        run_dir / "checks" / "non_secret_bundle_validation.json",
        result,
        "non_secret_bundle_validation",
    )

    if isinstance(report, dict):
        check_exact(result, "wrapper_intake_report_overall_status_pass", report.get("overall_status"), "pass")
    if isinstance(meta, dict):
        check_exact(result, "wrapper_intake_meta_surface_kind", meta.get("surface_kind"), "live-wrapper-intake")
        check_exact(result, "wrapper_intake_meta_wrapper_intake_only", meta.get("wrapper_intake_only"), True)
        check_exact(result, "wrapper_intake_meta_live_runtime_apply_false", meta.get("live_runtime_apply"), False)
        check_exact(result, "wrapper_intake_meta_live_wrapper_false", meta.get("live_wrapper"), False)
        check_exact(result, "wrapper_intake_meta_crab_approved_false", meta.get("crab_approved"), False)
    if isinstance(non_secret_check, dict):
        check_exact(result, "non_secret_bundle_validation_status_pass", non_secret_check.get("status"), "pass")
    if isinstance(bundle, dict):
        check_exact(result, "execution_input_bundle_kind", bundle.get("bundle_kind"), "live-wrapper-intake-bundle")
        check_exact(result, "execution_input_bundle_live_runtime_apply_false", bundle.get("live_runtime_apply"), False)
        check_exact(result, "execution_input_bundle_live_wrapper_false", bundle.get("live_wrapper"), False)
        check_exact(result, "execution_input_bundle_crab_approved_false", bundle.get("crab_approved"), False)

    if result["status"] != "pass":
        return result, None

    return result, {
        "run_dir": run_dir,
        "report": report,
        "meta": meta,
        "bundle": bundle,
        "input_refs": input_refs,
        "non_secret_check": non_secret_check,
    }


def preflight_boundary_validation() -> dict[str, Any]:
    flags = {
        "target_mutation": False,
        "real_secret_loading": False,
        "broader_local_overlay_reading": False,
        "approval_granting": False,
        "rollback_execution": False,
        "live_runtime_apply": False,
        "crab_approved": False,
    }
    return {
        "status": "pass",
        "preflight_only": True,
        "flags": flags,
        "violations": [],
    }


def get_nested(value: dict[str, Any], *keys: str) -> Any:
    current: Any = value
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def build_wrapper_input_refs(intake_data: dict[str, Any] | None) -> dict[str, Any]:
    if intake_data is None:
        return {
            "wrapper_intake_run_dir": str(values["wrapper_intake_run_dir"]),
            "execution_input_bundle": None,
            "selector_execution_record": None,
            "approval_execution_record": None,
            "rollback_execution_record": None,
            "retained_evidence_dir": None,
            "contains_file_contents": False,
            "contains_source_declaration_body": False,
        }

    run_dir = intake_data["run_dir"]
    bundle = intake_data["bundle"]
    input_refs = intake_data["input_refs"] if isinstance(intake_data["input_refs"], dict) else {}
    execution_bundle = bundle.get("execution_bundle", {}) if isinstance(bundle, dict) else {}
    return {
        "wrapper_intake_run_dir": repo_rel(run_dir),
        "execution_input_bundle": repo_rel(run_dir / "execution_input_bundle.json"),
        "selector_execution_record": execution_bundle.get("selector_execution_record")
        or input_refs.get("selector_execution_record"),
        "approval_execution_record": execution_bundle.get("approval_execution_record")
        or input_refs.get("approval_execution_record"),
        "rollback_execution_record": execution_bundle.get("rollback_execution_record")
        or input_refs.get("rollback_execution_record"),
        "retained_evidence_dir": get_nested(bundle, "retention_bundle", "retained_evidence_dir")
        or input_refs.get("retained_evidence_dir"),
        "contains_file_contents": False,
        "contains_source_declaration_body": False,
    }


def execution_plan_stub(intake_data: dict[str, Any]) -> dict[str, Any]:
    run_dir = intake_data["run_dir"]
    bundle = intake_data["bundle"]
    identity = bundle.get("identity", {}) if isinstance(bundle, dict) else {}
    return {
        "plan_kind": "live-wrapper-preflight-stub",
        "preflight_only": True,
        "live_runtime_apply": False,
        "live_wrapper": False,
        "crab_approved": False,
        "approval_granting": False,
        "rollback_execution": False,
        "real_secret_loading": False,
        "target_identity": {
            "target_instance_label": identity.get("target_instance_label", ""),
            "execution_label": identity.get("execution_label", ""),
        },
        "inputs": {
            "wrapper_intake_run_dir": repo_rel(run_dir),
            "execution_input_bundle": repo_rel(run_dir / "execution_input_bundle.json"),
        },
        "future_steps": [
            "real secret loading",
            "wrapper-integrated redaction",
            "live runtime apply",
        ],
        "contains_raw_secrets": False,
        "contains_retained_contents": False,
        "contains_source_declaration_body": False,
        "contains_target_mutation_commands": False,
    }


def wrapper_report(
    intake_result: dict[str, Any],
    boundary_result: dict[str, Any],
    plan_written: bool,
) -> dict[str, Any]:
    statuses = {
        "wrapper_intake_validation": intake_result["status"],
        "preflight_boundary_validation": boundary_result["status"],
    }
    overall_status = (
        "pass"
        if plan_written and all(value == "pass" for value in statuses.values())
        else "fail"
    )
    return {
        "overall_status": overall_status,
        **statuses,
        "plan_written": plan_written,
        "preflight_only": True,
        "live_runtime_apply": False,
        "live_wrapper": False,
        "crab_approved": False,
        "approval_granting": False,
        "rollback_execution": False,
        "real_secret_loading": False,
    }


def main() -> int:
    parse_args()
    run_id = str(values["run_id"])
    validate_run_id(run_id)

    run_dir = runs_root / run_id
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)
    write_json(run_dir / "wrapper_meta.json", wrapper_meta(run_id))

    intake_result, intake_data = validate_wrapper_intake(str(values["wrapper_intake_run_dir"]))
    boundary_result = preflight_boundary_validation()

    write_json(checks_dir / "wrapper_intake_validation.json", intake_result)
    write_json(checks_dir / "preflight_boundary_validation.json", boundary_result)
    write_json(run_dir / "wrapper_input_refs.json", build_wrapper_input_refs(intake_data))

    plan_written = False
    if intake_result["status"] == "pass" and boundary_result["status"] == "pass" and intake_data is not None:
        write_json(run_dir / "execution_plan_stub.json", execution_plan_stub(intake_data))
        plan_written = True

    report = wrapper_report(intake_result, boundary_result, plan_written)
    exit_code = 0 if report["overall_status"] == "pass" else 1
    write_json(run_dir / "wrapper_report.json", report)
    write_text(run_dir / "exit_code", f"{exit_code}\n")

    if exit_code == 0:
        print(f"PASS live wrapper preflight: {run_id}")
    else:
        print(f"FAIL live wrapper preflight: {run_id}", file=sys.stderr)
    return exit_code


try:
    raise SystemExit(main())
except WrapperPreflightError as exc:
    print(f"FAIL {exc}", file=sys.stderr)
    usage()
    raise SystemExit(1)
except Exception as exc:
    print(f"FAIL unexpected live wrapper preflight error: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
