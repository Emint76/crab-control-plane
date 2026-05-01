#!/usr/bin/env bash
set -u
set -o pipefail

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="${OPENCLAW_LOCAL_PROOF_PYTHON_BIN:-python}"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="${OPENCLAW_LOCAL_PROOF_PYTHON_BIN:-python3}"
else
  echo "FAIL python runtime not found; set OPENCLAW_LOCAL_PROOF_PYTHON_BIN or install python/python3" >&2
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


class ProofError(Exception):
    pass


repo_root = Path(sys.argv[1]).resolve(strict=True)
args = sys.argv[2:]
proof_root = repo_root / "operations" / "harness-openclaw-local-proof"
runs_root = proof_root / "runs"
steps = [
    ("orchestration-ci", "make orchestration-ci"),
    ("openclaw-dryrun-ci", "make openclaw-dryrun-ci"),
    ("disposable-target-validation-ci", "make disposable-target-validation-ci"),
    ("no-secret-leakage-ci", "make no-secret-leakage-ci"),
    ("controlled-disposable-apply-ci", "make controlled-disposable-apply-ci"),
    ("local-target-selector-ci", "make local-target-selector-ci"),
]
run_id = ""


def fail(message: str) -> None:
    raise ProofError(message)


def usage() -> None:
    print("usage: run_full_local_disposable_cycle.sh --run-id <SAFE_RUN_ID>", file=sys.stderr)


def parse_args() -> None:
    global run_id
    index = 0
    while index < len(args):
        arg = args[index]
        if arg != "--run-id":
            fail(f"unknown argument: {arg}")
        if index + 1 >= len(args):
            fail("missing value for --run-id")
        if run_id:
            fail("duplicate argument: --run-id")
        run_id = args[index + 1]
        index += 2
    if not run_id:
        fail("missing required argument: --run-id")


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


def canonical_run_dir() -> str:
    return f"operations/harness-openclaw-local-proof/runs/{run_id}"


def repo_ref(path: Path) -> str:
    resolved = path.resolve(strict=False)
    try:
        return resolved.relative_to(repo_root).as_posix()
    except ValueError:
        return resolved.as_posix()


def iter_strings(value: Any):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from iter_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from iter_strings(item)


def assert_no_host_specific_text(payload: Any) -> None:
    for text in iter_strings(payload):
        lowered = text.lower()
        if "/mnt/" in text or "/home/" in text or "C:\\" in text:
            fail("host-specific path leaked into proof evidence")
        if "live runtime target" in lowered or "production target" in lowered:
            fail("host-specific live-target wording leaked into proof evidence")


