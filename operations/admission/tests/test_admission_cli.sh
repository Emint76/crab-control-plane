#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMISSION_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ADMISSION_ROOT}/../.." && pwd)"
RUNNER="${ADMISSION_ROOT}/bin/run_admission.sh"
TMP_PARENT="${TMPDIR:-/tmp}"
TMP_ROOT="$(mktemp -d "${TMP_PARENT%/}/admission-cli.XXXXXX")"

PYTHON_BIN="${ADMISSION_TEST_PYTHON_BIN:-${ADMISSION_PYTHON_BIN:-${PYTHON:-python3}}}"

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && -d "${TMP_ROOT}" && "${TMP_ROOT}" == "${TMP_PARENT%/}"/admission-cli.* ]]; then
    rm -rf "${TMP_ROOT}"
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL %s\n' "$*" >&2
  exit 1
}

snapshot_repo_surfaces() {
  "${PYTHON_BIN}" - "${REPO_ROOT}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

repo = Path(sys.argv[1])
paths = [
    "knowledge/kb",
    "operations/harness-phase2/runs",
    "operations/harness-phase3/runs",
    "operations/harness-phase3/targets",
    "operations/harness-phase4/runs",
]
snapshot = {}
for rel in paths:
    root = repo / rel
    if root.exists():
        snapshot[rel] = sorted(path.relative_to(root).as_posix() for path in root.rglob("*"))
    else:
        snapshot[rel] = []
print(json.dumps(snapshot, sort_keys=True))
PY
}

assert_json_result() {
  local output="$1"
  "${PYTHON_BIN}" - "${output}" "${ADMISSION_ROOT}/schemas/admission_result.schema.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

output = Path(sys.argv[1])
schema_path = Path(sys.argv[2])
text = output.read_text(encoding="utf-8")
assert text.lstrip().startswith("{"), text
assert text.rstrip().endswith("}"), text
result = json.loads(text)
schema = json.loads(schema_path.read_text(encoding="utf-8"))
Draft202012Validator.check_schema(schema)
errors = sorted(Draft202012Validator(schema).iter_errors(result), key=lambda error: list(error.absolute_path))
assert not errors, [error.message for error in errors]
PY
}

assert_result_field() {
  local output="$1"
  local field="$2"
  local expected_json="$3"
  "${PYTHON_BIN}" - "${output}" "${field}" "${expected_json}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

result = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
field = sys.argv[2]
expected = json.loads(sys.argv[3])
value = result
for part in field.split("."):
    value = value[part]
assert value == expected, (field, value, expected, result)
PY
}

assert_blocker() {
  local output="$1"
  local expected_code="$2"
  "${PYTHON_BIN}" - "${output}" "${expected_code}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

result = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expected = sys.argv[2]
codes = [item["code"] for item in result["blockers"]]
assert result["validation_status"] == "fail", result
assert expected in codes, (expected, codes, result)
assert result["admission_status"] == "not_run", result
assert result["evidence"]["phase_invoked"] is False, result
assert result["evidence"]["canonical_write_performed"] is False, result
PY
}

run_package() {
  local package_dir="$1"
  local output="$2"
  local stderr_path="$3"
  set +e
  ADMISSION_PYTHON_BIN="${PYTHON_BIN}" bash "${RUNNER}" --package "${package_dir}" --dry-run >"${output}" 2>"${stderr_path}"
  local status=$?
  set -e
  return "${status}"
}

write_source_package() {
  local package_dir="$1"
  local payload_name="${2:-payload}"
  local review_status="${3:-approved}"
  mkdir -p "${package_dir}/${payload_name}"
  cat > "${package_dir}/admission_package.json" <<EOF
{
  "admission_kind": "source_capture",
  "profile_id": "source_capture.v1",
  "asset_id": "source-example",
  "payload_path": "${payload_name}",
  "review_status": "${review_status}",
  "provenance": {
    "operator": "test"
  }
}
EOF
}

write_knowledge_package() {
  local package_dir="$1"
  local knowledge_profile_id="${2:-product_type_extraction.v1}"
  local payload_name="${3:-payload.json}"
  local review_status="${4:-approved}"
  mkdir -p "${package_dir}"
  printf '{"payload": true}\n' > "${package_dir}/${payload_name}"
  cat > "${package_dir}/admission_package.json" <<EOF
{
  "admission_kind": "knowledge_asset",
  "profile_id": "knowledge_asset.v1",
  "asset_id": "knowledge-example",
  "payload_path": "${payload_name}",
  "review_status": "${review_status}",
  "provenance": {
    "source_id": "SOURCE-ID-FROM-CANONICAL-PACKAGE",
    "source_asset_path": "canonical/source/path"
  },
  "knowledge_profile_id": "${knowledge_profile_id}",
  "profile_data": {
    "arbitrary_type_specific_field": {
      "not_checked_by_admission": true
    }
  }
}
EOF
}

