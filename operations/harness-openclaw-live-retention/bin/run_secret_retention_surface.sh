#!/usr/bin/env bash
set -u
set -o pipefail

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_RETENTION_PYTHON_BIN:-python}"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="${LIVE_RETENTION_PYTHON_BIN:-python3}"
else
  echo "FAIL python runtime not found; set LIVE_RETENTION_PYTHON_BIN or install python/python3" >&2
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


class RetentionCliError(Exception):
    pass


repo_root = Path(sys.argv[1]).resolve(strict=True)
args = sys.argv[2:]
surface_root = repo_root / "operations" / "harness-openclaw-live-retention"
runs_root = surface_root / "runs"
schema_path = surface_root / "schemas" / "secret_material_source_declaration.schema.json"

allowed_args = {
    "--source-declaration-file": "source_declaration_file",
    "--candidate-evidence-dir": "candidate_evidence_dir",
    "--run-id": "run_id",
}
values: dict[str, str | None] = {value: None for value in allowed_args.values()}
allowed_suffixes = {".json", ".md", ".log", ".txt"}
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
allowed_declaration_key = "contains_raw_secrets"


def fail(message: str) -> None:
    raise RetentionCliError(message)


def usage() -> None:
    print(
        "usage: run_secret_retention_surface.sh "
        "--source-declaration-file <ABSOLUTE_PATH_OUTSIDE_GIT> "
        "--candidate-evidence-dir <ABSOLUTE_PATH_OUTSIDE_GIT> "
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
    return f"operations/harness-openclaw-live-retention/runs/{run_id}"


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


def secret_key_match(key: str, *, declaration_mode: bool = False) -> bool:
    if declaration_mode and key == allowed_declaration_key:
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


def iter_forbidden_key_paths(value: Any, prefix: str = "") -> list[str]:
    violations: list[str] = []
    if isinstance(value, dict):
        for key, item in value.items():
            key_text = str(key)
            child_prefix = f"{prefix}.{key_text}" if prefix else key_text
            if secret_key_match(key_text, declaration_mode=True):
                violations.append(child_prefix)
            violations.extend(iter_forbidden_key_paths(item, child_prefix))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            violations.extend(iter_forbidden_key_paths(item, f"{prefix}[{index}]"))
    return violations


def validate_input_path(raw: str, *, kind: str) -> tuple[Path | None, list[str], dict[str, Any]]:
    violations: list[str] = []
    item = {
        "provided": bool(raw),
        "absolute_path": False,
        "exists": False,
        "file": False,
        "directory": False,
        "outside_repo": False,
        "git_tracked_repo_path": False,
    }

    if raw == "" or raw != raw.strip():
        violations.append(f"{kind}_path_empty_or_whitespace")
        return None, violations, item

    path = Path(raw)
    item["absolute_path"] = path.is_absolute()
    if not item["absolute_path"]:
        violations.append(f"{kind}_path_not_absolute")
        return None, violations, item

    try:
        resolved = path.resolve(strict=True)
    except OSError:
        violations.append(f"{kind}_path_missing")
        return None, violations, item

    item["exists"] = True
    item["file"] = resolved.is_file()
    item["directory"] = resolved.is_dir()
    item["outside_repo"] = not path_is_inside_repo(resolved)
    item["git_tracked_repo_path"] = path_is_inside_repo(resolved)

    if not item["outside_repo"]:
        violations.append(f"{kind}_path_inside_repo")
    if kind == "source_declaration" and not item["file"]:
        violations.append(f"{kind}_path_not_file")
    if kind == "candidate_evidence" and not item["directory"]:
        violations.append(f"{kind}_path_not_directory")

    if violations:
        return None, violations, item
    return resolved, violations, item


def validate_source_declaration(raw_path: str) -> tuple[dict[str, Any], Any | None]:
    result: dict[str, Any] = {
        "status": "pass",
        "validation_only": False,
        "live_runtime_apply": False,
        "retention_only": True,
        "input_file": {},
        "schema": {"status": "not_run", "violations": []},
        "forbidden_key_paths": [],
        "source_path_checks": [],
        "violations": [],
    }

    declaration_path, path_violations, path_item = validate_input_path(
        raw_path, kind="source_declaration"
    )
    result["input_file"] = path_item
    result["violations"].extend(path_violations)
    if declaration_path is None:
        result["status"] = "fail"
        return result, None

    payload, error = load_json_file(declaration_path)
    if error is not None:
        result["status"] = "fail"
        result["violations"].append("source_declaration_json_unreadable")
        result["schema"] = {"status": "fail", "violations": [error]}
        return result, None

    try:
        import jsonschema
    except ImportError:
        result["status"] = "fail"
        result["schema"] = {
            "status": "fail",
            "violations": [
                "jsonschema is required; install operations/harness-phase2/requirements.txt"
            ],
        }
        return result, payload

    schema = json.loads(schema_path.read_text(encoding="utf-8-sig"))
    jsonschema.Draft202012Validator.check_schema(schema)
    validator = jsonschema.Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(payload), key=lambda error: list(error.path))
    schema_violations = []
    for error in errors:
        location = "/".join(str(part) for part in error.path) or "<root>"
        schema_violations.append(f"{location}: {error.message}")
    result["schema"] = {
        "status": "fail" if schema_violations else "pass",
        "violations": schema_violations,
    }
    result["violations"].extend(f"schema:{item}" for item in schema_violations)

    result["forbidden_key_paths"] = iter_forbidden_key_paths(payload)
    if result["forbidden_key_paths"]:
        result["violations"].append("forbidden_secret_like_key_in_declaration")

    if isinstance(payload, dict) and isinstance(payload.get("sources"), list):
        for index, source in enumerate(payload["sources"]):
            check = {
                "index": index,
                "source_label": source.get("source_label") if isinstance(source, dict) else None,
                "absolute_path": False,
                "outside_repo": False,
                "status": "fail",
            }
            raw_source_path = source.get("source_path") if isinstance(source, dict) else None
            if isinstance(raw_source_path, str):
                source_path = Path(raw_source_path)
                check["absolute_path"] = source_path.is_absolute()
                if check["absolute_path"]:
                    resolved = source_path.resolve(strict=False)
                    check["outside_repo"] = not path_is_inside_repo(resolved)
            if check["absolute_path"] and check["outside_repo"]:
                check["status"] = "pass"
            else:
                result["violations"].append(f"source_path_{index}_invalid_or_inside_repo")
            result["source_path_checks"].append(check)

    if result["violations"]:
        result["status"] = "fail"
    return result, payload


