#!/usr/bin/env bash
set -u
set -o pipefail

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_WRAPPER_INTAKE_PYTHON_BIN:-python}"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_WRAPPER_INTAKE_PYTHON_BIN:-python3}"
else
  echo "FAIL python runtime not found; set LIVE_WRAPPER_INTAKE_PYTHON_BIN or install python/python3" >&2
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


class WrapperIntakeError(Exception):
    pass


repo_root = Path(sys.argv[1]).resolve(strict=True)
args = sys.argv[2:]
surface_root = repo_root / "operations" / "harness-openclaw-live-wrapper-intake"
runs_root = surface_root / "runs"
execution_prep_runs_root = (
    repo_root / "operations" / "harness-openclaw-live-execution-prep" / "runs"
)
retention_runs_root = repo_root / "operations" / "harness-openclaw-live-retention" / "runs"

allowed_args = {
    "--execution-prep-run-dir": "execution_prep_run_dir",
    "--retention-run-dir": "retention_run_dir",
    "--run-id": "run_id",
}
values: dict[str, str | None] = {value: None for value in allowed_args.values()}

forbidden_key_terms = {
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
allowed_secret_like_keys = {"real_secret_loading"}
secret_value_pattern = re.compile(
    r"(?i)\b(?:secret|token|password|api[_-]?key|apikey|oauth|credential|private[_-]?key|session[_-]?cookie)\b\s*[:=]\s*(?!\[REDACTED\])\S+"
)


def fail(message: str) -> None:
    raise WrapperIntakeError(message)


def usage() -> None:
    print(
        "usage: run_live_wrapper_intake.sh "
        "--execution-prep-run-dir <REPO_LOCAL_RUN_DIR> "
        "--retention-run-dir <REPO_LOCAL_RUN_DIR> "
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
    return f"operations/harness-openclaw-live-wrapper-intake/runs/{run_id}"


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


def resolve_repo_local_run_dir(raw: str, approved_root: Path, kind: str) -> tuple[Path | None, dict[str, Any]]:
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
        result["violations"].append(f"{kind}_path_empty_or_whitespace")
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
        result["violations"].append(f"{kind}_run_dir_not_under_approved_root")

    if not result["direct_child"]:
        if f"{kind}_run_dir_not_under_approved_root" not in result["violations"]:
            result["violations"].append(f"{kind}_run_dir_not_direct_child")

    result["exists"] = resolved.exists()
    result["directory"] = resolved.is_dir()
    if not result["exists"]:
        result["violations"].append(f"{kind}_run_dir_missing")
    elif not result["directory"]:
        result["violations"].append(f"{kind}_run_dir_not_directory")

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
    result["checks"][name] = {"expected": expected, "actual": actual, "status": "pass" if passed else "fail"}
    if not passed:
        result["violations"].append(name)
        result["status"] = "fail"


def nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def validate_execution_prep(raw: str) -> tuple[dict[str, Any], dict[str, Any] | None]:
    result: dict[str, Any] = {
        "status": "pass",
        "wrapper_intake_only": True,
        "live_runtime_apply": False,
        "root_validation": {},
        "files": {},
        "checks": {},
        "identity_checks": {},
        "violations": [],
    }
    run_dir, root_result = resolve_repo_local_run_dir(raw, execution_prep_runs_root, "execution_prep")
    result["root_validation"] = root_result
    if run_dir is None:
        result["status"] = "fail"
        result["violations"].extend(root_result["violations"])
        return result, None

    report = require_json(run_dir / "execution_prep_report.json", result, "execution_prep_report")
    meta = require_json(run_dir / "execution_prep_meta.json", result, "execution_prep_meta")
    selector = require_json(run_dir / "selector_execution_record.json", result, "selector_execution_record")
    approval = require_json(run_dir / "approval_execution_record.json", result, "approval_execution_record")
    rollback = require_json(run_dir / "rollback_execution_record.json", result, "rollback_execution_record")
    input_refs = require_json(run_dir / "input_refs.json", result, "input_refs")

    if isinstance(report, dict):
        check_exact(result, "execution_prep_report_overall_status_pass", report.get("overall_status"), "pass")
    if isinstance(meta, dict):
        check_exact(result, "execution_prep_meta_surface_kind", meta.get("surface_kind"), "live-execution-prep")
        check_exact(result, "execution_prep_meta_execution_prep_only", meta.get("execution_prep_only"), True)
        check_exact(result, "execution_prep_meta_live_runtime_apply_false", meta.get("live_runtime_apply"), False)
        check_exact(result, "execution_prep_meta_live_wrapper_false", meta.get("live_wrapper"), False)
        check_exact(result, "execution_prep_meta_crab_approved_false", meta.get("crab_approved"), False)

    if all(isinstance(item, dict) for item in (selector, approval, rollback)):
        identity_checks = {
            "selector_approval_target_match": selector.get("target_instance_label") == approval.get("target_instance_label"),
            "selector_rollback_target_match": selector.get("target_instance_label") == rollback.get("target_instance_label"),
            "approval_rollback_execution_match": approval.get("execution_label") == rollback.get("execution_label"),
            "target_instance_label_non_empty": nonempty_string(selector.get("target_instance_label")),
            "execution_label_non_empty": nonempty_string(approval.get("execution_label")),
        }
        result["identity_checks"] = {
            key: "pass" if value else "fail" for key, value in identity_checks.items()
        }
        for key, passed in identity_checks.items():
            if not passed:
                result["violations"].append(key)
                result["status"] = "fail"

    if result["status"] != "pass":
        return result, None

    return result, {
        "run_dir": run_dir,
        "report": report,
        "meta": meta,
        "selector": selector,
        "approval": approval,
        "rollback": rollback,
        "input_refs": input_refs,
    }


def validate_retention(raw: str) -> tuple[dict[str, Any], dict[str, Any] | None]:
    result: dict[str, Any] = {
        "status": "pass",
        "wrapper_intake_only": True,
        "live_runtime_apply": False,
        "root_validation": {},
        "files": {},
        "checks": {},
        "violations": [],
    }
    run_dir, root_result = resolve_repo_local_run_dir(raw, retention_runs_root, "retention")
    result["root_validation"] = root_result
    if run_dir is None:
        result["status"] = "fail"
        result["violations"].extend(root_result["violations"])
        return result, None

    report = require_json(run_dir / "retention_report.json", result, "retention_report")
    meta = require_json(run_dir / "retention_meta.json", result, "retention_meta")
    source_check = require_json(run_dir / "checks" / "source_declaration_validation.json", result, "source_declaration_validation")
    candidate_check = require_json(run_dir / "checks" / "candidate_evidence_validation.json", result, "candidate_evidence_validation")
    redaction_check = require_json(run_dir / "checks" / "redaction_validation.json", result, "redaction_validation")
    retained_dir = run_dir / "retained"

    if isinstance(report, dict):
        check_exact(result, "retention_report_overall_status_pass", report.get("overall_status"), "pass")
        retained_file_count = report.get("retained_file_count")
        retained_file_count_ok = isinstance(retained_file_count, int) and retained_file_count >= 1
        result["checks"]["retained_file_count_at_least_one"] = {
            "actual": retained_file_count,
            "status": "pass" if retained_file_count_ok else "fail",
        }
        if not retained_file_count_ok:
            result["violations"].append("retained_file_count_at_least_one")
            result["status"] = "fail"
    if isinstance(meta, dict):
        check_exact(result, "retention_meta_surface_kind", meta.get("surface_kind"), "live-secret-retention")
        check_exact(result, "retention_meta_live_runtime_apply_false", meta.get("live_runtime_apply"), False)
        check_exact(result, "retention_meta_live_wrapper_false", meta.get("live_wrapper"), False)
        check_exact(result, "retention_meta_crab_approved_false", meta.get("crab_approved"), False)
        check_exact(result, "retention_meta_retention_only", meta.get("retention_only"), True)
        check_exact(result, "retention_meta_redaction_applied", meta.get("redaction_applied"), True)

    for check_name, payload in (
        ("source_declaration_validation_status_pass", source_check),
        ("candidate_evidence_validation_status_pass", candidate_check),
        ("redaction_validation_status_pass", redaction_check),
    ):
        if isinstance(payload, dict):
            check_exact(result, check_name, payload.get("status"), "pass")

    retained_dir_exists = retained_dir.is_dir()
    result["checks"]["retained_dir_exists"] = {
        "path": repo_rel(retained_dir),
        "status": "pass" if retained_dir_exists else "fail",
    }
    if not retained_dir_exists:
        result["violations"].append("retained_dir_missing")
        result["status"] = "fail"

    if result["status"] != "pass":
        return result, None

    return result, {
        "run_dir": run_dir,
        "report": report,
        "meta": meta,
        "source_check": source_check,
        "candidate_check": candidate_check,
        "redaction_check": redaction_check,
        "retained_dir": retained_dir,
    }


def wrapper_intake_meta(run_id: str) -> dict[str, Any]:
    return {
        "surface_kind": "live-wrapper-intake",
        "run_id": run_id,
        "canonical_run_dir": canonical_run_dir(run_id),
        "wrapper_intake_only": True,
        "live_runtime_apply": False,
        "live_wrapper": False,
        "crab_approved": False,
        "approval_granting": False,
        "rollback_execution": False,
        "real_secret_loading": False,
        "broader_local_overlay_reading": False,
        "created_at": now_utc(),
    }


def path_ref(path: Path) -> str:
    return repo_rel(path)


def build_input_refs(execution_data: dict[str, Any] | None, retention_data: dict[str, Any] | None) -> dict[str, Any]:
    execution_run_dir = execution_data["run_dir"] if execution_data else None
    retention_run_dir = retention_data["run_dir"] if retention_data else None
    return {
        "execution_prep_run_dir": path_ref(execution_run_dir) if execution_run_dir else str(values["execution_prep_run_dir"]),
        "retention_run_dir": path_ref(retention_run_dir) if retention_run_dir else str(values["retention_run_dir"]),
        "selector_execution_record": path_ref(execution_run_dir / "selector_execution_record.json") if execution_run_dir else None,
        "approval_execution_record": path_ref(execution_run_dir / "approval_execution_record.json") if execution_run_dir else None,
        "rollback_execution_record": path_ref(execution_run_dir / "rollback_execution_record.json") if execution_run_dir else None,
        "retained_evidence_dir": path_ref(retention_run_dir / "retained") if retention_run_dir else None,
        "contains_file_contents": False,
        "contains_source_declaration_body": False,
    }


def build_bundle(execution_data: dict[str, Any], retention_data: dict[str, Any]) -> dict[str, Any]:
    execution_run_dir = execution_data["run_dir"]
    retention_run_dir = retention_data["run_dir"]
    selector = execution_data["selector"]
    approval = execution_data["approval"]
    rollback = execution_data["rollback"]
    retention_report = retention_data["report"]
    return {
        "bundle_kind": "live-wrapper-intake-bundle",
        "wrapper_intake_only": True,
        "live_runtime_apply": False,
        "live_wrapper": False,
        "crab_approved": False,
        "approval_granting": False,
        "rollback_execution": False,
        "real_secret_loading": False,
        "execution_bundle": {
            "execution_prep_run_dir": path_ref(execution_run_dir),
            "selector_execution_record": path_ref(execution_run_dir / "selector_execution_record.json"),
            "approval_execution_record": path_ref(execution_run_dir / "approval_execution_record.json"),
            "rollback_execution_record": path_ref(execution_run_dir / "rollback_execution_record.json"),
        },
        "retention_bundle": {
            "retention_run_dir": path_ref(retention_run_dir),
            "retained_evidence_dir": path_ref(retention_run_dir / "retained"),
            "retained_file_count": retention_report.get("retained_file_count", 0),
        },
        "identity": {
            "target_instance_label": selector["target_instance_label"],
            "execution_label": approval["execution_label"],
        },
        "input_refs": build_input_refs(execution_data, retention_data),
    }


def key_is_secret_like(key: str) -> bool:
    if key in allowed_secret_like_keys:
        return False
    lowered = key.lower()
    compact = lowered.replace("-", "_")
    collapsed = compact.replace("_", "")
    for term in forbidden_key_terms:
        term_compact = term.replace("-", "_")
        term_collapsed = term_compact.replace("_", "")
        if term_compact in compact or term_collapsed in collapsed:
            return True
    return False


def iter_secret_like_keys(value: Any, prefix: str = "") -> list[str]:
    violations: list[str] = []
    if isinstance(value, dict):
        for key, item in value.items():
            key_text = str(key)
            child_prefix = f"{prefix}.{key_text}" if prefix else key_text
            if key_is_secret_like(key_text):
                violations.append(child_prefix)
            violations.extend(iter_secret_like_keys(item, child_prefix))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            violations.extend(iter_secret_like_keys(item, f"{prefix}[{index}]"))
    return violations


def iter_secret_like_values(value: Any, prefix: str = "") -> list[str]:
    violations: list[str] = []
    if isinstance(value, dict):
        for key, item in value.items():
            child_prefix = f"{prefix}.{key}" if prefix else str(key)
            violations.extend(iter_secret_like_values(item, child_prefix))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            violations.extend(iter_secret_like_values(item, f"{prefix}[{index}]"))
    elif isinstance(value, str) and secret_value_pattern.search(value):
        violations.append(prefix or "<root>")
    return violations


def retained_contents_inlined(bundle_text: str, retained_dir: Path) -> list[str]:
    violations: list[str] = []
    if not retained_dir.is_dir():
        return violations
    for path in sorted(retained_dir.rglob("*")):
        if not path.is_file():
            continue
        try:
            content = path.read_text(encoding="utf-8-sig").strip()
        except UnicodeError:
            continue
        if len(content) >= 32 and content in bundle_text:
            violations.append(path.relative_to(retained_dir).as_posix())
    return violations


def validate_non_secret_bundle(bundle: dict[str, Any] | None, retention_data: dict[str, Any] | None) -> dict[str, Any]:
    result: dict[str, Any] = {
        "status": "pass",
        "wrapper_intake_only": True,
        "live_runtime_apply": False,
        "checked_bundle": bundle is not None,
        "violations": [],
    }
    if bundle is None:
        result["status"] = "fail"
        result["violations"].append("bundle_not_generated")
        return result

    key_violations = iter_secret_like_keys(bundle)
    value_violations = iter_secret_like_values(bundle)
    result["secret_like_key_paths"] = key_violations
    result["secret_like_value_paths"] = value_violations
    result["retained_content_inlined"] = []

    if retention_data is not None:
        bundle_text = json.dumps(bundle, sort_keys=True)
        result["retained_content_inlined"] = retained_contents_inlined(
            bundle_text,
            retention_data["retained_dir"],
        )

    if key_violations:
        result["violations"].append("secret_like_key_in_bundle")
    if value_violations:
        result["violations"].append("secret_like_value_in_bundle")
    if result["retained_content_inlined"]:
        result["violations"].append("retained_file_content_inlined")
    if result["violations"]:
        result["status"] = "fail"
    return result


def wrapper_intake_report(
    execution_result: dict[str, Any],
    retention_result: dict[str, Any],
    non_secret_result: dict[str, Any],
    bundle_written: bool,
) -> dict[str, Any]:
    statuses = {
        "execution_prep_validation": execution_result["status"],
        "retention_validation": retention_result["status"],
        "non_secret_bundle_validation": non_secret_result["status"],
    }
    overall_status = (
        "pass"
        if bundle_written and all(value == "pass" for value in statuses.values())
        else "fail"
    )
    return {
        "overall_status": overall_status,
        **statuses,
        "bundle_written": bundle_written,
        "wrapper_intake_only": True,
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
    write_json(run_dir / "wrapper_intake_meta.json", wrapper_intake_meta(run_id))

    execution_result, execution_data = validate_execution_prep(str(values["execution_prep_run_dir"]))
    retention_result, retention_data = validate_retention(str(values["retention_run_dir"]))

    bundle = None
    if execution_result["status"] == "pass" and retention_result["status"] == "pass":
        bundle = build_bundle(execution_data, retention_data)  # type: ignore[arg-type]
    non_secret_result = validate_non_secret_bundle(bundle, retention_data)

    bundle_written = False
    if (
        execution_result["status"] == "pass"
        and retention_result["status"] == "pass"
        and non_secret_result["status"] == "pass"
        and bundle is not None
    ):
        write_json(run_dir / "execution_input_bundle.json", bundle)
        bundle_written = True

    write_json(run_dir / "input_refs.json", build_input_refs(execution_data, retention_data))
    write_json(checks_dir / "execution_prep_validation.json", execution_result)
    write_json(checks_dir / "retention_validation.json", retention_result)
    write_json(checks_dir / "non_secret_bundle_validation.json", non_secret_result)

    report = wrapper_intake_report(
        execution_result,
        retention_result,
        non_secret_result,
        bundle_written,
    )
    exit_code = 0 if report["overall_status"] == "pass" else 1
    write_json(run_dir / "wrapper_intake_report.json", report)
    write_text(run_dir / "exit_code", f"{exit_code}\n")

    if exit_code == 0:
        print(f"PASS live wrapper intake: {run_id}")
    else:
        print(f"FAIL live wrapper intake: {run_id}", file=sys.stderr)
    return exit_code


try:
    raise SystemExit(main())
except WrapperIntakeError as exc:
    print(f"FAIL {exc}", file=sys.stderr)
    usage()
    raise SystemExit(1)
except Exception as exc:
    print(f"FAIL unexpected live wrapper intake error: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
