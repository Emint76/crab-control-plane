#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PHASE2_ROOT}/../.." && pwd)"
PREFLIGHT_SCRIPT="${PHASE2_ROOT}/bin/preflight_wrong_root_scan.sh"

TMP_PARENT="${TMPDIR:-/tmp}"
TMP_ROOT="$(mktemp -d "${TMP_PARENT%/}/phase2-preflight.XXXXXX")"

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && -d "${TMP_ROOT}" && "${TMP_ROOT}" == "${TMP_PARENT%/}"/phase2-preflight.* ]]; then
    rm -rf "${TMP_ROOT}"
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL %s\n' "$*" >&2
  exit 1
}

copy_repo() {
  local case_name="$1"
  local case_dir="${TMP_ROOT}/${case_name}/repo"

  mkdir -p "${case_dir}"
  git -C "${REPO_ROOT}" ls-files -z | while IFS= read -r -d '' rel_path; do
    mkdir -p "${case_dir}/$(dirname "${rel_path}")"
    cp -p "${REPO_ROOT}/${rel_path}" "${case_dir}/${rel_path}"
  done

  printf '%s\n' "${case_dir}"
}

prepare_case() {
  local case_name="$1"
  local repo="$2"

  case "${case_name}" in
    clean)
      ;;
    root-contracts)
      mkdir -p "${repo}/contracts"
      ;;
    operations-harness)
      mkdir -p "${repo}/operations/harness"
      ;;
    root-policy)
      mkdir -p "${repo}/policy"
      ;;
    root-runtime)
      mkdir -p "${repo}/runtime"
      ;;
    shortened-harness-phase2)
      mkdir -p "${repo}/harness-phase2"
      ;;
    state-harness-phase2)
      mkdir -p "${repo}/state/harness-phase2"
      ;;
    state-control-plane-harness-phase2)
      mkdir -p "${repo}/state/control-plane/harness-phase2"
      ;;
    phase2-report-outside)
      printf 'stray phase 2 report\n' > "${repo}/docs/PHASE2_REPORT.md"
      ;;
    validation-report-outside)
      printf '{}\n' > "${repo}/knowledge/kb/validation_report.json"
      ;;
    *)
      fail "unknown case: ${case_name}"
      ;;
  esac
}

run_case() {
  local case_name="$1"
  local expected="$2"
  local expected_path="${3:-}"
  local repo
  local run_dir
  local report_path
  local rc=0

  repo="$(copy_repo "${case_name}")"
  prepare_case "${case_name}" "${repo}"

  run_dir="${TMP_ROOT}/${case_name}/run"
  mkdir -p "${run_dir}"

  if bash "${PREFLIGHT_SCRIPT}" "${repo}" "${run_dir}" >"${run_dir}/stdout.log" 2>"${run_dir}/stderr.log"; then
    rc=0
  else
    rc=$?
  fi

  report_path="${run_dir}/checks/wrong_root_preflight.txt"
  [[ -f "${report_path}" ]] || fail "${case_name}: missing wrong_root_preflight.txt"

  if [[ "${expected}" == "pass" ]]; then
    [[ "${rc}" -eq 0 ]] || fail "${case_name}: expected pass, got exit ${rc}"
    grep -Fxq 'status=PASS' "${report_path}" || fail "${case_name}: missing status=PASS"
  else
    [[ "${rc}" -ne 0 ]] || fail "${case_name}: expected failure"
    grep -Fxq 'status=FAIL' "${report_path}" || fail "${case_name}: missing status=FAIL"
    grep -Fxq -- "- ${expected_path}" "${report_path}" || fail "${case_name}: missing ${expected_path}"
  fi

  printf 'PASS %s\n' "${case_name}"
}

run_case clean pass
run_case root-contracts fail "contracts/"
run_case operations-harness fail "operations/harness/"
run_case root-policy fail "policy/"
run_case root-runtime fail "runtime/"
run_case shortened-harness-phase2 fail "harness-phase2/"
run_case state-harness-phase2 fail "state/harness-phase2/"
run_case state-control-plane-harness-phase2 fail "state/control-plane/harness-phase2/"
run_case phase2-report-outside fail "docs/PHASE2_REPORT.md"
run_case validation-report-outside fail "knowledge/kb/validation_report.json"
