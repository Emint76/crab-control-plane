#!/usr/bin/env bash
set -u
set -o pipefail

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_SECRET_SESSION_PYTHON_BIN:-python}"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_SECRET_SESSION_PYTHON_BIN:-python3}"
else
  echo "FAIL python runtime not found; set LIVE_SECRET_SESSION_PYTHON_BIN or install python/python3" >&2
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


class SecretSessionError(Exception):
    pass


repo_root = Path(sys.argv[1]).resolve(strict=True)
args = sys.argv[2:]
surface_root = repo_root / "operations" / "harness-openclaw-live-secret-session"
runs_root = surface_root / "runs"
material_runs_root = repo_root / "operations" / "harness-openclaw-live-material-resolution" / "runs"

allowed_args = {
    "--material-resolution-run-dir": "material_resolution_run_dir",
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
allowed_secret_like_keys = {
    "real_secret_loading",
    "secret_session_only",
}
secret_value_pattern = re.compile(
    r"(?i)\b(?:secret|token|password|api[_-]?key|apikey|oauth|credential|private[_-]?key|session[_-]?cookie)\b\s*[:=]\s*(?!\[REDACTED\])\S+"
)
redaction_assignment_pattern = re.compile(
    r"(?i)\b(?:token|password|api[_-]?key|apikey|oauth|credential)\b\s*[:=]\s*(?!\[REDACTED\])[^ \t\r\n,;]+"
)
bearer_pattern = re.compile(
    r"(?i)authorization\s*:\s*bearer\s+(?!\[REDACTED\])[^ \t\r\n]+"
)
private_key_pattern = re.compile(
    "-----BEGIN " + r"[A-Z ]*PRIVATE KEY-----.*?-----END " + r"[A-Z ]*PRIVATE KEY-----",
    re.DOTALL,
)
private_key_begin_pattern = re.compile(
    "-----BEGIN " + r"[A-Z ]*PRIVATE KEY-----"
)


def fail(message: str) -> None:
    raise SecretSessionError(message)


def usage() -> None:
    print(
        "usage: run_live_secret_session.sh "
        "--material-resolution-run-dir <REPO_LOCAL_RUN_DIR> "
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
    return f"operations/harness-openclaw-live-secret-session/runs/{run_id}"


def output_ref(run_id: str, filename: str) -> str:
    return f"{canonical_run_dir(run_id)}/{filename}"


def repo_rel(path: Path) -> str:
    return path.relative_to(repo_root).as_posix()


def path_is_inside_repo(path: Path) -> bool:
    try:
        path.relative_to(repo_root)
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


def validate_material_resolution(raw: str) -> tuple[dict[str, Any], dict[str, Any] | None]:
    result: dict[str, Any] = {
        "status": "pass",
        "secret_session_only": True,
        "live_runtime_apply": False,
        "root_validation": {},
        "files": {},
        "checks": {},
        "violations": [],
    }
    run_dir, root_result = resolve_repo_local_run_dir(raw, material_runs_root, "material_resolution")
    result["root_validation"] = root_result
    if run_dir is None:
        result["status"] = "fail"
        result["violations"].extend(root_result["violations"])
        return result, None

    report = require_json(run_dir / "material_resolution_report.json", result, "material_resolution_report")
    meta = require_json(run_dir / "material_resolution_meta.json", result, "material_resolution_meta")
    refs = require_json(run_dir / "resolved_material_refs.json", result, "resolved_material_refs")
    bundle = require_json(run_dir / "wrapper_material_bundle.json", result, "wrapper_material_bundle")
    input_refs = require_json(run_dir / "input_refs.json", result, "input_refs")
    non_secret_check = require_json(
        run_dir / "checks" / "non_secret_bundle_validation.json",
        result,
        "non_secret_bundle_validation",
    )

    if isinstance(report, dict):
        check_exact(result, "material_resolution_report_overall_status_pass", report.get("overall_status"), "pass")
    if isinstance(meta, dict):
        check_exact(result, "material_resolution_meta_surface_kind", meta.get("surface_kind"), "live-material-resolution")
        check_exact(result, "material_resolution_meta_material_resolution_only", meta.get("material_resolution_only"), True)
        check_exact(result, "material_resolution_meta_live_runtime_apply_false", meta.get("live_runtime_apply"), False)
        check_exact(result, "material_resolution_meta_live_wrapper_false", meta.get("live_wrapper"), False)
        check_exact(result, "material_resolution_meta_crab_approved_false", meta.get("crab_approved"), False)
        check_exact(result, "material_resolution_meta_real_secret_loading_false", meta.get("real_secret_loading"), False)
    if isinstance(non_secret_check, dict):
        check_exact(result, "material_resolution_non_secret_bundle_validation_status_pass", non_secret_check.get("status"), "pass")
    if isinstance(refs, dict):
        check_exact(result, "resolved_material_refs_bundle_kind", refs.get("bundle_kind"), "live-material-refs")
    if isinstance(bundle, dict):
        check_exact(result, "wrapper_material_bundle_kind", bundle.get("bundle_kind"), "live-wrapper-material-bundle")
        check_exact(result, "wrapper_material_bundle_live_runtime_apply_false", bundle.get("live_runtime_apply"), False)
        check_exact(result, "wrapper_material_bundle_live_wrapper_false", bundle.get("live_wrapper"), False)
        check_exact(result, "wrapper_material_bundle_crab_approved_false", bundle.get("crab_approved"), False)

    if result["status"] != "pass":
        return result, None

    return result, {
        "run_dir": run_dir,
        "report": report,
        "meta": meta,
        "resolved_material_refs": refs,
        "wrapper_material_bundle": bundle,
        "input_refs": input_refs,
        "non_secret_check": non_secret_check,
    }


def decode_text(bytes_value: bytes) -> tuple[str | None, bool]:
    for encoding in ("utf-8-sig", "utf-8"):
        try:
            return bytes_value.decode(encoding), True
        except UnicodeDecodeError:
            continue
    return None, False


def redact_text(value: str) -> tuple[str, int]:
    redacted, count_a = private_key_pattern.subn("[REDACTED]", value)
    redacted, count_b = private_key_begin_pattern.subn("[REDACTED]", redacted)
    redacted, count_c = redaction_assignment_pattern.subn("[REDACTED]", redacted)
    redacted, count_d = bearer_pattern.subn("[REDACTED]", redacted)
    return redacted, count_a + count_b + count_c + count_d


def bounded_preview(value: str) -> tuple[str, int]:
    non_empty_lines = [line for line in value.splitlines() if line.strip()]
    if non_empty_lines:
        preview_lines = non_empty_lines[:3]
        preview = "\n".join(preview_lines)
        if len(preview) > 300:
            preview = preview[:300]
        return preview, len(preview_lines)
    return value[:300], 0


def regular_files_under(directory: Path) -> list[Path]:
    return sorted(path for path in directory.rglob("*") if path.is_file())


def load_file_source(source: dict[str, Any], path: Path) -> tuple[dict[str, Any], dict[str, Any] | None, list[dict[str, Any]]]:
    bytes_value = path.read_bytes()
    text_value, text_decodable = decode_text(bytes_value)
    line_count = len(text_value.splitlines()) if text_value is not None else 0
    manifest_item = {
        "source_label": source["source_label"],
        "source_class": source["source_class"],
        "source_path": str(path),
        "resolved_path_kind": "file",
        "loaded": True,
        "byte_count": len(bytes_value),
        "line_count": line_count,
        "file_count": 1,
        "text_file_count": 1 if text_decodable else 0,
        "text_decodable": text_decodable,
        "contains_raw_secrets": source.get("contains_raw_secrets") is True,
    }
    observation = None
    raw_content_records = [{"path": str(path), "content": text_value or ""}]
    if text_value is not None:
        redacted_text, redaction_count = redact_text(text_value)
        preview, preview_line_count = bounded_preview(redacted_text)
        observation = {
            "source_label": source["source_label"],
            "source_path": str(path),
            "resolved_path_kind": "file",
            "preview_redacted": preview,
            "preview_line_count": preview_line_count,
            "redaction_applied": True,
            "redaction_count": redaction_count,
        }
    return manifest_item, observation, raw_content_records


def load_directory_source(source: dict[str, Any], path: Path) -> tuple[dict[str, Any], dict[str, Any], list[dict[str, Any]], list[str]]:
    files = regular_files_under(path)
    symlink_violations = [str(item) for item in path.rglob("*") if item.is_symlink()]
    total_byte_count = 0
    text_file_count = 0
    observations = []
    raw_content_records: list[dict[str, Any]] = []

    for file_path in files:
        bytes_value = file_path.read_bytes()
        total_byte_count += len(bytes_value)
        text_value, text_decodable = decode_text(bytes_value)
        if text_value is None:
            continue
        text_file_count += 1
        raw_content_records.append({"path": str(file_path), "content": text_value})
        if len(observations) < 5:
            redacted_text, redaction_count = redact_text(text_value)
            preview, _preview_line_count = bounded_preview(redacted_text)
            observations.append(
                {
                    "relative_path": file_path.relative_to(path).as_posix(),
                    "preview_redacted": preview,
                    "redaction_applied": True,
                    "redaction_count": redaction_count,
                }
            )

    manifest_item = {
        "source_label": source["source_label"],
        "source_class": source["source_class"],
        "source_path": str(path),
        "resolved_path_kind": "directory",
        "loaded": True,
        "byte_count": total_byte_count,
        "line_count": 0,
        "file_count": len(files),
        "text_file_count": text_file_count,
        "contains_raw_secrets": source.get("contains_raw_secrets") is True,
    }
    observation = {
        "source_label": source["source_label"],
        "source_path": str(path),
        "resolved_path_kind": "directory",
        "redaction_applied": True,
        "observed_files": observations,
    }
    return manifest_item, observation, raw_content_records, symlink_violations


def validate_and_load_materials(material_data: dict[str, Any] | None) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], list[dict[str, Any]]]:
    result: dict[str, Any] = {
        "status": "pass",
        "secret_session_only": True,
        "live_runtime_apply": False,
        "source_results": [],
        "missing_source_violations": [],
        "symlink_violations": [],
        "type_drift_violations": [],
        "duplicate_label_violations": [],
        "violations": [],
    }
    manifest = {
        "manifest_kind": "live-loaded-material-manifest",
        "secret_session_only": True,
        "live_runtime_apply": False,
        "live_wrapper": False,
        "crab_approved": False,
        "real_secret_loading": True,
        "loaded_sources": [],
    }
    observations = {
        "observation_kind": "live-redacted-material-observations",
        "secret_session_only": True,
        "live_runtime_apply": False,
        "live_wrapper": False,
        "crab_approved": False,
        "real_secret_loading": True,
        "redaction_applied": True,
        "observations": [],
    }
    raw_content_records: list[dict[str, Any]] = []

    if material_data is None:
        result["status"] = "fail"
        result["violations"].append("material_resolution_not_available")
        return result, manifest, observations, raw_content_records

    refs = material_data.get("resolved_material_refs")
    sources = refs.get("resolved_sources") if isinstance(refs, dict) else None
    if not isinstance(sources, list) or not sources:
        result["status"] = "fail"
        result["violations"].append("resolved_sources_missing")
        return result, manifest, observations, raw_content_records

    seen_labels: set[str] = set()
    for index, source in enumerate(sources):
        source_result: dict[str, Any] = {
            "index": index,
            "source_label": source.get("source_label") if isinstance(source, dict) else None,
            "status": "pass",
            "loaded": False,
            "violations": [],
        }
        if not isinstance(source, dict):
            source_result["status"] = "fail"
            source_result["violations"].append("source_not_object")
            result["source_results"].append(source_result)
            result["violations"].append(f"source_{index}_not_object")
            continue

        source_label = source.get("source_label")
        if not isinstance(source_label, str) or not source_label.strip():
            source_result["violations"].append("source_label_empty")
        elif source_label in seen_labels:
            source_result["violations"].append("duplicate_source_label")
            result["duplicate_label_violations"].append(source_label)
        else:
            seen_labels.add(source_label)

        source_path_value = source.get("source_path")
        expected_kind = source.get("resolved_path_kind")
        if expected_kind not in {"file", "directory"}:
            source_result["violations"].append("unsupported_resolved_path_kind")
        if not isinstance(source_path_value, str) or not Path(source_path_value).is_absolute():
            source_result["violations"].append("source_path_not_absolute")
        else:
            raw_path = Path(source_path_value)
            source_result["source_path"] = str(raw_path)
            if raw_path.is_symlink():
                source_result["violations"].append("source_path_symlink")
                result["symlink_violations"].append(str(raw_path))
            resolved_path = raw_path.resolve(strict=False)
            source_result["resolved_path"] = str(resolved_path)
            if path_is_inside_repo(resolved_path):
                source_result["violations"].append("source_path_inside_repo")
            if not raw_path.exists():
                source_result["violations"].append("source_path_missing")
                result["missing_source_violations"].append(str(raw_path))
            elif expected_kind == "file" and not raw_path.is_file():
                source_result["violations"].append("source_type_drift")
                result["type_drift_violations"].append(str(raw_path))
            elif expected_kind == "directory" and not raw_path.is_dir():
                source_result["violations"].append("source_type_drift")
                result["type_drift_violations"].append(str(raw_path))
            elif raw_path.exists() and not raw_path.is_symlink() and not source_result["violations"]:
                try:
                    if expected_kind == "file":
                        manifest_item, observation, raw_records = load_file_source(source, raw_path)
                        if observation is not None:
                            observations["observations"].append(observation)
                        raw_content_records.extend(raw_records)
                    else:
                        manifest_item, observation, raw_records, symlink_violations = load_directory_source(source, raw_path)
                        if symlink_violations:
                            source_result["violations"].append("directory_contains_symlink")
                            result["symlink_violations"].extend(symlink_violations)
                        else:
                            observations["observations"].append(observation)
                            raw_content_records.extend(raw_records)
                    if not source_result["violations"]:
                        manifest["loaded_sources"].append(manifest_item)
                        source_result["loaded"] = True
                except OSError as exc:
                    source_result["violations"].append(f"source_read_failed:{exc}")

        if source_result["violations"]:
            source_result["status"] = "fail"
            result["violations"].extend(f"source_{index}_{item}" for item in source_result["violations"])
        result["source_results"].append(source_result)

    if result["violations"]:
        result["status"] = "fail"
    return result, manifest, observations, raw_content_records


