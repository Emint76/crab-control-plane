#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${HARNESS_ROOT}/../.." && pwd)"
RUNS_ROOT="${HARNESS_ROOT}/runs"
CAPTURE_RUN_ID="knowledge-smoke-capture-only-test"
SEMANTIC_MISSING_RUN_ID="knowledge-smoke-semantic-required-missing-test"
SEMANTIC_INVALID_RUN_ID="knowledge-smoke-semantic-required-invalid-test"
SEMANTIC_VALID_RUN_ID="knowledge-smoke-semantic-required-valid-test"
BAD_PYTHON_RUN_ID="knowledge-smoke-bad-python-test"
SOURCE_REF="control-plane/policy/ADMISSION_POLICY.md"

PYTHON_BIN="${KNOWLEDGE_PIPELINE_TEST_PYTHON_BIN:-${KNOWLEDGE_PIPELINE_PYTHON_BIN:-}}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set KNOWLEDGE_PIPELINE_TEST_PYTHON_BIN or install python/python3" >&2
    exit 1
  fi
fi

fail() {
  echo "FAIL $*" >&2
  exit 1
}

safe_remove_run_dir() {
  local run_id="$1"
  "${PYTHON_BIN}" - "${RUNS_ROOT}" "${run_id}" <<'PY'
from __future__ import annotations

import shutil
import sys
from pathlib import Path

runs_root = Path(sys.argv[1]).resolve(strict=False)
run_id = sys.argv[2]
target = (runs_root / run_id).resolve(strict=False)
try:
    relative = target.relative_to(runs_root)
except ValueError:
    print(f"refusing to remove outside knowledge runs: {target}", file=sys.stderr)
    raise SystemExit(1)
if len(relative.parts) != 1 or relative.parts[0] != run_id:
    print(f"refusing to remove non-direct knowledge run child: {target}", file=sys.stderr)
    raise SystemExit(1)
shutil.rmtree(target, ignore_errors=True)
PY
}

cleanup() {
  safe_remove_run_dir "${CAPTURE_RUN_ID}"
  safe_remove_run_dir "${SEMANTIC_MISSING_RUN_ID}"
  safe_remove_run_dir "${SEMANTIC_INVALID_RUN_ID}"
  safe_remove_run_dir "${SEMANTIC_VALID_RUN_ID}"
  safe_remove_run_dir "${BAD_PYTHON_RUN_ID}"
}

assert_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing file: ${path}"
}

assert_absent() {
  local path="$1"
  [[ ! -e "${path}" ]] || fail "unexpected path exists: ${path}"
}

assert_exit_code_file() {
  local run_id="$1"
  local expected="$2"
  local actual
  actual="$(tr -d '\r\n' < "${RUNS_ROOT}/${run_id}/exit_code")"
  [[ "${actual}" == "${expected}" ]] || fail "${run_id} exit_code expected ${expected}, got ${actual}"
}