schemas=(
  "${ADMISSION_ROOT}/schemas/admission_package.schema.json"
  "${ADMISSION_ROOT}/schemas/admission_result.schema.json"
  "${ADMISSION_ROOT}/schemas/source_capture.v1.schema.json"
  "${ADMISSION_ROOT}/schemas/knowledge_asset.v1.schema.json"
)

"${PYTHON_BIN}" - "${schemas[@]}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

for arg in sys.argv[1:]:
    schema = json.loads(Path(arg).read_text(encoding="utf-8"))
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema", arg
    Draft202012Validator.check_schema(schema)
PY

[[ ! -e "${ADMISSION_ROOT}/schemas/knowledge-types" ]] || fail "admission knowledge-types schemas directory must not exist"
[[ ! -e "${ADMISSION_ROOT}/schemas/product_type_extraction.v1.schema.json" ]] || fail "product type schema must not exist in admission"
[[ ! -e "${ADMISSION_ROOT}/schemas/recipe_formula_extraction.v1.schema.json" ]] || fail "recipe schema must not exist in admission"
[[ ! -e "${ADMISSION_ROOT}/schemas/component_profile.v1.schema.json" ]] || fail "component schema must not exist in admission"
if rg -n "class .*Validator|profile_data_schema_failed|structural_validator_ref|schema_ref.*product_type|knowledge-types" \
  "${ADMISSION_ROOT}/lib" \
  "${ADMISSION_ROOT}/profiles" \
  "${ADMISSION_ROOT}/knowledge-profiles" \
  "${ADMISSION_ROOT}/schemas" >/tmp/admission-forbidden-validator.out; then
  cat /tmp/admission-forbidden-validator.out >&2
  fail "custom/fallback or type-specific validator marker found"
fi

before_snapshot="$(snapshot_repo_surfaces)"

source_pkg="${TMP_ROOT}/valid-source"
write_source_package "${source_pkg}"
if ! run_package "${source_pkg}" "${TMP_ROOT}/source.out" "${TMP_ROOT}/source.err"; then
  cat "${TMP_ROOT}/source.err" >&2
  fail "valid source package failed"
fi
assert_json_result "${TMP_ROOT}/source.out"
assert_result_field "${TMP_ROOT}/source.out" "validation_status" '"pass"'
assert_result_field "${TMP_ROOT}/source.out" "knowledge_profile_id" 'null'
[[ ! -s "${TMP_ROOT}/source.err" ]] || fail "valid source emitted stderr"

knowledge_pkg="${TMP_ROOT}/valid-knowledge"
write_knowledge_package "${knowledge_pkg}"
if ! run_package "${knowledge_pkg}" "${TMP_ROOT}/knowledge.out" "${TMP_ROOT}/knowledge.err"; then
  cat "${TMP_ROOT}/knowledge.err" >&2
  fail "valid knowledge package failed"
fi
assert_json_result "${TMP_ROOT}/knowledge.out"
assert_result_field "${TMP_ROOT}/knowledge.out" "validation_status" '"pass"'
assert_result_field "${TMP_ROOT}/knowledge.out" "knowledge_profile_id" '"product_type_extraction.v1"'
[[ ! -s "${TMP_ROOT}/knowledge.err" ]] || fail "valid knowledge emitted stderr"

semantic_free_pkg="${TMP_ROOT}/semantic-free"
write_knowledge_package "${semantic_free_pkg}"
"${PYTHON_BIN}" - "${semantic_free_pkg}/admission_package.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["profile_data"] = {"no_product": True, "ambiguous": ["not", "checked"], "confidence": "not-a-product-type-vocabulary"}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
if ! run_package "${semantic_free_pkg}" "${TMP_ROOT}/semantic-free.out" "${TMP_ROOT}/semantic-free.err"; then
  cat "${TMP_ROOT}/semantic-free.err" >&2
  fail "opaque profile_data package failed"
fi
assert_result_field "${TMP_ROOT}/semantic-free.out" "validation_status" '"pass"'

malformed="${TMP_ROOT}/malformed"
mkdir -p "${malformed}"
printf '{not-json\n' > "${malformed}/admission_package.json"
if run_package "${malformed}" "${TMP_ROOT}/malformed.out" "${TMP_ROOT}/malformed.err"; then
  fail "malformed package unexpectedly passed"
fi
assert_json_result "${TMP_ROOT}/malformed.out"
assert_blocker "${TMP_ROOT}/malformed.out" "package_json_invalid"

unknown_kind="${TMP_ROOT}/unknown-kind"
write_source_package "${unknown_kind}"
"${PYTHON_BIN}" - "${unknown_kind}/admission_package.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["admission_kind"] = "future_kind"
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
if run_package "${unknown_kind}" "${TMP_ROOT}/unknown-kind.out" "${TMP_ROOT}/unknown-kind.err"; then
  fail "unknown kind unexpectedly passed"
