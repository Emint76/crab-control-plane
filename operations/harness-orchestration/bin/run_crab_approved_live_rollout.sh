#!/usr/bin/env bash
set -u
set -o pipefail

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="${CRAB_APPROVED_LIVE_ROLLOUT_PYTHON_BIN:-python}"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="${CRAB_APPROVED_LIVE_ROLLOUT_PYTHON_BIN:-python3}"
else
  echo "FAIL python runtime not found; set CRAB_APPROVED_LIVE_ROLLOUT_PYTHON_BIN or install python/python3" >&2
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
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class CrabApprovedLiveRolloutError(Exception):
    pass


repo_root = Path(sys.argv[1]).resolve(strict=True)
args = sys.argv[2:]
orch_root = repo_root / "operations" / "harness-orchestration"
runs_root = orch_root / "runs"
apply_runs_root = repo_root / "operations" / "harness-openclaw-live-wrapper" / "runs"
delegate_script = "operations/harness-openclaw-live-wrapper/bin/run_first_real_rollout.sh"

allowed_args = {
    "--apply-run-dir": "apply_run_dir",
    "--rollout-declaration-file": "rollout_declaration_file",
    "--run-id": "run_id",
}
values: dict[str, str | None] = {value: None for value in allowed_args.values()}

allowed_declaration_keys = {
    "declaration_kind",
    "target_instance_label",
    "execution_label",
    "working_directory",
    "launch_argv",
    "healthcheck_argv",
    "environment_mode",
}
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
    "env",
    "environment",
}
allowed_secret_like_keys = {
    "environment_mode",
    "non_secret_evidence_validation",
    "secret_session_direct",
}
secret_value_pattern = re.compile(
    r"(?i)\b(?:secret|token|password|api[_-]?key|apikey|oauth|credential|private[_-]?key|session[_-]?cookie)\b\s*[:=]\s*(?!\[REDACTED\])\S+"
)
bearer_pattern = re.compile(r"(?i)authorization\s*:\s*bearer\s+(?!\[REDACTED\])[^ \t\r\n]+")
private_key_pattern = re.compile("-----BEGIN " + r"[A-Z ]*PRIVATE KEY-----")
forbidden_shell_wrappers = {
    ("sh", "-c"),
    ("bash", "-c"),
    ("cmd", "/c"),
    ("powershell", "-command"),
    ("powershell.exe", "-command"),
}


def fail(message: str) -> None:
    raise CrabApprovedLiveRolloutError(message)


