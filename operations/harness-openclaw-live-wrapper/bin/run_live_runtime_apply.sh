#!/usr/bin/env bash
set -u
set -o pipefail

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_RUNTIME_APPLY_PYTHON_BIN:-python}"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_RUNTIME_APPLY_PYTHON_BIN:-python3}"
else
  echo "FAIL python runtime not found; set LIVE_RUNTIME_APPLY_PYTHON_BIN or install python/python3" >&2
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
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class LiveRuntimeApplyError(Exception):
    pass


repo_root = Path(sys.argv[1]).resolve(strict=True)
args = sys.argv[2:]
surface_root = repo_root / "operations" / "harness-openclaw-live-wrapper"
runs_root = surface_root / "runs"

allowed_args = {
    "--execution-owner-run-dir": "execution_owner_run_dir",
    "--run-id": "run_id",
}
values: dict[str, str | None] = {value: None for value in allowed_args.values()}

supported_source_classes = {"workspace", "state", "runtime"}
root_by_source_class = {
    "workspace": "workspace_root",
    "state": "state_root",
    "runtime": "runtime_root",
}
disposable_path_terms = {"disposable", "scratch", "sandbox"}
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
    "non_secret_evidence_validation",
}
secret_value_pattern = re.compile(
    r"(?i)\b(?:secret|token|password|api[_-]?key|apikey|oauth|credential|private[_-]?key|session[_-]?cookie)\b\s*[:=]\s*(?!\[REDACTED\])\S+"
)
bearer_pattern = re.compile(r"(?i)authorization\s*:\s*bearer\s+(?!\[REDACTED\])[^ \t\r\n]+")
private_key_pattern = re.compile("-----BEGIN " + r"[A-Z ]*PRIVATE KEY-----")


def fail(message: str) -> None:
    raise LiveRuntimeApplyError(message)