def validate_candidate_evidence(raw_path: str) -> tuple[dict[str, Any], Path | None, list[Path]]:
    result: dict[str, Any] = {
        "status": "pass",
        "validation_only": False,
        "live_runtime_apply": False,
        "retention_only": True,
        "input_dir": {},
        "allowed_extensions": sorted(allowed_suffixes),
        "files": [],
        "violations": [],
    }
    candidate_dir, path_violations, path_item = validate_input_path(
        raw_path, kind="candidate_evidence"
    )
    result["input_dir"] = path_item
    result["violations"].extend(path_violations)
    if candidate_dir is None:
        result["status"] = "fail"
        return result, None, []

    files: list[Path] = []
    for path in sorted(candidate_dir.rglob("*")):
        if path.is_dir():
            continue
        rel = path.relative_to(candidate_dir).as_posix()
        item = {
            "relative_path": rel,
            "extension": path.suffix,
            "status": "pass",
        }
        if path.is_symlink():
            item["status"] = "fail"
            result["violations"].append(f"symlink_not_allowed:{rel}")
        elif path.suffix not in allowed_suffixes:
            item["status"] = "fail"
            result["violations"].append(f"forbidden_extension:{rel}")
        else:
            files.append(path)
        result["files"].append(item)

    if result["violations"]:
        result["status"] = "fail"
    return result, candidate_dir, files


def redact_json_value(value: Any) -> Any:
    if isinstance(value, dict):
        redacted: dict[str, Any] = {}
        for key, item in value.items():
            if secret_key_match(str(key)):
                redacted[key] = "[REDACTED]"
            else:
                redacted[key] = redact_json_value(item)
        return redacted
    if isinstance(value, list):
        return [redact_json_value(item) for item in value]
    return value


assignment_term = r"(?:secret|token|pass(?:word)?|api[_-]?key|apikey|oauth|credential|private[_-]?key|session[_-]?cookie)"
assignment_pattern = re.compile(
    rf"(?i)\b{assignment_term}\b\s*[:=]\s*(?!\[REDACTED\])[^ \t\r\n,;]+"
)
bearer_pattern = re.compile(
    r"(?i)authorization\s*:\s*bearer\s+(?!\[REDACTED\])[^ \t\r\n]+"
)


def redact_text(text: str) -> str:
    redacted = assignment_pattern.sub("[REDACTED]", text)
    redacted = bearer_pattern.sub("[REDACTED]", redacted)
    return redacted


def residual_secret_like_patterns(text: str) -> list[str]:
    findings = []
    for pattern_name, pattern in (
        ("assignment", assignment_pattern),
        ("bearer", bearer_pattern),
    ):
        for match in pattern.finditer(text):
            findings.append(f"{pattern_name}:{match.group(0)[:80]}")
    return findings