def usage() -> None:
    print(
        "usage: run_crab_approved_live_rollout.sh "
        "--apply-run-dir <REPO_LOCAL_RUN_DIR> "
        "--rollout-declaration-file <ABSOLUTE_PATH_OUTSIDE_GIT> "
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
    return f"operations/harness-orchestration/runs/{run_id}"


def delegate_canonical_run_dir(delegate_run_id: str) -> str:
    return f"operations/harness-openclaw-live-wrapper/runs/{delegate_run_id}"


def repo_rel(path: Path) -> str:
    return path.relative_to(repo_root).as_posix()


def path_is_inside_repo(path: Path) -> bool:
    try:
        path.resolve(strict=False).relative_to(repo_root)
    except ValueError:
        return False
    return True


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


def require_json(path: Path, result: dict[str, Any], key: str) -> Any | None:
    payload, error = load_json_file(path)
    result["files"][key] = {
        "path": repo_rel(path) if path_is_inside_repo(path) else str(path),
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


def resolve_repo_local_apply_run_dir(raw: str, output_run_dir: Path) -> tuple[Path | None, dict[str, Any]]:
    result: dict[str, Any] = {
        "provided": bool(raw),
        "path": raw,
        "exists": False,
        "directory": False,
        "under_approved_root": False,
        "direct_child": False,
        "not_output_run_dir": False,
        "status": "pass",
        "violations": [],
    }
    if raw == "" or raw != raw.strip():
        result["violations"].append("apply_run_path_empty_or_whitespace")
        result["status"] = "fail"
        return None, result

    raw_path = Path(raw)
    path = raw_path if raw_path.is_absolute() else repo_root / raw_path
    resolved = path.resolve(strict=False)
    try:
        rel = resolved.relative_to(apply_runs_root.resolve(strict=True))
        result["under_approved_root"] = True
        result["direct_child"] = len(rel.parts) == 1
    except (OSError, ValueError):
        result["violations"].append("apply_run_dir_not_under_approved_root")

    if not result["direct_child"] and "apply_run_dir_not_under_approved_root" not in result["violations"]:
        result["violations"].append("apply_run_dir_not_direct_child")

    result["not_output_run_dir"] = resolved != output_run_dir.resolve(strict=False)
    if not result["not_output_run_dir"]:
        result["violations"].append("apply_run_dir_is_output_run_dir")

    result["exists"] = resolved.exists()
    result["directory"] = resolved.is_dir()
    if not result["exists"]:
        result["violations"].append("apply_run_dir_missing")
    elif not result["directory"]:
        result["violations"].append("apply_run_dir_not_directory")

    if result["violations"]:
        result["status"] = "fail"
        return None, result
    result["path"] = repo_rel(resolved)
    return resolved, result


def validate_apply_run(raw: str, output_run_dir: Path) -> tuple[dict[str, Any], dict[str, Any] | None]:
    result: dict[str, Any] = {
        "status": "pass",
        "live_wrapper": True,
        "live_runtime_apply": True,
        "root_validation": {},
        "files": {},
        "checks": {},
        "violations": [],
    }
    run_dir, root_result = resolve_repo_local_apply_run_dir(raw, output_run_dir)
    result["root_validation"] = root_result
    if run_dir is None:
        result["status"] = "fail"
        result["violations"].extend(root_result["violations"])
        return result, None

    report = require_json(run_dir / "wrapper_apply_report.json", result, "wrapper_apply_report")
    meta = require_json(run_dir / "wrapper_apply_meta.json", result, "wrapper_apply_meta")
    actions = require_json(run_dir / "apply_actions.json", result, "apply_actions")
    handoff = require_json(run_dir / "rollback_handoff.json", result, "rollback_handoff")
    input_refs = require_json(run_dir / "wrapper_apply_input_refs.json", result, "wrapper_apply_input_refs")
    pre_apply = require_json(
        run_dir / "checks" / "pre_apply_boundary_validation.json",
        result,
        "pre_apply_boundary_validation",
    )
    post_apply = require_json(
        run_dir / "checks" / "post_apply_validation.json",
        result,
        "post_apply_validation",
    )
    non_secret = require_json(
        run_dir / "checks" / "non_secret_evidence_validation.json",
        result,
        "non_secret_evidence_validation",
    )

    if isinstance(report, dict):
        check_exact(result, "wrapper_apply_report_overall_status_pass", report.get("overall_status"), "pass")
    if isinstance(meta, dict):
        check_exact(result, "wrapper_apply_meta_surface_kind", meta.get("surface_kind"), "live-wrapper-apply")
        check_exact(result, "wrapper_apply_meta_live_runtime_apply_true", meta.get("live_runtime_apply"), True)
        check_exact(result, "wrapper_apply_meta_live_wrapper_true", meta.get("live_wrapper"), True)
        check_exact(result, "wrapper_apply_meta_crab_approved_false", meta.get("crab_approved"), False)
    if isinstance(pre_apply, dict):
        check_exact(result, "pre_apply_boundary_validation_status_pass", pre_apply.get("status"), "pass")
    if isinstance(post_apply, dict):
        check_exact(result, "post_apply_validation_status_pass", post_apply.get("status"), "pass")
    if isinstance(non_secret, dict):
        check_exact(result, "non_secret_evidence_validation_status_pass", non_secret.get("status"), "pass")
    if not isinstance(actions, list):
        result["violations"].append("apply_actions_not_array")
        result["status"] = "fail"
    if not isinstance(handoff, dict):
        result["violations"].append("rollback_handoff_not_object")
        result["status"] = "fail"

    if result["status"] != "pass":
        return result, None

    target_instance_label = handoff.get("target_instance_label")
    execution_label = handoff.get("execution_label")
    if not isinstance(target_instance_label, str) or not target_instance_label.strip():
        result["violations"].append("apply_target_instance_label_missing")
        result["status"] = "fail"
    if not isinstance(execution_label, str) or not execution_label.strip():
        result["violations"].append("apply_execution_label_missing")
        result["status"] = "fail"

    if result["status"] != "pass":
        return result, None

    return result, {
        "run_dir": run_dir,
        "report": report,
        "meta": meta,
        "actions": actions,
        "handoff": handoff,
        "input_refs": input_refs,
        "target_instance_label": target_instance_label,
        "execution_label": execution_label,
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
    elif isinstance(value, str):
        if secret_value_pattern.search(value) or bearer_pattern.search(value) or private_key_pattern.search(value):
            violations.append(prefix or "<root>")
    return violations


def validate_argv(value: Any, name: str, result: dict[str, Any]) -> list[str]:
    if not isinstance(value, list) or not value:
        result["violations"].append(f"{name}_not_non_empty_array")
        result["status"] = "fail"
        return []
    argv: list[str] = []
    for index, item in enumerate(value):
        if not isinstance(item, str) or item == "":
            result["violations"].append(f"{name}_{index}_not_non_empty_string")
            result["status"] = "fail"
        else:
            argv.append(item)
    if len(argv) >= 2:
        exe = Path(argv[0]).name.lower()
        flag = argv[1].lower()
        if (exe, flag) in forbidden_shell_wrappers:
            result["violations"].append(f"{name}_forbidden_shell_wrapper")
            result["status"] = "fail"
    return argv


def validate_declaration_path(raw: str, result: dict[str, Any]) -> Path | None:
    check = {
        "path": raw,
        "absolute": False,
        "exists": False,
        "file": False,
        "outside_repo": False,
        "status": "pass",
        "violations": [],
    }
    path = Path(raw)
    if not path.is_absolute():
        check["violations"].append("declaration_file_not_absolute")
    else:
        check["absolute"] = True
    resolved = path.resolve(strict=False)
    check["outside_repo"] = not path_is_inside_repo(resolved)
    if path_is_inside_repo(resolved):
        check["violations"].append("declaration_file_inside_repo")
    check["exists"] = resolved.exists()
    check["file"] = resolved.is_file()
    if not resolved.exists():
        check["violations"].append("declaration_file_missing")
    elif not resolved.is_file():
        check["violations"].append("declaration_file_not_file")
    if check["violations"]:
        check["status"] = "fail"
        result["status"] = "fail"
        result["violations"].extend(check["violations"])
        result["path_validation"] = check
        return None
    result["path_validation"] = check
    return resolved


def validate_working_directory(value: Any, result: dict[str, Any]) -> Path | None:
    check = {
        "path": value,
        "absolute": False,
        "exists": False,
        "directory": False,
        "outside_repo": False,
        "status": "pass",
        "violations": [],
    }
    if not isinstance(value, str) or not value.strip():
        check["violations"].append("working_directory_empty")
    else:
        path = Path(value)
        check["absolute"] = path.is_absolute()
        if not path.is_absolute():
            check["violations"].append("working_directory_not_absolute")
        resolved = path.resolve(strict=False)
        check["outside_repo"] = not path_is_inside_repo(resolved)
        if path_is_inside_repo(resolved):
            check["violations"].append("working_directory_inside_repo")
        check["exists"] = resolved.exists()
        check["directory"] = resolved.is_dir()
        if not resolved.exists():
            check["violations"].append("working_directory_missing")
        elif not resolved.is_dir():
            check["violations"].append("working_directory_not_directory")
    if check["violations"]:
        check["status"] = "fail"
        result["violations"].extend(check["violations"])
        result["status"] = "fail"
    result["working_directory_validation"] = check
    if check["status"] == "pass":
        return Path(str(value)).resolve(strict=False)
    return None


def validate_declaration(raw: str) -> tuple[dict[str, Any], dict[str, Any] | None]:
    result: dict[str, Any] = {
        "status": "pass",
        "files": {},
        "checks": {},
        "path_validation": {},
        "working_directory_validation": {},
        "forbidden_key_paths": [],
        "forbidden_value_paths": [],
        "violations": [],
    }
    path = validate_declaration_path(raw, result)
    if path is None:
        return result, None
    payload = require_json(path, result, "rollout_declaration")
    if not isinstance(payload, dict):
        result["violations"].append("rollout_declaration_not_object")
        result["status"] = "fail"
        return result, None

    extra_keys = sorted(set(payload) - allowed_declaration_keys)
    missing_keys = sorted(allowed_declaration_keys - set(payload))
    if extra_keys:
        result["violations"].append("rollout_declaration_additional_properties")
        result["extra_keys"] = extra_keys
        result["status"] = "fail"
    if missing_keys:
        result["violations"].append("rollout_declaration_missing_required")
        result["missing_keys"] = missing_keys
        result["status"] = "fail"

    result["forbidden_key_paths"] = iter_secret_like_keys(payload)
    result["forbidden_value_paths"] = iter_secret_like_values(payload)
    if result["forbidden_key_paths"]:
        result["violations"].append("secret_like_key_in_declaration")
        result["status"] = "fail"
    if result["forbidden_value_paths"]:
        result["violations"].append("secret_like_value_in_declaration")
        result["status"] = "fail"

    check_exact(result, "declaration_kind_first_real_rollout", payload.get("declaration_kind"), "first-real-rollout")
    for key in ("target_instance_label", "execution_label"):
        if not isinstance(payload.get(key), str) or not payload.get(key, "").strip():
            result["violations"].append(f"{key}_empty")
            result["status"] = "fail"
    check_exact(result, "environment_mode_inherit", payload.get("environment_mode"), "inherit")
    working_directory = validate_working_directory(payload.get("working_directory"), result)
    launch_argv = validate_argv(payload.get("launch_argv"), "launch_argv", result)
    healthcheck_argv = validate_argv(payload.get("healthcheck_argv"), "healthcheck_argv", result)

    if result["status"] != "pass":
        return result, None

    sanitized = {
        "declaration_kind": payload["declaration_kind"],
        "target_instance_label": payload["target_instance_label"],
        "execution_label": payload["execution_label"],
        "working_directory": payload["working_directory"],
        "launch_argv": list(payload["launch_argv"]),
        "healthcheck_argv": list(payload["healthcheck_argv"]),
        "environment_mode": payload["environment_mode"],
    }
    return result, {
        "path": path,
        "payload": payload,
        "sanitized": sanitized,
        "working_directory": working_directory,
        "launch_argv": launch_argv,
        "healthcheck_argv": healthcheck_argv,
        "target_instance_label": payload["target_instance_label"],
        "execution_label": payload["execution_label"],
    }


def validate_identity_binding(apply_data: dict[str, Any] | None, declaration_data: dict[str, Any] | None) -> dict[str, Any]:
    result: dict[str, Any] = {"status": "pass", "checks": {}, "violations": []}
    if apply_data is None:
        result["status"] = "fail"
        result["violations"].append("apply_run_not_available")
        return result
    if declaration_data is None:
        result["status"] = "fail"
        result["violations"].append("rollout_declaration_not_available")
        return result
    check_exact(
        result,
        "target_instance_label_matches_apply",
        declaration_data.get("target_instance_label"),
        apply_data.get("target_instance_label"),
    )
    check_exact(
        result,
        "execution_label_matches_apply",
        declaration_data.get("execution_label"),
        apply_data.get("execution_label"),
    )
    return result


def allowed_surface_validation() -> dict[str, Any]:
    return {
        "status": "pass",
        "crab_approved_surface": "first-real-rollout-only",
        "bounded_live_runtime_apply_direct": False,
        "execution_owner_direct": False,
        "secret_session_direct": False,
        "material_resolution_direct": False,
        "orchestration_framework": False,
        "retries": False,
        "supervisors": False,
        "schedulers": False,
    }


def meta_payload(run_id: str) -> dict[str, Any]:
    return {
        "surface_kind": "crab-approved-live-rollout",
        "run_id": run_id,
        "canonical_run_dir": canonical_run_dir(run_id),
        "crab_approved": True,
        "approved_surface": "first-real-rollout",
        "live_runtime_apply": False,
        "rollout_orchestration": False,
        "deploy_framework": False,
        "approval_granting": False,
        "rollback_execution": False,
        "created_at": now_utc(),
    }


def input_validation_report(
    apply_result: dict[str, Any],
    declaration_result: dict[str, Any],
    identity_result: dict[str, Any],
) -> dict[str, Any]:
    status = "pass" if all(
        item["status"] == "pass" for item in (apply_result, declaration_result, identity_result)
    ) else "fail"
    return {
        "status": status,
        "apply_run_validation": apply_result["status"],
        "rollout_declaration_validation": declaration_result["status"],
        "identity_binding_validation": identity_result["status"],
        "violations": sorted(
            set(
                list(apply_result.get("violations", []))
                + list(declaration_result.get("violations", []))
                + list(identity_result.get("violations", []))
            )
        ),
    }


def delegate_ref(delegate_run_id: str, delegate_status: str) -> dict[str, Any]:
    return {
        "delegate_kind": "first-real-rollout",
        "delegate_run_id": delegate_run_id,
        "delegate_run_dir": delegate_canonical_run_dir(delegate_run_id),
        "delegate_status": delegate_status,
    }


def validate_delegate_run(delegate_run_id: str, delegate_return_code: int | None) -> dict[str, Any]:
    run_dir = apply_runs_root / delegate_run_id
    result: dict[str, Any] = {
        "status": "pass",
        "delegate_run_id": delegate_run_id,
        "delegate_run_dir": delegate_canonical_run_dir(delegate_run_id),
        "delegate_return_code": delegate_return_code,
        "delegate_run_exists": run_dir.is_dir(),
        "delegate_run_green": False,
        "delegate_kind_first_real_rollout": False,
        "delegate_evidence_present": False,
        "violations": [],
    }
    required_files = [
        "rollout_meta.json",
        "rollout_report.json",
        "rollout_declaration_snapshot.json",
        "rollout_launch_record.json",
        "rollout_healthcheck_record.json",
        "rollout_input_refs.json",
        "checks/apply_run_validation.json",
        "checks/rollout_declaration_validation.json",
        "checks/identity_binding_validation.json",
        "checks/launch_validation.json",
        "checks/healthcheck_validation.json",
        "checks/non_secret_evidence_validation.json",
        "exit_code",
    ]
    missing = [name for name in required_files if not (run_dir / name).is_file()]
    result["missing_files"] = missing
    result["delegate_evidence_present"] = not missing
    if not result["delegate_run_exists"]:
        result["violations"].append("delegate_run_missing")
    if missing:
        result["violations"].append("delegate_evidence_missing")

    meta, meta_error = load_json_file(run_dir / "rollout_meta.json")
    report, report_error = load_json_file(run_dir / "rollout_report.json")
    if meta_error is not None:
        result["violations"].append("delegate_meta_unreadable")
    elif isinstance(meta, dict) and meta.get("surface_kind") == "first-real-rollout":
        result["delegate_kind_first_real_rollout"] = True
    else:
        result["violations"].append("delegate_kind_not_first_real_rollout")

    if report_error is not None:
        result["violations"].append("delegate_report_unreadable")
    elif isinstance(report, dict) and report.get("overall_status") == "pass":
        result["delegate_run_green"] = True
    else:
        result["violations"].append("delegate_run_not_green")

    if delegate_return_code != 0:
        result["violations"].append("delegate_return_code_nonzero")

    if result["violations"]:
        result["status"] = "fail"
    return result


def content_markers_from_apply_actions(apply_data: dict[str, Any] | None) -> list[str]:
    if apply_data is None or not isinstance(apply_data.get("actions"), list):
        return []
    markers: list[str] = []
    candidate_paths: list[Path] = []
    for action in apply_data["actions"]:
        if not isinstance(action, dict):
            continue
        for key in ("source_path", "destination_path"):
            value = action.get(key)
            if isinstance(value, str) and Path(value).is_absolute():
                path = Path(value)
                if path.is_file():
                    candidate_paths.append(path)
                elif path.is_dir():
                    candidate_paths.extend(sorted(item for item in path.rglob("*") if item.is_file()))
    for path in candidate_paths:
        try:
            content = path.read_text(encoding="utf-8-sig").strip()
        except (OSError, UnicodeError):
            continue
        if len(content) >= 8:
            markers.append(content)
    return markers


def validate_non_secret_evidence(payloads: list[Any], apply_data: dict[str, Any] | None) -> dict[str, Any]:
    result: dict[str, Any] = {
        "status": "pass",
        "raw_secret_like_key_names": False,
        "raw_secret_like_inline_values": False,
        "copied_source_contents": False,
        "copied_live_root_contents": False,
        "violations": [],
        "forbidden_key_paths": [],
        "forbidden_value_paths": [],
        "inlined_material_content_paths": [],
    }
    combined = {f"payload_{index}": payload for index, payload in enumerate(payloads)}
    result["forbidden_key_paths"] = iter_secret_like_keys(combined)
    result["forbidden_value_paths"] = iter_secret_like_values(combined)
    combined_text = json.dumps(combined, sort_keys=True)
    for marker in content_markers_from_apply_actions(apply_data):
        if marker in combined_text:
            result["inlined_material_content_paths"].append("[REDACTED_MATERIAL_CONTENT]")

    if result["forbidden_key_paths"]:
        result["raw_secret_like_key_names"] = True
        result["violations"].append("secret_like_key_in_evidence")
    if result["forbidden_value_paths"]:
        result["raw_secret_like_inline_values"] = True
        result["violations"].append("secret_like_value_in_evidence")
    if result["inlined_material_content_paths"]:
        result["copied_source_contents"] = True
        result["copied_live_root_contents"] = True
        result["violations"].append("material_content_inlined")
    if result["violations"]:
        result["status"] = "fail"
    return result


def invocation_record(
    apply_data: dict[str, Any] | None,
    declaration_data: dict[str, Any] | None,
    apply_run_dir_ref: str,
    declaration_file: str,
    delegate_run_id: str,
) -> dict[str, Any]:
    return {
        "record_kind": "crab-approved-live-rollout-invocation",
        "crab_approved": True,
        "approved_surface": "first-real-rollout",
        "target_instance_label": str((declaration_data or apply_data or {}).get("target_instance_label", "")),
        "execution_label": str((declaration_data or apply_data or {}).get("execution_label", "")),
        "apply_run_dir": apply_run_dir_ref,
        "rollout_declaration_file": declaration_file,
        "delegate_run_dir": delegate_canonical_run_dir(delegate_run_id),
    }


def report_payload(
    input_result: dict[str, Any],
    surface_result: dict[str, Any],
    delegate_result: dict[str, Any],
    non_secret_result: dict[str, Any],
) -> dict[str, Any]:
    statuses = {
        "input_validation": input_result["status"],
        "allowed_surface_validation": surface_result["status"],
        "delegate_run_validation": delegate_result["status"],
        "non_secret_evidence_validation": non_secret_result["status"],
    }
    overall_status = "pass" if all(value == "pass" for value in statuses.values()) else "fail"
    return {
        "overall_status": overall_status,
        **statuses,
        "crab_approved": True,
        "approved_surface": "first-real-rollout",
        "rollout_orchestration": False,
    }


def main() -> int:
    parse_args()
    run_id = str(values["run_id"])
    validate_run_id(run_id)

    run_dir = runs_root / run_id
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)

    apply_run_dir_value = str(values["apply_run_dir"])
    declaration_file_value = str(values["rollout_declaration_file"])
    delegate_run_id = f"{run_id}-delegate"

    meta = meta_payload(run_id)
    write_json(run_dir / "crab_live_rollout_meta.json", meta)

    apply_result, apply_data = validate_apply_run(apply_run_dir_value, run_dir)
    declaration_result, declaration_data = validate_declaration(declaration_file_value)
    identity_result = validate_identity_binding(apply_data, declaration_data)
    input_result = input_validation_report(apply_result, declaration_result, identity_result)
    surface_result = allowed_surface_validation()

    delegate_return_code: int | None = None
    if input_result["status"] == "pass" and surface_result["status"] == "pass":
        completed = subprocess.run(
            [
                "bash",
                delegate_script,
                "--apply-run-dir",
                repo_rel(apply_data["run_dir"]) if apply_data is not None else apply_run_dir_value,
                "--rollout-declaration-file",
                declaration_file_value,
                "--run-id",
                delegate_run_id,
            ],
            cwd=str(repo_root),
            env=None,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        delegate_return_code = int(completed.returncode)

    delegate_result = validate_delegate_run(delegate_run_id, delegate_return_code)
    delegate_status = "pass" if delegate_result["status"] == "pass" else "fail"
    delegate_ref_payload = delegate_ref(delegate_run_id, delegate_status)
    invocation = invocation_record(
        apply_data,
        declaration_data,
        repo_rel(apply_data["run_dir"]) if apply_data is not None else apply_run_dir_value,
        declaration_file_value,
        delegate_run_id,
    )

    pre_report_payloads = [
        meta,
        input_result,
        surface_result,
        delegate_ref_payload,
        invocation,
        delegate_result,
    ]
    non_secret_result = validate_non_secret_evidence(pre_report_payloads, apply_data)
    report = report_payload(input_result, surface_result, delegate_result, non_secret_result)
    exit_code = 0 if report["overall_status"] == "pass" else 1

    write_json(run_dir / "invocation_record.json", invocation)
    write_json(run_dir / "delegate_rollout_ref.json", delegate_ref_payload)
    write_json(checks_dir / "input_validation.json", input_result)
    write_json(checks_dir / "allowed_surface_validation.json", surface_result)
    write_json(checks_dir / "delegate_run_validation.json", delegate_result)
    write_json(checks_dir / "non_secret_evidence_validation.json", non_secret_result)
    write_json(run_dir / "crab_live_rollout_report.json", report)
    write_text(run_dir / "exit_code", f"{exit_code}\n")

    if exit_code == 0:
        print(f"PASS Crab-approved live rollout: {run_id}")
    else:
        print(f"FAIL Crab-approved live rollout: {run_id}", file=sys.stderr)
    return exit_code


try:
    raise SystemExit(main())
except CrabApprovedLiveRolloutError as exc:
    print(f"FAIL {exc}", file=sys.stderr)
    usage()
    raise SystemExit(1)
except Exception as exc:
    print(f"FAIL unexpected Crab-approved live rollout error: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
