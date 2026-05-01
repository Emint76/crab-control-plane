#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RETENTION_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
REPO_ROOT="$(cd "${RETENTION_ROOT}/../.." && pwd -P)"
RUNS_ROOT="${RETENTION_ROOT}/runs"

PYTHON_BIN="${LIVE_RETENTION_TEST_PYTHON_BIN:-${LIVE_RETENTION_PYTHON_BIN:-${PHASE2_PYTHON_BIN:-}}}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set LIVE_RETENTION_TEST_PYTHON_BIN or install python/python3" >&2
    exit 1
  fi
fi
export LIVE_RETENTION_PYTHON_BIN="${LIVE_RETENTION_PYTHON_BIN:-${PYTHON_BIN}}"

VALID_RUN_ID="live-secret-retention-valid"
REPO_LOCAL_DECL_RUN_ID="live-secret-retention-repo-local-declaration"
BAD_EXT_RUN_ID="live-secret-retention-forbidden-extension"
BLOCKED_FIELD_RUN_ID="live-secret-retention-blocked-field"
BROKEN_REDACTION_RUN_ID="live-secret-retention-broken-redaction"
INVALID_RUN_ID="../bad"

VALID_RUN_DIR="${RUNS_ROOT}/${VALID_RUN_ID}"
REPO_LOCAL_DECL_RUN_DIR="${RUNS_ROOT}/${REPO_LOCAL_DECL_RUN_ID}"
BAD_EXT_RUN_DIR="${RUNS_ROOT}/${BAD_EXT_RUN_ID}"
BLOCKED_FIELD_RUN_DIR="${RUNS_ROOT}/${BLOCKED_FIELD_RUN_ID}"
BROKEN_REDACTION_RUN_DIR="${RUNS_ROOT}/${BROKEN_REDACTION_RUN_ID}"

TMP_ROOT="$(mktemp -d)"
DECLARATION_FILE="${TMP_ROOT}/source-declaration.json"
CANDIDATE_DIR="${TMP_ROOT}/candidate-evidence"
REPO_LOCAL_DECLARATION="${SCRIPT_DIR}/repo-local-source-declaration.tmp.json"
BAD_EXT_CANDIDATE_DIR="${TMP_ROOT}/candidate-evidence-bad-extension"
BLOCKED_FIELD_DECLARATION="${TMP_ROOT}/source-declaration-blocked-field.json"
BROKEN_REDACTION_CANDIDATE_DIR="${TMP_ROOT}/candidate-evidence-broken-redaction"

fail() {
  echo "FAIL $*" >&2
  exit 1
}

