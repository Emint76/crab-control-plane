#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="${1:-$(cd "${PHASE2_ROOT}/../.." && pwd)}"
RUN_DIR="${2:-}"

if [[ -z "${RUN_DIR}" ]]; then
  echo "usage: $0 <repo-root> <run-dir>" >&2
  exit 1
fi

CHECKS_DIR="${RUN_DIR}/checks"
REPORT_PATH="${CHECKS_DIR}/wrong_root_preflight.txt"
mkdir -p "${CHECKS_DIR}"

STATUS="PASS"
declare -a ISSUES=()

required_paths=(
  "control-plane/"
  "docs/"
  "operations/notion/"
  "knowledge/obsidian/"
  "knowledge/kb/"
  "observability/"
)

for rel_path in "${required_paths[@]}"; do
  if [[ ! -e "${REPO_ROOT}/${rel_path}" ]]; then
    STATUS="FAIL"
    ISSUES+=("missing required architectural path: ${rel_path}")
  fi
done

for forbidden_root in ".env" "openclaw.json" "state" "workspace"; do
  if [[ -e "${REPO_ROOT}/${forbidden_root}" ]]; then
    STATUS="FAIL"
    ISSUES+=("forbidden root-level artifact present: ${forbidden_root}")
  fi
done

tracked_tmp=""
scan_mode="tree-scan"
self_scan_exempt="operations/harness-phase2/bin/preflight_wrong_root_scan.sh"
if git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  tracked_tmp="$(mktemp)"
  git -C "${REPO_ROOT}" ls-files > "${tracked_tmp}" || true
  if [[ -s "${tracked_tmp}" ]]; then
    scan_mode="tracked-files"
  else
    rm -f "${tracked_tmp}"
    tracked_tmp=""
  fi
fi

secret_pattern='(BEGIN [A-Z ]*PRIVATE KEY|API_KEY|SECRET_KEY|ACCESS_KEY|TOKEN=|password=)'
if [[ -n "${tracked_tmp}" ]]; then
  while IFS= read -r rel_file; do
    [[ -n "${rel_file}" ]] || continue
    [[ "${rel_file}" == "${self_scan_exempt}" ]] && continue
    if grep -IE -n "${secret_pattern}" "${REPO_ROOT}/${rel_file}" >/dev/null 2>&1; then
      STATUS="FAIL"
      ISSUES+=("probable secret material detected in tracked file: ${rel_file}")
    fi
  done < "${tracked_tmp}"
  rm -f "${tracked_tmp}"
else
  while IFS= read -r file_path; do
    rel_path="${file_path#${REPO_ROOT}/}"
    [[ "${rel_path}" == "${self_scan_exempt}" ]] && continue
    if grep -IE -n "${secret_pattern}" "${file_path}" >/dev/null 2>&1; then
      STATUS="FAIL"
      ISSUES+=("probable secret material detected in scanned file: ${rel_path}")
    fi
  done < <(
    find "${REPO_ROOT}" \
      \( -path "${REPO_ROOT}/.git" -o -path "${REPO_ROOT}/operations/harness-phase2/runs" -o -path "${REPO_ROOT}/.venv" -o -path "${REPO_ROOT}/node_modules" -o -path "${REPO_ROOT}/.pytest_cache" \) -prune \
      -o -type f -print
  )
fi

{
  printf 'status=%s\n' "${STATUS}"
  printf 'scan_mode=%s\n' "${scan_mode}"
  printf 'repo_root=%s\n' "${REPO_ROOT}"
  if [[ ${#ISSUES[@]} -eq 0 ]]; then
    printf 'details=wrong-root preflight passed\n'
  else
    printf 'details:\n'
    for issue in "${ISSUES[@]}"; do
      printf -- '- %s\n' "${issue}"
    done
  fi
} > "${REPORT_PATH}"

if [[ "${STATUS}" != "PASS" ]]; then
  exit 1
fi
