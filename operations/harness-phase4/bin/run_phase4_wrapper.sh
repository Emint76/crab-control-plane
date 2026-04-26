#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE4_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PHASE4_ROOT}/../.." && pwd)"
PYTHON_BIN="${PHASE4_PYTHON_BIN:-${PHASE3_PYTHON_BIN:-python}}"

usage() {
  cat <<'EOF' >&2
usage: run_phase4_wrapper.sh \
  --phase2-run-dir <PATH> \
  --execution-target-json <PATH> \
  --phase3-run-id <RUN_ID> \
  --operator <OPERATOR_ID> \
  [--wrapper-run-id <WRAPPER_RUN_ID>]
EOF
}

if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  echo "FAIL python runtime not found: ${PYTHON_BIN}" >&2
  exit 1
fi
PYTHON_BIN_RESOLVED="$(command -v "${PYTHON_BIN}")"
PHASE4_PYTHON_BIN_RESOLVED="${PYTHON_BIN_RESOLVED}"
BASH_BIN_RESOLVED="$(command -v bash)"
if command -v cygpath >/dev/null 2>&1; then
  BASH_BIN_RESOLVED="$(cygpath -w "${BASH_BIN_RESOLVED}")"
fi
PHASE4_BASH_BIN_RESOLVED="${BASH_BIN_RESOLVED}"

export PHASE4_ROOT
export REPO_ROOT
export PHASE4_PYTHON_BIN_RESOLVED
export PHASE4_BASH_BIN_RESOLVED

"${PYTHON_BIN}" - "$@" <<'PY'
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


RUN_ID_RE = re.compile(r"^[A-Za-z0-9._-]+$")
OPERATOR_RE = re.compile(r"^[A-Za-z0-9._:@-]+$")
PHASE3_ENTRYPOINT = "operations/harness-phase3/bin/run_phase3_bundle.sh"


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def generated_wrapper_run_id() -> str:
    return datetime.now(timezone.utc).strftime("phase4-%Y%m%dT%H%M%SZ")


def parse_args(argv: list[str]) -> tuple[dict[str, str], list[str]]:
    values = {
        "phase2_run_dir": "",
        "execution_target_json": "",
        "phase3_run_id": "",
        "operator": "",
        "wrapper_run_id": "",
    }
    errors: list[str] = []
    index = 0
    key_map = {
        "--phase2-run-dir": "phase2_run_dir",
        "--execution-target-json": "execution_target_json",
        "--phase3-run-id": "phase3_run_id",
        "--operator": "operator",
        "--wrapper-run-id": "wrapper_run_id",
    }
    while index < len(argv):
        arg = argv[index]
        if arg not in key_map:
            errors.append(f"unknown_argument:{arg}")
            index += 1
            continue
        if index + 1 >= len(argv):
            errors.append(f"missing_value:{arg}")
            values[key_map[arg]] = ""
            index += 1
            continue
        values[key_map[arg]] = argv[index + 1]
        index += 2
    if not values["wrapper_run_id"]:
        values["wrapper_run_id"] = generated_wrapper_run_id()
    return values, errors


def is_valid_run_id(value: str) -> bool:
    if not value:
        return False
    if value != value.strip():
        return False
    if value in {".", ".."}:
        return False
    return bool(RUN_ID_RE.fullmatch(value))


def is_valid_operator(value: str) -> bool:
    if not value:
        return False
    if value != value.strip():
        return False
    return bool(OPERATOR_RE.fullmatch(value))


def resolve_user_path(repo_root: Path, value: str) -> Path:
    path = Path(value).expanduser()
    if path.is_absolute():
        return path.resolve(strict=False)
    return (repo_root / path).resolve(strict=False)


def repo_ref(repo_root: Path, path: Path) -> str:
    resolved = path.resolve(strict=False)
    try:
        return resolved.relative_to(repo_root.resolve(strict=False)).as_posix()
    except ValueError:
        return resolved.as_posix()


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def add_check(checks: list[dict[str, str]], name: str, status: str, detail: str) -> None:
    checks.append({"name": name, "status": status, "detail": detail})


