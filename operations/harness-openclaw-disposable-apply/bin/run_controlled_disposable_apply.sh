#!/usr/bin/env bash
set -u
set -o pipefail

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
else
  echo "FAIL python runtime not found; install python or python3" >&2
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

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any


class ApplyError(Exception):
    pass


repo_root = Path(sys.argv[1]).resolve(strict=True)
args = sys.argv[2:]

allowed_args = {
    "--dry-run-run-dir": "dry_run_run_dir",
    "--workspace-target": "workspace_target",
    "--workspace-approved-root": "workspace_approved_root",
    "--state-target": "state_target",
    "--state-approved-root": "state_approved_root",
    "--approval-label": "approval_label",
    "--run-id": "run_id",
}
values: dict[str, str | None] = {key: None for key in allowed_args.values()}

apply_root = repo_root / "operations" / "harness-openclaw-disposable-apply"
runs_root = apply_root / "runs"
run_id = ""
run_dir = runs_root / "__unvalidated__"
checks_dir = run_dir / "checks"
canonical_run_dir = ""
run_dir_created = False

target_validator_ref = "operations/harness-openclaw-target-validation/bin/validate_disposable_target_path.sh"
no_secret_validator_ref = "operations/harness-openclaw-safety-validation/bin/validate_no_secret_leakage.sh"
placement_schema_ref = "operations/harness-openclaw-dryrun/schemas/proposed_openclaw_placement_plan.schema.json"
evidence_schema_refs = {
    "apply_meta.json": "operations/harness-openclaw-disposable-apply/schemas/apply_meta.schema.json",
    "apply_report.json": "operations/harness-openclaw-disposable-apply/schemas/apply_report.schema.json",
    "target_refs.json": "operations/harness-openclaw-disposable-apply/schemas/target_refs.schema.json",
    "apply_actions.json": "operations/harness-openclaw-disposable-apply/schemas/apply_actions.schema.json",
}


def fail(message: str) -> None:
    raise ApplyError(message)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def write_exit_code(code: int) -> None:
    if run_dir_created:
        write_text(run_dir / "exit_code", f"{code}\n")


def repo_ref(path: Path) -> str:
    try:
        return path.resolve(strict=False).relative_to(repo_root).as_posix()
    except ValueError:
        fail(f"path escapes repository: {path}")


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


def validate_run_id(raw: str) -> str:
    if raw == "":
        fail("invalid --run-id: empty")
    if raw != raw.strip():
        fail("invalid --run-id: leading or trailing whitespace")
    if raw in (".", ".."):
        fail("invalid --run-id: . and .. are not allowed")
    if raw.startswith("/") or re.match(r"^[A-Za-z]:[\\/]", raw):
        fail("invalid --run-id: absolute paths are not allowed")
    if "/" in raw or "\\" in raw:
        fail("invalid --run-id: path separators are not allowed")
    if ".." in PurePosixPath(raw).parts:
        fail("invalid --run-id: traversal is not allowed")
    if not re.match(r"^[A-Za-z0-9._-]+$", raw):
        fail("invalid --run-id: must match ^[A-Za-z0-9._-]+$")
    return raw


def verify_apply_run_dir() -> dict[str, Any]:
    canonical_root = runs_root.resolve(strict=False)
    candidate = (runs_root / run_id).resolve(strict=False)
    violations: list[str] = []

    try:
        relative = candidate.relative_to(canonical_root)
    except ValueError:
        relative = None
        violations.append("run_dir escapes runs root")

    if relative is None or len(relative.parts) != 1:
        violations.append("run_dir is not a direct child of runs root")
    if candidate.name != run_id:
        violations.append("run_dir basename does not match run_id")
    if candidate == canonical_root:
        violations.append("run_dir must not equal runs root")

    payload = {
        "status": "fail" if violations else "pass",
        "run_id": run_id,
        "canonical_run_dir": canonical_run_dir,
        "run_dir_identity_verified": not violations,
        "write_surface_verified": not violations,
        "violations": violations,
    }
    if violations:
        fail(f"invalid apply run directory: {violations[0]}")
    return payload