def key_is_secret_like(key: str, value: Any = None) -> bool:
    if key in allowed_secret_like_keys:
        return value is not True
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
        if secret_value_pattern.search(value) or bearer_pattern.search(value) or private_key_begin_pattern.search(value):
            violations.append(prefix or "<root>")
    return violations


def validate_redaction(output_files: list[Path]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "status": "pass",
        "secret_session_only": True,
        "live_runtime_apply": False,
        "violations": [],
        "unredacted_value_paths": [],
        "checked_output_files": [repo_rel(path) for path in output_files],
    }
    for path in output_files:
        payload, error = load_json_file(path)
        if error is not None:
            result["violations"].append(f"unreadable_output:{repo_rel(path)}")
            continue
        for item in iter_secret_like_values(payload):
            result["unredacted_value_paths"].append(f"{repo_rel(path)}:{item}")
    if result["unredacted_value_paths"]:
        result["violations"].append("unredacted_secret_like_value")
    if result["violations"]:
        result["status"] = "fail"
    return result


def contents_inlined(bundle_text: str, raw_content_records: list[dict[str, Any]]) -> list[str]:
    violations: list[str] = []
    for record in raw_content_records:
        content = str(record.get("content", "")).strip()
        if len(content) >= 32 and content in bundle_text:
            violations.append(str(record.get("path")))
    return violations