fi
assert_blocker "${TMP_ROOT}/unknown-kind.out" "unknown_admission_kind"

unknown_profile="${TMP_ROOT}/unknown-profile"
write_source_package "${unknown_profile}"
"${PYTHON_BIN}" - "${unknown_profile}/admission_package.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["profile_id"] = "future_profile.v1"
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
if run_package "${unknown_profile}" "${TMP_ROOT}/unknown-profile.out" "${TMP_ROOT}/unknown-profile.err"; then
  fail "unknown profile unexpectedly passed"
fi
assert_blocker "${TMP_ROOT}/unknown-profile.out" "unknown_profile_id"

mismatch="${TMP_ROOT}/mismatch"
write_source_package "${mismatch}"
"${PYTHON_BIN}" - "${mismatch}/admission_package.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["profile_id"] = "knowledge_asset.v1"
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
if run_package "${mismatch}" "${TMP_ROOT}/mismatch.out" "${TMP_ROOT}/mismatch.err"; then
  fail "kind/profile mismatch unexpectedly passed"
fi
assert_blocker "${TMP_ROOT}/mismatch.out" "kind_profile_mismatch"

missing_knowledge="${TMP_ROOT}/missing-knowledge-profile"
write_knowledge_package "${missing_knowledge}"
"${PYTHON_BIN}" - "${missing_knowledge}/admission_package.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
del payload["knowledge_profile_id"]
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
if run_package "${missing_knowledge}" "${TMP_ROOT}/missing-knowledge.out" "${TMP_ROOT}/missing-knowledge.err"; then
  fail "missing knowledge_profile_id unexpectedly passed"
fi
assert_blocker "${TMP_ROOT}/missing-knowledge.out" "missing_knowledge_profile_id"

forbidden_knowledge="${TMP_ROOT}/forbidden-knowledge-profile"
write_source_package "${forbidden_knowledge}"
"${PYTHON_BIN}" - "${forbidden_knowledge}/admission_package.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["knowledge_profile_id"] = "product_type_extraction.v1"
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
if run_package "${forbidden_knowledge}" "${TMP_ROOT}/forbidden-knowledge.out" "${TMP_ROOT}/forbidden-knowledge.err"; then
  fail "forbidden knowledge_profile_id unexpectedly passed"
fi
assert_blocker "${TMP_ROOT}/forbidden-knowledge.out" "forbidden_knowledge_profile_id"

forbidden_profile_data="${TMP_ROOT}/forbidden-profile-data"
write_source_package "${forbidden_profile_data}"
"${PYTHON_BIN}" - "${forbidden_profile_data}/admission_package.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["profile_data"] = {"forbidden": True}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
if run_package "${forbidden_profile_data}" "${TMP_ROOT}/forbidden-profile-data.out" "${TMP_ROOT}/forbidden-profile-data.err"; then
  fail "forbidden profile_data unexpectedly passed"
fi
assert_blocker "${TMP_ROOT}/forbidden-profile-data.out" "forbidden_profile_data"

unknown_kp="${TMP_ROOT}/unknown-knowledge-profile"
write_knowledge_package "${unknown_kp}" "future_profile.v1"
if run_package "${unknown_kp}" "${TMP_ROOT}/unknown-kp.out" "${TMP_ROOT}/unknown-kp.err"; then
  fail "unknown knowledge profile unexpectedly passed"
fi
assert_blocker "${TMP_ROOT}/unknown-kp.out" "unknown_knowledge_profile_id"

for disabled in recipe_formula_extraction.v1 component_profile.v1; do
  disabled_pkg="${TMP_ROOT}/disabled-${disabled}"
  write_knowledge_package "${disabled_pkg}" "${disabled}"
  if run_package "${disabled_pkg}" "${TMP_ROOT}/disabled-${disabled}.out" "${TMP_ROOT}/disabled-${disabled}.err"; then
    fail "disabled knowledge profile unexpectedly passed: ${disabled}"
  fi
  assert_blocker "${TMP_ROOT}/disabled-${disabled}.out" "disabled_knowledge_profile_id"
done

missing_profile_data="${TMP_ROOT}/missing-profile-data"
write_knowledge_package "${missing_profile_data}"
"${PYTHON_BIN}" - "${missing_profile_data}/admission_package.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
del payload["profile_data"]
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
if run_package "${missing_profile_data}" "${TMP_ROOT}/missing-profile-data.out" "${TMP_ROOT}/missing-profile-data.err"; then
  fail "missing profile_data unexpectedly passed"
fi
assert_blocker "${TMP_ROOT}/missing-profile-data.out" "missing_profile_data"