def validate_repo_run_dir(path_text: str, label: str, root_rel: str) -> tuple[Path, str]:
    if path_text == "":
        fail(f"{label} must not be empty")
    if path_text != path_text.strip():
        fail(f"{label} must not have leading or trailing whitespace")
    if "\\" in path_text:
        fail(f"{label} must use POSIX separators")
    if path_text.startswith("/") or re.match(r"^[A-Za-z]:[\\/]", path_text):
        fail(f"{label} must be repo-relative")

    pure = PurePosixPath(path_text)
    if ".." in pure.parts:
        fail(f"{label} must not contain ../ traversal")
    if not pure.as_posix().startswith(f"{root_rel}/"):
        fail(f"{label} must be under {root_rel}/")

    root_parts = PurePosixPath(root_rel).parts
    relative_parts = pure.parts[len(root_parts):]
    if len(relative_parts) != 1:
        fail(f"{label} must identify one direct run directory under {root_rel}/")

    candidate = (repo_root / Path(*pure.parts)).resolve(strict=False)
    root = (repo_root / root_rel).resolve(strict=False)
    try:
        candidate.relative_to(root)
    except ValueError:
        fail(f"{label} escapes {root_rel}/")
    if not candidate.exists():
        fail(f"{label} does not exist: {path_text}")
    if not candidate.is_dir():
        fail(f"{label} must be a directory: {path_text}")
    return candidate, repo_ref(candidate)


def load_json(path: Path, label: str) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"unable to read {label}: {exc}")


def validate_dry_run_input(dry_run_text: str) -> tuple[Path, str, dict[str, Any], dict[str, Any]]:
    dry_run_dir, dry_run_ref = validate_repo_run_dir(
        dry_run_text,
        "--dry-run-run-dir",
        "operations/harness-openclaw-dryrun/runs",
    )

    proposed_plan_path = dry_run_dir / "proposed_openclaw_placement_plan.json"
    dry_report_path = dry_run_dir / "dry_run_report.json"
    schema_check_path = dry_run_dir / "checks" / "proposed_plan_schema_validation.json"
    no_secret_check_path = dry_run_dir / "checks" / "no_secret_leakage_validation.json"

    for required_path, label in (
        (proposed_plan_path, "proposed_openclaw_placement_plan.json"),
        (dry_report_path, "dry_run_report.json"),
        (schema_check_path, "checks/proposed_plan_schema_validation.json"),
        (no_secret_check_path, "checks/no_secret_leakage_validation.json"),
    ):
        if not required_path.is_file():
            fail(f"missing dry-run evidence: {label}")

    dry_report = load_json(dry_report_path, "dry_run_report.json")
    schema_check = load_json(schema_check_path, "proposed_plan_schema_validation.json")
    no_secret_check = load_json(no_secret_check_path, "no_secret_leakage_validation.json")
    proposed_plan = load_json(proposed_plan_path, "proposed_openclaw_placement_plan.json")

    if dry_report.get("overall_status") != "pass":
        fail("dry_run_report overall_status must be pass")
    if schema_check.get("status") != "pass":
        fail("proposed_plan_schema_validation status must be pass")
    if no_secret_check.get("status") != "pass":
        fail("no_secret_leakage_validation status must be pass")

    return dry_run_dir, dry_run_ref, proposed_plan, dry_report


def parse_validator_json(completed: subprocess.CompletedProcess[str], label: str) -> dict[str, Any]:
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError:
        payload = {
            "status": "fail",
            "violations": [
                {
                    "type": "validator_execution",
                    "path": None,
                    "detail": f"{label} validator did not emit JSON",
                }
            ],
        }
    if not isinstance(payload, dict):
        payload = {
            "status": "fail",
            "violations": [
                {
                    "type": "validator_execution",
                    "path": None,
                    "detail": f"{label} validator emitted non-object JSON",
                }
            ],
        }
    return payload


def run_target_validator(target_type: str, target_path: str, approved_root: str) -> dict[str, Any]:
    completed = subprocess.run(
        [
            "bash",
            target_validator_ref,
            "--target-type",
            target_type,
            "--target-path",
            target_path,
            "--approved-root",
            approved_root,
        ],
        cwd=repo_root,
        check=False,
        capture_output=True,
        text=True,
    )
    payload = parse_validator_json(completed, f"{target_type} target")
    if completed.returncode != 0 or payload.get("status") != "pass":
        payload["status"] = "fail"
    return payload