def usage() -> None:
    print(
        "usage: run_live_runtime_apply.sh "
        "--execution-owner-run-dir <REPO_LOCAL_RUN_DIR> "
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


def resolve_repo_local_run_dir(raw: str, output_run_dir: Path) -> tuple[Path | None, dict[str, Any]]:
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
        result["violations"].append("execution_owner_path_empty_or_whitespace")
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
        result["violations"].append("execution_owner_run_dir_not_under_approved_root")

    if not result["direct_child"]:
        if "execution_owner_run_dir_not_under_approved_root" not in result["violations"]:
            result["violations"].append("execution_owner_run_dir_not_direct_child")

    result["not_output_run_dir"] = resolved != output_run_dir.resolve(strict=False)
    if not result["not_output_run_dir"]:
        result["violations"].append("execution_owner_run_dir_is_output_run_dir")

    result["exists"] = resolved.exists()
    result["directory"] = resolved.is_dir()
    if not result["exists"]:
        result["violations"].append("execution_owner_run_dir_missing")
    elif not result["directory"]:
        result["violations"].append("execution_owner_run_dir_not_directory")

    if result["violations"]:
        result["status"] = "fail"
        return None, result
    result["path"] = repo_rel(resolved)
    return resolved, result


def validate_execution_owner(raw: str, output_run_dir: Path) -> tuple[dict[str, Any], dict[str, Any] | None]:
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
    run_dir, root_result = resolve_repo_local_run_dir(raw, output_run_dir)
    result["root_validation"] = root_result
    if run_dir is None:
        result["status"] = "fail"
        result["violations"].extend(root_result["violations"])
        return result, None

    report = require_json(run_dir / "wrapper_execution_report.json", result, "wrapper_execution_report")
    meta = require_json(run_dir / "wrapper_execution_meta.json", result, "wrapper_execution_meta")
    manifest = require_json(run_dir / "execution_owner_manifest.json", result, "execution_owner_manifest")
    stub = require_json(run_dir / "apply_request_stub.json", result, "apply_request_stub")
    session_refs = require_json(run_dir / "wrapper_session_refs.json", result, "wrapper_session_refs")
    boundary = require_json(
        run_dir / "checks" / "execution_owner_boundary_validation.json",
        result,
        "execution_owner_boundary_validation",
    )
    non_secret = require_json(
        run_dir / "checks" / "non_secret_bundle_validation.json",
        result,
        "non_secret_bundle_validation",
    )

    if isinstance(report, dict):
        check_exact(result, "wrapper_execution_report_overall_status_pass", report.get("overall_status"), "pass")
    if isinstance(meta, dict):
        check_exact(result, "wrapper_execution_meta_surface_kind", meta.get("surface_kind"), "live-wrapper-execution-owner")
        check_exact(result, "wrapper_execution_meta_execution_owner_true", meta.get("execution_owner"), True)
        check_exact(result, "wrapper_execution_meta_live_wrapper_true", meta.get("live_wrapper"), True)
        check_exact(result, "wrapper_execution_meta_live_runtime_apply_false", meta.get("live_runtime_apply"), False)
        check_exact(result, "wrapper_execution_meta_crab_approved_false", meta.get("crab_approved"), False)
    if isinstance(manifest, dict):
        check_exact(result, "execution_owner_manifest_execution_owner_true", manifest.get("execution_owner"), True)
        check_exact(result, "execution_owner_manifest_live_wrapper_true", manifest.get("live_wrapper"), True)
        check_exact(result, "execution_owner_manifest_live_runtime_apply_false", manifest.get("live_runtime_apply"), False)
        check_exact(result, "execution_owner_manifest_crab_approved_false", manifest.get("crab_approved"), False)
    if isinstance(boundary, dict):
        check_exact(result, "execution_owner_boundary_validation_status_pass", boundary.get("status"), "pass")
    if isinstance(non_secret, dict):
        check_exact(result, "non_secret_bundle_validation_status_pass", non_secret.get("status"), "pass")

    if result["status"] != "pass":
        return result, None

    return result, {
        "run_dir": run_dir,
        "report": report,
        "meta": meta,
        "manifest": manifest,
        "stub": stub,
        "session_refs": session_refs,
        "boundary": boundary,
        "non_secret": non_secret,
    }


def trace_upstream_refs(execution_data: dict[str, Any] | None) -> tuple[dict[str, Any], dict[str, Any]]:
    result: dict[str, Any] = {
        "status": "pass",
        "files": {},
        "violations": [],
    }
    refs: dict[str, Any] = {
        "execution_owner_run_dir": None,
        "wrapper_session_refs": None,
        "loaded_material_manifest": None,
        "resolved_material_refs": None,
        "execution_owner_manifest": None,
        "selector_execution_record": None,
    }
    if execution_data is None:
        result["status"] = "fail"
        result["violations"].append("execution_owner_not_available")
        return result, refs

    execution_dir: Path = execution_data["run_dir"]
    session_refs = execution_data["session_refs"] if isinstance(execution_data["session_refs"], dict) else {}
    refs["execution_owner_run_dir"] = repo_rel(execution_dir)
    refs["wrapper_session_refs"] = repo_rel(execution_dir / "wrapper_session_refs.json")
    refs["execution_owner_manifest"] = repo_rel(execution_dir / "execution_owner_manifest.json")

    loaded_manifest_path = repo_path_from_ref(session_refs.get("loaded_material_manifest"))
    if loaded_manifest_path is None:
        result["status"] = "fail"
        result["violations"].append("loaded_material_manifest_ref_missing")
    else:
        refs["loaded_material_manifest"] = repo_rel(loaded_manifest_path.resolve(strict=False))
        require_json(loaded_manifest_path, result, "loaded_material_manifest")

    secret_session_dir = repo_path_from_ref(session_refs.get("secret_session_run_dir"))
    if secret_session_dir is None:
        result["status"] = "fail"
        result["violations"].append("secret_session_run_dir_ref_missing")
        return result, refs

    secret_input_refs = require_json(secret_session_dir / "input_refs.json", result, "secret_session_input_refs")
    material_dir = None
    if isinstance(secret_input_refs, dict):
        material_dir = repo_path_from_ref(secret_input_refs.get("material_resolution_run_dir"))
        resolved_refs_path = repo_path_from_ref(secret_input_refs.get("resolved_material_refs"))
        if resolved_refs_path is not None:
            refs["resolved_material_refs"] = repo_rel(resolved_refs_path.resolve(strict=False))
            require_json(resolved_refs_path, result, "resolved_material_refs")
        else:
            result["status"] = "fail"
            result["violations"].append("resolved_material_refs_ref_missing")
    else:
        result["status"] = "fail"
        result["violations"].append("secret_session_input_refs_not_object")

    if material_dir is None:
        result["status"] = "fail"
        result["violations"].append("material_resolution_run_dir_ref_missing")
        return result, refs

    material_input_refs = require_json(material_dir / "input_refs.json", result, "material_resolution_input_refs")
    selector_path = None
    if isinstance(material_input_refs, dict):
        wrapper_refs_path = repo_path_from_ref(material_input_refs.get("wrapper_input_refs"))
        wrapper_refs = require_json(wrapper_refs_path, result, "wrapper_input_refs") if wrapper_refs_path is not None else None
        if wrapper_refs_path is None:
            result["status"] = "fail"
            result["violations"].append("wrapper_input_refs_ref_missing")
        if isinstance(wrapper_refs, dict):
            selector_path = repo_path_from_ref(wrapper_refs.get("selector_execution_record"))
    else:
        result["status"] = "fail"
        result["violations"].append("material_resolution_input_refs_not_object")

    if selector_path is None:
        result["status"] = "fail"
        result["violations"].append("selector_execution_record_ref_missing")
    else:
        refs["selector_execution_record"] = repo_rel(selector_path.resolve(strict=False))
        require_json(selector_path, result, "selector_execution_record")

    return result, refs


def loaded_sources_by_label(loaded_manifest: Any) -> dict[str, dict[str, Any]]:
    if not isinstance(loaded_manifest, dict):
        return {}
    loaded = loaded_manifest.get("loaded_sources")
    if not isinstance(loaded, list):
        return {}
    return {
        item["source_label"]: item
        for item in loaded
        if isinstance(item, dict) and isinstance(item.get("source_label"), str)
    }


def directory_symlinks(path: Path) -> list[str]:
    if not path.is_dir():
        return []
    return [str(item) for item in sorted(path.rglob("*")) if item.is_symlink()]


def validate_material_sources(trace_result: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    result: dict[str, Any] = {
        "status": "pass",
        "source_checks": [],
        "duplicate_source_labels": [],
        "violations": [],
    }
    sources: list[dict[str, Any]] = []
    loaded_manifest = trace_result.get("files", {}).get("loaded_material_manifest", {})
    resolved_refs = trace_result.get("files", {}).get("resolved_material_refs", {})

    loaded_payload = None
    resolved_payload = None
    for key, payload in trace_result.get("_payloads", {}).items():
        if key == "loaded_material_manifest":
            loaded_payload = payload
        if key == "resolved_material_refs":
            resolved_payload = payload

    if loaded_payload is None:
        path = repo_path_from_ref(loaded_manifest.get("path")) if isinstance(loaded_manifest, dict) else None
        if path is not None:
            loaded_payload, _ = load_json_file(path)
    if resolved_payload is None:
        path = repo_path_from_ref(resolved_refs.get("path")) if isinstance(resolved_refs, dict) else None
        if path is not None:
            resolved_payload, _ = load_json_file(path)

    if not isinstance(resolved_payload, dict) or not isinstance(resolved_payload.get("resolved_sources"), list):
        result["status"] = "fail"
        result["violations"].append("resolved_sources_missing")
        return result, sources

    loaded_by_label = loaded_sources_by_label(loaded_payload)
    seen_labels: set[str] = set()

    for index, source in enumerate(resolved_payload["resolved_sources"]):
        check: dict[str, Any] = {
            "index": index,
            "status": "pass",
            "source_label": None,
            "source_class": None,
            "source_path": None,
            "exists": False,
            "outside_repo": False,
            "resolved_path_kind": None,
            "violations": [],
        }
        if not isinstance(source, dict):
            check["status"] = "fail"
            check["violations"].append("source_not_object")
            result["source_checks"].append(check)
            result["violations"].append(f"source_{index}_not_object")
            continue

        source_label = source.get("source_label")
        source_class = source.get("source_class")
        source_path_value = source.get("source_path")
        expected_kind = source.get("resolved_path_kind")
        check["source_label"] = source_label
        check["source_class"] = source_class
        check["source_path"] = source_path_value
        check["resolved_path_kind"] = expected_kind

        if not isinstance(source_label, str) or not source_label.strip():
            check["violations"].append("source_label_empty")
        elif source_label in seen_labels:
            check["violations"].append("duplicate_source_label")
            result["duplicate_source_labels"].append(source_label)
        else:
            seen_labels.add(source_label)

        if source_class not in supported_source_classes:
            check["violations"].append("unsupported_source_class")

        if expected_kind not in {"file", "directory"}:
            check["violations"].append("unsupported_resolved_path_kind")

        loaded = loaded_by_label.get(str(source_label))
        if loaded is None:
            check["violations"].append("loaded_source_metadata_missing")
        else:
            if loaded.get("source_class") != source_class:
                check["violations"].append("loaded_source_class_drift")
            if loaded.get("source_path") != source_path_value:
                check["violations"].append("loaded_source_path_drift")
            if loaded.get("resolved_path_kind") != expected_kind:
                check["violations"].append("loaded_source_kind_drift")

        if not isinstance(source_path_value, str) or not Path(source_path_value).is_absolute():
            check["violations"].append("source_path_not_absolute")
        else:
            raw_path = Path(source_path_value)
            resolved_path = raw_path.resolve(strict=False)
            check["outside_repo"] = not path_is_inside_repo(resolved_path)
            if path_is_inside_repo(resolved_path):
                check["violations"].append("source_path_inside_repo")
            if raw_path.is_symlink():
                check["violations"].append("source_path_symlink")
            check["exists"] = raw_path.exists()
            if not raw_path.exists():
                check["violations"].append("source_path_missing")
            elif expected_kind == "file" and not raw_path.is_file():
                check["violations"].append("source_type_drift")
            elif expected_kind == "directory" and not raw_path.is_dir():
                check["violations"].append("source_type_drift")
            elif expected_kind == "directory":
                symlinks = directory_symlinks(raw_path)
                if symlinks:
                    check["violations"].append("directory_contains_symlink")
                    check["symlink_paths"] = symlinks

        if check["violations"]:
            check["status"] = "fail"
            result["violations"].extend(f"source_{index}_{item}" for item in check["violations"])
        else:
            sources.append(
                {
                    "source_label": str(source_label),
                    "source_class": str(source_class),
                    "source_path": str(Path(str(source_path_value)).resolve(strict=False)),
                    "resolved_path_kind": str(expected_kind),
                }
            )
        result["source_checks"].append(check)

    if result["violations"]:
        result["status"] = "fail"
    return result, sources


def validate_source_label_for_destination(label: str) -> list[str]:
    violations: list[str] = []
    if not label.strip():
        violations.append("source_label_empty")
    label_path = Path(label)
    if label_path.is_absolute() or re.match(r"^[A-Za-z]:[\\/]", label):
        violations.append("source_label_absolute")
    if "\\" in label:
        violations.append("source_label_backslash")
    parts = [part for part in label.split("/") if part != ""]
    if not parts:
        violations.append("source_label_no_path_parts")
    if any(part in {".", ".."} for part in parts):
        violations.append("source_label_traversal")
    return violations


def validate_roots(selector: Any) -> tuple[dict[str, Any], dict[str, Path]]:
    result: dict[str, Any] = {
        "status": "pass",
        "root_checks": {},
        "violations": [],
    }
    roots: dict[str, Path] = {}
    if not isinstance(selector, dict):
        result["status"] = "fail"
        result["violations"].append("selector_execution_record_not_available")
        return result, roots

    for root_key in ("workspace_root", "state_root", "runtime_root"):
        raw = selector.get(root_key)
        item = {
            "path": raw,
            "absolute": False,
            "outside_repo": False,
            "not_disposable_looking": False,
            "status": "fail",
            "violations": [],
        }
        if not isinstance(raw, str) or not raw.strip():
            item["violations"].append("root_empty")
        else:
            path = Path(raw)
            item["absolute"] = path.is_absolute()
            if not path.is_absolute():
                item["violations"].append("root_not_absolute")
            resolved = path.resolve(strict=False)
            item["outside_repo"] = not path_is_inside_repo(resolved)
            if path_is_inside_repo(resolved):
                item["violations"].append("root_inside_repo")
            lowered_parts = {part.lower() for part in resolved.parts}
            item["not_disposable_looking"] = not bool(lowered_parts & disposable_path_terms)
            if not item["not_disposable_looking"]:
                item["violations"].append("root_disposable_looking")
            if not item["violations"]:
                roots[root_key] = resolved
                item["status"] = "pass"
        result["root_checks"][root_key] = item
        result["violations"].extend(f"{root_key}_{violation}" for violation in item["violations"])

    resolved_roots = list(roots.values())
    if len(set(resolved_roots)) != len(resolved_roots):
        result["violations"].append("target_roots_not_pairwise_distinct")
    if result["violations"]:
        result["status"] = "fail"
    return result, roots


def destination_is_under_root(destination: Path, root: Path) -> bool:
    try:
        destination.resolve(strict=False).relative_to(root.resolve(strict=False))
    except ValueError:
        return False
    return True


def plan_apply_actions(sources: list[dict[str, Any]], selector: Any) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    result, roots = validate_roots(selector)
    result.update(
        {
            "destination_checks": [],
            "planned_action_count": 0,
            "no_target_mutation_outside_mapped_roots": True,
        }
    )
    actions: list[dict[str, Any]] = []
    for index, source in enumerate(sources):
        source_class = source["source_class"]
        source_label = source["source_label"]
        root_key = root_by_source_class.get(source_class)
        root = roots.get(root_key or "")
        check: dict[str, Any] = {
            "index": index,
            "source_label": source_label,
            "source_class": source_class,
            "target_root_class": source_class,
            "status": "pass",
            "violations": [],
        }
        label_violations = validate_source_label_for_destination(source_label)
        check["violations"].extend(label_violations)
        if root is None:
            check["violations"].append("mapped_root_unavailable")
        else:
            destination = (root / source_label).resolve(strict=False)
            check["destination_path"] = str(destination)
            check["under_mapped_root"] = destination_is_under_root(destination, root)
            check["outside_repo"] = not path_is_inside_repo(destination)
            if not check["under_mapped_root"]:
                check["violations"].append("destination_escapes_mapped_root")
            if path_is_inside_repo(destination):
                check["violations"].append("destination_inside_repo")

        if check["violations"]:
            check["status"] = "fail"
            result["violations"].extend(f"destination_{index}_{item}" for item in check["violations"])
            result["status"] = "fail"
        else:
            actions.append(
                {
                    "source_label": source_label,
                    "source_class": source_class,
                    "source_path": source["source_path"],
                    "destination_path": str(destination),
                    "applied_kind": "file" if source["resolved_path_kind"] == "file" else "directory",
                    "status": "planned",
                }
            )
        result["destination_checks"].append(check)

    result["planned_action_count"] = len(actions)
    if result["status"] != "pass":
        result["no_target_mutation_outside_mapped_roots"] = False
    return result, actions


def copy_file(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)


def copy_directory(source: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for path in sorted(source.rglob("*")):
        if path.is_symlink():
            fail(f"symlink appeared during copy: {path}")
        if path.is_dir():
            continue
        if not path.is_file():
            fail(f"non-regular file appeared during copy: {path}")
        relative = path.relative_to(source)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)


def apply_actions(planned: list[dict[str, Any]]) -> list[dict[str, Any]]:
    applied: list[dict[str, Any]] = []
    for action in planned:
        source = Path(action["source_path"])
        destination = Path(action["destination_path"])
        if action["applied_kind"] == "file":
            copy_file(source, destination)
        else:
            copy_directory(source, destination)
        applied.append({**action, "status": "applied"})
    return applied


def post_apply_validation(actions: list[dict[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "status": "pass",
        "destination_checks": [],
        "unexpected_destination_outside_recorded_actions": [],
        "violations": [],
    }
    for index, action in enumerate(actions):
        path = Path(action["destination_path"])
        check = {
            "index": index,
            "source_label": action["source_label"],
            "destination_path": str(path),
            "exists": path.exists(),
            "kind_matches": False,
            "status": "pass",
            "violations": [],
        }
        if not path.exists():
            check["violations"].append("destination_missing")
        elif action["applied_kind"] == "file" and not path.is_file():
            check["violations"].append("destination_kind_mismatch")
        elif action["applied_kind"] == "directory" and not path.is_dir():
            check["violations"].append("destination_kind_mismatch")
        else:
            check["kind_matches"] = True
        if check["violations"]:
            check["status"] = "fail"
            result["violations"].extend(f"destination_{index}_{item}" for item in check["violations"])
        result["destination_checks"].append(check)
    if result["violations"]:
        result["status"] = "fail"
    return result


def key_is_secret_like(key: str, value: Any = None) -> bool:
    if key in allowed_secret_like_keys:
        return key == "real_secret_loading" and value is not True
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


def source_content_markers(actions: list[dict[str, Any]]) -> list[str]:
    markers: list[str] = []
    for action in actions:
        source = Path(action["source_path"])
        files = [source] if source.is_file() else sorted(path for path in source.rglob("*") if path.is_file())
        for path in files:
            try:
                content = path.read_text(encoding="utf-8-sig").strip()
            except (OSError, UnicodeError):
                continue
            if len(content) >= 8:
                markers.append(content)
    return markers


def validate_non_secret_evidence(payloads: list[Any], actions: list[dict[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "status": "pass",
        "violations": [],
        "forbidden_key_paths": [],
        "forbidden_value_paths": [],
        "inlined_source_content_paths": [],
    }
    combined = {f"payload_{index}": payload for index, payload in enumerate(payloads)}
    result["forbidden_key_paths"] = iter_secret_like_keys(combined)
    result["forbidden_value_paths"] = iter_secret_like_values(combined)
    combined_text = json.dumps(combined, sort_keys=True)
    for marker in source_content_markers(actions):
        if marker in combined_text:
            result["inlined_source_content_paths"].append("[REDACTED_SOURCE_CONTENT]")

    if result["forbidden_key_paths"]:
        result["violations"].append("secret_like_key_in_evidence")
    if result["forbidden_value_paths"]:
        result["violations"].append("secret_like_value_in_evidence")
    if result["inlined_source_content_paths"]:
        result["violations"].append("source_content_inlined")
    if result["violations"]:
        result["status"] = "fail"
    return result


def wrapper_apply_meta(run_id: str) -> dict[str, Any]:
    return {
        "surface_kind": "live-wrapper-apply",
        "run_id": run_id,
        "canonical_run_dir": canonical_run_dir(run_id),
        "execution_owner": True,
        "live_wrapper": True,
        "live_runtime_apply": True,
        "crab_approved": False,
        "approval_granting": False,
        "rollback_execution": False,
        "real_secret_loading": True,
        "created_at": now_utc(),
    }


def rollback_handoff(execution_data: dict[str, Any] | None, actions: list[dict[str, Any]], ready: bool) -> dict[str, Any]:
    identity = {}
    if execution_data is not None and isinstance(execution_data.get("manifest"), dict):
        identity = execution_data["manifest"].get("target_identity", {})
    return {
        "handoff_kind": "live-runtime-rollback-handoff",
        "target_instance_label": str(identity.get("target_instance_label", "")) if isinstance(identity, dict) else "",
        "execution_label": str(identity.get("execution_label", "")) if isinstance(identity, dict) else "",
        "applied_paths": [
            {
                "source_label": action["source_label"],
                "target_root_class": action["source_class"],
                "destination_path": action["destination_path"],
                "applied_kind": action["applied_kind"],
            }
            for action in actions
        ],
        "rollback_ready": ready,
    }


def wrapper_apply_report(
    execution_result: dict[str, Any],
    material_result: dict[str, Any],
    boundary_result: dict[str, Any],
    post_result: dict[str, Any],
    non_secret_result: dict[str, Any],
) -> dict[str, Any]:
    statuses = {
        "execution_owner_validation": execution_result["status"],
        "material_source_validation": material_result["status"],
        "pre_apply_boundary_validation": boundary_result["status"],
        "post_apply_validation": post_result["status"],
        "non_secret_evidence_validation": non_secret_result["status"],
    }
    overall_status = "pass" if all(value == "pass" for value in statuses.values()) else "fail"
    return {
        "overall_status": overall_status,
        **statuses,
        "execution_owner": True,
        "live_wrapper": True,
        "live_runtime_apply": True,
        "crab_approved": False,
    }


def main() -> int:
    parse_args()
    run_id = str(values["run_id"])
    validate_run_id(run_id)

    run_dir = runs_root / run_id
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)

    meta = wrapper_apply_meta(run_id)
    write_json(run_dir / "wrapper_apply_meta.json", meta)

    execution_result, execution_data = validate_execution_owner(str(values["execution_owner_run_dir"]), run_dir)
    trace_result, input_refs = trace_upstream_refs(execution_data)
    trace_payloads: dict[str, Any] = {}
    for file_key in ("loaded_material_manifest", "resolved_material_refs", "selector_execution_record"):
        path = repo_path_from_ref(input_refs.get(file_key))
        if path is not None:
            payload, error = load_json_file(path)
            if error is None:
                trace_payloads[file_key] = payload
    trace_result["_payloads"] = trace_payloads

    material_result, sources = validate_material_sources(trace_result)
    if trace_result["status"] != "pass":
        material_result["status"] = "fail"
        material_result["violations"].extend(f"trace_{item}" for item in trace_result["violations"])

    selector_payload = trace_payloads.get("selector_execution_record")
    boundary_result, planned_actions = plan_apply_actions(sources, selector_payload)

    applied_actions: list[dict[str, Any]] = []
    mutation_ready = (
        execution_result["status"] == "pass"
        and material_result["status"] == "pass"
        and boundary_result["status"] == "pass"
    )
    if mutation_ready:
        applied_actions = apply_actions(planned_actions)

    post_result = post_apply_validation(applied_actions) if mutation_ready else {
        "status": "fail",
        "destination_checks": [],
        "unexpected_destination_outside_recorded_actions": [],
        "violations": ["apply_not_executed"],
    }

    handoff = rollback_handoff(execution_data, applied_actions, mutation_ready and post_result["status"] == "pass")
    input_refs_payload = {
        "execution_owner_run_dir": input_refs.get("execution_owner_run_dir") or str(values["execution_owner_run_dir"]),
        "wrapper_session_refs": input_refs.get("wrapper_session_refs"),
        "loaded_material_manifest": input_refs.get("loaded_material_manifest"),
        "resolved_material_refs": input_refs.get("resolved_material_refs"),
        "execution_owner_manifest": input_refs.get("execution_owner_manifest"),
        "selector_execution_record": input_refs.get("selector_execution_record"),
        "contains_raw_contents": False,
        "contains_source_file_contents": False,
    }
    non_secret_payloads = [meta, input_refs_payload, applied_actions, handoff]
    non_secret_result = validate_non_secret_evidence(non_secret_payloads, applied_actions)

    report = wrapper_apply_report(
        execution_result,
        material_result,
        boundary_result,
        post_result,
        non_secret_result,
    )
    exit_code = 0 if report["overall_status"] == "pass" else 1

    write_json(run_dir / "wrapper_apply_input_refs.json", input_refs_payload)
    write_json(run_dir / "apply_actions.json", applied_actions)
    write_json(run_dir / "rollback_handoff.json", handoff)
    write_json(checks_dir / "execution_owner_validation.json", execution_result)
    write_json(checks_dir / "material_source_validation.json", material_result)
    write_json(checks_dir / "pre_apply_boundary_validation.json", boundary_result)
    write_json(checks_dir / "post_apply_validation.json", post_result)
    write_json(checks_dir / "non_secret_evidence_validation.json", non_secret_result)
    write_json(run_dir / "wrapper_apply_report.json", report)
    write_text(run_dir / "exit_code", f"{exit_code}\n")

    if exit_code == 0:
        print(f"PASS live runtime apply: {run_id}")
    else:
        print(f"FAIL live runtime apply: {run_id}", file=sys.stderr)
    return exit_code


try:
    raise SystemExit(main())
except LiveRuntimeApplyError as exc:
    print(f"FAIL {exc}", file=sys.stderr)
    usage()
    raise SystemExit(1)
except Exception as exc:
    print(f"FAIL unexpected live runtime apply error: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