def make_wrapper_refs(wrapper_run_id: str, phase3_run_id: str) -> dict[str, str]:
    phase3_run_dir = f"operations/harness-phase3/runs/{phase3_run_id}"
    return {
        "wrapper_run_dir": f"operations/harness-phase4/runs/{wrapper_run_id}",
        "phase3_canonical_run_dir": phase3_run_dir,
        "phase3_report_json": f"{phase3_run_dir}/report.json",
        "phase3_report_md": f"{phase3_run_dir}/report.md",
        "phase3_exit_code": f"{phase3_run_dir}/exit_code",
    }


def wrapper_meta(wrapper_run_id: str, operator: str, phase3_run_id: str) -> dict[str, Any]:
    refs = make_wrapper_refs(wrapper_run_id, phase3_run_id)
    return {
        "phase": "phase4",
        "profile": "thin-wrapper",
        "wrapper_run_id": wrapper_run_id,
        "operator": operator,
        "phase3_run_id": phase3_run_id,
        "phase3_canonical_run_dir": refs["phase3_canonical_run_dir"],
        "phase3_report_json": refs["phase3_report_json"],
        "phase3_report_md": refs["phase3_report_md"],
        "phase3_exit_code": refs["phase3_exit_code"],
        "generated_at": now_utc(),
        "runtime_statement": {
            "phase4_is_canonical_execution_owner": False,
            "phase4_created_canonical_outputs": False,
            "phase4_mutated_phase3_outputs": False,
            "live_openclaw_runtime_mutation": False,
            "plugin_gateway_channel_model_auth_token_config_changes": False,
        },
    }


def invocation_payload(
    *,
    phase3_invoked: bool,
    phase3_exit_status: int | None,
    phase2_run_ref: str | None,
    execution_target_ref: str | None,
    phase3_run_id: str,
    reason: str | None = None,
) -> dict[str, Any]:
    refs = make_wrapper_refs("unused", phase3_run_id)
    payload: dict[str, Any] = {
        "phase3_invoked": phase3_invoked,
        "phase3_exit_status": phase3_exit_status,
    }
    if phase3_invoked:
        payload.update(
            {
                "phase3_command": [
                    PHASE3_ENTRYPOINT,
                    "--phase2-run-dir",
                    phase2_run_ref,
                    "--execution-target-json",
                    execution_target_ref,
                    "--run-id",
                    phase3_run_id,
                ],
                "phase3_canonical_run_dir": refs["phase3_canonical_run_dir"],
                "phase3_report_json": refs["phase3_report_json"],
                "phase3_report_md": refs["phase3_report_md"],
                "phase3_exit_code": refs["phase3_exit_code"],
            }
        )
    if reason:
        payload["reason"] = reason
    return payload


def write_summary(
    wrapper_run_dir: Path,
    wrapper_run_id: str,
    operator: str,
    phase3_run_id: str,
    phase3_exit_status: int | str,
) -> None:
    refs = make_wrapper_refs(wrapper_run_id, phase3_run_id)
    write_text(
        wrapper_run_dir / "wrapper_summary.md",
        "\n".join(
            [
                "# Phase 4 wrapper summary",
                "",
                "## Wrapper identity",
                f"- wrapper_run_id: `{wrapper_run_id}`",
                f"- operator: `{operator}`",
                "- profile: `thin-wrapper`",
                "",
                "## Phase 3 invocation",
                f"- phase3_run_id: `{phase3_run_id}`",
                f"- phase3_exit_status: `{phase3_exit_status}`",
                f"- phase3_canonical_run_dir: `{refs['phase3_canonical_run_dir']}`",
                f"- phase3_report_json: `{refs['phase3_report_json']}`",
                f"- phase3_report_md: `{refs['phase3_report_md']}`",
                f"- phase3_exit_code: `{refs['phase3_exit_code']}`",
                "",
                "## Boundary statement",
                "- Phase 4 did not create canonical execution outputs.",
                "- Phase 4 did not mutate Phase 3 outputs.",
                "- Phase 3 remains the canonical execution owner.",
                "",
            ]
        ),
    )