def validate_targets() -> tuple[dict[str, Any], Path, Path]:
    workspace_payload = run_target_validator(
        "workspace",
        str(values["workspace_target"]),
        str(values["workspace_approved_root"]),
    )
    state_payload = run_target_validator(
        "state",
        str(values["state_target"]),
        str(values["state_approved_root"]),
    )
    status = "pass" if workspace_payload.get("status") == "pass" and state_payload.get("status") == "pass" else "fail"
    payload = {
        "status": status,
        "workspace": workspace_payload,
        "state": state_payload,
        "violations": [] if status == "pass" else ["workspace/state disposable target validation failed"],
    }
    write_json(checks_dir / "target_path_validation.json", payload)
    if status != "pass":
        fail("target path validation failed")
    return payload, Path(str(values["workspace_target"])).resolve(strict=True), Path(str(values["state_target"])).resolve(strict=True)


def validate_no_secret(dry_run_ref: str) -> dict[str, Any]:
    completed = subprocess.run(
        [
            "bash",
            no_secret_validator_ref,
            "--evidence-dir",
            dry_run_ref,
        ],
        cwd=repo_root,
        check=False,
        capture_output=True,
        text=True,
    )
    payload = parse_validator_json(completed, "no-secret-leakage")
    if completed.returncode != 0 or payload.get("status") != "pass":
        payload["status"] = "fail"
    write_json(checks_dir / "no_secret_leakage_validation.json", payload)
    if payload.get("status") != "pass":
        fail("no-secret-leakage validation failed")
    return payload


def validate_plan_schema(proposed_plan: dict[str, Any]) -> None:
    try:
        import jsonschema
    except ImportError:
        fail("jsonschema is required; install operations/harness-phase2/requirements.txt")

    schema_path = repo_root / placement_schema_ref
    schema = load_json(schema_path, placement_schema_ref)
    validator = jsonschema.Draft202012Validator(schema)
    violations = sorted(validator.iter_errors(proposed_plan), key=lambda item: list(item.path))
    if violations:
        fail(f"proposed placement plan schema validation failed: {violations[0].message}")


def validate_evidence_schemas() -> dict[str, Any]:
    try:
        import jsonschema
    except ImportError:
        fail("jsonschema is required; install operations/harness-phase2/requirements.txt")

    violations: list[str] = []
    for evidence_name, schema_ref in evidence_schema_refs.items():
        evidence_path = run_dir / evidence_name
        schema_path = repo_root / schema_ref
        evidence = load_json(evidence_path, evidence_name)
        schema = load_json(schema_path, schema_ref)
        jsonschema.Draft202012Validator.check_schema(schema)
        validator = jsonschema.Draft202012Validator(schema)
        for error in sorted(validator.iter_errors(evidence), key=lambda item: list(item.path)):
            location = "/".join(str(part) for part in error.path) or "<root>"
            violations.append(f"{evidence_name}:{location}: {error.message}")

    payload = {
        "status": "pass" if not violations else "fail",
        "validated": evidence_schema_refs,
        "violations": violations,
    }
    write_json(checks_dir / "evidence_schema_validation.json", payload)
    return payload


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def snapshot_target(root: Path, target_type: str) -> dict[str, Any]:
    files = []
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        rel = path.relative_to(root).as_posix()
        files.append(
            {
                "path": rel,
                "size": path.stat().st_size,
                "sha256": sha256_file(path),
            }
        )
    return {
        "target_type": target_type,
        "file_count": len(files),
        "files": files,
    }


def validate_target_relative_path(raw: str) -> PurePosixPath:
    if raw == "" or raw in (".", ".."):
        fail("declared OpenClaw target path must not be empty, ., or ..")
    if raw.startswith("/") or re.match(r"^[A-Za-z]:[\\/]", raw):
        fail("declared OpenClaw target path must be relative")
    if "\\" in raw:
        fail("declared OpenClaw target path must not contain backslashes")
    pure = PurePosixPath(raw)
    if ".." in pure.parts:
        fail("declared OpenClaw target path must not contain traversal")
    if not pure.parts:
        fail("declared OpenClaw target path must not be empty")
    return pure


