#!/usr/bin/env bash
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRYRUN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${DRYRUN_ROOT}/../.." && pwd)"
PYTHON_BIN="${OPENCLAW_DRYRUN_PYTHON_BIN:-${PHASE3_PYTHON_BIN:-${PHASE2_PYTHON_BIN:-}}}"

usage() {
  cat <<'EOF' >&2
usage: run_openclaw_dry_run.sh --phase3-run-dir <repo-relative Phase 3 run dir> --run-id <SAFE_RUN_ID> [--phase2-run-dir <repo-relative Phase 2 run dir>]
EOF
}

fail() {
  echo "FAIL $*" >&2
  exit "${2:-1}"
}

detect_python() {
  if [[ -n "${PYTHON_BIN}" ]]; then
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set OPENCLAW_DRYRUN_PYTHON_BIN or install python/python3" >&2
    return 1
  fi
}

validate_run_id() {
  local run_id="$1"
  if [[ -z "${run_id}" ]]; then
    echo "invalid run id: empty" >&2
    return 1
  fi
  if [[ "${run_id}" =~ ^[[:space:]] || "${run_id}" =~ [[:space:]]$ ]]; then
    echo "invalid run id: leading or trailing whitespace" >&2
    return 1
  fi
  if [[ "${run_id}" == "." || "${run_id}" == ".." ]]; then
    echo "invalid run id: . and .. are not allowed" >&2
    return 1
  fi
  if [[ "${run_id}" == /* || "${run_id}" =~ ^[A-Za-z]:[\\/] ]]; then
    echo "invalid run id: absolute paths are not allowed" >&2
    return 1
  fi
  if [[ "${run_id}" == *"/"* || "${run_id}" == *"\\"* ]]; then
    echo "invalid run id: traversal and path separators are not allowed" >&2
    return 1
  fi
  if [[ ! "${run_id}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "invalid run id: must match ^[A-Za-z0-9._-]+$" >&2
    return 1
  fi
}

PHASE3_RUN_DIR=""
PHASE2_RUN_DIR=""
RUN_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase3-run-dir)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      PHASE3_RUN_DIR="$2"
      shift 2
      ;;
    --phase2-run-dir)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      PHASE2_RUN_DIR="$2"
      shift 2
      ;;
    --run-id)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      RUN_ID="$2"
      shift 2
      ;;
    *)
      echo "FAIL unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

[[ -n "${PHASE3_RUN_DIR}" ]] || { echo "FAIL missing --phase3-run-dir" >&2; usage; exit 2; }
[[ -n "${RUN_ID}" ]] || { echo "FAIL missing --run-id" >&2; usage; exit 2; }

validate_run_id "${RUN_ID}" || fail "invalid --run-id: ${RUN_ID}" 2
detect_python || exit 1
[[ -d "${REPO_ROOT}" ]] || fail "missing repo root"

cd "${REPO_ROOT}" || fail "missing repo root"

"${PYTHON_BIN}" - "${REPO_ROOT}" "${RUN_ID}" "${PHASE3_RUN_DIR}" "${PHASE2_RUN_DIR}" <<'PY'
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any


class AdapterError(Exception):
    pass


repo_root = Path(sys.argv[1]).resolve(strict=False)
run_id = sys.argv[2]
phase3_run_dir_text = sys.argv[3]
phase2_run_dir_text = sys.argv[4]
dryrun_root = repo_root / "operations" / "harness-openclaw-dryrun"
runs_root = dryrun_root / "runs"
run_dir = runs_root / run_id
checks_dir = run_dir / "checks"
canonical_run_dir = f"operations/harness-openclaw-dryrun/runs/{run_id}"
schema_ref = "operations/harness-openclaw-dryrun/schemas/proposed_openclaw_placement_plan.schema.json"
schema_path = repo_root / schema_ref
proposed_plan_ref = f"{canonical_run_dir}/proposed_openclaw_placement_plan.json"
run_dir_created = False


def fail(message: str) -> None:
    raise AdapterError(message)


def repo_ref(path: Path) -> str:
    resolved = path.resolve(strict=False)
    try:
        return resolved.relative_to(repo_root).as_posix()
    except ValueError:
        fail(f"path escapes repository: {path}")


def is_host_specific(value: str) -> bool:
    if value.startswith("/"):
        return True
    if re.match(r"^[A-Za-z]:[\\/]", value):
        return True
    if "\\" in value:
        return True
    return any(token in value for token in ("/mnt/", "/home/"))


def iter_strings(value: Any):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from iter_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from iter_strings(item)


def assert_no_host_paths(payload: dict[str, Any]) -> None:
    leaked = sorted({value for value in iter_strings(payload) if is_host_specific(value)})
    if leaked:
        fail(f"host-specific path leaked into evidence: {leaked[0]}")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    assert_no_host_paths(payload)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def write_text(path: Path, text: str) -> None:
    if any(token in text for token in ("/mnt/", "/home/", "C:\\")):
        fail(f"host-specific path leaked into text evidence: {path.name}")
    path.write_text(text, encoding="utf-8")


def validate_repo_relative_input(path_text: str, label: str, root_rel: str) -> tuple[Path, str]:
    if not path_text:
        fail(f"{label} is required")
    if path_text != path_text.strip():
        fail(f"{label} must not have leading or trailing whitespace")
    if "\\" in path_text:
        fail(f"{label} must use repo-relative POSIX paths")
    if path_text.startswith("/") or re.match(r"^[A-Za-z]:[\\/]", path_text):
        fail(f"{label} must be repo-relative")

    pure_path = PurePosixPath(path_text)
    if ".." in pure_path.parts:
        fail(f"{label} must not contain ../ traversal")

    candidate = (repo_root / Path(*pure_path.parts)).resolve(strict=False)
    root = (repo_root / root_rel).resolve(strict=False)
    try:
        relative = candidate.relative_to(root)
    except ValueError:
        fail(f"{label} must be under {root_rel}/")
    if len(relative.parts) != 1:
        fail(f"{label} must identify one direct run directory under {root_rel}/")
    if not candidate.exists():
        fail(f"{label} does not exist: {path_text}")
    if not candidate.is_dir():
        fail(f"{label} must be a directory: {path_text}")

    return candidate, repo_ref(candidate)


def load_json(path: Path, label: str) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"unable to read {label}: {exc}")
    if not isinstance(payload, dict):
        fail(f"{label} must contain a JSON object")
    return payload


def verify_run_dir_invariants() -> dict[str, Any]:
    violations: list[str] = []
    resolved_runs_root = runs_root.resolve(strict=False)
    resolved_run_dir = run_dir.resolve(strict=False)
    expected_run_dir = (resolved_runs_root / run_id).resolve(strict=False)

    try:
        relative = resolved_run_dir.relative_to(resolved_runs_root)
    except ValueError:
        violations.append("run_dir_outside_openclaw_dryrun_runs_root")
        relative = None

    if relative is not None and len(relative.parts) != 1:
        violations.append("run_dir_must_be_direct_child_of_openclaw_dryrun_runs_root")
    if resolved_run_dir.name != run_id:
        violations.append("run_dir_basename_mismatch")
    if resolved_run_dir != expected_run_dir:
        violations.append("run_dir_identity_mismatch")
    if repo_ref(resolved_run_dir) != canonical_run_dir:
        violations.append("canonical_run_dir_repo_ref_mismatch")

    payload = {
        "status": "fail" if violations else "pass",
        "run_id": run_id,
        "canonical_run_dir": canonical_run_dir,
        "run_dir_identity_verified": not violations,
        "write_surface_verified": not violations,
        "violations": sorted(set(violations)),
    }
    if violations:
        fail(f"run-dir invariant violation: {', '.join(payload['violations'])}")
    return payload


def proposed_writes_for(phase3_ref: str, staging_dir: Path, staging_ref: str) -> list[dict[str, str]]:
    proposed: list[dict[str, str]] = []
    if not staging_dir.exists():
        return proposed
    for source_path in sorted(path for path in staging_dir.rglob("*") if path.is_file()):
        relative_source = source_path.relative_to(staging_dir).as_posix()
        proposed.append(
            {
                "source": f"{staging_ref}/{relative_source}",
                "target": f"declared-openclaw-target:{relative_source}",
                "write_mode": "proposed-only",
                "reason": "dry-run placement proposal derived from Phase 3 staging output",
            }
        )
    return proposed


def validate_proposed_plan_schema(proposed_plan: dict[str, Any]) -> dict[str, Any]:
    try:
        import jsonschema
    except ImportError:
        fail("jsonschema is required; install operations/harness-phase2/requirements.txt")

    schema = load_json(schema_path, "proposed placement plan schema")
    try:
        jsonschema.Draft202012Validator.check_schema(schema)
    except jsonschema.exceptions.SchemaError as exc:
        fail(f"proposed placement plan schema is invalid: {exc.message}")

    validator = jsonschema.Draft202012Validator(schema)
    violations = sorted(error.message for error in validator.iter_errors(proposed_plan))
    payload = {
        "status": "fail" if violations else "pass",
        "schema": schema_ref,
        "validated_file": proposed_plan_ref,
        "violations": violations,
    }
    if violations:
        write_json(checks_dir / "proposed_plan_schema_validation.json", payload)
        fail("proposed placement plan schema validation failed")
    return payload


def main() -> int:
    global run_dir_created

    phase3_run_dir, phase3_ref = validate_repo_relative_input(
        phase3_run_dir_text,
        "--phase3-run-dir",
        "operations/harness-phase3/runs",
    )
    phase3_report_path = phase3_run_dir / "report.json"
    phase3_staging_dir = phase3_run_dir / "staging" / "runtime-ready-applied"
    if not phase3_report_path.is_file():
        fail("Phase 3 run dir must contain report.json")
    if not phase3_staging_dir.is_dir():
        fail("Phase 3 run dir must contain staging/runtime-ready-applied/")
    phase3_report = load_json(phase3_report_path, "Phase 3 report.json")
    if phase3_report.get("overall_status") != "pass":
        fail("Phase 3 report overall_status must be pass")

    phase2_run_dir = None
    phase2_ref = None
    phase2_handoff_ref = None
    phase2_verified: bool | None = None
    if phase2_run_dir_text:
        phase2_run_dir, phase2_ref = validate_repo_relative_input(
            phase2_run_dir_text,
            "--phase2-run-dir",
            "operations/harness-phase2/runs",
        )
        phase2_handoff = phase2_run_dir / "handoff_ready.json"
        if not phase2_handoff.is_file():
            fail("Phase 2 run dir must contain handoff_ready.json")
        phase2_handoff_ref = repo_ref(phase2_handoff)
        phase2_verified = True

    run_dir_invariants = verify_run_dir_invariants()
    checks_dir.mkdir(parents=True, exist_ok=True)
    run_dir_created = True

    phase3_report_ref = repo_ref(phase3_report_path)
    phase3_staging_ref = repo_ref(phase3_staging_dir)
    created_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    proposed_writes = proposed_writes_for(phase3_ref, phase3_staging_dir, phase3_staging_ref)

    adapter_meta = {
        "profile": "openclaw-dry-run-adapter",
        "run_id": run_id,
        "phase3_run_dir": phase3_ref,
        "phase2_run_dir": phase2_ref,
        "canonical_run_dir": canonical_run_dir,
        "dry_run_only": True,
        "live_writes_performed": False,
        "openclaw_runtime_mutation": False,
        "deploy_or_migration": False,
        "real_kb_write_back": False,
        "secrets_required": False,
        "created_at": created_at,
    }
    input_refs = {
        "phase3_run_dir": phase3_ref,
        "phase3_report": phase3_report_ref,
        "phase3_runtime_ready_applied": phase3_staging_ref,
        "phase2_run_dir": phase2_ref,
        "phase2_handoff_ready": phase2_handoff_ref,
    }
    proposed_plan = {
        "status": "dry-run",
        "target_runtime": "openclaw",
        "source_phase3_run_dir": phase3_ref,
        "proposed_writes": proposed_writes,
        "live_writes_performed": False,
    }
    proposed_plan_path = run_dir / "proposed_openclaw_placement_plan.json"
    write_json(proposed_plan_path, proposed_plan)
    proposed_plan_schema_validation = validate_proposed_plan_schema(proposed_plan)
    input_refs_validation = {
        "status": "pass",
        "phase3_run_dir_verified": True,
        "phase3_report_pass": True,
        "phase2_run_dir_verified": phase2_verified,
        "violations": [],
    }
    no_live_write_validation = {
        "status": "pass",
        "live_writes_performed": False,
        "openclaw_runtime_mutation": False,
        "deploy_or_migration": False,
        "real_kb_write_back": False,
        "secrets_read": False,
        "violations": [],
    }
    dry_run_report = {
        "overall_status": "pass",
        "dry_run_only": True,
        "live_writes_performed": False,
        "proposed_write_count": len(proposed_writes),
        "checks": {
            "run_dir_invariants": "pass",
            "input_refs_validation": "pass",
            "no_live_write_validation": "pass",
            "proposed_plan_schema_validation": "pass",
        },
    }
    dry_run_report_md = f"""# OpenClaw dry-run adapter report

## Result

- overall_status: `pass`
- run_id: `{run_id}`
- proposed_write_count: `{len(proposed_writes)}`

## Boundary statement

No live OpenClaw writes were performed.
No secrets were read.
No deploy or migration was performed.
No real KB write-back was performed.
"""

    write_json(run_dir / "adapter_meta.json", adapter_meta)
    write_json(run_dir / "input_refs.json", input_refs)
    write_json(run_dir / "dry_run_report.json", dry_run_report)
    write_json(checks_dir / "run_dir_invariants.json", run_dir_invariants)
    write_json(checks_dir / "input_refs_validation.json", input_refs_validation)
    write_json(checks_dir / "no_live_write_validation.json", no_live_write_validation)
    write_json(checks_dir / "proposed_plan_schema_validation.json", proposed_plan_schema_validation)
    write_text(run_dir / "dry_run_report.md", dry_run_report_md)
    write_text(run_dir / "exit_code", "0\n")

    print(f"PASS OpenClaw dry-run adapter skeleton: {run_id}")
    return 0


try:
    raise SystemExit(main())
except AdapterError as exc:
    print(f"FAIL {exc}", file=sys.stderr)
    if run_dir_created:
        try:
            write_text(run_dir / "exit_code", "1\n")
        except Exception:
            pass
    raise SystemExit(1)
PY