write_valid_semantic_artifacts() {
  local run_id="$1"
  "${PYTHON_BIN}" - "${RUNS_ROOT}/${run_id}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])
output = run_dir / "output"
output.mkdir(parents=True, exist_ok=True)
source_ref = {"ref": "input/source.md", "description": "Captured source document", "locator": "full document"}
claim_ref = {"ref": "input/source_capture_package.json", "description": "Hash-bound source capture package"}
artifacts = [
    "output/normalized_note.md",
    "output/normalized_note.json",
    "output/result_packet.json",
    "output/placement_decision.candidate.json",
    "output/admission_decision.candidate.json",
    "output/canonical_knowledge_candidate.md",
    "output/wiki_derived_draft.md",
]
produced_artifacts = [
    {"path": "output/normalized_note.md", "kind": "markdown", "schema_ref": None, "description": "Human-readable normalized note"},
    {"path": "output/normalized_note.json", "kind": "json", "schema_ref": "operations/harness-knowledge-pipeline/contracts/normalized_note.schema.json", "description": "Machine-readable normalized note"},
    {"path": "output/result_packet.json", "kind": "json", "schema_ref": "operations/harness-knowledge-pipeline/contracts/result_packet.schema.json", "description": "Machine-readable result packet"},
    {"path": "output/placement_decision.candidate.json", "kind": "json", "schema_ref": "operations/harness-knowledge-pipeline/contracts/placement_decision_candidate.schema.json", "description": "Placement candidate"},
    {"path": "output/admission_decision.candidate.json", "kind": "json", "schema_ref": "operations/harness-knowledge-pipeline/contracts/admission_decision_candidate.schema.json", "description": "Admission candidate"},
    {"path": "output/canonical_knowledge_candidate.md", "kind": "markdown", "schema_ref": None, "description": "Draft canonical knowledge candidate"},
    {"path": "output/wiki_derived_draft.md", "kind": "markdown", "schema_ref": None, "description": "Derived wiki draft"},
]

def write_json(name: str, payload: object) -> None:
    (output / name).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

(output / "normalized_note.md").write_text(
    "# Admission policy normalized note\n\nClaim references `input/source_capture_package.json` and `input/source.md`.\n",
    encoding="utf-8",
)
write_json("normalized_note.json", {
    "artifact_type": "normalized-note",
    "status": "candidate",
    "source_refs": [source_ref, claim_ref],
    "title": "Admission policy semantic handoff",
    "summary": "A bounded semantic handoff note derived only from the captured admission policy source.",
    "claims": [{"claim_id": "claim-one", "text": "Canonical admission remains review gated and is not automatic.", "source_refs": [claim_ref], "confidence": "high"}],
    "entities": [{"name": "Admission policy", "description": "Policy source under review", "source_refs": [source_ref]}],
    "concepts": [{"name": "Canonical gate", "description": "Review boundary before canonical writes", "source_refs": [claim_ref]}],
    "gaps": [{"text": "No external source capture is included in this run.", "source_refs": [claim_ref]}],
    "uncertainties": [{"text": "Future synthesis behavior remains out of scope.", "source_refs": [claim_ref]}],
    "provenance": {"source_capture_ref": "input/source_capture_package.json", "task_packet_ref": "input/task_packet.json", "captured_source_ref": "input/source.md"},
})
write_json("result_packet.json", {
    "artifact_type": "knowledge-result-packet",
    "status": "candidate",
    "source_refs": [claim_ref],
    "summary": "Semantic artifacts are present, source-linked, and remain candidate-only.",
    "produced_artifacts": produced_artifacts,
    "claims": [{"claim_id": "claim-one", "text": "The run produced only run-dir semantic candidate artifacts.", "source_refs": [claim_ref]}],
    "gaps": [{"text": "Canonical KB admission is not performed.", "source_refs": [claim_ref]}],
    "improvement_candidates": [{"text": "Keep semantic-required validation schema-backed.", "scope": "validation", "rationale": "Schema-backed validation prevents silent contract drift."}],
    "validation_notes": ["Markdown artifacts are presence checked only in this PR."],
})
write_json("placement_decision.candidate.json", {
    "artifact_type": "placement-decision-candidate",
    "status": "candidate",
    "target_layer": "observability",
    "target_path": "operations/harness-knowledge-pipeline/runs/<RUN_ID>/output/",
    "rationale": "Semantic handoff artifacts remain run-scoped evidence until reviewed.",
    "review_required": True,
    "canonical_write_allowed": False,
    "source_refs": [claim_ref],
    "artifact_refs": artifacts,
    "blockers": [],
    "conditions": ["Separate canonical admission review is required before any KB write."],
})
write_json("admission_decision.candidate.json", {
    "artifact_type": "admission-decision-candidate",
    "decision": "hold",
    "canonical_admitted": False,
    "rationale": "This semantic-required run validates candidate artifacts only and does not admit canonical knowledge.",
    "checklist": [{"item": "Captured source remains hash-bound", "status": "pass", "evidence_refs": ["input/source_capture_package.json"]}],
    "blockers": ["Canonical KB write requires separate future gate."],
    "required_follow_up": ["Run admission review before any canonical KB promotion."],
    "source_refs": [claim_ref],
    "artifact_refs": artifacts,
})
(output / "canonical_knowledge_candidate.md").write_text(
    "# Canonical knowledge candidate\n\nCandidate-only draft. canonical_admitted=false. Source: `input/source_capture_package.json`.\n",
    encoding="utf-8",
)
(output / "wiki_derived_draft.md").write_text(
    "# Wiki derived draft\n\nDerived from `output/canonical_knowledge_candidate.md`; no new claims are introduced.\n",
    encoding="utf-8",
)
PY
}