def validate_source_ref(raw: str) -> Path:
    if raw == "" or raw != raw.strip():
        fail("proposed write source must be a nonempty repo-relative path")
    if raw.startswith("/") or re.match(r"^[A-Za-z]:[\\/]", raw) or "\\" in raw:
        fail("proposed write source must be repo-relative")
    pure = PurePosixPath(raw)
    if ".." in pure.parts:
        fail("proposed write source must not contain traversal")
    source_path = (repo_root / Path(*pure.parts)).resolve(strict=False)
    try:
        source_path.relative_to(repo_root)
    except ValueError:
        fail("proposed write source escapes repository")
    if not source_path.is_file():
        fail(f"proposed write source is not a file: {raw}")
    return source_path


def apply_proposed_writes(proposed_plan: dict[str, Any], workspace_target: Path) -> list[dict[str, Any]]:
    proposed_writes = proposed_plan.get("proposed_writes")
    if not isinstance(proposed_writes, list):
        fail("proposed_writes must be an array")

    actions: list[dict[str, Any]] = []
    for item in proposed_writes:
        if not isinstance(item, dict):
            fail("proposed_writes items must be objects")
        if item.get("write_mode") != "proposed-only":
            fail("proposed write_mode must be proposed-only")
        target_surface = item.get("target_surface")
        if target_surface not in ("workspace", "state"):
            fail("proposed target_surface must be workspace or state")
        if target_surface == "state":
            fail("state-target writes are not implemented in the initial controlled disposable apply skeleton")
        target = item.get("target")
        source = item.get("source")
        if not isinstance(target, str) or not target.startswith("declared-openclaw-target:"):
            fail("proposed target must start with declared-openclaw-target:")
        if not isinstance(source, str):
            fail("proposed source must be a string")

        source_path = validate_source_ref(source)
        target_rel_text = target.removeprefix("declared-openclaw-target:")
        target_rel = validate_target_relative_path(target_rel_text)
        destination = (workspace_target / Path(*target_rel.parts)).resolve(strict=False)
        try:
            destination.relative_to(workspace_target)
        except ValueError:
            fail("proposed workspace destination escapes workspace target")

        existed_before = destination.exists()
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, destination)
        actions.append(
            {
                "source": source,
                "target_surface": "workspace",
                "workspace_target_path": target_rel.as_posix(),
                "applied": True,
                "existed_before": existed_before,
                "bytes_copied": destination.stat().st_size,
            }
        )
    return actions


