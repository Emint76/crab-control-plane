#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PHASE2_ROOT}/../.." && pwd)"
RUNS_ROOT="${PHASE2_ROOT}/runs"
TMP_DIR="$(mktemp -d)"

PYTHON_BIN="${PHASE2_PYTHON_BIN:-python}"
export PHASE2_PYTHON_BIN="${PYTHON_BIN}"

BUNDLE_RUN_ID="phase2-run-dir-bundle-valid"
CHECK_LAYER_RUN_ID="phase2-run-dir-check-layer-valid"

fail() {
  printf 'FAIL %s\n' "$*" >&2
  exit 1
}

remove_generated_path() {
  local path="$1"
  case "${path}" in
    "${RUNS_ROOT}/"*|"${PHASE2_ROOT}/bad"|"${PHASE2_ROOT}/run_meta.json")
      rm -rf -- "${path}"
      ;;
    *)
      fail "refusing to remove outside Phase 2 generated surfaces: ${path}"
      ;;
  esac
}

snapshot_run_dirs() {
  find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort
}

cleanup() {
  rm -rf "${TMP_DIR}"
  remove_generated_path "${RUNS_ROOT}/${BUNDLE_RUN_ID}"
  remove_generated_path "${RUNS_ROOT}/${CHECK_LAYER_RUN_ID}"
  remove_generated_path "${RUNS_ROOT}/bad"
  remove_generated_path "${RUNS_ROOT}/ bad"
  remove_generated_path "${RUNS_ROOT}/bad "
  remove_generated_path "${RUNS_ROOT}/tmp"
  remove_generated_path "${RUNS_ROOT}/bad\\run"
  remove_generated_path "${RUNS_ROOT}/run_meta.json"
  remove_generated_path "${PHASE2_ROOT}/bad"
  remove_generated_path "${PHASE2_ROOT}/run_meta.json"
}

trap cleanup EXIT
cleanup
mkdir -p "${RUNS_ROOT}" "${TMP_DIR}"

assert_valid_run() {
  local entrypoint="$1"
  local run_id="$2"
  local expected_profile="$3"
  local run_dir="${RUNS_ROOT}/${run_id}"

  bash "${entrypoint}" "${run_id}"

  [[ -f "${run_dir}/run_meta.json" ]] || fail "missing run_meta.json for ${run_id}"
  [[ -f "${run_dir}/checks/run_dir_invariants.json" ]] || fail "missing run_dir_invariants.json for ${run_id}"
  [[ -f "${run_dir}/exit_code" ]] || fail "missing exit_code for ${run_id}"
  [[ "$(tr -d '\r\n' < "${run_dir}/exit_code")" == "0" ]] || fail "exit_code was not 0 for ${run_id}"

  "${PYTHON_BIN}" - "${run_dir}/run_meta.json" "${run_dir}/checks/run_dir_invariants.json" "${run_id}" "${expected_profile}" <<'PY'
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


def iter_strings(value: Any, path: str = ""):
    if isinstance(value, str):
        yield path, value
    elif isinstance(value, dict):
        for key, item in value.items():
            child = str(key) if not path else f"{path}.{key}"
            yield from iter_strings(item, child)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from iter_strings(item, f"{path}[{index}]")


def is_unsafe_host_path(value: str) -> bool:
    if value.startswith("/"):
        return True
    if re.match(r"^[A-Za-z]:[\\/]", value):
        return True
    if "\\" in value:
        return True
    return any(token in value for token in ("/tmp/", "/home/", "/Users/", "/mnt/"))


run_meta = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
invariants = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
run_id = sys.argv[3]
expected_profile = sys.argv[4]
expected_run_dir = f"operations/harness-phase2/runs/{run_id}"
expected_write_surface = f"{expected_run_dir}/"

assert run_meta["phase"] == "phase2", run_meta
assert run_meta["profile"] == expected_profile, run_meta
assert run_meta["run_id"] == run_id, run_meta
assert Path(expected_run_dir).name == run_meta["run_id"], run_meta
assert run_meta["canonical_run_dir"] == expected_run_dir, run_meta
assert run_meta["run_dir_identity_verified"] is True, run_meta
assert run_meta["write_surface"] == expected_write_surface, run_meta

unsafe_fields = [(path, value) for path, value in iter_strings(run_meta) if is_unsafe_host_path(value)]
assert unsafe_fields == [], unsafe_fields

assert invariants["status"] == "pass", invariants
assert invariants["run_id"] == run_id, invariants
assert invariants["canonical_run_dir"] == expected_run_dir, invariants
assert invariants["run_dir_identity_verified"] is True, invariants
assert invariants["write_surface_verified"] is True, invariants
assert invariants["violations"] == [], invariants
PY

  if [[ -f "${run_dir}/CREATED_PATHS.txt" ]]; then
    grep -Fq "operations/harness-phase2/runs/${run_id}/checks/run_dir_invariants.json" "${run_dir}/CREATED_PATHS.txt" \
      || fail "CREATED_PATHS.txt missing run_dir_invariants.json for ${run_id}"
  fi

  printf 'PASS valid Phase 2 run-dir invariants: %s\n' "${run_id}"
}