safe_rm_generated_dir() {
  local target="$1"
  local approved_root="$2"
  local expected_name="$3"

  "${PYTHON_BIN}" - "${target}" "${approved_root}" "${expected_name}" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

target = Path(sys.argv[1]).resolve(strict=False)
approved_root = Path(sys.argv[2]).resolve(strict=False)
expected_name = sys.argv[3]

try:
    relative = target.relative_to(approved_root)
except ValueError:
    print(f"refusing to delete outside live retention runs: {target}", file=sys.stderr)
    raise SystemExit(1)

if len(relative.parts) != 1 or target.name != expected_name:
    print(f"refusing to delete non-direct live retention run child: {target}", file=sys.stderr)
    raise SystemExit(1)
PY

  rm -rf -- "${target}"
}

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && "${TMP_ROOT}" == /tmp/* && -d "${TMP_ROOT}" ]]; then
    rm -rf -- "${TMP_ROOT}"
  fi
  rm -f -- "${REPO_LOCAL_DECLARATION}"
  safe_rm_generated_dir "${VALID_RUN_DIR}" "${RUNS_ROOT}" "${VALID_RUN_ID}"
  safe_rm_generated_dir "${REPO_LOCAL_DECL_RUN_DIR}" "${RUNS_ROOT}" "${REPO_LOCAL_DECL_RUN_ID}"
  safe_rm_generated_dir "${BAD_EXT_RUN_DIR}" "${RUNS_ROOT}" "${BAD_EXT_RUN_ID}"
  safe_rm_generated_dir "${BLOCKED_FIELD_RUN_DIR}" "${RUNS_ROOT}" "${BLOCKED_FIELD_RUN_ID}"
  safe_rm_generated_dir "${BROKEN_REDACTION_RUN_DIR}" "${RUNS_ROOT}" "${BROKEN_REDACTION_RUN_ID}"
}

assert_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing file: ${path}"
}

assert_dir() {
  local path="$1"
  [[ -d "${path}" ]] || fail "missing directory: ${path}"
}

assert_file_text_equals() {
  local path="$1"
  local expected="$2"
  assert_file "${path}"
  local actual
  actual="$(tr -d '\r\n' < "${path}")"
  [[ "${actual}" == "${expected}" ]] || fail "${path} expected ${expected}, got ${actual}"
}

write_declaration() {
  local path="$1"
  "${PYTHON_BIN}" - "${path}" "${TMP_ROOT}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
tmp_root = Path(sys.argv[2])
payload = {
    "declaration_kind": "secret-material-source-declaration",
    "declaration_label": "reviewed-live-material-source",
    "execution_label": "retention-execution-a",
    "local_only": True,
    "outside_git": True,
    "sources": [
        {
            "source_label": "reviewed-provider-config",
            "source_class": "outside-git-local-material",
            "source_path": str(tmp_root / "reviewed-material-root"),
            "contains_raw_secrets": True,
        }
    ],
}
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

write_candidate_evidence() {
  local dir="$1"
  "${PYTHON_BIN}" - "${dir}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.mkdir(parents=True, exist_ok=True)
(path / "event.json").write_text(
    json.dumps(
        {
            "event": "candidate-retention-evidence",
            "nested": {
                "api_key": "json-clear-value",
                "oauth": "json-oauth-value",
            },
            "plain": "kept",
        },
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)
(path / "operator.log").write_text(
    "\n".join(
        [
            "token=clear-token-value",
            "pass" + "word=clear-pass-value",
            "Authorization: Bearer clear-bearer-value",
            "credential=clear-credential-value",
            "safe_line=kept",
        ]
    )
    + "\n",
    encoding="utf-8",
)
(path / "notes.md").write_text(
    "review note with apikey=clear-apikey-value\n",
    encoding="utf-8",
)
PY
}

assert_report_field() {
  local report_path="$1"
  local field="$2"
  local expected="$3"
  "${PYTHON_BIN}" - "${report_path}" "${field}" "${expected}" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
field = sys.argv[2]
expected_raw = sys.argv[3]
if expected_raw == "true":
    expected = True
elif expected_raw == "false":
    expected = False
else:
    expected = expected_raw
actual = report[field]
assert actual == expected, (field, actual, expected, report)
PY
}

run_retention_expect_fail() {
  local label="$1"
  local run_id="$2"
  local run_dir="$3"
  local expected_field="$4"
  shift 4
  safe_rm_generated_dir "${run_dir}" "${RUNS_ROOT}" "${run_id}"

  set +e
  bash operations/harness-openclaw-live-retention/bin/run_secret_retention_surface.sh "$@" --run-id "${run_id}" >/dev/null 2>&1
  local status=$?
  set -e
  [[ "${status}" -ne 0 ]] || fail "negative live retention case unexpectedly passed: ${label}"
  assert_file "${run_dir}/retention_report.json"
  assert_report_field "${run_dir}/retention_report.json" "${expected_field}" "fail"
  echo "PASS live retention negative case rejected: ${label}"
}

cd "${REPO_ROOT}"
mkdir -p "${RUNS_ROOT}"
cleanup
trap cleanup EXIT

write_declaration "${DECLARATION_FILE}"
write_candidate_evidence "${CANDIDATE_DIR}"

bash operations/harness-openclaw-live-retention/bin/run_secret_retention_surface.sh \
  --source-declaration-file "${DECLARATION_FILE}" \
  --candidate-evidence-dir "${CANDIDATE_DIR}" \
  --run-id "${VALID_RUN_ID}"

assert_file "${VALID_RUN_DIR}/retention_meta.json"
assert_file "${VALID_RUN_DIR}/retention_report.json"
assert_file "${VALID_RUN_DIR}/checks/source_declaration_validation.json"
assert_file "${VALID_RUN_DIR}/checks/candidate_evidence_validation.json"
assert_file "${VALID_RUN_DIR}/checks/redaction_validation.json"
assert_dir "${VALID_RUN_DIR}/retained"
assert_file "${VALID_RUN_DIR}/retained/event.json"
assert_file "${VALID_RUN_DIR}/retained/operator.log"
assert_file "${VALID_RUN_DIR}/retained/notes.md"
assert_file "${VALID_RUN_DIR}/exit_code"
assert_file_text_equals "${VALID_RUN_DIR}/exit_code" "0"

"${PYTHON_BIN}" - "${VALID_RUN_DIR}" <<'PY'
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])

def load(name: str):
    return json.loads((run_dir / name).read_text(encoding="utf-8-sig"))

meta = load("retention_meta.json")
report = load("retention_report.json")
source_check = load("checks/source_declaration_validation.json")
candidate_check = load("checks/candidate_evidence_validation.json")
redaction_check = load("checks/redaction_validation.json")
event = load("retained/event.json")
operator_log = (run_dir / "retained" / "operator.log").read_text(encoding="utf-8-sig")
notes_md = (run_dir / "retained" / "notes.md").read_text(encoding="utf-8-sig")

assert meta["surface_kind"] == "live-secret-retention", meta
assert meta["live_runtime_apply"] is False, meta
assert meta["live_wrapper"] is False, meta
assert meta["crab_approved"] is False, meta
assert meta["retention_only"] is True, meta
assert meta["redaction_applied"] is True, meta

assert report["overall_status"] == "pass", report
assert report["source_declaration_validation"] == "pass", report
assert report["candidate_evidence_validation"] == "pass", report
assert report["redaction_validation"] == "pass", report
assert report["retained_file_count"] >= 1, report
assert report["live_runtime_apply"] is False, report
assert report["crab_approved"] is False, report
assert report["retention_only"] is True, report

assert source_check["status"] == "pass", source_check
assert candidate_check["status"] == "pass", candidate_check
assert redaction_check["status"] == "pass", redaction_check

assert event["nested"]["api_key"] == "[REDACTED]", event
assert event["nested"]["oauth"] == "[REDACTED]", event
assert "json-clear-value" not in json.dumps(event), event
assert "clear-token-value" not in operator_log, operator_log
assert "clear-pass-value" not in operator_log, operator_log
assert "clear-bearer-value" not in operator_log, operator_log
assert "clear-credential-value" not in operator_log, operator_log
assert "clear-apikey-value" not in notes_md, notes_md
assert operator_log.count("[REDACTED]") >= 4, operator_log
assert "[REDACTED]" in notes_md, notes_md

retained_text = "\n".join(
    path.read_text(encoding="utf-8-sig") for path in (run_dir / "retained").rglob("*") if path.is_file()
)
for raw in [
    "clear-token-value",
    "clear-pass-value",
    "clear-bearer-value",
    "clear-credential-value",
    "clear-apikey-value",
    "json-clear-value",
]:
    assert raw not in retained_text, raw
residual = re.search(r"(?i)(token|api[_-]?key|apikey|oauth|credential)\s*[:=]\s*(?!\[REDACTED\])\S+", retained_text)
assert residual is None, residual.group(0) if residual else None
PY

cp "${DECLARATION_FILE}" "${REPO_LOCAL_DECLARATION}"
run_retention_expect_fail \
  "repo-local declaration file" \
  "${REPO_LOCAL_DECL_RUN_ID}" \
  "${REPO_LOCAL_DECL_RUN_DIR}" \
  "source_declaration_validation" \
  --source-declaration-file "${REPO_LOCAL_DECLARATION}" \
  --candidate-evidence-dir "${CANDIDATE_DIR}"

mkdir -p "${BAD_EXT_CANDIDATE_DIR}"
cp "${CANDIDATE_DIR}/event.json" "${BAD_EXT_CANDIDATE_DIR}/event.json"
printf 'raw bytes are not allowed here\n' > "${BAD_EXT_CANDIDATE_DIR}/event.bin"
run_retention_expect_fail \
  "forbidden file extension" \
  "${BAD_EXT_RUN_ID}" \
  "${BAD_EXT_RUN_DIR}" \
  "candidate_evidence_validation" \
  --source-declaration-file "${DECLARATION_FILE}" \
  --candidate-evidence-dir "${BAD_EXT_CANDIDATE_DIR}"

cp "${DECLARATION_FILE}" "${BLOCKED_FIELD_DECLARATION}"
"${PYTHON_BIN}" - "${BLOCKED_FIELD_DECLARATION}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8-sig"))
payload["api_key"] = "not-allowed-in-declaration"
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
run_retention_expect_fail \
  "declaration forbidden key" \
  "${BLOCKED_FIELD_RUN_ID}" \
  "${BLOCKED_FIELD_RUN_DIR}" \
  "source_declaration_validation" \
  --source-declaration-file "${BLOCKED_FIELD_DECLARATION}" \
  --candidate-evidence-dir "${CANDIDATE_DIR}"

mkdir -p "${BROKEN_REDACTION_CANDIDATE_DIR}"
"${PYTHON_BIN}" - "${BROKEN_REDACTION_CANDIDATE_DIR}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.mkdir(parents=True, exist_ok=True)
(path / "broken.json").write_text(
    json.dumps({"message": "token=residual-value"}, indent=2) + "\n",
    encoding="utf-8",
)
PY
run_retention_expect_fail \
  "residual redaction pattern" \
  "${BROKEN_REDACTION_RUN_ID}" \
  "${BROKEN_REDACTION_RUN_DIR}" \
  "redaction_validation" \
  --source-declaration-file "${DECLARATION_FILE}" \
  --candidate-evidence-dir "${BROKEN_REDACTION_CANDIDATE_DIR}"

before_runs="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort)"
set +e
bash operations/harness-openclaw-live-retention/bin/run_secret_retention_surface.sh \
  --source-declaration-file "${DECLARATION_FILE}" \
  --candidate-evidence-dir "${CANDIDATE_DIR}" \
  --run-id "${INVALID_RUN_ID}" >/dev/null 2>&1
invalid_status=$?
set -e
[[ "${invalid_status}" -ne 0 ]] || fail "invalid run id unexpectedly passed"
after_runs="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort)"
[[ "${before_runs}" == "${after_runs}" ]] || fail "invalid run id created a live retention run dir"

echo "PASS live secret retention valid run"
echo "PASS live secret retention rejects invalid inputs"
