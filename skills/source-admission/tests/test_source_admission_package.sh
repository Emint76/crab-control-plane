#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PACKAGE_ROOT}/../.." && pwd)"
PYTHON_BIN="${PYTHON:-python3}"
EXPECTED_SKILL_SHA256="cba5f18ad16f961ec632bc5ac689b3235436aad06eb25e271d5fc786689f76b1"

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
require_file "${PACKAGE_ROOT}/scripts/check_source_admission_inputs.py"
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

"${PYTHON_BIN}" - "${PACKAGE_ROOT}/scripts/check_source_admission_inputs.py" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
compile(source, str(path), "exec")
PY

if find "${PACKAGE_ROOT}" -type f \( -iname '*secret*' -o -iname '*credential*' -o -iname '*token*' -o -iname '*password*' -o -iname '*.env' -o -iname 'id_rsa*' \) -print -quit | grep -q .; then
  fail "obvious secret or credential file found inside source-admission package"
fi

"${PYTHON_BIN}" - "${PACKAGE_ROOT}" <<'PY'
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

printf 'PASS source-admission skill package validation\n'