def retained_contents_from_material(material_data: dict[str, Any] | None) -> list[dict[str, Any]]:
    if material_data is None:
        return []
    input_refs = material_data.get("input_refs")
    wrapper_input_refs_path = input_refs.get("wrapper_input_refs") if isinstance(input_refs, dict) else None
    if not isinstance(wrapper_input_refs_path, str):
        return []
    wrapper_refs_path = repo_root / wrapper_input_refs_path
    wrapper_refs, error = load_json_file(wrapper_refs_path)
    if error is not None or not isinstance(wrapper_refs, dict):
        return []
    retained_dir_value = wrapper_refs.get("retained_evidence_dir")
    if not isinstance(retained_dir_value, str):
        return []
    retained_dir = repo_root / retained_dir_value
    if not retained_dir.is_dir():
        return []
    records: list[dict[str, Any]] = []
    for path in sorted(retained_dir.rglob("*")):
        if not path.is_file():
            continue
        try:
            content = path.read_text(encoding="utf-8-sig")
        except (OSError, UnicodeError):
            continue
        records.append({"path": repo_rel(path), "content": content})
    return records


def validate_non_secret_bundle(
    payloads: list[dict[str, Any]],
    raw_content_records: list[dict[str, Any]],
    retained_content_records: list[dict[str, Any]],
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "status": "pass",
        "secret_session_only": True,
        "live_runtime_apply": False,
        "violations": [],
        "secret_like_key_paths": [],
        "secret_like_value_paths": [],
        "inlined_source_content_paths": [],
        "inlined_retained_content_paths": [],
    }
    combined = {f"payload_{index}": payload for index, payload in enumerate(payloads)}
    result["secret_like_key_paths"] = iter_secret_like_keys(combined)
    result["secret_like_value_paths"] = iter_secret_like_values(combined)
    bundle_text = json.dumps(combined, sort_keys=True)
    result["inlined_source_content_paths"] = contents_inlined(bundle_text, raw_content_records)
    result["inlined_retained_content_paths"] = contents_inlined(bundle_text, retained_content_records)

    if result["secret_like_key_paths"]:
        result["violations"].append("secret_like_key_in_bundle")
    if result["secret_like_value_paths"]:
        result["violations"].append("secret_like_value_in_bundle")
    if result["inlined_source_content_paths"]:
        result["violations"].append("source_content_inlined")
    if result["inlined_retained_content_paths"]:
        result["violations"].append("retained_content_inlined")
    if result["violations"]:
        result["status"] = "fail"
    return result


