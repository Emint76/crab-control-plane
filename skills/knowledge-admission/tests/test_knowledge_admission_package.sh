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
    "KNOWLEDGE_DISTILLATION_FLOW_MATRIX=/path/to/instance/knowledge-distillation-flow-matrix.json",
    "accepted provenance-bearing input asset",
    "accepted `source_capture` assets",
    "already admitted `knowledge_asset` assets",
    "select active instance distillation flow",
    "select the flow-defined knowledge_profile_id",
    "use the output node knowledge_type",
    "each flow is exactly one edge",
    "only `active` flows may be executed",
    "draft or disabled flows must not be executed",
    "If exactly one active direct flow matches",
    "If multiple direct flows match",
    "If no active direct flow or connected active path exists",
    "A concrete input asset must be mapped to a declared matrix input node before flow selection",
    "If exactly one declared node matches",
    "If multiple declared nodes match",
    "Flow execution begins only after both input and output nodes are unambiguous",
    "must not guess a node from folder name, source-family name, asset ID, asset slug, profile ID, or undocumented semantic interpretation",
    "Do not invent a direct shortcut",
    "ordered sequence of connected active flows",
    "finite and simple",
    "same `flow_id` must not occur more than once in one path",
    "same `node_id` must not occur more than once in one path",
    "must not execute a cyclic or indefinitely repeating path",
    "exactly one matching finite simple active path",
    "Process one flow at a time",
    "The next hop may begin only after successful Phase3 evidence for the previous hop",
    "Each flow in a path has its own `knowledge_profile_id`",
    "A later hop does not inherit the preceding hop's profile",
    "Do not combine several hops into one knowledge candidate",
    "Do not use an unadmitted intermediate candidate",
    "Graph reachability does not authorize an undeclared direct flow",
    "branching paths and multiple independent incoming flows",
    "stop and request explicit user approval",
    "Semantic extraction is agent-owned",
    "Admission, Phase2, Phase3, and Phase4 do not validate semantic correctness, domain-specific correctness, domain-specific safety or compliance",
    "Semantic review is deferred to the later wiki/semantic layer",
    "profile_contract_id: knowledge_extraction.v1",
    "ADMISSION_KNOWLEDGE_PROFILE_REGISTRY",
    "ADMISSION_KNOWLEDGE_PROFILE_REGISTRY=/path/to/instance/knowledge-profile-registry.json",
    "knowledge_type` is an instance-local placement taxonomy segment",
    "<domain-area>/<source-family-id>/knowledge/<knowledge-type>/<asset-slug>/",
    "ADMISSION_KB_TAXONOMY_CONFIG=/path/to/instance/kb-taxonomy-config.json",
    "local taxonomy config is missing, nonexistent, not a file, invalid JSON, schema-invalid, or disallows the selected profile/type mapping",
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
    "knowledge_extraction.v1",
    "<instance-defined-knowledge-profile-id>",
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
if profiles:
    raise SystemExit("canonical knowledge profile registry must not contain active concrete profiles")

generic_contract = repo / "knowledge/kb/extraction-profiles/knowledge-extraction.v1.md"
if not generic_contract.is_file():
    raise SystemExit("missing generic knowledge_extraction.v1 contract")

matrix_contract_path = repo / "knowledge/kb/KNOWLEDGE_DISTILLATION_FLOW_MATRIX.md"
if not matrix_contract_path.is_file():
    raise SystemExit("missing Knowledge Distillation Flow Matrix contract")
matrix_contract = matrix_contract_path.read_text(encoding="utf-8")
matrix_required = [
    "knowledge_distillation_flow_matrix.v1",
    "Each flow represents exactly one semantic transformation edge",
    "one declared input node",
    "one declared output node",
    "A concrete input asset must be mapped to a declared matrix input node before flow selection",
    "if exactly one declared node matches",
    "if multiple declared nodes match",
    "flow execution begins only after both input and output nodes are unambiguous",
    "The agent must not guess a node from",
    "A distillation path is an ordered sequence of connected active flows",
    "finite simple path",
    "the same `flow_id` must not occur more than once in one path",
    "the same `node_id` must not occur more than once in one path",
    "must not execute a cyclic or indefinitely repeating path",
    "exactly one matching finite simple active path",
    "Path order is derived from graph connectivity",
    "The existing `nodes + flows` model is sufficient",
    "Every step produces a separate admitted knowledge asset",
    "Graph reachability does not authorize an undeclared direct flow",
    "A single output node may have multiple independent incoming flows",
    "Non-normative",
    "illustrative",
    "instance-defined",
    "not canonical",
]
for fragment in matrix_required:
    if fragment not in matrix_contract:
        raise SystemExit(f"matrix contract missing required fragment: {fragment}")

matrix_template_path = repo / "knowledge/kb/templates/knowledge-distillation-flow-matrix.template.json"
if not matrix_template_path.is_file():
    raise SystemExit("missing Knowledge Distillation Flow Matrix template")
matrix_template = json.loads(matrix_template_path.read_text(encoding="utf-8"))
if matrix_template.get("matrix_contract_id") != "knowledge_distillation_flow_matrix.v1":
    raise SystemExit("matrix template must use knowledge_distillation_flow_matrix.v1")
if matrix_template.get("matrix_id") != "<instance-defined-matrix-id>":
    raise SystemExit("matrix template must use placeholder matrix_id")
flows = matrix_template.get("flows")
if not isinstance(flows, list) or not flows:
    raise SystemExit("matrix template must contain placeholder flows")
if any(flow.get("status") == "active" for flow in flows if isinstance(flow, dict)):
    raise SystemExit("matrix template must not contain an active flow")
template_text = matrix_template_path.read_text(encoding="utf-8")
for forbidden in [
    "humblebee",
    "cosmetics-household",
    "almond-oat",
    "recipe_formula_extraction",
    "product_type_extraction",
    "formulation_extraction",
    "component_extraction",
]:
    if forbidden in template_text:
        raise SystemExit(f"matrix template must not contain current-instance marker: {forbidden}")

profile_template = json.loads((repo / "operations/admission/knowledge-profiles/profile.template.json").read_text(encoding="utf-8"))
registry_template = json.loads((repo / "operations/admission/knowledge-profiles/registry.template.json").read_text(encoding="utf-8"))
if profile_template.get("profile_contract_id") != "knowledge_extraction.v1":
    raise SystemExit("profile template must use knowledge_extraction.v1")
for field in ["knowledge_profile_id", "instruction_ref", "output_template_ref", "payload_kind", "placement_policy_id", "status"]:
    if field not in profile_template:
        raise SystemExit(f"profile template missing {field}")
if "knowledge_type" in profile_template:
    raise SystemExit("profile template must not contain knowledge_type")
if registry_template != {"registry_id": "knowledge_profiles.v1", "profiles": {}}:
    raise SystemExit("registry template must be empty")
for text, label in [(skill, "SKILL.md"), (example, "knowledge-admission-example.md")]:
    for forbidden in [
        "recipe_formula_extraction",
        "product_type_extraction.v1",
        "component_extraction.v1",
        "example-recipe-formula",
        "example-product-type",
        "example-component",
        "recipe " + "correctness",
        "ingredient " + "safety",
        "source-stated formula " + "facts",
        "preserva" + "tive",
        "shelf-" + "life",
        "relative, inside " + "the repository",
    ]:
        if forbidden in text:
            raise SystemExit(f"{label} must not contain concrete profile/example marker: {forbidden}")

print("PASS knowledge-admission skill package validation")
PY
