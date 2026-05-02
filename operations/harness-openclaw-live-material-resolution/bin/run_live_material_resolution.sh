#!/usr/bin/env bash
set -u
set -o pipefail

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_MATERIAL_RESOLUTION_PYTHON_BIN:-python}"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_MATERIAL_RESOLUTION_PYTHON_BIN:-python3}"
else
  echo "FAIL python runtime not found; set LIVE_MATERIAL_RESOLUTION_PYTHON_BIN or install python/python3" >&2
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


class MaterialResolutionError(Exception):
    pass


repo_root = Path(sys.argv[1]).resolve(strict=True)
args = sys.argv[2:]
surface_root = repo_root / "operations" / "harness-openclaw-live-material-resolution"
runs_root = surface_root / "runs"
wrapper_runs_root = repo_root / "operations" / "harness-openclaw-live-wrapper" / "runs"

allowed_args = {
    "--wrapper-preflight-run-dir": "wrapper_preflight_run_dir",
    "--source-declaration-file": "source_declaration_file",
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
allowed_source_declaration_key = "contains_raw_secrets"
allowed_bundle_secret_like_keys = {
    "contains_raw_secrets",
    "real_secret_loading",
}
declaration_top_level_keys = {
    "declaration_kind",
    "declaration_label",
    "execution_label",
    "local_only",
    "outside_git",
    "sources",
}
declaration_source_keys = {
    "source_label",
    "source_class",
    "source_path",
    "contains_raw_secrets",
}
secret_value_pattern = re.compile(
    r"(?i)\b(?:secret|token|password|api[_-]?key|apikey|oauth|credential|private[_-]?key|session[_-]?cookie)\b\s*[:=]\s*(?!\[REDACTED\])\S+"
)


def fail(message: str) -> None:
    raise MaterialResolutionError(message)


def usage() -> None:
    print(
        "usage: run_live_material_resolution.sh "
        "--wrapper-preflight-run-dir <REPO_LOCAL_RUN_DIR> "
        "--source-declaration-file <ABSOLUTE_PATH_OUTSIDE_GIT> "
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
    return f"operations/harness-openclaw-live-material-resolution/runs/{run_id}"


def repo_rel(path: Path) -> str:
    return path.relative_to(repo_root).as_posix()


def output_ref(run_id: str, filename: str) -> str:
    return f"{canonical_run_dir(run_id)}/{filename}"


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


def key_matches_forbidden(key: str, *, allow_source_key: bool = False, bundle_mode: bool = False, value: Any = None) -> bool:
    if allow_source_key and key == allowed_source_declaration_key:
        return False
    if bundle_mode and key in allowed_bundle_secret_like_keys:
        if key == "real_secret_loading":
            return value is not False
        if key == "contains_raw_secrets":
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


def iter_forbidden_key_paths(value: Any, prefix: str = "") -> list[str]:
    violations: list[str] = []
    if isinstance(value, dict):
        for key, item in value.items():
            key_text = str(key)
            child_prefix = f"{prefix}.{key_text}" if prefix else key_text
            if key_matches_forbidden(key_text, allow_source_key=True):
                violations.append(child_prefix)
            violations.extend(iter_forbidden_key_paths(item, child_prefix))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            violations.extend(iter_forbidden_key_paths(item, f"{prefix}[{index}]"))
    return violations


def iter_bundle_secret_like_keys(value: Any, prefix: str = "") -> list[str]:
    violations: list[str] = []
    if isinstance(value, dict):
        for key, item in value.items():
            key_text = str(key)
            child_prefix = f"{prefix}.{key_text}" if prefix else key_text
            if key_matches_forbidden(key_text, bundle_mode=True, value=item):
                violations.append(child_prefix)
            violations.extend(iter_bundle_secret_like_keys(item, child_prefix))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            violations.extend(iter_bundle_secret_like_keys(item, f"{prefix}[{index}]"))
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


def validate_wrapper_preflight(raw: str) -> tuple[dict[str, Any], dict[str, Any] | None]:
    result: dict[str, Any] = {
        "status": "pass",
        "material_resolution_only": True,
        "live_runtime_apply": False,
        "root_validation": {},
        "files": {},
        "checks": {},
        "violations": [],
    }
    run_dir, root_result = resolve_repo_local_run_dir(raw, wrapper_runs_root, "wrapper_preflight")
    result["root_validation"] = root_result
    if run_dir is None:
        result["status"] = "fail"
        result["violations"].extend(root_result["violations"])
        return result, None

    report = require_json(run_dir / "wrapper_report.json", result, "wrapper_report")
    meta = require_json(run_dir / "wrapper_meta.json", result, "wrapper_meta")
    input_refs = require_json(run_dir / "wrapper_input_refs.json", result, "wrapper_input_refs")
    plan = require_json(run_dir / "execution_plan_stub.json", result, "execution_plan_stub")
    boundary = require_json(
        run_dir / "checks" / "preflight_boundary_validation.json",
        result,
        "preflight_boundary_validation",
    )

    if isinstance(report, dict):
        check_exact(result, "wrapper_report_overall_status_pass", report.get("overall_status"), "pass")
    if isinstance(meta, dict):
        check_exact(result, "wrapper_meta_surface_kind", meta.get("surface_kind"), "live-wrapper-preflight")
        check_exact(result, "wrapper_meta_preflight_only", meta.get("preflight_only"), True)
        check_exact(result, "wrapper_meta_live_runtime_apply_false", meta.get("live_runtime_apply"), False)
        check_exact(result, "wrapper_meta_live_wrapper_false", meta.get("live_wrapper"), False)
        check_exact(result, "wrapper_meta_crab_approved_false", meta.get("crab_approved"), False)
    if isinstance(boundary, dict):
        check_exact(result, "preflight_boundary_validation_status_pass", boundary.get("status"), "pass")

    if result["status"] != "pass":
        return result, None

    return result, {
        "run_dir": run_dir,
        "report": report,
        "meta": meta,
        "input_refs": input_refs,
        "plan": plan,
        "boundary": boundary,
    }


def validate_source_declaration(raw: str) -> tuple[dict[str, Any], dict[str, Any] | None]:
    result: dict[str, Any] = {
        "status": "pass",
        "material_resolution_only": True,
        "live_runtime_apply": False,
        "input_file": {
            "path": raw,
            "absolute_path": False,
            "exists": False,
            "file": False,
            "outside_repo": False,
        },
        "shape_checks": {},
        "source_path_checks": [],
        "forbidden_key_paths": [],
        "violations": [],
    }
    if raw == "" or raw != raw.strip():
        result["violations"].append("source_declaration_path_empty_or_whitespace")
        result["status"] = "fail"
        return result, None

    path = Path(raw)
    result["input_file"]["absolute_path"] = path.is_absolute()
    if not path.is_absolute():
        result["violations"].append("source_declaration_path_not_absolute")
        result["status"] = "fail"
        return result, None

    try:
        resolved = path.resolve(strict=True)
    except OSError:
        result["violations"].append("source_declaration_path_missing")
        result["status"] = "fail"
        return result, None

    result["input_file"]["exists"] = True
    result["input_file"]["file"] = resolved.is_file()
    result["input_file"]["outside_repo"] = not path_is_inside_repo(resolved)
    if not resolved.is_file():
        result["violations"].append("source_declaration_path_not_file")
    if path_is_inside_repo(resolved):
        result["violations"].append("source_declaration_path_inside_repo")

    payload, error = load_json_file(resolved)
    if error is not None:
        result["violations"].append("source_declaration_json_unreadable")
        result["json_error"] = error
    if result["violations"]:
        result["status"] = "fail"
        return result, payload if isinstance(payload, dict) else None

    if not isinstance(payload, dict):
        result["violations"].append("source_declaration_not_object")
        result["status"] = "fail"
        return result, None

    sources = payload.get("sources")
    shape_checks = {
        "declaration_kind": payload.get("declaration_kind") == "secret-material-source-declaration",
        "declaration_label_non_empty": isinstance(payload.get("declaration_label"), str) and bool(str(payload.get("declaration_label")).strip()),
        "execution_label_non_empty": isinstance(payload.get("execution_label"), str) and bool(str(payload.get("execution_label")).strip()),
        "local_only": payload.get("local_only") is True,
        "outside_git": payload.get("outside_git") is True,
        "sources_non_empty": isinstance(sources, list) and len(sources) > 0,
        "no_top_level_extra_keys": set(payload.keys()).issubset(declaration_top_level_keys),
    }
    result["shape_checks"] = {key: "pass" if passed else "fail" for key, passed in shape_checks.items()}
    for key, passed in shape_checks.items():
        if not passed:
            result["violations"].append(key)

    result["forbidden_key_paths"] = iter_forbidden_key_paths(payload)
    if result["forbidden_key_paths"]:
        result["violations"].append("forbidden_secret_like_key_in_declaration")

    if isinstance(sources, list):
        for index, source in enumerate(sources):
            raw_source_path = source.get("source_path") if isinstance(source, dict) else None
            check = {
                "index": index,
                "source_label": source.get("source_label") if isinstance(source, dict) else None,
                "absolute_path": False,
                "outside_repo": False,
                "status": "fail",
            }
            if not isinstance(source, dict):
                result["violations"].append(f"source_{index}_not_object")
            else:
                if not set(source.keys()).issubset(declaration_source_keys):
                    result["violations"].append(f"source_{index}_extra_keys")
                if source.get("contains_raw_secrets") is not True:
                    result["violations"].append(f"source_{index}_contains_raw_secrets_not_true")
            if isinstance(raw_source_path, str):
                source_path = Path(raw_source_path)
                check["absolute_path"] = source_path.is_absolute()
                if source_path.is_absolute():
                    check["outside_repo"] = not path_is_inside_repo(source_path.resolve(strict=False))
            if check["absolute_path"] and check["outside_repo"]:
                check["status"] = "pass"
            else:
                result["violations"].append(f"source_path_{index}_invalid_or_inside_repo")
            result["source_path_checks"].append(check)

    if result["violations"]:
        result["status"] = "fail"
    return result, payload


def validate_material_paths(declaration: dict[str, Any] | None) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    result: dict[str, Any] = {
        "status": "pass",
        "material_resolution_only": True,
        "live_runtime_apply": False,
        "source_checks": [],
        "duplicate_source_labels": [],
        "violations": [],
    }
    resolved_sources: list[dict[str, Any]] = []
    if not isinstance(declaration, dict) or not isinstance(declaration.get("sources"), list):
        result["status"] = "fail"
        result["violations"].append("source_declaration_not_available")
        return result, resolved_sources

    seen_labels: set[str] = set()
    for index, source in enumerate(declaration["sources"]):
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
        raw_source_path = source.get("source_path")
        check["source_label"] = source_label
        check["source_class"] = source_class
        check["source_path"] = raw_source_path

        if not isinstance(source_label, str) or not source_label.strip():
            check["violations"].append("source_label_empty")
        elif source_label in seen_labels:
            check["violations"].append("duplicate_source_label")
            result["duplicate_source_labels"].append(source_label)
        else:
            seen_labels.add(source_label)

        if not isinstance(source_class, str) or not source_class.strip():
            check["violations"].append("source_class_empty")

        if not isinstance(raw_source_path, str) or not Path(raw_source_path).is_absolute():
            check["violations"].append("source_path_not_absolute")
        else:
            source_path = Path(raw_source_path)
            resolved = source_path.resolve(strict=False)
            check["outside_repo"] = not path_is_inside_repo(resolved)
            if not check["outside_repo"]:
                check["violations"].append("source_path_inside_repo")
            check["exists"] = resolved.exists()
            if not check["exists"]:
                check["violations"].append("source_path_missing")
            elif resolved.is_file():
                check["resolved_path_kind"] = "file"
            elif resolved.is_dir():
                check["resolved_path_kind"] = "directory"
            else:
                check["violations"].append("source_path_not_file_or_directory")

        if check["violations"]:
            check["status"] = "fail"
            result["violations"].extend(f"source_{index}_{item}" for item in check["violations"])
        else:
            resolved_sources.append(
                {
                    "source_label": str(source_label),
                    "source_class": str(source_class),
                    "source_path": str(Path(str(raw_source_path)).resolve(strict=False)),
                    "resolved_path_kind": check["resolved_path_kind"],
                    "contains_raw_secrets": source.get("contains_raw_secrets") is True,
                }
            )
        result["source_checks"].append(check)

    if result["violations"]:
        result["status"] = "fail"
    return result, resolved_sources


def material_resolution_meta(run_id: str) -> dict[str, Any]:
    return {
        "surface_kind": "live-material-resolution",
        "run_id": run_id,
        "canonical_run_dir": canonical_run_dir(run_id),
        "material_resolution_only": True,
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


def build_resolved_material_refs(resolved_sources: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "bundle_kind": "live-material-refs",
        "material_resolution_only": True,
        "live_runtime_apply": False,
        "live_wrapper": False,
        "crab_approved": False,
        "resolved_sources": resolved_sources,
    }


def build_wrapper_material_bundle(
    run_id: str,
    wrapper_data: dict[str, Any],
    resolved_sources: list[dict[str, Any]],
) -> dict[str, Any]:
    plan = wrapper_data["plan"]
    identity = plan.get("target_identity", {}) if isinstance(plan, dict) else {}
    return {
        "bundle_kind": "live-wrapper-material-bundle",
        "material_resolution_only": True,
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
        "wrapper_preflight": {
            "wrapper_preflight_run_dir": repo_rel(wrapper_data["run_dir"]),
            "execution_plan_stub": repo_rel(wrapper_data["run_dir"] / "execution_plan_stub.json"),
        },
        "material_refs": {
            "resolved_material_refs": output_ref(run_id, "resolved_material_refs.json"),
            "resolved_source_count": len(resolved_sources),
        },
    }


def build_input_refs(run_id: str, wrapper_data: dict[str, Any] | None) -> dict[str, Any]:
    wrapper_dir = wrapper_data["run_dir"] if wrapper_data else None
    return {
        "wrapper_preflight_run_dir": repo_rel(wrapper_dir) if wrapper_dir else str(values["wrapper_preflight_run_dir"]),
        "source_declaration_file": str(values["source_declaration_file"]),
        "execution_plan_stub": repo_rel(wrapper_dir / "execution_plan_stub.json") if wrapper_dir else None,
        "wrapper_input_refs": repo_rel(wrapper_dir / "wrapper_input_refs.json") if wrapper_dir else None,
        "resolved_material_refs": output_ref(run_id, "resolved_material_refs.json"),
        "contains_file_contents": False,
        "contains_source_declaration_body": False,
        "real_secret_loading": False,
    }


def source_contents_inlined(bundle_text: str, source_paths: list[str]) -> list[str]:
    violations: list[str] = []
    for raw_path in source_paths:
        path = Path(raw_path).resolve(strict=False)
        candidates: list[Path] = []
        if path.is_file():
            candidates.append(path)
        elif path.is_dir():
            candidates.extend(item for item in sorted(path.rglob("*")) if item.is_file())
        for candidate in candidates:
            try:
                content = candidate.read_text(encoding="utf-8-sig").strip()
            except (OSError, UnicodeError):
                continue
            if len(content) >= 32 and content in bundle_text:
                violations.append(str(candidate))
    return violations


def validate_non_secret_bundle(
    bundle_payloads: list[dict[str, Any]],
    source_paths: list[str],
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "status": "pass",
        "material_resolution_only": True,
        "live_runtime_apply": False,
        "violations": [],
        "secret_like_key_paths": [],
        "secret_like_value_paths": [],
        "inlined_material_content_paths": [],
    }
    combined = {
        f"payload_{index}": payload for index, payload in enumerate(bundle_payloads)
    }
    result["secret_like_key_paths"] = iter_bundle_secret_like_keys(combined)
    result["secret_like_value_paths"] = iter_secret_like_values(combined)
    bundle_text = json.dumps(combined, sort_keys=True)
    result["inlined_material_content_paths"] = source_contents_inlined(bundle_text, source_paths)

    if result["secret_like_key_paths"]:
        result["violations"].append("secret_like_key_in_generated_bundle")
    if result["secret_like_value_paths"]:
        result["violations"].append("secret_like_value_in_generated_bundle")
    if result["inlined_material_content_paths"]:
        result["violations"].append("outside_git_material_content_inlined")
    if result["violations"]:
        result["status"] = "fail"
    return result


def material_resolution_report(
    wrapper_result: dict[str, Any],
    source_result: dict[str, Any],
    material_result: dict[str, Any],
    non_secret_result: dict[str, Any],
    bundle_written: bool,
) -> dict[str, Any]:
    statuses = {
        "wrapper_preflight_validation": wrapper_result["status"],
        "source_declaration_validation": source_result["status"],
        "material_path_validation": material_result["status"],
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
        "material_resolution_only": True,
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
    write_json(run_dir / "material_resolution_meta.json", material_resolution_meta(run_id))

    wrapper_result, wrapper_data = validate_wrapper_preflight(str(values["wrapper_preflight_run_dir"]))
    source_result, declaration = validate_source_declaration(str(values["source_declaration_file"]))
    material_result, resolved_sources = validate_material_paths(declaration if source_result["status"] == "pass" else None)

    resolved_material_refs = build_resolved_material_refs(resolved_sources)
    wrapper_material_bundle = None
    if wrapper_result["status"] == "pass" and wrapper_data is not None:
        wrapper_material_bundle = build_wrapper_material_bundle(run_id, wrapper_data, resolved_sources)

    source_paths = [item["source_path"] for item in resolved_sources]
    bundle_payloads = [resolved_material_refs, build_input_refs(run_id, wrapper_data)]
    if wrapper_material_bundle is not None:
        bundle_payloads.append(wrapper_material_bundle)
    non_secret_result = validate_non_secret_bundle(bundle_payloads, source_paths)

    bundle_written = False
    if (
        wrapper_result["status"] == "pass"
        and source_result["status"] == "pass"
        and material_result["status"] == "pass"
        and non_secret_result["status"] == "pass"
        and wrapper_material_bundle is not None
    ):
        write_json(run_dir / "resolved_material_refs.json", resolved_material_refs)
        write_json(run_dir / "wrapper_material_bundle.json", wrapper_material_bundle)
        bundle_written = True

    write_json(run_dir / "input_refs.json", build_input_refs(run_id, wrapper_data))
    write_json(checks_dir / "wrapper_preflight_validation.json", wrapper_result)
    write_json(checks_dir / "source_declaration_validation.json", source_result)
    write_json(checks_dir / "material_path_validation.json", material_result)
    write_json(checks_dir / "non_secret_bundle_validation.json", non_secret_result)

    report = material_resolution_report(
        wrapper_result,
        source_result,
        material_result,
        non_secret_result,
        bundle_written,
    )
    exit_code = 0 if report["overall_status"] == "pass" else 1
    write_json(run_dir / "material_resolution_report.json", report)
    write_text(run_dir / "exit_code", f"{exit_code}\n")

    if exit_code == 0:
        print(f"PASS live material resolution: {run_id}")
    else:
        print(f"FAIL live material resolution: {run_id}", file=sys.stderr)
    return exit_code


try:
    raise SystemExit(main())
except MaterialResolutionError as exc:
    print(f"FAIL {exc}", file=sys.stderr)
    usage()
    raise SystemExit(1)
except Exception as exc:
    print(f"FAIL unexpected live material resolution error: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