cd "${REPO_ROOT}"
mkdir -p "${RUNS_ROOT}"
cleanup
trap cleanup EXIT

# Default mode is capture-only and must pass without semantic outputs.
KNOWLEDGE_PIPELINE_PYTHON_BIN="${PYTHON_BIN}" \
  bash operations/harness-knowledge-pipeline/bin/run_local_source_smoke.sh \
    "${CAPTURE_RUN_ID}" \
    "${SOURCE_REF}"

CAPTURE_RUN_DIR="${RUNS_ROOT}/${CAPTURE_RUN_ID}"
assert_file "${CAPTURE_RUN_DIR}/run_meta.json"
assert_file "${CAPTURE_RUN_DIR}/input/source.md"
assert_file "${CAPTURE_RUN_DIR}/input/source.sha256"
assert_file "${CAPTURE_RUN_DIR}/input/source_capture_package.json"
assert_file "${CAPTURE_RUN_DIR}/input/task_packet.json"
assert_file "${CAPTURE_RUN_DIR}/checks/expected_core_files.json"
assert_file "${CAPTURE_RUN_DIR}/checks/source_capture_schema.json"
assert_file "${CAPTURE_RUN_DIR}/checks/task_packet_schema.json"
assert_file "${CAPTURE_RUN_DIR}/checks/source_hash_validation.json"
assert_file "${CAPTURE_RUN_DIR}/checks/no_live_surface_validation.json"
assert_file "${CAPTURE_RUN_DIR}/report.json"
assert_file "${CAPTURE_RUN_DIR}/report.md"
assert_file "${CAPTURE_RUN_DIR}/exit_code"
assert_absent "${CAPTURE_RUN_DIR}/output/normalized_note.json"
assert_exit_code_file "${CAPTURE_RUN_ID}" "0"

"${PYTHON_BIN}" - "${CAPTURE_RUN_DIR}/report.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert report["mode"] == "capture-only", report
assert report["semantic_outputs_required"] is False, report
assert report["status"] == "pass", report
assert report["exit_code"] == 0, report
assert not any(check.get("status") == "awaiting_semantic_outputs" for check in report["checks"]), report
PY

# Explicit semantic-required mode returns 3 while semantic artifacts are absent.
set +e
KNOWLEDGE_PIPELINE_PYTHON_BIN="${PYTHON_BIN}" \
  bash operations/harness-knowledge-pipeline/bin/run_local_source_smoke.sh \
    --mode semantic-required \
    "${SEMANTIC_MISSING_RUN_ID}" \
    "${SOURCE_REF}"
semantic_missing_status=$?
set -e
[[ "${semantic_missing_status}" -eq 3 ]] || fail "semantic-required missing outputs expected exit 3, got ${semantic_missing_status}"
assert_exit_code_file "${SEMANTIC_MISSING_RUN_ID}" "3"

"${PYTHON_BIN}" - "${RUNS_ROOT}/${SEMANTIC_MISSING_RUN_ID}/report.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert report["mode"] == "semantic-required", report
assert report["semantic_outputs_required"] is True, report
assert report["status"] == "awaiting_semantic_outputs", report
assert report["exit_code"] == 3, report
assert any(check.get("status") == "awaiting_semantic_outputs" for check in report["checks"]), report
PY

# Semantic-required returns 1 when semantic JSON exists but fails schema validation.
KNOWLEDGE_PIPELINE_PYTHON_BIN="${PYTHON_BIN}" \
  bash operations/harness-knowledge-pipeline/bin/run_local_source_smoke.sh \
    --mode capture-only \
    "${SEMANTIC_INVALID_RUN_ID}" \
    "${SOURCE_REF}"