def retain_redacted_files(candidate_dir: Path, files: list[Path], retained_dir: Path) -> dict[str, Any]:
    result: dict[str, Any] = {
        "status": "pass",
        "validation_only": False,
        "live_runtime_apply": False,
        "retention_only": True,
        "redaction_applied": True,
        "retained_files": [],
        "retained_file_count": 0,
        "violations": [],
    }

    if retained_dir.exists():
        shutil.rmtree(retained_dir)
    retained_dir.mkdir(parents=True, exist_ok=True)

    for source_path in files:
        rel = source_path.relative_to(candidate_dir)
        rel_posix = rel.as_posix()
        target_path = retained_dir / rel
        try:
            if source_path.suffix == ".json":
                payload = json.loads(source_path.read_text(encoding="utf-8-sig"))
                redacted_payload = redact_json_value(payload)
                rendered = json.dumps(redacted_payload, indent=2, sort_keys=True) + "\n"
            else:
                rendered = redact_text(source_path.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError, UnicodeError) as exc:
            result["violations"].append(f"redaction_read_failed:{rel_posix}:{exc}")
            continue

        residuals = residual_secret_like_patterns(rendered)
        if residuals:
            result["violations"].append(f"residual_secret_like_pattern:{rel_posix}")
            result["retained_files"].append(
                {
                    "relative_path": rel_posix,
                    "status": "fail",
                    "residuals": residuals,
                }
            )
            continue

        target_path.parent.mkdir(parents=True, exist_ok=True)
        target_path.write_text(rendered, encoding="utf-8")
        result["retained_files"].append(
            {
                "relative_path": rel_posix,
                "status": "pass",
                "redacted_copy": f"retained/{rel_posix}",
            }
        )

    result["retained_file_count"] = sum(
        1 for item in result["retained_files"] if item["status"] == "pass"
    )
    if result["violations"]:
        result["status"] = "fail"
    return result


def retention_meta(run_id: str) -> dict[str, Any]:
    return {
        "surface_kind": "live-secret-retention",
        "run_id": run_id,
        "canonical_run_dir": canonical_run_dir(run_id),
        "validation_only": False,
        "live_runtime_apply": False,
        "live_wrapper": False,
        "crab_approved": False,
        "retention_only": True,
        "redaction_applied": True,
        "real_secret_loading": False,
        "local_overlay_reading": False,
        "approval_execution": False,
        "rollback_execution": False,
        "created_at": now_utc(),
    }


def retention_report(
    source_result: dict[str, Any],
    candidate_result: dict[str, Any],
    redaction_result: dict[str, Any],
) -> dict[str, Any]:
    statuses = {
        "source_declaration_validation": source_result["status"],
        "candidate_evidence_validation": candidate_result["status"],
        "redaction_validation": redaction_result["status"],
    }
    overall_status = "pass" if all(value == "pass" for value in statuses.values()) else "fail"
    return {
        "overall_status": overall_status,
        **statuses,
        "retained_file_count": redaction_result.get("retained_file_count", 0),
        "validation_only": False,
        "live_runtime_apply": False,
        "live_wrapper": False,
        "crab_approved": False,
        "retention_only": True,
        "redaction_applied": True,
    }


def main() -> int:
    parse_args()
    run_id = str(values["run_id"])
    validate_run_id(run_id)

    run_dir = runs_root / run_id
    checks_dir = run_dir / "checks"
    retained_dir = run_dir / "retained"
    checks_dir.mkdir(parents=True, exist_ok=True)
    write_json(run_dir / "retention_meta.json", retention_meta(run_id))

    source_result, _payload = validate_source_declaration(str(values["source_declaration_file"]))
    candidate_result, candidate_dir, candidate_files = validate_candidate_evidence(
        str(values["candidate_evidence_dir"])
    )

    if source_result["status"] == "pass" and candidate_result["status"] == "pass" and candidate_dir:
        redaction_result = retain_redacted_files(candidate_dir, candidate_files, retained_dir)
    else:
        retained_dir.mkdir(parents=True, exist_ok=True)
        redaction_result = {
            "status": "fail",
            "validation_only": False,
            "live_runtime_apply": False,
            "retention_only": True,
            "redaction_applied": False,
            "retained_files": [],
            "retained_file_count": 0,
            "violations": ["skipped_due_to_failed_input_validation"],
        }

    report = retention_report(source_result, candidate_result, redaction_result)
    exit_code = 0 if report["overall_status"] == "pass" else 1

    write_json(checks_dir / "source_declaration_validation.json", source_result)
    write_json(checks_dir / "candidate_evidence_validation.json", candidate_result)
    write_json(checks_dir / "redaction_validation.json", redaction_result)
    write_json(run_dir / "retention_report.json", report)
    write_text(run_dir / "exit_code", f"{exit_code}\n")

    if exit_code == 0:
        print(f"PASS live secret retention surface: {run_id}")
    else:
        print(f"FAIL live secret retention surface: {run_id}", file=sys.stderr)
    return exit_code


try:
    raise SystemExit(main())
except RetentionCliError as exc:
    print(f"FAIL {exc}", file=sys.stderr)
    usage()
    raise SystemExit(1)
except Exception as exc:
    print(f"FAIL unexpected live secret retention error: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
