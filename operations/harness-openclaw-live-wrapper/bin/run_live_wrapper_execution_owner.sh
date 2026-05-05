#!/usr/bin/env bash
set -u
set -o pipefail

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_WRAPPER_EXECUTION_OWNER_PYTHON_BIN:-python}"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_WRAPPER_EXECUTION_OWNER_PYTHON_BIN:-python3}"
else
  echo "FAIL python runtime not found; set LIVE_WRAPPER_EXECUTION_OWNER_PYTHON_BIN or install python/python3" >&2
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


class WrapperExecutionOwnerError(Exception):
    pass


repo_root = Path(sys.argv[1]).resolve(strict=True)
args = sys.argv[2:]
surface_root = repo_root / "operations" / "harness-openclaw-live-wrapper"
runs_root = surface_root / "runs"
secret_session_runs_root = repo_root / "operations" / "harness-openclaw-live-secret-session" / "runs"

allowed_args = {
    "--secret-session-run-dir": "secret_session_run_dir",
    "--run-id": "run_id",
}
values: dict[str, str | None] = {value: None for value in allowed_args.values()}

secret_value_pattern = re.compile(
    r"(?i)\b(?:secret|token|password|api[_-]?key|apikey|oauth|credential|private[_-]?key|session[_-]?cookie)\b\s*[:=]\s*(?!\[REDACTED\])\S+"
)
bearer_pattern = re.compile(r"(?i)authorization\s*:\s*bearer\s+(?!\[REDACTED\])[^ \t\r\n]+")
private_key_pattern = re.compile("-----BEGIN " + r"[A-Z ]*PRIVATE KEY-----")
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
allowed_structural_secret_keys = {
    "real_secret_loading",
    "secret_session_run_dir",
    "wrapper_secret_session_bundle",
}


def fail(message: str) -> None:
    raise WrapperExecutionOwnerError(message)


