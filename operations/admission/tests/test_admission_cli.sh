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

import hashlib
import json
import os
import stat
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


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def object_record(path: Path, rel_path: str | None = None) -> dict[str, object]:
    st = os.lstat(path)
    mode = st.st_mode
    record: dict[str, object] = {}
    if rel_path is not None:
        record["path"] = rel_path
    if stat.S_ISDIR(mode):
        record["type"] = "directory"
    elif stat.S_ISREG(mode):
        record["type"] = "file"
        record["sha256"] = file_sha256(path)
    elif stat.S_ISLNK(mode):
        record["type"] = "symlink"
        record["target"] = os.readlink(path)
    else:
        record["type"] = "other"
        record["mode"] = stat.S_IFMT(mode)
    return record


def snapshot_root(root: Path) -> dict[str, object]:
    if not root.exists() and not root.is_symlink():
        return {"state": "missing", "entries": []}

    root_record = object_record(root)
    root_type = str(root_record["type"])
    if root_type == "file":
        return {"state": "file", "sha256": root_record["sha256"], "entries": []}
    if root_type == "symlink":
        return {"state": "symlink", "target": root_record["target"], "entries": []}
    if root_type != "directory":
        return {"state": root_type, "entries": []}

    entries: list[dict[str, object]] = []

    def walk(directory: Path) -> None:
        for child in sorted(directory.iterdir(), key=lambda item: item.name):
            rel = child.relative_to(root).as_posix()
            record = object_record(child, rel)
            entries.append(record)
            if record["type"] == "directory":
                walk(child)

    walk(root)
    return {"state": "directory", "entries": entries}


snapshot = {}
for rel in paths:
    snapshot[rel] = snapshot_root(repo / rel)
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

"${PYTHON_BIN}" - "${ADMISSION_ROOT}/schemas/admission_result.schema.json" <<'PY'
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

schema = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema)

base = {
    "validation_status": "pass",
    "admission_status": "not_run",
    "mode": "dry_run",
    "admission_kind": "knowledge_asset",
    "profile_id": "knowledge_asset.v1",
    "knowledge_profile_id": "product_type_extraction.v1",
    "asset_id": "example",
    "package_path": "/tmp/package",
    "payload_path": "/tmp/package/payload.json",
    "proposed_target_path": None,
    "blockers": [],
    "evidence": {
        "phase_invoked": False,
        "canonical_write_performed": False,
    },
}


def assert_valid(payload: dict[str, object]) -> None:
    errors = sorted(validator.iter_errors(payload), key=lambda error: list(error.absolute_path))
    assert not errors, [error.message for error in errors]


def assert_invalid(payload: dict[str, object]) -> None:
    errors = sorted(validator.iter_errors(payload), key=lambda error: list(error.absolute_path))
    assert errors, payload


valid_pass = copy.deepcopy(base)
assert_valid(valid_pass)

invalid_pass = copy.deepcopy(base)
invalid_pass["blockers"] = [{"code": "x", "message": "should not be present"}]
assert_invalid(invalid_pass)

valid_fail = copy.deepcopy(base)
valid_fail["validation_status"] = "fail"
valid_fail["blockers"] = [{"code": "x", "message": "validation failed"}]
assert_valid(valid_fail)

invalid_fail = copy.deepcopy(base)
invalid_fail["validation_status"] = "fail"
assert_invalid(invalid_fail)

valid_source = copy.deepcopy(base)
valid_source["admission_kind"] = "source_capture"
valid_source["profile_id"] = "source_capture.v1"
valid_source["knowledge_profile_id"] = None
assert_valid(valid_source)

invalid_source = copy.deepcopy(valid_source)
invalid_source["knowledge_profile_id"] = "product_type_extraction.v1"
assert_invalid(invalid_source)

valid_knowledge = copy.deepcopy(base)
assert_valid(valid_knowledge)

invalid_knowledge = copy.deepcopy(base)
invalid_knowledge["knowledge_profile_id"] = None
assert_invalid(invalid_knowledge)