def secret_session_meta(run_id: str) -> dict[str, Any]:
    return {
        "surface_kind": "live-secret-session",
        "run_id": run_id,
        "canonical_run_dir": canonical_run_dir(run_id),
        "secret_session_only": True,
        "live_runtime_apply": False,
        "live_wrapper": False,
        "crab_approved": False,
        "approval_granting": False,
        "rollback_execution": False,
        "real_secret_loading": True,
        "target_mutation": False,
        "broader_local_overlay_reading": False,
        "created_at": now_utc(),
    }


def build_input_refs(run_id: str, material_data: dict[str, Any] | None) -> dict[str, Any]:
    material_dir = material_data["run_dir"] if material_data else None
    return {
        "material_resolution_run_dir": repo_rel(material_dir) if material_dir else str(values["material_resolution_run_dir"]),
        "resolved_material_refs": repo_rel(material_dir / "resolved_material_refs.json") if material_dir else None,
        "wrapper_material_bundle": repo_rel(material_dir / "wrapper_material_bundle.json") if material_dir else None,
        "loaded_material_manifest": output_ref(run_id, "loaded_material_manifest.json"),
        "redacted_material_observations": output_ref(run_id, "redacted_material_observations.json"),
        "contains_raw_contents": False,
        "real_secret_loading": True,
    }