def usage() -> None:
    print(
        "usage: run_live_wrapper_execution_owner.sh "
        "--secret-session-run-dir <REPO_LOCAL_RUN_DIR> "
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
    result["checks"][name] = {
        "expected": expected,
        "actual": actual,
        "status": "pass" if passed else "fail",
    }
    if not passed:
        result["violations"].append(name)
        result["status"] = "fail"


def validate_secret_session(raw: str) -> tuple[dict[str, Any], dict[str, Any] | None]:
    result: dict[str, Any] = {
        "status": "pass",
        "execution_owner": True,
        "live_wrapper": True,
        "live_runtime_apply": False,
        "root_validation": {},
        "files": {},
        "checks": {},
        "violations": [],
    }
    run_dir, root_result = resolve_repo_local_run_dir(raw, secret_session_runs_root, "secret_session")
    result["root_validation"] = root_result
    if run_dir is None:
        result["status"] = "fail"
        result["violations"].extend(root_result["violations"])
        return result, None

    report = require_json(run_dir / "secret_session_report.json", result, "secret_session_report")
    meta = require_json(run_dir / "secret_session_meta.json", result, "secret_session_meta")
    manifest = require_json(run_dir / "loaded_material_manifest.json", result, "loaded_material_manifest")
    observations = require_json(run_dir / "redacted_material_observations.json", result, "redacted_material_observations")
    bundle = require_json(run_dir / "wrapper_secret_session_bundle.json", result, "wrapper_secret_session_bundle")
    input_refs = require_json(run_dir / "input_refs.json", result, "input_refs")
    material_load = require_json(run_dir / "checks" / "material_load_validation.json", result, "material_load_validation")
    redaction = require_json(run_dir / "checks" / "redaction_validation.json", result, "redaction_validation")
    non_secret = require_json(run_dir / "checks" / "non_secret_bundle_validation.json", result, "non_secret_bundle_validation")

    if isinstance(report, dict):
        check_exact(result, "secret_session_report_overall_status_pass", report.get("overall_status"), "pass")
    if isinstance(meta, dict):
        check_exact(result, "secret_session_meta_surface_kind", meta.get("surface_kind"), "live-secret-session")
        check_exact(result, "secret_session_meta_secret_session_only", meta.get("secret_session_only"), True)
        check_exact(result, "secret_session_meta_live_runtime_apply_false", meta.get("live_runtime_apply"), False)
        check_exact(result, "secret_session_meta_live_wrapper_false", meta.get("live_wrapper"), False)
        check_exact(result, "secret_session_meta_crab_approved_false", meta.get("crab_approved"), False)
        check_exact(result, "secret_session_meta_real_secret_loading_true", meta.get("real_secret_loading"), True)
    if isinstance(material_load, dict):
        check_exact(result, "material_load_validation_status_pass", material_load.get("status"), "pass")
    if isinstance(redaction, dict):
        check_exact(result, "redaction_validation_status_pass", redaction.get("status"), "pass")
    if isinstance(non_secret, dict):
        check_exact(result, "non_secret_bundle_validation_status_pass", non_secret.get("status"), "pass")
    if isinstance(manifest, dict):
        check_exact(result, "loaded_material_manifest_kind", manifest.get("manifest_kind"), "live-loaded-material-manifest")
    if isinstance(bundle, dict):
        check_exact(result, "wrapper_secret_session_bundle_kind", bundle.get("bundle_kind"), "live-wrapper-secret-session-bundle")
        check_exact(result, "wrapper_secret_session_bundle_live_runtime_apply_false", bundle.get("live_runtime_apply"), False)
        check_exact(result, "wrapper_secret_session_bundle_live_wrapper_false", bundle.get("live_wrapper"), False)
        check_exact(result, "wrapper_secret_session_bundle_crab_approved_false", bundle.get("crab_approved"), False)

    if result["status"] != "pass":
        return result, None

    return result, {
        "run_dir": run_dir,
        "report": report,
        "meta": meta,
        "manifest": manifest,
        "observations": observations,
        "bundle": bundle,
        "input_refs": input_refs,
        "material_load": material_load,
        "redaction": redaction,
        "non_secret": non_secret,
    }


def execution_owner_boundary_validation() -> dict[str, Any]:
    flags = {
        "execution_owner": True,
        "live_wrapper": True,
        "live_runtime_apply": False,
        "target_mutation": False,
        "approval_granting": False,
        "rollback_execution": False,
        "crab_approved": False,
        "no_new_raw_secret_loading": True,
        "no_raw_secret_persistence": True,
    }
    return {
        "status": "pass",
        "flags": flags,
        "violations": [],
    }


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


def observation_entries(observations: Any) -> list[Any]:
    if not isinstance(observations, dict):
        return []
    entries = observations.get("observations")
    return entries if isinstance(entries, list) else []


def validate_redacted_observations(secret_data: dict[str, Any] | None) -> dict[str, Any]:
    result: dict[str, Any] = {
        "status": "pass",
        "execution_owner": True,
        "live_wrapper": True,
        "live_runtime_apply": False,
        "observations_exist": False,
        "json_readable": False,
        "observation_count": 0,
        "violations": [],
        "unredacted_value_paths": [],
    }
    if secret_data is None:
        result["status"] = "fail"
        result["violations"].append("secret_session_not_available")
        return result

    run_dir = secret_data["run_dir"]
    observations_path = run_dir / "redacted_material_observations.json"
    result["path"] = repo_rel(observations_path)
    result["observations_exist"] = observations_path.is_file()
    observations, error = load_json_file(observations_path)
    result["json_readable"] = error is None
    if error is not None:
        result["status"] = "fail"
        result["violations"].append("redacted_observations_unreadable")
        result["error"] = error
        return result

    entries = observation_entries(observations)
    result["observation_count"] = len(entries)
    if not entries:
        result["violations"].append("redacted_observations_empty")
    result["unredacted_value_paths"] = iter_secret_like_values(observations)
    if result["unredacted_value_paths"]:
        result["violations"].append("unredacted_secret_like_value")
    if result["violations"]:
        result["status"] = "fail"
    return result


def key_is_secret_like(key: str, value: Any = None) -> bool:
    if key == "real_secret_loading":
        return value is not True
    if key in allowed_structural_secret_keys:
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


def collect_texts_from_payload(value: Any) -> list[str]:
    texts: list[str] = []
    if isinstance(value, dict):
        for item in value.values():
            texts.extend(collect_texts_from_payload(item))
    elif isinstance(value, list):
        for item in value:
            texts.extend(collect_texts_from_payload(item))
    elif isinstance(value, str):
        texts.append(value)
    return texts


def read_retained_contents(secret_data: dict[str, Any] | None) -> list[str]:
    if secret_data is None:
        return []
    input_refs = secret_data.get("input_refs")
    material_resolution = input_refs.get("material_resolution_run_dir") if isinstance(input_refs, dict) else None
    if not isinstance(material_resolution, str):
        return []
    material_dir = repo_root / material_resolution
    material_refs, error = load_json_file(material_dir / "input_refs.json")
    if error is not None or not isinstance(material_refs, dict):
        return []
    wrapper_input_refs_path = material_refs.get("wrapper_input_refs")
    if not isinstance(wrapper_input_refs_path, str):
        return []
    wrapper_refs, error = load_json_file(repo_root / wrapper_input_refs_path)
    if error is not None or not isinstance(wrapper_refs, dict):
        return []
    retained_dir_value = wrapper_refs.get("retained_evidence_dir")
    if not isinstance(retained_dir_value, str):
        return []
    retained_dir = repo_root / retained_dir_value
    if not retained_dir.is_dir():
        return []
    contents: list[str] = []
    for path in sorted(retained_dir.rglob("*")):
        if not path.is_file():
            continue
        try:
            contents.append(path.read_text(encoding="utf-8-sig").strip())
        except (OSError, UnicodeError):
            continue
    return [item for item in contents if len(item) >= 32]


def source_content_markers(secret_data: dict[str, Any] | None) -> list[str]:
    if secret_data is None:
        return []
    observations = secret_data.get("observations")
    markers: list[str] = []
    if isinstance(observations, dict):
        for text in collect_texts_from_payload(observations):
            if "[REDACTED]" in text and len(text) >= 16:
                markers.append(text)
    return markers


def contents_inlined(bundle_text: str, candidates: list[str]) -> list[str]:
    violations: list[str] = []
    for item in candidates:
        stripped = item.strip()
        if len(stripped) >= 16 and stripped in bundle_text:
            violations.append(stripped[:80])
    return violations


def validate_non_secret_bundle(payloads: list[dict[str, Any]], secret_data: dict[str, Any] | None) -> dict[str, Any]:
    result: dict[str, Any] = {
        "status": "pass",
        "execution_owner": True,
        "live_wrapper": True,
        "live_runtime_apply": False,
        "violations": [],
        "secret_like_key_paths": [],
        "secret_like_value_paths": [],
        "inlined_redacted_observation_paths": [],
        "inlined_source_content_paths": [],
        "inlined_retained_content_paths": [],
    }
    combined = {f"payload_{index}": payload for index, payload in enumerate(payloads)}
    result["secret_like_key_paths"] = iter_secret_like_keys(combined)
    result["secret_like_value_paths"] = iter_secret_like_values(combined)
    bundle_text = json.dumps(combined, sort_keys=True)
    result["inlined_redacted_observation_paths"] = contents_inlined(bundle_text, source_content_markers(secret_data))
    result["inlined_source_content_paths"] = []
    result["inlined_retained_content_paths"] = contents_inlined(bundle_text, read_retained_contents(secret_data))

    if result["secret_like_key_paths"]:
        result["violations"].append("secret_like_key_in_bundle")
    if result["secret_like_value_paths"]:
        result["violations"].append("secret_like_value_in_bundle")
    if result["inlined_redacted_observation_paths"]:
        result["violations"].append("redacted_observation_body_inlined")
    if result["inlined_source_content_paths"]:
        result["violations"].append("source_content_inlined")
    if result["inlined_retained_content_paths"]:
        result["violations"].append("retained_content_inlined")
    if result["violations"]:
        result["status"] = "fail"
    return result


def identity_from_secret_bundle(secret_data: dict[str, Any] | None) -> dict[str, str]:
    if secret_data is None:
        return {"target_instance_label": "", "execution_label": ""}
    bundle = secret_data.get("bundle")
    identity = bundle.get("target_identity", {}) if isinstance(bundle, dict) else {}
    return {
        "target_instance_label": str(identity.get("target_instance_label", "")),
        "execution_label": str(identity.get("execution_label", "")),
    }


def wrapper_execution_meta(run_id: str) -> dict[str, Any]:
    return {
        "surface_kind": "live-wrapper-execution-owner",
        "run_id": run_id,
        "canonical_run_dir": canonical_run_dir(run_id),
        "execution_owner": True,
        "live_wrapper": True,
        "live_runtime_apply": False,
        "crab_approved": False,
        "approval_granting": False,
        "rollback_execution": False,
        "real_secret_loading": True,
        "target_mutation": False,
        "new_raw_secret_loading": False,
        "broader_local_overlay_reading": False,
        "created_at": now_utc(),
    }


def wrapper_session_refs(run_id: str, secret_data: dict[str, Any] | None) -> dict[str, Any]:
    run_dir = secret_data["run_dir"] if secret_data else None
    identity = identity_from_secret_bundle(secret_data)
    return {
        "secret_session_run_dir": repo_rel(run_dir) if run_dir else str(values["secret_session_run_dir"]),
        "loaded_material_manifest": repo_rel(run_dir / "loaded_material_manifest.json") if run_dir else None,
        "redacted_material_observations": repo_rel(run_dir / "redacted_material_observations.json") if run_dir else None,
        "wrapper_secret_session_bundle": repo_rel(run_dir / "wrapper_secret_session_bundle.json") if run_dir else None,
        "target_instance_label": identity["target_instance_label"],
        "execution_label": identity["execution_label"],
        "contains_raw_contents": False,
        "contains_observation_body": False,
    }


def execution_owner_manifest(run_id: str, session_refs: dict[str, Any]) -> dict[str, Any]:
    return {
        "manifest_kind": "live-wrapper-execution-owner",
        "execution_owner": True,
        "live_wrapper": True,
        "live_runtime_apply": False,
        "crab_approved": False,
        "approval_granting": False,
        "rollback_execution": False,
        "real_secret_loading": True,
        "target_identity": {
            "target_instance_label": session_refs.get("target_instance_label", ""),
            "execution_label": session_refs.get("execution_label", ""),
        },
        "inputs": {
            "secret_session_run_dir": session_refs.get("secret_session_run_dir"),
            "loaded_material_manifest": session_refs.get("loaded_material_manifest"),
            "redacted_material_observations": session_refs.get("redacted_material_observations"),
            "wrapper_secret_session_bundle": session_refs.get("wrapper_secret_session_bundle"),
        },
        "wrapper_policy_flags": {
            "target_mutation": False,
            "apply_authorized": False,
            "crab_approved": False,
            "rollback_execution": False,
        },
        "contains_redacted_observation_body": False,
    }


def apply_request_stub(run_id: str, session_refs: dict[str, Any]) -> dict[str, Any]:
    return {
        "request_kind": "live-runtime-apply-request-stub",
        "execution_owner": True,
        "live_wrapper": True,
        "live_runtime_apply": False,
        "apply_authorized": False,
        "crab_approved": False,
        "target_identity": {
            "target_instance_label": session_refs.get("target_instance_label", ""),
            "execution_label": session_refs.get("execution_label", ""),
        },
        "refs": {
            "execution_owner_manifest": output_ref(run_id, "execution_owner_manifest.json"),
            "wrapper_session_refs": output_ref(run_id, "wrapper_session_refs.json"),
        },
        "future_requirements": [
            "bounded live runtime apply implementation",
            "operator approval binding at apply time",
            "first real rollout",
        ],
        "contains_retained_content": False,
        "contains_observation_body": False,
        "contains_mutation_commands": False,
    }


def wrapper_execution_report(
    secret_result: dict[str, Any],
    boundary_result: dict[str, Any],
    observation_result: dict[str, Any],
    non_secret_result: dict[str, Any],
    outputs_written: bool,
) -> dict[str, Any]:
    statuses = {
        "secret_session_validation": secret_result["status"],
        "execution_owner_boundary_validation": boundary_result["status"],
        "redacted_observation_validation": observation_result["status"],
        "non_secret_bundle_validation": non_secret_result["status"],
    }
    overall_status = (
        "pass"
        if outputs_written and all(value == "pass" for value in statuses.values())
        else "fail"
    )
    return {
        "overall_status": overall_status,
        **statuses,
        "outputs_written": outputs_written,
        "execution_owner": True,
        "live_wrapper": True,
        "live_runtime_apply": False,
        "crab_approved": False,
        "approval_granting": False,
        "rollback_execution": False,
        "real_secret_loading": True,
    }


def main() -> int:
    parse_args()
    run_id = str(values["run_id"])
    validate_run_id(run_id)

    run_dir = runs_root / run_id
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)

    write_json(run_dir / "wrapper_execution_meta.json", wrapper_execution_meta(run_id))

    secret_result, secret_data = validate_secret_session(str(values["secret_session_run_dir"]))
    boundary_result = execution_owner_boundary_validation()
    observation_result = validate_redacted_observations(secret_data)

    session_refs = wrapper_session_refs(run_id, secret_data)
    manifest = execution_owner_manifest(run_id, session_refs)
    stub = apply_request_stub(run_id, session_refs)
    non_secret_result = validate_non_secret_bundle([session_refs, manifest, stub], secret_data)

    write_json(checks_dir / "secret_session_validation.json", secret_result)
    write_json(checks_dir / "execution_owner_boundary_validation.json", boundary_result)
    write_json(checks_dir / "redacted_observation_validation.json", observation_result)
    write_json(checks_dir / "non_secret_bundle_validation.json", non_secret_result)

    outputs_written = False
    if (
        secret_result["status"] == "pass"
        and boundary_result["status"] == "pass"
        and observation_result["status"] == "pass"
        and non_secret_result["status"] == "pass"
    ):
        write_json(run_dir / "wrapper_session_refs.json", session_refs)
        write_json(run_dir / "execution_owner_manifest.json", manifest)
        write_json(run_dir / "apply_request_stub.json", stub)
        outputs_written = True

    report = wrapper_execution_report(
        secret_result,
        boundary_result,
        observation_result,
        non_secret_result,
        outputs_written,
    )
    exit_code = 0 if report["overall_status"] == "pass" else 1
    write_json(run_dir / "wrapper_execution_report.json", report)
    write_text(run_dir / "exit_code", f"{exit_code}\n")

    if exit_code == 0:
        print(f"PASS live wrapper execution owner: {run_id}")
    else:
        print(f"FAIL live wrapper execution owner: {run_id}", file=sys.stderr)
    return exit_code


try:
    raise SystemExit(main())
except WrapperExecutionOwnerError as exc:
    print(f"FAIL {exc}", file=sys.stderr)
    usage()
    raise SystemExit(1)
except Exception as exc:
    print(f"FAIL unexpected live wrapper execution owner error: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
