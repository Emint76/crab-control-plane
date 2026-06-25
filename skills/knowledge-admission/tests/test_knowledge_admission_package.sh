#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PACKAGE_ROOT}/../.." && pwd)"

fail() {
  printf 'FAIL %s\n' "$*" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing required file: ${path#${REPO_ROOT}/}"
}

cd "${REPO_ROOT}"

require_file "${PACKAGE_ROOT}/SKILL.md"
require_file "${PACKAGE_ROOT}/references/knowledge-admission-example.md"
require_file "${PACKAGE_ROOT}/tests/test_knowledge_admission_package.sh"
require_file "knowledge/kb/extraction-profiles/cosmetics-household-chemistry/recipe-formula-extraction.v1.md"

if find "${PACKAGE_ROOT}" -type l -print -quit | grep -q .; then
  fail "symlink found inside knowledge-admission package"
fi

if find "${PACKAGE_ROOT}" \( -type d -name '__pycache__' -o -type f -name '*.pyc' \) -print -quit | grep -q .; then
  fail "cache or bytecode found inside knowledge-admission package"
fi

if find "${PACKAGE_ROOT}" \( -path '*/runs' -o -path '*/runs/*' -o -path '*/state' -o -path '*/state/*' -o -path '*/kb' -o -path '*/kb/*' \) -print -quit | grep -q .; then
  fail "generated runs, live state, or KB data found inside knowledge-admission package"
fi

if find "${PACKAGE_ROOT}" -type f \( -iname '*secret*' -o -iname '*credential*' -o -iname '*token*' -o -iname '*password*' -o -iname '*.env' -o -iname 'id_rsa*' \) -print -quit | grep -q .; then
  fail "obvious secret or credential file found inside knowledge-admission package"
fi

if ! awk '
  NR == 1 && $0 != "---" { exit 1 }
  NR > 1 && $0 == "---" { exit found ? 0 : 1 }
  NR > 1 && $0 == "name: knowledge-admission" { found = 1 }
  END { if (NR == 0) exit 1 }
' "${PACKAGE_ROOT}/SKILL.md"; then
  fail "SKILL.md frontmatter must contain name: knowledge-admission"
fi

python3 - "${REPO_ROOT}" <<'PY'
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1])
package = repo / "skills/knowledge-admission"
skill = (package / "SKILL.md").read_text(encoding="utf-8")
example = (package / "references/knowledge-admission-example.md").read_text(encoding="utf-8")
profile_path = repo / "knowledge/kb/extraction-profiles/cosmetics-household-chemistry/recipe-formula-extraction.v1.md"
profile = profile_path.read_text(encoding="utf-8")
template = (repo / "knowledge/kb/asset-templates/recipe-formula-extraction.md").read_text(encoding="utf-8")
registry = json.loads((repo / "operations/admission/knowledge-profiles/registry.v1.json").read_text(encoding="utf-8"))

patterns = [
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)\b(password|api[_-]?key|access[_-]?token|secret[_-]?key)\s*[:=]\s*['\"]?[^'\"\s]+"),
]
violations: list[str] = []
for path in sorted(item for item in package.rglob("*") if item.is_file()):
    text = path.read_text(encoding="utf-8", errors="replace")
    for pattern in patterns:
        if pattern.search(text):
            violations.append(path.relative_to(package).as_posix())
            break
assert not violations, "obvious credential material found: " + ", ".join(violations)

skill_required = [
    "Semantic extraction is agent-owned",
    "Admission, Phase2, Phase3, and Phase4 do not validate semantics",
    "Semantic review is deferred to the later wiki/semantic layer",
    "knowledge_profile_id: recipe_formula_extraction.v1",
    "knowledge_type` is an instance-local placement taxonomy segment",
    "<domain-area>/<source-family-id>/knowledge/<knowledge-type>/<asset-slug>/",
    "ADMISSION_KB_TAXONOMY_CONFIG=/absolute/outside-repository/kb-taxonomy-config.json",
    "Phase4 is the default operator-facing invocation route",
    "Phase3 remains the sole canonical execution owner",
    "the current repository Git HEAD exactly equals that recorded HEAD",
]
for fragment in skill_required:
    assert fragment in skill, fragment

example_required = [
    "admission_package.json",
    "review-decision.json",
    "admission_manifest.json",
    "execution_target.json",
    "admission_handoff.json",
    "standalone admission preflight",
    "exact-HEAD Phase2 baseline",
    "Phase4 wrapper",
    "Phase3 kb_admission",
    "example-recipe-formula",
    "recipe_formula_extraction.v1 -> example-recipe-formula",
]
for fragment in example_required:
    assert fragment in example, fragment
assert example.index("admission_package.json") < example.index("admission_handoff.json") < example.index("standalone admission preflight")
assert "This authorizes admission and placement only. It is not semantic review" in example
assert "Phase3 evidence proves runtime intake" in example

profile_required = [
    "# recipe_formula_extraction.v1",
    "`recipe_formula_extraction.v1` is an agent instruction profile",
    "knowledge/kb/asset-templates/recipe-formula-extraction.md",
    "This document is instruction metadata. It is not a JSON Schema, semantic validator, parser, Phase check, admission engine, or canonical taxonomy definition.",
    "This profile does not define `knowledge_type`.",
    "knowledge_profile_id` remains",
    "Phase2, Phase3, and Phase4 do not validate recipe semantics.",
]
for fragment in profile_required:
    assert fragment in profile, fragment

profiles = registry["profiles"]
entry = profiles["recipe_formula_extraction.v1"]
assert entry["status"] == "registered", entry
assert entry["instruction_ref"] == "knowledge/kb/extraction-profiles/cosmetics-household-chemistry/recipe-formula-extraction.v1.md"
assert (repo / entry["instruction_ref"]).is_file(), entry
assert "recipe_formula_extraction.v1" in (repo / entry["instruction_ref"]).read_text(encoding="utf-8")
for forbidden in ["knowledge_type", "schema_ref", "semantic_validator", "structural_validator_ref", "parser_ref"]:
    assert forbidden not in entry, (forbidden, entry)

for profile_id, profile_entry in profiles.items():
    assert "enabled_for_admission" not in profile_entry, profile_id
    allowed = {"payload_kind", "placement_policy_id", "status", "instruction_ref"}
    assert set(profile_entry).issubset(allowed), (profile_id, profile_entry)

assert 'knowledge_type: "recipe_formula_extraction"' not in template
assert 'knowledge_profile_id: "recipe_formula_extraction.v1"' in template
assert 'knowledge_type: "<instance-local-knowledge-type>"' in template

for text, label in [(skill, "SKILL.md"), (example, "knowledge-admission-example.md"), (profile, "recipe profile")]:
    for forbidden in [
        "semantic_validator",
        "recipe parser",
        "Phase semantic check",
        "semantic correctness is validated by Phase",
    ]:
        assert forbidden not in text, (label, forbidden)

print("PASS knowledge-admission skill package validation")
PY