assert_absent() {
  local path="$1"
  [[ ! -e "${path}" ]] || fail "unexpected path exists: ${path}"
}

run_invalid() {
  local entrypoint="$1"
  local entry_label="$2"
  local case_label="$3"
  local run_id="$4"
  shift 4
  local forbidden_paths=("$@")
  local log_path="${TMP_DIR}/${entry_label}-${case_label}.log"

  for path in "${forbidden_paths[@]}"; do
    remove_generated_path "${path}"
    assert_absent "${path}"
  done

  local before_snapshot
  local after_snapshot
  before_snapshot="$(snapshot_run_dirs)"

  set +e
  bash "${entrypoint}" "${run_id}" >"${log_path}" 2>&1
  local status=$?
  set -e

  [[ "${status}" -ne 0 ]] || fail "${entry_label} invalid RUN_ID unexpectedly passed: ${case_label}"

  after_snapshot="$(snapshot_run_dirs)"
  [[ "${before_snapshot}" == "${after_snapshot}" ]] || fail "${entry_label} invalid RUN_ID created a run dir: ${case_label}"

  for path in "${forbidden_paths[@]}"; do
    assert_absent "${path}"
  done

  printf 'PASS invalid Phase 2 RUN_ID rejected: %s %s\n' "${entry_label}" "${case_label}"
}

run_invalid_cases_for_entrypoint() {
  local entrypoint="$1"
  local entry_label="$2"

  run_invalid "${entrypoint}" "${entry_label}" "traversal" "../bad" "${PHASE2_ROOT}/bad"
  run_invalid "${entrypoint}" "${entry_label}" "forward-slash" "bad/run" "${RUNS_ROOT}/bad"
  run_invalid "${entrypoint}" "${entry_label}" "backslash" 'bad\run' "${RUNS_ROOT}/bad\\run"
  run_invalid "${entrypoint}" "${entry_label}" "absolute" "/tmp/bad" "${RUNS_ROOT}/tmp"
  run_invalid "${entrypoint}" "${entry_label}" "leading-whitespace" " bad" "${RUNS_ROOT}/ bad"
  run_invalid "${entrypoint}" "${entry_label}" "trailing-whitespace" "bad " "${RUNS_ROOT}/bad "
  run_invalid "${entrypoint}" "${entry_label}" "empty" "" "${RUNS_ROOT}/run_meta.json"
  run_invalid "${entrypoint}" "${entry_label}" "dot" "." "${RUNS_ROOT}/run_meta.json"
  run_invalid "${entrypoint}" "${entry_label}" "dotdot" ".." "${PHASE2_ROOT}/run_meta.json"
}

assert_valid_run "${PHASE2_ROOT}/bin/run_phase2_bundle.sh" "${BUNDLE_RUN_ID}" "repo-native-scaffold"
assert_valid_run "${PHASE2_ROOT}/bin/run_phase2_check_layer.sh" "${CHECK_LAYER_RUN_ID}" "check-layer-strict"

run_invalid_cases_for_entrypoint "${PHASE2_ROOT}/bin/run_phase2_bundle.sh" "bundle"
run_invalid_cases_for_entrypoint "${PHASE2_ROOT}/bin/run_phase2_check_layer.sh" "check-layer"

printf 'PASS Phase 2 run-dir invariants\n'