def main(argv: list[str]) -> int:
    repo_root = Path(os.environ["REPO_ROOT"]).resolve(strict=False)
    phase4_root = Path(os.environ["PHASE4_ROOT"]).resolve(strict=False)
    values, parse_errors = parse_args(argv)

    phase2_run_dir_arg = values["phase2_run_dir"]
    execution_target_arg = values["execution_target_json"]
    phase3_run_id = values["phase3_run_id"]
    operator = values["operator"]
    wrapper_run_id = values["wrapper_run_id"]

    wrapper_run_id_valid = is_valid_run_id(wrapper_run_id)
    if not wrapper_run_id_valid:
        print("FAIL invalid --wrapper-run-id", file=sys.stderr)
        return 2

    wrapper_runs_root = (phase4_root / "runs").resolve(strict=False)
    wrapper_run_dir = (wrapper_runs_root / wrapper_run_id).resolve(strict=False)
    wrapper_write_surface_valid = False
    try:
        wrapper_rel = wrapper_run_dir.relative_to(wrapper_runs_root)
        wrapper_write_surface_valid = len(wrapper_rel.parts) == 1 and wrapper_run_dir.name == wrapper_run_id
    except ValueError:
        wrapper_write_surface_valid = False

    if wrapper_write_surface_valid:
        wrapper_run_dir.mkdir(parents=True, exist_ok=True)

    checks: list[dict[str, str]] = []
    violations: list[str] = []
    for error in parse_errors:
        violations.append(error)

    phase3_entrypoint = repo_root / PHASE3_ENTRYPOINT
    if phase3_entrypoint.is_file():
        add_check(checks, "phase3_entrypoint_exists", "pass", f"{PHASE3_ENTRYPOINT} exists.")
    else:
        add_check(checks, "phase3_entrypoint_exists", "fail", f"{PHASE3_ENTRYPOINT} is missing.")
        violations.append("phase3_entrypoint_exists")

    phase2_run_ref: str | None = None
    if phase2_run_dir_arg:
        phase2_run_dir = resolve_user_path(repo_root, phase2_run_dir_arg)
        phase2_runs_root = (repo_root / "operations" / "harness-phase2" / "runs").resolve(strict=False)
        try:
            phase2_rel = phase2_run_dir.relative_to(phase2_runs_root)
            phase2_valid = len(phase2_rel.parts) == 1 and phase2_run_dir.is_dir()
        except ValueError:
            phase2_valid = False
        if phase2_valid:
            phase2_run_ref = repo_ref(repo_root, phase2_run_dir)
            add_check(checks, "phase2_run_dir_repo_contained", "pass", "Phase 2 run dir resolves under operations/harness-phase2/runs/.")
        else:
            add_check(checks, "phase2_run_dir_repo_contained", "fail", "Phase 2 run dir must be an existing direct child under operations/harness-phase2/runs/.")
            violations.append("phase2_run_dir_repo_contained")
    else:
        add_check(checks, "phase2_run_dir_repo_contained", "fail", "--phase2-run-dir is required.")
        violations.append("phase2_run_dir_repo_contained")

    execution_target_ref: str | None = None
    if execution_target_arg:
        execution_target_json = resolve_user_path(repo_root, execution_target_arg)
        try:
            execution_target_json.relative_to(repo_root)
            target_valid = execution_target_json.is_file()
        except ValueError:
            target_valid = False
        if target_valid:
            execution_target_ref = repo_ref(repo_root, execution_target_json)
            add_check(checks, "execution_target_json_repo_contained", "pass", "Execution target JSON resolves inside the repository.")
        else:
            add_check(checks, "execution_target_json_repo_contained", "fail", "Execution target JSON must be an existing file inside the repository.")
            violations.append("execution_target_json_repo_contained")
    else:
        add_check(checks, "execution_target_json_repo_contained", "fail", "--execution-target-json is required.")
        violations.append("execution_target_json_repo_contained")

    if is_valid_run_id(phase3_run_id):
        add_check(checks, "phase3_run_id_valid", "pass", "Phase 3 run id matches ^[A-Za-z0-9._-]+$.")
    else:
        add_check(checks, "phase3_run_id_valid", "fail", "Phase 3 run id must match ^[A-Za-z0-9._-]+$ and must not contain path separators or whitespace.")
        violations.append("phase3_run_id_valid")

    add_check(
        checks,
        "wrapper_run_id_valid",
        "pass" if wrapper_run_id_valid else "fail",
        "Wrapper run id matches ^[A-Za-z0-9._-]+$." if wrapper_run_id_valid else "Wrapper run id is invalid.",
    )
    if not wrapper_run_id_valid:
        violations.append("wrapper_run_id_valid")

    if is_valid_operator(operator):
        add_check(checks, "operator_valid", "pass", "Operator id matches ^[A-Za-z0-9._:@-]+$.")
    else:
        add_check(checks, "operator_valid", "fail", "Operator id must match ^[A-Za-z0-9._:@-]+$ and must not contain spaces.")
        violations.append("operator_valid")

    add_check(
        checks,
        "phase4_write_surface_valid",
        "pass" if wrapper_write_surface_valid else "fail",
        "Wrapper write surface is operations/harness-phase4/runs/<WRAPPER_RUN_ID>/."
        if wrapper_write_surface_valid
        else "Wrapper write surface must remain under operations/harness-phase4/runs/<WRAPPER_RUN_ID>/.",
    )
    if not wrapper_write_surface_valid:
        violations.append("phase4_write_surface_valid")

    preflight = {
        "status": "fail" if violations else "pass",
        "checks": checks,
        "violations": sorted(set(violations)),
    }

    if wrapper_write_surface_valid:
        write_json(wrapper_run_dir / "wrapper_meta.json", wrapper_meta(wrapper_run_id, operator, phase3_run_id))
        write_json(wrapper_run_dir / "preflight.json", preflight)

    if preflight["status"] != "pass":
        if wrapper_write_surface_valid:
            write_json(
                wrapper_run_dir / "phase3_invocation.json",
                invocation_payload(
                    phase3_invoked=False,
                    phase3_exit_status=None,
                    phase2_run_ref=phase2_run_ref,
                    execution_target_ref=execution_target_ref,
                    phase3_run_id=phase3_run_id,
                    reason="preflight_failed",
                ),
            )
            write_summary(wrapper_run_dir, wrapper_run_id, operator, phase3_run_id, "not_invoked")
            write_text(wrapper_run_dir / "wrapper_exit_code", "1\n")
        print("FAIL Phase 4 wrapper preflight failed", file=sys.stderr)
        return 1

    assert phase2_run_ref is not None
    assert execution_target_ref is not None
    bash_bin = os.environ.get("PHASE4_BASH_BIN_RESOLVED", "bash")
    phase3_command = [
        bash_bin,
        PHASE3_ENTRYPOINT,
        "--phase2-run-dir",
        phase2_run_ref,
        "--execution-target-json",
        execution_target_ref,
        "--run-id",
        phase3_run_id,
    ]
    phase3_env = os.environ.copy()
    python_dir = str(Path(sys.executable).resolve(strict=False).parent)
    phase3_env["PATH"] = python_dir + os.pathsep + phase3_env.get("PATH", "")
    phase3_env["PHASE3_PYTHON_BIN"] = phase3_env.get(
        "PHASE4_PYTHON_BIN_RESOLVED",
        phase3_env.get("PHASE3_PYTHON_BIN", "python"),
    )
    phase3_result = subprocess.run(phase3_command, cwd=repo_root, env=phase3_env, check=False)
    phase3_exit_status = phase3_result.returncode

    refs = make_wrapper_refs(wrapper_run_id, phase3_run_id)
    phase3_report_json_exists = (repo_root / refs["phase3_report_json"]).is_file()
    phase3_report_md_exists = (repo_root / refs["phase3_report_md"]).is_file()
    phase3_exit_code_exists = (repo_root / refs["phase3_exit_code"]).is_file()
    missing_phase3_evidence = not (phase3_report_json_exists and phase3_report_md_exists and phase3_exit_code_exists)

    write_json(
        wrapper_run_dir / "phase3_invocation.json",
        invocation_payload(
            phase3_invoked=True,
            phase3_exit_status=phase3_exit_status,
            phase2_run_ref=phase2_run_ref,
            execution_target_ref=execution_target_ref,
            phase3_run_id=phase3_run_id,
        ),
    )

    if missing_phase3_evidence:
        wrapper_exit_status = phase3_exit_status if phase3_exit_status != 0 else 1
    else:
        wrapper_exit_status = phase3_exit_status
    if wrapper_exit_status < 0 or wrapper_exit_status > 255:
        wrapper_exit_status = 1

    write_summary(wrapper_run_dir, wrapper_run_id, operator, phase3_run_id, phase3_exit_status)
    write_text(wrapper_run_dir / "wrapper_exit_code", f"{wrapper_exit_status}\n")

    if missing_phase3_evidence:
        print("FAIL Phase 3 canonical report surface is missing after invocation", file=sys.stderr)
    return wrapper_exit_status


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
PY
