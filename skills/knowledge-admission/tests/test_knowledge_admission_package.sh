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
if violations:
    raise SystemExit("obvious credential material found: " + ", ".join(violations))

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
    "Only Phase3 freezes execution inputs",
    "When the shared Phase admission procedure Skill exists",
    "Allowed claims",
    "Forbidden claims",
    "Required Final Report",
    "/home/node/.openclaw/workspace/repos/crab-control-plane",
    "OPENCLAW_WORKSPACE_KB_ROOT",
]
for fragment in skill_required:
    if fragment not in skill:
        raise SystemExit(f"SKILL.md missing required fragment: {fragment}")

example_required = [
    "accepted provenance-bearing source",
    "recipe_formula_extraction.v1",
    "candidate",
    "knowledge package",
    "admission_package.json",
    "admission_handoff.json",
    "standalone admission preflight",
    "exact-HEAD Phase2 baseline",
    "Phase4 wrapper",
    "Phase3 kb_admission",
    "Phase3 evidence",
]
for fragment in example_required:
    if fragment not in example:
        raise SystemExit(f"knowledge-admission example missing route fragment: {fragment}")

profiles = registry["profiles"]
entry = profiles["recipe_formula_extraction.v1"]
instruction_ref = entry.get("instruction_ref")
if not isinstance(instruction_ref, str) or not instruction_ref:
    raise SystemExit("recipe_formula_extraction.v1 must have instruction_ref")
if instruction_ref.startswith("/") or ".." in Path(instruction_ref).parts:
    raise SystemExit("instruction_ref must be repo-relative and safe")
if not (repo / instruction_ref).is_file():
    raise SystemExit("instruction_ref target is missing: " + instruction_ref)

for forbidden in ["schema_ref", "semantic_validator", "structural_validator_ref", "parser_ref"]:
    if forbidden in entry:
        raise SystemExit(f"registry entry must not contain {forbidden}")

print("PASS knowledge-admission skill package validation")
PY
