#!/usr/bin/env bash
set -u
set -o pipefail

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="${FIRST_REAL_ROLLOUT_PYTHON_BIN:-python}"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="${FIRST_REAL_ROLLOUT_PYTHON_BIN:-python3}"
else
  echo "FAIL python runtime not found; set FIRST_REAL_ROLLOUT_PYTHON_BIN or install python/python3" >&2
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


class FirstRealRolloutError(Exception):
    pass


repo_root = Path(sys.argv[1]).resolve(strict=True)
args = sys.argv[2:]
surface_root = repo_root / "operations" / "harness-openclaw-live-wrapper"
runs_root = surface_root / "runs"

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
    raise FirstRealRolloutError(message)


def usage() -> None:
    print(
        "usage: run_first_real_rollout.sh "
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
    return f"operations/harness-openclaw-live-wrapper/runs/{run_id}"


def output_ref(run_id: str, filename: str) -> str:
    return f"{canonical_run_dir(run_id)}/{filename}"


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


def repo_path_from_ref(value: Any) -> Path | None:
    if not isinstance(value, str) or not value.strip():
        return None
    candidate = Path(value)
    return candidate if candidate.is_absolute() else repo_root / candidate


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
        "absolute_or_repo_relative": False,
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
    result["absolute_or_repo_relative"] = True
    resolved = path.resolve(strict=False)

    try:
        rel = resolved.relative_to(runs_root.resolve(strict=True))
        result["under_approved_root"] = True
        result["direct_child"] = len(rel.parts) == 1
    except (OSError, ValueError):
        result["violations"].append("apply_run_dir_not_under_approved_root")

    if not result["direct_child"]:
        if "apply_run_dir_not_under_approved_root" not in result["violations"]:
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
        "execution_owner": True,
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
        check_exact(result, "wrapper_apply_meta_execution_owner_true", meta.get("execution_owner"), True)
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

    target_instance_label = handoff.get("target_instance_label") if isinstance(handoff, dict) else None
    execution_label = handoff.get("execution_label") if isinstance(handoff, dict) else None
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


def key_is_secret_like(key: str, value: Any = None) -> bool:
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
            if key_is_secret_like(key_text, item):
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
    result["path_validation"] = {
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
        result["path_validation"]["violations"].append("declaration_file_not_absolute")
    else:
        result["path_validation"]["absolute"] = True
    resolved = path.resolve(strict=False)
    result["path_validation"]["outside_repo"] = not path_is_inside_repo(resolved)
    if path_is_inside_repo(resolved):
        result["path_validation"]["violations"].append("declaration_file_inside_repo")
    result["path_validation"]["exists"] = resolved.exists()
    result["path_validation"]["file"] = resolved.is_file()
    if not resolved.exists():
        result["path_validation"]["violations"].append("declaration_file_missing")
    elif not resolved.is_file():
        result["path_validation"]["violations"].append("declaration_file_not_file")
    if result["path_validation"]["violations"]:
        result["path_validation"]["status"] = "fail"
        result["status"] = "fail"
        result["violations"].extend(result["path_validation"]["violations"])
        return None
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


def sanitize_declaration(payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "declaration_kind": payload["declaration_kind"],
        "target_instance_label": payload["target_instance_label"],
        "execution_label": payload["execution_label"],
        "working_directory": payload["working_directory"],
        "launch_argv": list(payload["launch_argv"]),
        "healthcheck_argv": list(payload["healthcheck_argv"]),
        "environment_mode": payload["environment_mode"],
    }


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

    sanitized = sanitize_declaration(payload)
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
    result: dict[str, Any] = {
        "status": "pass",
        "checks": {},
        "violations": [],
    }
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


def rollout_meta(run_id: str) -> dict[str, Any]:
    return {
        "surface_kind": "first-real-rollout",
        "run_id": run_id,
        "canonical_run_dir": canonical_run_dir(run_id),
        "execution_owner": True,
        "live_wrapper": True,
        "live_runtime_apply": True,
        "first_real_rollout": True,
        "crab_approved": False,
        "approval_granting": False,
        "rollback_execution": False,
        "rollout_orchestration": False,
        "created_at": now_utc(),
    }


def skipped_launch_record(declaration_data: dict[str, Any] | None) -> dict[str, Any]:
    return {
        "record_kind": "rollout-launch-record",
        "target_instance_label": str((declaration_data or {}).get("target_instance_label", "")),
        "execution_label": str((declaration_data or {}).get("execution_label", "")),
        "working_directory": str((declaration_data or {}).get("working_directory", "")),
        "launch_argv": list((declaration_data or {}).get("launch_argv", [])),
        "launch_status": "failed",
        "pid": 0,
        "exit_code": 1,
        "started_at": None,
    }


def launch_runtime(declaration_data: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    started_at = now_utc()
    record = {
        "record_kind": "rollout-launch-record",
        "target_instance_label": declaration_data["target_instance_label"],
        "execution_label": declaration_data["execution_label"],
        "working_directory": str(declaration_data["working_directory"]),
        "launch_argv": declaration_data["launch_argv"],
        "launch_status": "failed",
        "pid": 0,
        "exit_code": 1,
        "started_at": started_at,
    }
    result: dict[str, Any] = {
        "status": "pass",
        "argv_array_only": True,
        "inherited_environment": True,
        "forbidden_shell_wrapper": False,
        "violations": [],
    }
    try:
        process = subprocess.Popen(
            declaration_data["launch_argv"],
            cwd=str(declaration_data["working_directory"]),
            env=None,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        record["pid"] = int(process.pid)
        try:
            exit_code = process.wait(timeout=0.25)
            record["launch_status"] = "exited"
            record["exit_code"] = int(exit_code)
            if exit_code != 0:
                result["status"] = "fail"
                result["violations"].append("launch_exited_nonzero")
        except subprocess.TimeoutExpired:
            record["launch_status"] = "started"
            record["exit_code"] = 0
    except (OSError, ValueError) as exc:
        record["launch_status"] = "failed"
        record["exit_code"] = 1
        result["status"] = "fail"
        result["violations"].append("launch_start_failed")
        result["error"] = str(exc)

    return result, record


def skipped_healthcheck_record(declaration_data: dict[str, Any] | None) -> dict[str, Any]:
    return {
        "record_kind": "rollout-healthcheck-record",
        "target_instance_label": str((declaration_data or {}).get("target_instance_label", "")),
        "execution_label": str((declaration_data or {}).get("execution_label", "")),
        "healthcheck_argv": list((declaration_data or {}).get("healthcheck_argv", [])),
        "healthcheck_status": "fail",
        "exit_code": 1,
        "started_at": None,
        "finished_at": None,
        "stdout_byte_count": 0,
        "stderr_byte_count": 0,
        "stdout_truncated": False,
        "stderr_truncated": False,
    }


def run_healthcheck(declaration_data: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    started_at = now_utc()
    result: dict[str, Any] = {
        "status": "pass",
        "argv_array_only": True,
        "inherited_environment": True,
        "forbidden_shell_wrapper": False,
        "violations": [],
    }
    record = {
        "record_kind": "rollout-healthcheck-record",
        "target_instance_label": declaration_data["target_instance_label"],
        "execution_label": declaration_data["execution_label"],
        "healthcheck_argv": declaration_data["healthcheck_argv"],
        "healthcheck_status": "fail",
        "exit_code": 1,
        "started_at": started_at,
        "finished_at": None,
        "stdout_byte_count": 0,
        "stderr_byte_count": 0,
        "stdout_truncated": False,
        "stderr_truncated": False,
    }
    try:
        completed = subprocess.run(
            declaration_data["healthcheck_argv"],
            cwd=str(declaration_data["working_directory"]),
            env=None,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=False,
            timeout=10,
            check=False,
        )
        stdout = completed.stdout or b""
        stderr = completed.stderr or b""
        record["finished_at"] = now_utc()
        record["exit_code"] = int(completed.returncode)
        record["stdout_byte_count"] = len(stdout)
        record["stderr_byte_count"] = len(stderr)
        record["stdout_truncated"] = len(stdout) > 4096
        record["stderr_truncated"] = len(stderr) > 4096
        if completed.returncode == 0:
            record["healthcheck_status"] = "pass"
        else:
            result["status"] = "fail"
            result["violations"].append("healthcheck_exited_nonzero")
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        record["finished_at"] = now_utc()
        result["status"] = "fail"
        result["violations"].append("healthcheck_failed")
        result["error"] = str(exc)
    return result, record


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
        result["violations"].append("secret_like_key_in_evidence")
    if result["forbidden_value_paths"]:
        result["violations"].append("secret_like_value_in_evidence")
    if result["inlined_material_content_paths"]:
        result["violations"].append("material_content_inlined")
    if result["violations"]:
        result["status"] = "fail"
    return result


def rollout_report(
    apply_result: dict[str, Any],
    declaration_result: dict[str, Any],
    identity_result: dict[str, Any],
    launch_result: dict[str, Any],
    healthcheck_result: dict[str, Any],
    non_secret_result: dict[str, Any],
) -> dict[str, Any]:
    statuses = {
        "apply_run_validation": apply_result["status"],
        "rollout_declaration_validation": declaration_result["status"],
        "identity_binding_validation": identity_result["status"],
        "launch_validation": launch_result["status"],
        "healthcheck_validation": healthcheck_result["status"],
        "non_secret_evidence_validation": non_secret_result["status"],
    }
    overall_status = "pass" if all(value == "pass" for value in statuses.values()) else "fail"
    return {
        "overall_status": overall_status,
        **statuses,
        "execution_owner": True,
        "live_wrapper": True,
        "live_runtime_apply": True,
        "first_real_rollout": True,
        "crab_approved": False,
        "rollout_orchestration": False,
    }


def main() -> int:
    parse_args()
    run_id = str(values["run_id"])
    validate_run_id(run_id)

    run_dir = runs_root / run_id
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)

    meta = rollout_meta(run_id)
    write_json(run_dir / "rollout_meta.json", meta)

    apply_result, apply_data = validate_apply_run(str(values["apply_run_dir"]), run_dir)
    declaration_result, declaration_data = validate_declaration(str(values["rollout_declaration_file"]))
    identity_result = validate_identity_binding(apply_data, declaration_data)

    can_launch = (
        apply_result["status"] == "pass"
        and declaration_result["status"] == "pass"
        and identity_result["status"] == "pass"
        and declaration_data is not None
    )
    if can_launch:
        launch_result, launch_record = launch_runtime(declaration_data)
    else:
        launch_result = {"status": "fail", "argv_array_only": True, "inherited_environment": True, "violations": ["launch_prerequisites_failed"]}
        launch_record = skipped_launch_record(declaration_data)

    can_healthcheck = can_launch and launch_result["status"] == "pass" and declaration_data is not None
    if can_healthcheck:
        healthcheck_result, healthcheck_record = run_healthcheck(declaration_data)
    else:
        healthcheck_result = {"status": "fail", "argv_array_only": True, "inherited_environment": True, "violations": ["healthcheck_prerequisites_failed"]}
        healthcheck_record = skipped_healthcheck_record(declaration_data)

    snapshot = declaration_data["sanitized"] if declaration_data is not None else {}
    input_refs_payload = {
        "apply_run_dir": repo_rel(apply_data["run_dir"]) if apply_data is not None else str(values["apply_run_dir"]),
        "rollout_declaration_file": str(values["rollout_declaration_file"]),
        "rollout_declaration_snapshot": output_ref(run_id, "rollout_declaration_snapshot.json"),
        "rollout_launch_record": output_ref(run_id, "rollout_launch_record.json"),
        "rollout_healthcheck_record": output_ref(run_id, "rollout_healthcheck_record.json"),
        "contains_source_file_contents": False,
        "contains_material_file_contents": False,
    }
    non_secret_payloads = [meta, snapshot, launch_record, healthcheck_record, input_refs_payload]
    non_secret_result = validate_non_secret_evidence(non_secret_payloads, apply_data)
    report = rollout_report(
        apply_result,
        declaration_result,
        identity_result,
        launch_result,
        healthcheck_result,
        non_secret_result,
    )
    exit_code = 0 if report["overall_status"] == "pass" else 1

    write_json(run_dir / "rollout_declaration_snapshot.json", snapshot)
    write_json(run_dir / "rollout_launch_record.json", launch_record)
    write_json(run_dir / "rollout_healthcheck_record.json", healthcheck_record)
    write_json(run_dir / "rollout_input_refs.json", input_refs_payload)
    write_json(checks_dir / "apply_run_validation.json", apply_result)
    write_json(checks_dir / "rollout_declaration_validation.json", declaration_result)
    write_json(checks_dir / "identity_binding_validation.json", identity_result)
    write_json(checks_dir / "launch_validation.json", launch_result)
    write_json(checks_dir / "healthcheck_validation.json", healthcheck_result)
    write_json(checks_dir / "non_secret_evidence_validation.json", non_secret_result)
    write_json(run_dir / "rollout_report.json", report)
    write_text(run_dir / "exit_code", f"{exit_code}\n")

    if exit_code == 0:
        print(f"PASS first real rollout: {run_id}")
    else:
        print(f"FAIL first real rollout: {run_id}", file=sys.stderr)
    return exit_code


try:
    raise SystemExit(main())
except FirstRealRolloutError as exc:
    print(f"FAIL {exc}", file=sys.stderr)
    usage()
    raise SystemExit(1)
except Exception as exc:
    print(f"FAIL unexpected first real rollout error: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
