# Phase 3 unresolved items

## execution_target schema contract

Status: closed.

Resolved by:
- `operations/harness-phase3/contracts/execution_target.schema.json`
- schema validation in `operations/harness-phase3/bin/validate_execution_target.py`
- `operations/harness-phase3/tests/test_execution_target_schema_contract.sh`

Current note:
- Semantic checks remain in code because run-specific canonical `target_ref`, write-surface, and unsafe path rules are not pure schema concerns.