early_failure = copy.deepcopy(base)
early_failure["validation_status"] = "fail"
early_failure["admission_kind"] = None
early_failure["profile_id"] = None
early_failure["knowledge_profile_id"] = None
early_failure["asset_id"] = None
early_failure["payload_path"] = None
early_failure["blockers"] = [{"code": "missing_package_file", "message": "Package file is missing"}]
assert_valid(early_failure)
PY

"${PYTHON_BIN}" - "${TMP_ROOT}" <<'PY'
from __future__ import annotations

import hashlib
import json
import os
import stat
import sys
from pathlib import Path

tmp = Path(sys.argv[1]) / "snapshot-model"
tmp.mkdir()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        digest.update(handle.read())
    return digest.hexdigest()


def object_record(path: Path, rel_path: str | None = None) -> dict[str, object]:
    st = os.lstat(path)
    mode = st.st_mode
    record: dict[str, object] = {}
    if rel_path is not None:
        record["path"] = rel_path
    if stat.S_ISDIR(mode):
        record["type"] = "directory"
    elif stat.S_ISREG(mode):
        record["type"] = "file"
        record["sha256"] = file_sha256(path)
    elif stat.S_ISLNK(mode):
        record["type"] = "symlink"
        record["target"] = os.readlink(path)
    else:
        record["type"] = "other"
    return record


def snapshot_root(root: Path) -> dict[str, object]:
    if not root.exists() and not root.is_symlink():
        return {"state": "missing", "entries": []}
    root_record = object_record(root)
    root_type = str(root_record["type"])
    if root_type == "file":
        return {"state": "file", "sha256": root_record["sha256"], "entries": []}
    if root_type == "symlink":
        return {"state": "symlink", "target": root_record["target"], "entries": []}
    if root_type != "directory":
        return {"state": root_type, "entries": []}
    entries: list[dict[str, object]] = []
    for child in sorted(root.iterdir(), key=lambda item: item.name):
        record = object_record(child, child.relative_to(root).as_posix())
        entries.append(record)
    return {"state": "directory", "entries": entries}


missing = snapshot_root(tmp / "missing")
empty_dir_path = tmp / "empty"
empty_dir_path.mkdir()
empty_dir = snapshot_root(empty_dir_path)
file_path = tmp / "file"
file_path.write_text("content", encoding="utf-8")
file_root = snapshot_root(file_path)
target_path = tmp / "target"
target_path.write_text("target-content", encoding="utf-8")
symlink_path = tmp / "link"
symlink_path.symlink_to("target")
symlink_root = snapshot_root(symlink_path)
nested = tmp / "nested"
nested.mkdir()
(nested / "empty-child").mkdir()
(nested / "child.txt").write_text("child", encoding="utf-8")
(nested / "child-link").symlink_to("child.txt")
nested_root = snapshot_root(nested)

assert missing == {"state": "missing", "entries": []}, missing
assert empty_dir == {"state": "directory", "entries": []}, empty_dir
assert missing != empty_dir
assert file_root["state"] == "file" and file_root["sha256"] == hashlib.sha256(b"content").hexdigest(), file_root
assert symlink_root == {"state": "symlink", "target": "target", "entries": []}, symlink_root
entry_by_path = {entry["path"]: entry for entry in nested_root["entries"]}
assert entry_by_path["empty-child"]["type"] == "directory", json.dumps(nested_root, sort_keys=True)
assert entry_by_path["child.txt"]["sha256"] == hashlib.sha256(b"child").hexdigest(), nested_root
assert entry_by_path["child-link"]["target"] == "child.txt", nested_root
PY

