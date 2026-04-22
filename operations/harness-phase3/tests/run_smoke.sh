#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE3_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PHASE3_ROOT}/../.." && pwd)"
TMP_DIR="${SCRIPT_DIR}/tmp"

mkdir -p "${TMP_DIR}"

if [[ -z "${PHASE3_PYTHON_BIN:-}" ]]; then
  if command -v python >/dev/null 2>&1; then
    export PHASE3_PYTHON_BIN="python"
  elif [[ -x "/c/Program Files/LibreOffice/program/python.exe" ]]; then
    export PHASE3_PYTHON_BIN="/c/Program Files/LibreOffice/program/python.exe"
  fi
fi
PYTHON_BIN="${PHASE3_PYTHON_BIN:-python}"

PHASE2_RUN_DIR="${REPO_ROOT}/operations/harness-phase2/runs/pr2d-pass"
POS_RUN_ID="phase3-smoke-positive"
NEG_RUN_ID="phase3-smoke-negative"
LATE_FAIL_RUN_ID="phase3-smoke-late-fail"
POS_RUN_DIR="${PHASE3_ROOT}/runs/${POS_RUN_ID}"
NEG_RUN_DIR="${PHASE3_ROOT}/runs/${NEG_RUN_ID}"
LATE_FAIL_RUN_DIR="${PHASE3_ROOT}/runs/${LATE_FAIL_RUN_ID}"

POS_TARGET_JSON="${TMP_DIR}/execution_target.positive.json"
NEG_TARGET_JSON="${TMP_DIR}/execution_target.negative.json"
LATE_FAIL_TARGET_JSON="${TMP_DIR}/execution_target.late-fail.json"
LATE_FAIL_PHASE2_RUN_DIR="${TMP_DIR}/phase2-late-fail"

rm -rf "${POS_RUN_DIR}" "${NEG_RUN_DIR}" "${LATE_FAIL_RUN_DIR}" "${LATE_FAIL_PHASE2_RUN_DIR}"

cat > "${POS_TARGET_JSON}" <<EOF
{
  "target_runtime": "openclaw",
  "target_kind": "phase3_staging",
  "target_ref": "operations/harness-phase3/runs/${POS_RUN_ID}/staging/runtime-ready-applied",
  "apply_mode": "staged",
  "approval_ref": "manual://phase3-smoke-positive",
  "invoked_by": "smoke://phase3-positive"
}
EOF

cat > "${NEG_TARGET_JSON}" <<'EOF'
{
  "target_runtime": "openclaw",
  "target_kind": "phase3_staging",
  "target_ref": "operations/harness-phase2/runs/pr2d-pass/output/runtime-ready",
  "apply_mode": "staged",
  "approval_ref": "manual://phase3-smoke-negative",
  "invoked_by": "smoke://phase3-negative"
}
EOF

cp -R "${PHASE2_RUN_DIR}" "${LATE_FAIL_PHASE2_RUN_DIR}"
rm -f "${LATE_FAIL_PHASE2_RUN_DIR}/output/runtime-ready/APPLY_MODEL.md"

cat > "${LATE_FAIL_TARGET_JSON}" <<EOF
{
  "target_runtime": "openclaw",
  "target_kind": "phase3_staging",
  "target_ref": "operations/harness-phase3/runs/${LATE_FAIL_RUN_ID}/staging/runtime-ready-applied",
  "apply_mode": "staged",
  "approval_ref": "manual://phase3-smoke-late-fail",
  "invoked_by": "smoke://phase3-late-fail"
}
EOF

bash "${PHASE3_ROOT}/bin/run_phase3_bundle.sh" \
  --phase2-run-dir "${PHASE2_RUN_DIR}" \
  --execution-target-json "${POS_TARGET_JSON}" \
  --run-id "${POS_RUN_ID}"