def build_wrapper_secret_session_bundle(
    run_id: str,
    material_data: dict[str, Any],
    manifest: dict[str, Any],
) -> dict[str, Any]:
    material_dir = material_data["run_dir"]
    wrapper_material_bundle = material_data["wrapper_material_bundle"]
    identity = wrapper_material_bundle.get("target_identity", {}) if isinstance(wrapper_material_bundle, dict) else {}
    return {
        "bundle_kind": "live-wrapper-secret-session-bundle",
        "secret_session_only": True,
        "live_runtime_apply": False,
        "live_wrapper": False,
        "crab_approved": False,
        "approval_granting": False,
        "rollback_execution": False,
        "real_secret_loading": True,
        "target_identity": {
            "target_instance_label": identity.get("target_instance_label", ""),
            "execution_label": identity.get("execution_label", ""),
        },
        "material_resolution": {
            "material_resolution_run_dir": repo_rel(material_dir),
            "wrapper_material_bundle": repo_rel(material_dir / "wrapper_material_bundle.json"),
        },
        "loaded_materials": {
            "loaded_material_manifest": output_ref(run_id, "loaded_material_manifest.json"),
            "redacted_material_observations": output_ref(run_id, "redacted_material_observations.json"),
            "loaded_source_count": len(manifest.get("loaded_sources", [])),
        },
    }