[[ ! -e "${ADMISSION_ROOT}/schemas/knowledge-types" ]] || fail "admission knowledge-types schemas directory must not exist"
[[ ! -e "${ADMISSION_ROOT}/schemas/product_type_extraction.v1.schema.json" ]] || fail "product type schema must not exist in admission"
[[ ! -e "${ADMISSION_ROOT}/schemas/recipe_formula_extraction.v1.schema.json" ]] || fail "recipe schema must not exist in admission"
[[ ! -e "${ADMISSION_ROOT}/schemas/component_profile.v1.schema.json" ]] || fail "component schema must not exist in admission"
"${PYTHON_BIN}" - "${ADMISSION_ROOT}" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
forbidden_files = {
    "product_type_extraction.v1.schema.json",
    "recipe_formula_extraction.v1.schema.json",
    "component_profile.v1.schema.json",
}
found_files = [
    path.relative_to(root).as_posix()
    for path in root.rglob("*")
    if path.is_file() and path.name in forbidden_files
]
if found_files:
    print("Type-specific admission schema files found:", file=sys.stderr)
    for item in found_files:
        print(f"- {item}", file=sys.stderr)
    raise SystemExit(1)

surfaces = [
    root / "lib",
    root / "profiles",
    root / "knowledge-profiles",
    root / "schemas",
]
patterns = [
    ("custom JSON Schema validator class", re.compile(r"class\s+(?!AdmissionError|InternalResultError)\w*Validator\b")),
    ("manual JSON Schema keyword implementation", re.compile(r"\b(anyOf|oneOf|allOf|patternProperties)\b.*\bin\s+schema\b")),
    ("profile_data_schema_failed blocker", re.compile(r"profile_data_schema_failed")),
    ("structural validator reference", re.compile(r"structural_validator_ref")),
    ("type-specific schema_ref", re.compile(r"schema_ref.*(product_type|recipe_formula|component_profile)")),
    ("semantic validator invocation", re.compile(r"semantic_.*validator|validator_ref")),
    ("admission-owned type schema path", re.compile(r"(knowledge-types|product_type_extraction\.v1\.schema|recipe_formula_extraction\.v1\.schema|component_profile\.v1\.schema)")),
    ("jsonschema validate shortcut", re.compile(r"jsonschema\.validate")),
]
violations: list[str] = []
for surface in surfaces:
    for path in sorted(surface.rglob("*")):
        if not path.is_file():
            continue
        if "__pycache__" in path.parts or path.suffix == ".pyc":
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            print(f"Could not read {path}: {exc}", file=sys.stderr)
            raise SystemExit(1) from exc
        for label, pattern in patterns:
            if pattern.search(text):
                violations.append(f"{path.relative_to(root)}: {label}")
if violations:
    print("Forbidden admission runtime/config/schema implementation markers found:", file=sys.stderr)
    for item in violations:
        print(f"- {item}", file=sys.stderr)
    raise SystemExit(1)
print("Custom or fallback JSON Schema validator implementation is absent. Admission uses only the standard jsonschema.Draft202012Validator.", file=sys.stderr)
PY

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

"${PYTHON_BIN}" - "${ADMISSION_ROOT}" "${source_pkg}" "${TMP_ROOT}" <<'PY'
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import sys
from pathlib import Path

admission_root = Path(sys.argv[1])
source_pkg = Path(sys.argv[2])
tmp_root = Path(sys.argv[3])
module_path = admission_root / "lib" / "admission_cli.py"
broken_schema = tmp_root / "broken_result.schema.json"
broken_schema.write_text(
    json.dumps(
        {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "type": "object",
            "properties": {
                "impossible": {"const": "required"}
            },
            "required": ["impossible"],
            "additionalProperties": False,
        },
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)

spec = importlib.util.spec_from_file_location("admission_cli_under_test", module_path)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
module.RESULT_SCHEMA = broken_schema

stdout = io.StringIO()
stderr = io.StringIO()
with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
    status = module.main(["--package", source_pkg.as_posix(), "--dry-run"])

assert status != 0, status
assert stdout.getvalue() == "", stdout.getvalue()
assert "internal admission result schema validation failed" in stderr.getvalue(), stderr.getvalue()
assert (admission_root / "schemas" / "admission_result.schema.json").read_text(encoding="utf-8")
PY

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