write_valid_semantic_artifacts "${SEMANTIC_INVALID_RUN_ID}"
"${PYTHON_BIN}" - "${RUNS_ROOT}/${SEMANTIC_INVALID_RUN_ID}/output/normalized_note.json" <<'PY'
from pathlib import Path
import json
import sys
path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload.pop("claims", None)
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
set +e
KNOWLEDGE_PIPELINE_PYTHON_BIN="${PYTHON_BIN}" \
  bash operations/harness-knowledge-pipeline/bin/run_local_source_smoke.sh \
    --mode semantic-required \
    "${SEMANTIC_INVALID_RUN_ID}" \
    "${SOURCE_REF}"
semantic_invalid_status=$?
set -e
[[ "${semantic_invalid_status}" -eq 1 ]] || fail "semantic-required invalid JSON expected exit 1, got ${semantic_invalid_status}"
assert_exit_code_file "${SEMANTIC_INVALID_RUN_ID}" "1"

"${PYTHON_BIN}" - "${RUNS_ROOT}/${SEMANTIC_INVALID_RUN_ID}/report.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert report["status"] == "fail", report
assert report["exit_code"] == 1, report
assert any(check.get("status") == "fail" and "normalized_note" in check.get("path", "") for check in report["checks"]), report
PY

# Semantic-required returns 0 when all required semantic artifacts exist and validate.
KNOWLEDGE_PIPELINE_PYTHON_BIN="${PYTHON_BIN}" \
  bash operations/harness-knowledge-pipeline/bin/run_local_source_smoke.sh \
    --mode capture-only \
    "${SEMANTIC_VALID_RUN_ID}" \
    "${SOURCE_REF}"
write_valid_semantic_artifacts "${SEMANTIC_VALID_RUN_ID}"
KNOWLEDGE_PIPELINE_PYTHON_BIN="${PYTHON_BIN}" \
  bash operations/harness-knowledge-pipeline/bin/run_local_source_smoke.sh \
    --mode semantic-required \
    "${SEMANTIC_VALID_RUN_ID}" \
    "${SOURCE_REF}"
assert_exit_code_file "${SEMANTIC_VALID_RUN_ID}" "0"

"${PYTHON_BIN}" - "${RUNS_ROOT}/${SEMANTIC_VALID_RUN_ID}/report.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert report["status"] == "pass", report
assert report["exit_code"] == 0, report
for check_name in [
    "semantic_artifact_set_schema",
    "normalized_note_schema",
    "result_packet_schema",
    "placement_decision_candidate_schema",
    "admission_decision_candidate_schema",
    "semantic_markdown_artifacts",
]:
    assert any(check_name in check.get("path", "") and check.get("status") == "pass" for check in report["checks"]), (check_name, report)
PY

# Explicit unavailable Python override must fail before capture with a clear diagnostic.
set +e
KNOWLEDGE_PIPELINE_PYTHON_BIN="/definitely/missing/python-for-knowledge-smoke" \
  bash operations/harness-knowledge-pipeline/bin/run_local_source_smoke.sh \
    --mode capture-only \
    "${BAD_PYTHON_RUN_ID}" \
    "${SOURCE_REF}" >"${RUNS_ROOT}/bad-python.stdout" 2>"${RUNS_ROOT}/bad-python.stderr"
bad_python_status=$?
set -e
[[ "${bad_python_status}" -ne 0 ]] || fail "missing python override unexpectedly succeeded"
grep -Fq "KNOWLEDGE_PIPELINE_PYTHON_BIN" "${RUNS_ROOT}/bad-python.stderr" || fail "missing diagnostic did not mention KNOWLEDGE_PIPELINE_PYTHON_BIN"
grep -Fq "python" "${RUNS_ROOT}/bad-python.stderr" || fail "missing diagnostic did not mention python"
assert_absent "${RUNS_ROOT}/${BAD_PYTHON_RUN_ID}"
rm -f -- "${RUNS_ROOT}/bad-python.stdout" "${RUNS_ROOT}/bad-python.stderr"

echo "PASS knowledge capture-only smoke exits 0 without semantic outputs"
echo "PASS knowledge semantic-required smoke exits 3 without semantic outputs"
echo "PASS knowledge semantic-required smoke exits 1 for invalid semantic JSON"
echo "PASS knowledge semantic-required smoke exits 0 for valid semantic artifacts"
echo "PASS knowledge runner reports unavailable Python override clearly"