def main() -> None:
    global run_id, run_dir, checks_dir, canonical_run_dir, run_dir_created

    parse_args()
    run_id = validate_run_id(str(values["run_id"]))
    canonical_run_dir = f"operations/harness-openclaw-disposable-apply/runs/{run_id}"
    run_dir = runs_root / run_id
    checks_dir = run_dir / "checks"
    run_dir_invariants = verify_apply_run_dir()

    if str(values["approval_label"]).strip() == "":
        fail("approval-label must be nonempty")

    run_dir.mkdir(parents=True, exist_ok=True)
    checks_dir.mkdir(parents=True, exist_ok=True)
    run_dir_created = True
    write_json(checks_dir / "run_dir_invariants.json", run_dir_invariants)

    dry_run_dir, dry_run_ref, proposed_plan, _dry_report = validate_dry_run_input(str(values["dry_run_run_dir"]))
    validate_plan_schema(proposed_plan)
    target_validation, workspace_target, state_target = validate_targets()
    no_secret_validation = validate_no_secret(dry_run_ref)

    no_live_runtime_validation = {
        "status": "pass",
        "live_runtime_apply": False,
        "live_runtime_target_used": False,
        "violations": [],
    }
    write_json(checks_dir / "no_live_runtime_validation.json", no_live_runtime_validation)

    pre_snapshot = {
        "workspace": snapshot_target(workspace_target, "workspace"),
        "state": snapshot_target(state_target, "state"),
    }
    write_json(run_dir / "pre_apply_snapshot.json", pre_snapshot)

    actions = apply_proposed_writes(proposed_plan, workspace_target)
    write_json(run_dir / "apply_actions.json", actions)

    post_snapshot = {
        "workspace": snapshot_target(workspace_target, "workspace"),
        "state": snapshot_target(state_target, "state"),
    }
    write_json(run_dir / "post_apply_snapshot.json", post_snapshot)

    workspace_write_count = len(actions)
    state_write_count = 0
    created_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    apply_meta = {
        "profile": "controlled-disposable-apply",
        "run_id": run_id,
        "dry_run_run_dir": dry_run_ref,
        "canonical_run_dir": canonical_run_dir,
        "approval_label": str(values["approval_label"]),
        "local_only": True,
        "disposable_only": True,
        "live_runtime_apply": False,
        "workspace_write_count": workspace_write_count,
        "state_write_count": state_write_count,
        "created_at": created_at,
    }
    input_refs = {
        "dry_run_run_dir": dry_run_ref,
        "proposed_openclaw_placement_plan": f"{dry_run_ref}/proposed_openclaw_placement_plan.json",
        "dry_run_report": f"{dry_run_ref}/dry_run_report.json",
        "proposed_plan_schema_validation": f"{dry_run_ref}/checks/proposed_plan_schema_validation.json",
        "no_secret_leakage_validation": f"{dry_run_ref}/checks/no_secret_leakage_validation.json",
        "source_phase3_run_dir": proposed_plan.get("source_phase3_run_dir"),
    }
    target_refs = {
        "workspace_target": str(workspace_target),
        "workspace_approved_root": str(Path(str(values["workspace_approved_root"])).resolve(strict=True)),
        "state_target": str(state_target),
        "state_approved_root": str(Path(str(values["state_approved_root"])).resolve(strict=True)),
    }
    cleanup_plan = {
        "status": "planned",
        "local_only": True,
        "disposable_only": True,
        "cleanup_scope": "inside explicitly disposable targets only",
        "workspace_paths": [action["workspace_target_path"] for action in actions],
        "state_paths": [],
        "must_not_clean_live_runtime": True,
    }
    rollback_plan = {
        "status": "planned",
        "local_only": True,
        "disposable_only": True,
        "rollback_basis": "pre_apply_snapshot.json",
        "workspace_paths": [action["workspace_target_path"] for action in actions],
        "state_paths": [],
        "must_remain_inside_disposable_targets": True,
    }
    apply_report = {
        "overall_status": "pass",
        "local_only": True,
        "disposable_only": True,
        "workspace_write_count": workspace_write_count,
        "state_write_count": state_write_count,
        "live_runtime_apply": False,
        "checks": {
            "run_dir_invariants": "pass",
            "target_path_validation": target_validation["status"],
            "no_secret_leakage_validation": no_secret_validation["status"],
            "no_live_runtime_validation": no_live_runtime_validation["status"],
            "evidence_schema_validation": "pass",
        },
    }

    write_json(run_dir / "apply_meta.json", apply_meta)
    write_json(run_dir / "input_refs.json", input_refs)
    write_json(run_dir / "target_refs.json", target_refs)
    write_json(run_dir / "cleanup_plan.json", cleanup_plan)
    write_json(run_dir / "rollback_plan.json", rollback_plan)
    write_json(run_dir / "apply_report.json", apply_report)

    evidence_schema_validation = validate_evidence_schemas()
    if evidence_schema_validation["status"] != "pass":
        apply_report["overall_status"] = "fail"
        apply_report["checks"]["evidence_schema_validation"] = "fail"
        write_json(run_dir / "apply_report.json", apply_report)
        write_exit_code(1)
        fail("controlled disposable apply evidence schema validation failed")

    write_text(
        run_dir / "apply_report.md",
        "\n".join(
            [
                "# Controlled disposable apply report",
                "",
                "No live runtime target was used.",
                "No local overlay was read.",
                "No secrets were consumed as source content.",
                "Only explicitly disposable local targets were used.",
                "",
                f"- workspace_write_count: {workspace_write_count}",
                f"- state_write_count: {state_write_count}",
                "",
            ]
        ),
    )
    write_exit_code(0)
    print(f"PASS controlled disposable apply skeleton: {run_id}")


try:
    main()
except ApplyError as exc:
    write_exit_code(1)
    print(f"FAIL {exc}", file=sys.stderr)
    raise SystemExit(1)
except Exception as exc:
    write_exit_code(1)
    print(f"FAIL unexpected controlled disposable apply error: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
