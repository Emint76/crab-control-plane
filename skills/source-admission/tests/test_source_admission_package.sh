#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PACKAGE_ROOT}/../.." && pwd)"
EXPECTED_SKILL_SHA256="13443f90dac9f24877c0a0ef72d39db76abc3b08e8b0ebac28b31705dfb1e26f"

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
require_file "${PACKAGE_ROOT}/references/source-admission-example.md"

if find "${PACKAGE_ROOT}" -type l -print -quit | grep -q .; then
  fail "symlink found inside source-admission package"
fi

if find "${PACKAGE_ROOT}" \( -type d -name '__pycache__' -o -type f -name '*.pyc' \) -print -quit | grep -q .; then
  fail "cache or bytecode found inside source-admission package"
fi

if find "${PACKAGE_ROOT}" \( -path '*/runs' -o -path '*/runs/*' -o -path '*/state' -o -path '*/state/*' -o -path '*/kb' -o -path '*/kb/*' \) -print -quit | grep -q .; then
  fail "generated runs, live state, or KB data found inside source-admission package"
fi

if ! awk '
  NR == 1 && $0 != "---" { exit 1 }
  NR > 1 && $0 == "---" { exit found ? 0 : 1 }
  NR > 1 && $0 == "name: source-admission" { found = 1 }
  END { if (NR == 0) exit 1 }
' "${PACKAGE_ROOT}/SKILL.md"; then
  fail "SKILL.md frontmatter must contain name: source-admission"
fi

actual_sha256="$(sha256sum "${PACKAGE_ROOT}/SKILL.md" | awk '{print $1}')"
[[ "${actual_sha256}" == "${EXPECTED_SKILL_SHA256}" ]] || fail "SKILL.md SHA-256 mismatch: ${actual_sha256}"

if find "${PACKAGE_ROOT}" -type f \( -iname '*secret*' -o -iname '*credential*' -o -iname '*token*' -o -iname '*password*' -o -iname '*.env' -o -iname 'id_rsa*' \) -print -quit | grep -q .; then
  fail "obvious secret or credential file found inside source-admission package"
fi

python3 - "${PACKAGE_ROOT}" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
patterns = [
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)\b(password|api[_-]?key|access[_-]?token|secret[_-]?key)\s*[:=]\s*['\"]?[^'\"\s]+"),
]
violations: list[str] = []
for path in sorted(item for item in root.rglob("*") if item.is_file()):
    text = path.read_text(encoding="utf-8", errors="replace")
    for pattern in patterns:
        if pattern.search(text):
            violations.append(path.relative_to(root).as_posix())
            break
if violations:
    raise SystemExit("obvious credential material found: " + ", ".join(violations))
PY

python3 - "${PACKAGE_ROOT}" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

root = Path(sys.argv[1])
skill = (root / "SKILL.md").read_text(encoding="utf-8")
example = (root / "references" / "source-admission-example.md").read_text(encoding="utf-8")

for text, label in [(skill, "SKILL.md"), (example, "source-admission-example.md")]:
    for fragment in [
        "admission_package.json",
        "admission_handoff.json",
        "Phase3 `admission_manifest.json`",
        "Phase3 `execution_target.json`",
        "check_admission_policy.py",
    ]:
        if fragment not in text:
            raise SystemExit(f"{label} missing canonical source-admission fragment: {fragment}")
    if "Legacy compatibility" not in text:
        raise SystemExit(f"{label} must label legacy fixture compatibility")
    before_legacy = text.split("Legacy compatibility", 1)[0]
    if "admission-fixture.json" in before_legacy:
        raise SystemExit(f"{label} presents admission-fixture.json before the legacy compatibility section")
    if "admission-fixture.json` is not a Stage 2 handoff" not in text:
        raise SystemExit(f"{label} must state that admission-fixture.json is not a Stage 2 handoff")

if "operations/harness-phase2/bin/check_admission_policy.py \\\n  /home/node/.openclaw/workspace/repos/crab-control-plane \\\n  /path/to/source-admission-proof/admission_handoff.json" not in skill:
    raise SystemExit("SKILL.md canonical preflight command must check admission_handoff.json")

if "Never run standalone preflight before the files referenced by `admission_handoff.json` exist." not in example:
    raise SystemExit("reference example must preserve the corrected preparation order")

if "Phase3 remains the sole canonical execution owner" not in skill and "Phase3 performs admission and remains the only canonical execution owner" not in skill:
    raise SystemExit("SKILL.md must preserve Phase3 canonical ownership")
PY

printf 'PASS source-admission skill package validation\n'