def write_json(path: Path, payload: Any) -> None:
    assert_no_host_specific_text(payload)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_text(path: Path, text: str) -> None:
    if "/mnt/" in text or "/home/" in text or "C:\\" in text:
        fail(f"host-specific path leaked into text evidence: {path.name}")
    if "live runtime target" in text.lower() or "production target" in text.lower():
        fail(f"host-specific live-target wording leaked into text evidence: {path.name}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def verify_run_dir_invariants(run_dir: Path) -> dict[str, Any]:
    violations: list[str] = []
    resolved_runs_root = runs_root.resolve(strict=False)
    resolved_run_dir = run_dir.resolve(strict=False)
    expected_run_dir = (resolved_runs_root / run_id).resolve(strict=False)
    expected_canonical_run_dir = canonical_run_dir()

    try:
        relative = resolved_run_dir.relative_to(resolved_runs_root)
    except ValueError:
        violations.append("run_dir_outside_openclaw_local_proof_runs_root")
        relative = None

    if relative is not None and len(relative.parts) != 1:
        violations.append("run_dir_must_be_direct_child_of_openclaw_local_proof_runs_root")
    if resolved_run_dir.name != run_id:
        violations.append("run_dir_basename_mismatch")
    if resolved_run_dir != expected_run_dir:
        violations.append("run_dir_identity_mismatch")
    if repo_ref(resolved_run_dir) != expected_canonical_run_dir:
        violations.append("canonical_run_dir_repo_ref_mismatch")

    return {
        "status": "fail" if violations else "pass",
        "run_id": run_id,
        "canonical_run_dir": expected_canonical_run_dir,
        "run_dir_identity_verified": not violations,
        "write_surface_verified": not violations,
        "proof_evidence_surface_only": not violations,
        "violations": sorted(set(violations)),
    }


def initial_step_results() -> list[dict[str, Any]]:
    return [
        {
            "name": name,
            "command": command,
            "exit_status": None,
            "status": "not_run",
        }
        for name, command in steps
    ]


def proof_meta(created_at: str) -> dict[str, Any]:
    return {
        "proof_kind": "full-local-disposable-cycle",
        "run_id": run_id,
        "canonical_run_dir": canonical_run_dir(),
        "local_only": True,
        "disposable_only": True,
        "live_runtime_apply": False,
        "crab_approved": False,
        "proof_wrapper_only": True,
        "owns_inner_canonical_evidence": False,
        "creates_live_runtime_wrapper": False,
        "creates_new_openclaw_integration_power": False,
        "broader_local_overlay_reading": False,
        "created_at": created_at,
    }


def proof_report(step_results: list[dict[str, Any]], overall_status: str) -> dict[str, Any]:
    steps_passed = sum(1 for step in step_results if step["exit_status"] == 0)
    steps_failed = sum(
        1
        for step in step_results
        if step["exit_status"] is not None and step["exit_status"] != 0
    )
    steps_not_run = sum(1 for step in step_results if step["exit_status"] is None)
    return {
        "overall_status": overall_status,
        "steps_total": len(step_results),
        "steps_passed": steps_passed,
        "steps_failed": steps_failed,
        "steps_not_run": steps_not_run,
        "local_only": True,
        "disposable_only": True,
        "live_runtime_apply": False,
        "crab_approved": False,
        "proof_wrapper_only": True,
        "owns_inner_canonical_evidence": False,
        "checks": {
            "run_dir_invariants": "pass",
            "step_results": "pass" if steps_not_run == 0 and steps_failed == 0 else "fail",
        },
    }


def proof_report_md(report: dict[str, Any]) -> str:
    return f"""# Full local disposable cycle proof

## Result

- overall_status: `{report["overall_status"]}`
- run_id: `{run_id}`
- steps_total: `{report["steps_total"]}`
- steps_passed: `{report["steps_passed"]}`
- steps_failed: `{report["steps_failed"]}`

## Boundary

- local_only: `true`
- disposable_only: `true`
- live_runtime_apply: `false`
- crab_approved: `false`
- proof_wrapper_only: `true`
- owns_inner_canonical_evidence: `false`
- creates_live_runtime_wrapper: `false`
- creates_new_openclaw_integration_power: `false`
"""


def run_step(command: str) -> int:
    parts = command.split()
    try:
        completed = subprocess.run(parts, cwd=repo_root, check=False)
    except FileNotFoundError:
        return 127
    return int(completed.returncode)


def main() -> int:
    parse_args()
    validate_run_id(run_id)

    run_dir = runs_root / run_id
    checks_dir = run_dir / "checks"
    invariants = verify_run_dir_invariants(run_dir)
    if invariants["status"] != "pass":
        fail(f"run-dir invariant violation: {', '.join(invariants['violations'])}")

    checks_dir.mkdir(parents=True, exist_ok=True)
    created_at = now_utc()
    step_results = initial_step_results()
    write_json(checks_dir / "run_dir_invariants.json", invariants)
    write_json(run_dir / "proof_meta.json", proof_meta(created_at))
    write_json(checks_dir / "step_results.json", step_results)

    exit_code = 0
    for index, (_, command) in enumerate(steps):
        status_code = run_step(command)
        step_results[index]["exit_status"] = status_code
        step_results[index]["status"] = "pass" if status_code == 0 else "fail"
        write_json(checks_dir / "step_results.json", step_results)
        if status_code != 0:
            exit_code = status_code
            break

    overall_status = "pass" if exit_code == 0 else "fail"
    report = proof_report(step_results, overall_status)
    write_json(run_dir / "proof_report.json", report)
    write_text(run_dir / "proof_report.md", proof_report_md(report))
    write_text(run_dir / "exit_code", f"{exit_code}\n")

    if exit_code == 0:
        print(f"PASS full local disposable cycle proof: {run_id}")
    else:
        print(
            f"FAIL full local disposable cycle proof: {run_id} exit_code={exit_code}",
            file=sys.stderr,
        )
    return exit_code


try:
    raise SystemExit(main())
except ProofError as exc:
    print(f"FAIL {exc}", file=sys.stderr)
    usage()
    raise SystemExit(1)
except Exception as exc:
    print(f"FAIL unexpected proof wrapper error: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