def secret_session_report(
    material_result: dict[str, Any],
    load_result: dict[str, Any],
    redaction_result: dict[str, Any],
    non_secret_result: dict[str, Any],
    bundle_written: bool,
) -> dict[str, Any]:
    statuses = {
        "material_resolution_validation": material_result["status"],
        "material_load_validation": load_result["status"],
        "redaction_validation": redaction_result["status"],
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
        "secret_session_only": True,
        "live_runtime_apply": False,
        "live_wrapper": False,
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
    write_json(run_dir / "secret_session_meta.json", secret_session_meta(run_id))

    material_result, material_data = validate_material_resolution(str(values["material_resolution_run_dir"]))
    load_result, manifest, observations, raw_content_records = validate_and_load_materials(material_data)

    write_json(run_dir / "loaded_material_manifest.json", manifest)
    write_json(run_dir / "redacted_material_observations.json", observations)

    redaction_result = validate_redaction([run_dir / "redacted_material_observations.json"])

    wrapper_bundle = None
    if material_data is not None:
        wrapper_bundle = build_wrapper_secret_session_bundle(run_id, material_data, manifest)
    input_refs = build_input_refs(run_id, material_data)
    retained_content_records = retained_contents_from_material(material_data)
    non_secret_payloads = [input_refs]
    if wrapper_bundle is not None:
        non_secret_payloads.append(wrapper_bundle)
    non_secret_result = validate_non_secret_bundle(
        non_secret_payloads,
        raw_content_records,
        retained_content_records,
    )

    bundle_written = False
    if (
        material_result["status"] == "pass"
        and load_result["status"] == "pass"
        and redaction_result["status"] == "pass"
        and non_secret_result["status"] == "pass"
        and wrapper_bundle is not None
    ):
        write_json(run_dir / "wrapper_secret_session_bundle.json", wrapper_bundle)
        bundle_written = True

    write_json(run_dir / "input_refs.json", input_refs)
    write_json(checks_dir / "material_resolution_validation.json", material_result)
    write_json(checks_dir / "material_load_validation.json", load_result)
    write_json(checks_dir / "redaction_validation.json", redaction_result)
    write_json(checks_dir / "non_secret_bundle_validation.json", non_secret_result)

    report = secret_session_report(
        material_result,
        load_result,
        redaction_result,
        non_secret_result,
        bundle_written,
    )
    exit_code = 0 if report["overall_status"] == "pass" else 1
    write_json(run_dir / "secret_session_report.json", report)
    write_text(run_dir / "exit_code", f"{exit_code}\n")

    if exit_code == 0:
        print(f"PASS live secret session: {run_id}")
    else:
        print(f"FAIL live secret session: {run_id}", file=sys.stderr)
    return exit_code


try:
    raise SystemExit(main())
except SecretSessionError as exc:
    print(f"FAIL {exc}", file=sys.stderr)
    usage()
    raise SystemExit(1)
except Exception as exc:
    print(f"FAIL unexpected live secret session error: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