[[ -f "${POS_RUN_DIR}/exit_code" ]] || { echo "missing positive exit_code" >&2; exit 1; }
[[ "$(tr -d '\r\n' < "${POS_RUN_DIR}/exit_code")" == "0" ]] || { echo "positive run exit_code must be 0" >&2; exit 1; }
[[ -f "${POS_RUN_DIR}/run_meta.json" ]] || { echo "missing positive run_meta.json" >&2; exit 1; }
[[ -f "${POS_RUN_DIR}/input/runtime_ready_manifest.json" ]] || { echo "missing positive runtime_ready_manifest.json" >&2; exit 1; }
[[ -f "${POS_RUN_DIR}/input/runtime_ready.sha256" ]] || { echo "missing positive runtime_ready.sha256" >&2; exit 1; }
[[ -f "${POS_RUN_DIR}/input/input.sha256" ]] || { echo "missing positive input.sha256" >&2; exit 1; }
[[ -f "${POS_RUN_DIR}/checks/freeze_intake_validation.json" ]] || { echo "missing positive freeze_intake_validation.json" >&2; exit 1; }
[[ -f "${POS_RUN_DIR}/checks/pre_apply_validation.json" ]] || { echo "missing positive pre_apply_validation.json" >&2; exit 1; }
[[ -f "${POS_RUN_DIR}/checks/runtime_ready_reverify.json" ]] || { echo "missing positive runtime_ready_reverify.json" >&2; exit 1; }
[[ -f "${POS_RUN_DIR}/checks/declared_scope_evidence.json" ]] || { echo "missing positive declared_scope_evidence.json" >&2; exit 1; }
[[ -f "${POS_RUN_DIR}/checks/post_apply_validation.json" ]] || { echo "missing positive post_apply_validation.json" >&2; exit 1; }
[[ -f "${POS_RUN_DIR}/logs/apply.log" ]] || { echo "missing positive apply.log" >&2; exit 1; }
[[ -f "${POS_RUN_DIR}/execution_result.json" ]] || { echo "missing positive execution_result.json" >&2; exit 1; }
[[ -f "${POS_RUN_DIR}/report.json" ]] || { echo "missing positive report.json" >&2; exit 1; }
[[ -f "${POS_RUN_DIR}/report.md" ]] || { echo "missing positive report.md" >&2; exit 1; }
[[ -f "${POS_RUN_DIR}/timestamps.json" ]] || { echo "missing positive timestamps.json" >&2; exit 1; }
[[ -f "${POS_RUN_DIR}/staging/runtime-ready-applied/openclaw.template.json" ]] || { echo "missing positive staged package" >&2; exit 1; }

"${PYTHON_BIN}" - "${POS_RUN_DIR}/report.json" "${POS_RUN_DIR}/execution_result.json" "${POS_RUN_DIR}/run_meta.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
execution_result = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
run_meta = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8-sig"))

assert report["overall_status"] == "pass", report
assert report["summary"]["pre_apply_validation"] == "pass", report
assert report["summary"]["execution_result"] == "pass", report
assert execution_result["overall_status"] == "pass", execution_result
assert execution_result["summary"]["execute_apply"] == "pass", execution_result
assert run_meta["invoked_by"] == "smoke://phase3-positive", run_meta
PY

set +e
bash "${PHASE3_ROOT}/bin/run_phase3_bundle.sh" \
  --phase2-run-dir "${PHASE2_RUN_DIR}" \
  --execution-target-json "${NEG_TARGET_JSON}" \
  --run-id "${NEG_RUN_ID}"
NEG_BUNDLE_STATUS=$?
set -e

[[ "${NEG_BUNDLE_STATUS}" -ne 0 ]] || { echo "negative run must return non-zero" >&2; exit 1; }
[[ -f "${NEG_RUN_DIR}/exit_code" ]] || { echo "missing negative exit_code" >&2; exit 1; }
[[ "$(tr -d '\r\n' < "${NEG_RUN_DIR}/exit_code")" != "0" ]] || { echo "negative run exit_code must be non-zero" >&2; exit 1; }
[[ -f "${NEG_RUN_DIR}/checks/pre_apply_validation.json" ]] || { echo "missing negative pre_apply_validation.json" >&2; exit 1; }
[[ -f "${NEG_RUN_DIR}/report.json" ]] || { echo "missing negative report.json" >&2; exit 1; }
[[ -f "${NEG_RUN_DIR}/report.md" ]] || { echo "missing negative report.md" >&2; exit 1; }
[[ -f "${NEG_RUN_DIR}/timestamps.json" ]] || { echo "missing negative timestamps.json" >&2; exit 1; }
[[ ! -f "${NEG_RUN_DIR}/execution_result.json" ]] || { echo "negative execution_result.json must be absent" >&2; exit 1; }
[[ ! -d "${NEG_RUN_DIR}/staging/runtime-ready-applied" ]] || { echo "negative staging target must be absent" >&2; exit 1; }