for profile_data_value in '"not-object"' '{}'; do
  invalid_profile_data="${TMP_ROOT}/invalid-profile-data-${profile_data_value//[^A-Za-z0-9]/x}"
  write_knowledge_package "${invalid_profile_data}"
  "${PYTHON_BIN}" - "${invalid_profile_data}/admission_package.json" "${profile_data_value}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["profile_data"] = json.loads(sys.argv[2])
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
  if run_package "${invalid_profile_data}" "${TMP_ROOT}/invalid-profile-data.out" "${TMP_ROOT}/invalid-profile-data.err"; then
    fail "invalid profile_data unexpectedly passed: ${profile_data_value}"
  fi
  assert_blocker "${TMP_ROOT}/invalid-profile-data.out" "invalid_profile_data_container"
done

non_approved="${TMP_ROOT}/non-approved"
write_knowledge_package "${non_approved}" "product_type_extraction.v1" "payload.json" "pending"
if run_package "${non_approved}" "${TMP_ROOT}/non-approved.out" "${TMP_ROOT}/non-approved.err"; then
  fail "non-approved package unexpectedly passed"
fi
assert_blocker "${TMP_ROOT}/non-approved.out" "review_not_approved"

missing_payload="${TMP_ROOT}/missing-payload"
write_source_package "${missing_payload}" "payload"
rm -rf "${missing_payload}/payload"
if run_package "${missing_payload}" "${TMP_ROOT}/missing-payload.out" "${TMP_ROOT}/missing-payload.err"; then
  fail "missing payload unexpectedly passed"
fi
assert_blocker "${TMP_ROOT}/missing-payload.out" "missing_payload"

payload_kind="${TMP_ROOT}/payload-kind"
write_source_package "${payload_kind}" "payload"
rm -rf "${payload_kind}/payload"
printf 'not a directory\n' > "${payload_kind}/payload"
if run_package "${payload_kind}" "${TMP_ROOT}/payload-kind.out" "${TMP_ROOT}/payload-kind.err"; then
  fail "payload kind mismatch unexpectedly passed"
fi
assert_blocker "${TMP_ROOT}/payload-kind.out" "payload_kind_mismatch"

absolute_payload="${TMP_ROOT}/absolute-payload"
write_source_package "${absolute_payload}" "payload"
"${PYTHON_BIN}" - "${absolute_payload}/admission_package.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["payload_path"] = "/tmp/payload"
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
if run_package "${absolute_payload}" "${TMP_ROOT}/absolute-payload.out" "${TMP_ROOT}/absolute-payload.err"; then
  fail "absolute payload unexpectedly passed"
fi
assert_blocker "${TMP_ROOT}/absolute-payload.out" "absolute_payload_path"

traversal="${TMP_ROOT}/traversal"
write_source_package "${traversal}" "payload"
"${PYTHON_BIN}" - "${traversal}/admission_package.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["payload_path"] = "../payload"
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
if run_package "${traversal}" "${TMP_ROOT}/traversal.out" "${TMP_ROOT}/traversal.err"; then
  fail "traversal payload unexpectedly passed"
fi
assert_blocker "${TMP_ROOT}/traversal.out" "payload_path_escape"

extra_field="${TMP_ROOT}/extra-field"
write_source_package "${extra_field}" "payload"
"${PYTHON_BIN}" - "${extra_field}/admission_package.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["unexpected"] = True
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
if run_package "${extra_field}" "${TMP_ROOT}/extra-field.out" "${TMP_ROOT}/extra-field.err"; then
  fail "standard schema rejected package unexpectedly passed"
fi
assert_blocker "${TMP_ROOT}/extra-field.out" "common_schema_failed"

python_no_site="${TMP_ROOT}/python-no-site"
cat > "${python_no_site}" <<EOF
#!/usr/bin/env bash
exec "${PYTHON_BIN}" -S "\$@"
EOF
chmod +x "${python_no_site}"
set +e
ADMISSION_PYTHON_BIN="${python_no_site}" bash "${RUNNER}" --package "${source_pkg}" --dry-run >"${TMP_ROOT}/missing-jsonschema.out" 2>"${TMP_ROOT}/missing-jsonschema.err"
missing_dep_status=$?
set -e
[[ "${missing_dep_status}" -ne 0 ]] || fail "missing jsonschema unexpectedly passed"
[[ ! -s "${TMP_ROOT}/missing-jsonschema.out" ]] || fail "missing jsonschema wrote stdout"
grep -F "jsonschema is required" "${TMP_ROOT}/missing-jsonschema.err" >/dev/null || fail "missing jsonschema stderr was not clear"

after_snapshot="$(snapshot_repo_surfaces)"
[[ "${before_snapshot}" == "${after_snapshot}" ]] || fail "repo KB/Phase run surfaces changed"

printf 'PASS admission CLI Stage 1 dry-run validation\n'
