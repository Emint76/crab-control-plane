#!/usr/bin/env bash
set -u
set -o pipefail

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_EXECUTION_PREP_PYTHON_BIN:-python}"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_EXECUTION_PREP_PYTHON_BIN:-python3}"
else
  echo "FAIL python runtime not found; set LIVE_EXECUTION_PREP_PYTHON_BIN or install python/python3" >&2
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
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class ExecutionPrepError(Exception):
    pass


repo_root = Path(sys.argv[1]).resolve(strict=True)
args = sys.argv[2:]
prep_root = repo_root / "operations" / "harness-openclaw-live-execution-prep"
runs_root = prep_root / "runs"
precheck_ref = "operations/harness-openclaw-live-precheck/bin/run_live_preexecution_gate.sh"
precheck_runs_root = repo_root / "operations" / "harness-openclaw-live-precheck" / "runs"

allowed_args = {
    "--selector-file": "selector",
    "--approval-file": "approval",
    "--rollback-file": "rollback",
    "--run-id": "run_id",
}
values: dict[str, str | None] = {value: None for value in allowed_args.values()}


def fail(message: str) -> None:
    raise ExecutionPrepError(message)


def usage() -> None:
    print(
        "usage: run_live_execution_prep.sh "
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
    return f"operations/harness-openclaw-live-execution-prep/runs/{run_id}"


def precheck_run_dir_ref(precheck_run_id: str) -> str:
    return f"operations/harness-openclaw-live-precheck/runs/{precheck_run_id}"


def output_ref(run_id: str, filename: str) -> str:
    return f"{canonical_run_dir(run_id)}/{filename}"


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


def resolve_outside_file(raw: str) -> tuple[Path | None, str | None]:
    if raw == "" or raw != raw.strip():
        return None, "path_empty_or_whitespace"
    path = Path(raw)
    if not path.is_absolute():
        return None, "path_not_absolute"
    try:
        resolved = path.resolve(strict=True)
    except OSError:
        return None, "path_missing"
    if not resolved.is_file():
        return None, "path_not_file"
    if path_is_inside_repo(resolved):
        return None, "path_inside_repo"
    return resolved, None


def load_outside_inputs() -> tuple[dict[str, Any | None], dict[str, Any]]:
    payloads: dict[str, Any | None] = {"selector": None, "approval": None, "rollback": None}
    diagnostics: dict[str, Any] = {"status": "pass", "inputs": {}, "violations": []}
    for label in ("selector", "approval", "rollback"):
        resolved, violation = resolve_outside_file(str(values[label]))
        diagnostics["inputs"][label] = {
            "path": str(values[label]),
            "loaded": False,
            "violation": violation,
        }
        if violation is not None or resolved is None:
            diagnostics["status"] = "fail"
            diagnostics["violations"].append(f"{label}_{violation}")
            continue
        payload, error = load_json_file(resolved)
        if error is not None:
            diagnostics["status"] = "fail"
            diagnostics["violations"].append(f"{label}_json_unreadable")
            diagnostics["inputs"][label]["violation"] = error
            continue
        payloads[label] = payload
        diagnostics["inputs"][label]["loaded"] = True
    return payloads, diagnostics


def execution_prep_meta(run_id: str) -> dict[str, Any]:
    return {
        "surface_kind": "live-execution-prep",
        "run_id": run_id,
        "canonical_run_dir": canonical_run_dir(run_id),
        "execution_prep_only": True,
        "live_runtime_apply": False,
        "live_wrapper": False,
        "crab_approved": False,
        "approval_granting": False,
        "rollback_execution": False,
        "real_secret_loading": False,
        "broader_local_overlay_reading": False,
        "created_at": now_utc(),
    }


def run_precheck(precheck_run_id: str) -> dict[str, Any]:
    env = os.environ.copy()
    env["LIVE_PRECHECK_PYTHON_BIN"] = sys.executable
    completed = subprocess.run(
        [
            "bash",
            precheck_ref,
            "--selector-file",
            str(values["selector"]),
            "--approval-file",
            str(values["approval"]),
            "--rollback-file",
            str(values["rollback"]),
            "--run-id",
            precheck_run_id,
        ],
        cwd=repo_root,
        env=env,
        check=False,
    )
    precheck_dir = precheck_runs_root / precheck_run_id
    report_path = precheck_dir / "gate_report.json"
    report, error = load_json_file(report_path)
    overall_status = "missing"
    if isinstance(report, dict):
        overall_status = str(report.get("overall_status", "missing"))
    status = "pass" if completed.returncode == 0 and overall_status == "pass" else "fail"
    return {
        "status": status,
        "precheck_run_id": precheck_run_id,
        "precheck_run_dir": precheck_run_dir_ref(precheck_run_id),
        "overall_status": overall_status,
        "precheck_exit_code": completed.returncode,
        "report_read_error": error,
    }


def selector_execution_record(selector: dict[str, Any]) -> dict[str, Any]:
    return {
        "record_kind": "selector-execution-record",
        "selector_label": selector["selector_label"],
        "target_instance_label": selector["target_instance_label"],
        "target_class": selector["target_class"],
        "workspace_root": selector["workspace_root"],
        "state_root": selector["state_root"],
        "runtime_root": selector["runtime_root"],
        "is_disposable": selector["is_disposable"],
    }


def approval_execution_record(approval: dict[str, Any]) -> dict[str, Any]:
    return {
        "record_kind": "approval-execution-record",
        "approval_label": approval["approval_label"],
        "approved_operation_class": approval["approved_operation_class"],
        "target_instance_label": approval["target_instance_label"],
        "selector_label": approval["selector_label"],
        "execution_label": approval["execution_label"],
        "non_reusable": approval["non_reusable"],
        "approved_by": approval["approved_by"],
    }


def rollback_execution_record(rollback: dict[str, Any]) -> dict[str, Any]:
    return {
        "record_kind": "rollback-execution-record",
        "rollback_label": rollback["rollback_label"],
        "target_instance_label": rollback["target_instance_label"],
        "execution_label": rollback["execution_label"],
        "rollback_ready": rollback["rollback_ready"],
        "rollback_boundary": rollback["rollback_boundary"],
        "decision_points": rollback["decision_points"],
    }


def validate_approval_record(payloads: dict[str, Any | None]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "status": "pass",
        "execution_prep_only": True,
        "live_runtime_apply": False,
        "checks": {},
        "violations": [],
    }
    selector = payloads.get("selector")
    approval = payloads.get("approval")
    if not isinstance(selector, dict) or not isinstance(approval, dict):
        result["status"] = "fail"
        result["violations"].append("selector_or_approval_not_loaded")
        return result

    checks = result["checks"]
    checks["approved_operation_class_live_runtime_apply"] = (
        approval.get("approved_operation_class") == "live-runtime-apply"
    )
    checks["non_reusable_true"] = approval.get("non_reusable") is True
    checks["selector_label_matches"] = (
        approval.get("selector_label") == selector.get("selector_label")
    )
    checks["target_instance_label_matches"] = (
        approval.get("target_instance_label") == selector.get("target_instance_label")
    )
    checks["execution_label_non_empty"] = isinstance(
        approval.get("execution_label"), str
    ) and bool(str(approval.get("execution_label")).strip())

    for key, passed in checks.items():
        if not passed:
            result["violations"].append(key)
    if result["violations"]:
        result["status"] = "fail"
    return result


def validate_rollback_record(payloads: dict[str, Any | None]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "status": "pass",
        "execution_prep_only": True,
        "live_runtime_apply": False,
        "checks": {},
        "violations": [],
    }
    selector = payloads.get("selector")
    approval = payloads.get("approval")
    rollback = payloads.get("rollback")
    if not all(isinstance(item, dict) for item in (selector, approval, rollback)):
        result["status"] = "fail"
        result["violations"].append("selector_approval_or_rollback_not_loaded")
        return result

    checks = result["checks"]
    checks["rollback_ready_true"] = rollback.get("rollback_ready") is True
    checks["target_instance_label_matches"] = (
        rollback.get("target_instance_label") == selector.get("target_instance_label")
    )
    checks["execution_label_matches_approval"] = (
        rollback.get("execution_label") == approval.get("execution_label")
    )
    decision_points = rollback.get("decision_points")
    checks["decision_points_non_empty"] = (
        isinstance(decision_points, list)
        and len(decision_points) > 0
        and all(isinstance(item, str) and item.strip() for item in decision_points)
    )
    checks["rollback_boundary_non_empty"] = isinstance(
        rollback.get("rollback_boundary"), str
    ) and bool(str(rollback.get("rollback_boundary")).strip())

    for key, passed in checks.items():
        if not passed:
            result["violations"].append(key)
    if result["violations"]:
        result["status"] = "fail"
    return result


def input_refs(run_id: str, precheck_run_id: str) -> dict[str, Any]:
    return {
        "source_files": {
            "selector_file": str(values["selector"]),
            "approval_file": str(values["approval"]),
            "rollback_file": str(values["rollback"]),
        },
        "precheck": {
            "precheck_run_id": precheck_run_id,
            "precheck_run_dir": precheck_run_dir_ref(precheck_run_id),
        },
        "normalized_output_records": {
            "selector_execution_record": output_ref(run_id, "selector_execution_record.json"),
            "approval_execution_record": output_ref(run_id, "approval_execution_record.json"),
            "rollback_execution_record": output_ref(run_id, "rollback_execution_record.json"),
            "execution_prep_bundle": output_ref(run_id, "execution_prep_bundle.json"),
        },
        "contains_secrets": False,
    }


def execution_prep_report(
    precheck_result: dict[str, Any],
    approval_result: dict[str, Any],
    rollback_result: dict[str, Any],
    records_written: bool,
) -> dict[str, Any]:
    statuses = {
        "preexecution_gate_validation": precheck_result["status"],
        "approval_record_validation": approval_result["status"],
        "rollback_record_validation": rollback_result["status"],
    }
    overall_status = (
        "pass"
        if records_written and all(value == "pass" for value in statuses.values())
        else "fail"
    )
    return {
        "overall_status": overall_status,
        **statuses,
        "records_written": records_written,
        "execution_prep_only": True,
        "live_runtime_apply": False,
        "live_wrapper": False,
        "crab_approved": False,
        "approval_granting": False,
        "rollback_execution": False,
    }


def write_normalized_outputs(
    run_dir: Path,
    run_id: str,
    precheck_run_id: str,
    payloads: dict[str, Any | None],
) -> bool:
    selector = payloads.get("selector")
    approval = payloads.get("approval")
    rollback = payloads.get("rollback")
    if not all(isinstance(item, dict) for item in (selector, approval, rollback)):
        return False

    selector_record = selector_execution_record(selector)
    approval_record = approval_execution_record(approval)
    rollback_record = rollback_execution_record(rollback)
    refs = input_refs(run_id, precheck_run_id)
    bundle = {
        "bundle_kind": "live-execution-prep-bundle",
        "execution_prep_only": True,
        "live_runtime_apply": False,
        "live_wrapper": False,
        "crab_approved": False,
        "approval_granting": False,
        "rollback_execution": False,
        "records": {
            "selector": selector_record,
            "approval": approval_record,
            "rollback": rollback_record,
        },
        "input_refs": refs,
    }
    write_json(run_dir / "selector_execution_record.json", selector_record)
    write_json(run_dir / "approval_execution_record.json", approval_record)
    write_json(run_dir / "rollback_execution_record.json", rollback_record)
    write_json(run_dir / "execution_prep_bundle.json", bundle)
    write_json(run_dir / "input_refs.json", refs)
    return True


def main() -> int:
    parse_args()
    run_id = str(values["run_id"])
    validate_run_id(run_id)

    run_dir = runs_root / run_id
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)
    write_json(run_dir / "execution_prep_meta.json", execution_prep_meta(run_id))

    precheck_run_id = f"{run_id}-precheck"
    precheck_result = run_precheck(precheck_run_id)
    write_json(checks_dir / "preexecution_gate_validation.json", precheck_result)

    payloads, load_diagnostics = load_outside_inputs()
    approval_result = validate_approval_record(payloads)
    rollback_result = validate_rollback_record(payloads)
    if load_diagnostics["status"] != "pass":
        approval_result.setdefault("input_loading", load_diagnostics)
        rollback_result.setdefault("input_loading", load_diagnostics)

    write_json(checks_dir / "approval_record_validation.json", approval_result)
    write_json(checks_dir / "rollback_record_validation.json", rollback_result)

    records_written = False
    if (
        precheck_result["status"] == "pass"
        and approval_result["status"] == "pass"
        and rollback_result["status"] == "pass"
    ):
        records_written = write_normalized_outputs(run_dir, run_id, precheck_run_id, payloads)
    else:
        write_json(run_dir / "input_refs.json", input_refs(run_id, precheck_run_id))

    report = execution_prep_report(
        precheck_result,
        approval_result,
        rollback_result,
        records_written,
    )
    exit_code = 0 if report["overall_status"] == "pass" else 1
    write_json(run_dir / "execution_prep_report.json", report)
    write_text(run_dir / "exit_code", f"{exit_code}\n")

    if exit_code == 0:
        print(f"PASS live execution prep: {run_id}")
    else:
        print(f"FAIL live execution prep: {run_id}", file=sys.stderr)
    return exit_code


try:
    raise SystemExit(main())
except ExecutionPrepError as exc:
    print(f"FAIL {exc}", file=sys.stderr)
    usage()
    raise SystemExit(1)
except Exception as exc:
    print(f"FAIL unexpected live execution prep error: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