"${PYTHON_BIN}" - "${NEG_RUN_DIR}/checks/pre_apply_validation.json" "${NEG_RUN_DIR}/report.json" "${NEG_RUN_DIR}/run_meta.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

pre_apply = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
run_meta = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8-sig"))

assert pre_apply["status"] == "fail", pre_apply
assert report["overall_status"] == "fail", report
assert report["summary"]["execution_result"] == "not_reached", report
assert report["summary"]["materialize_staging"] == "not_reached", report
assert run_meta["invoked_by"] == "smoke://phase3-negative", run_meta
PY

set +e
bash "${PHASE3_ROOT}/bin/run_phase3_bundle.sh" \
  --phase2-run-dir "${LATE_FAIL_PHASE2_RUN_DIR}" \
  --execution-target-json "${LATE_FAIL_TARGET_JSON}" \
  --run-id "${LATE_FAIL_RUN_ID}"
LATE_FAIL_BUNDLE_STATUS=$?
set -e

[[ "${LATE_FAIL_BUNDLE_STATUS}" -ne 0 ]] || { echo "late-fail run must return non-zero" >&2; exit 1; }
[[ -f "${LATE_FAIL_RUN_DIR}/logs/apply.log" ]] || { echo "late-fail apply.log must exist" >&2; exit 1; }
[[ ! -f "${LATE_FAIL_RUN_DIR}/checks/declared_scope_evidence.json" ]] || { echo "late-fail declared_scope_evidence.json must be absent" >&2; exit 1; }
[[ ! -f "${LATE_FAIL_RUN_DIR}/checks/post_apply_validation.json" ]] || { echo "late-fail post_apply_validation.json must be absent" >&2; exit 1; }
[[ ! -f "${LATE_FAIL_RUN_DIR}/execution_result.json" ]] || { echo "late-fail execution_result.json must be absent" >&2; exit 1; }
[[ -f "${LATE_FAIL_RUN_DIR}/report.json" ]] || { echo "missing late-fail report.json" >&2; exit 1; }
[[ -f "${LATE_FAIL_RUN_DIR}/report.md" ]] || { echo "missing late-fail report.md" >&2; exit 1; }
[[ -f "${LATE_FAIL_RUN_DIR}/timestamps.json" ]] || { echo "missing late-fail timestamps.json" >&2; exit 1; }
[[ -f "${LATE_FAIL_RUN_DIR}/exit_code" ]] || { echo "missing late-fail exit_code" >&2; exit 1; }
[[ "$(tr -d '\r\n' < "${LATE_FAIL_RUN_DIR}/exit_code")" != "0" ]] || { echo "late-fail exit_code must be non-zero" >&2; exit 1; }

"${PYTHON_BIN}" - "${LATE_FAIL_RUN_DIR}/report.json" "${LATE_FAIL_RUN_DIR}/run_meta.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
run_meta = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8-sig"))

assert report["overall_status"] == "fail", report
assert report["summary"]["materialize_staging"] == "pass", report
assert report["summary"]["execute_apply"] == "fail", report
assert report["summary"]["declared_scope_evidence"] == "not_reached", report
assert report["summary"]["post_apply_validation"] == "not_reached", report
assert report["summary"]["execution_result"] == "not_reached", report
assert run_meta["invoked_by"] == "smoke://phase3-late-fail", run_meta
PY

echo "phase3 smoke tests passed"
