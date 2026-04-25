# harness-phase2

## Purpose

`operations/harness-phase2/` provides the Phase 2 scaffold-only mechanical validate/apply surface for `crab-control-plane`.

It validates contracts and policy, then renders machine-readable scaffold decisions and a runtime-ready package into a run-scoped output directory.

## Responsibilities

- run wrong-root preflight checks
- validate Phase 2 schemas and examples
- validate selected runtime and policy consistency
- render scaffold machine-readable decisions
- render a runtime-ready package into the run scope only

`render_apply_plan.py` in PR-1 is a scaffold decision layer, not a full policy engine.

## Non-goals

- no live runtime writes
- no deploy logic
- no runtime migration
- no secrets or identity management
- no pretending that scaffold outputs are a real decision engine

`runtime-ready/` is a special Phase 2 render output, not a placement artifact.

## Entrypoint

Run the Phase 2 bundle with:

```bash
bash operations/harness-phase2/bin/run_phase2_bundle.sh <RUN_ID>
```

If `<RUN_ID>` is omitted, the bundle generates a UTC timestamp-based id.

## Fixture smoke suite

```bash
bash operations/harness-phase2/tests/run_fixture_smoke.sh
```

- checks schema-positive and schema-negative contract fixtures from `control-plane/contracts/schemas/`
- rejects a KB placement fixture that violates the Phase 2 placement policy
- rejects admission fixtures with missing source capture evidence
- proves semantic fail-closed behavior when `placement.artifact_type` is not `source-capture-package`

## Outputs

Required outputs for each run:
- `run_meta.json`
- `exit_code`
- `apply_plan.json`
- `validation_report.json`
- `admission_decision.json`
- `placement_decision.json`
- `checks/wrong_root_preflight.txt`
- `checks/contracts_validation.json`
- `checks/policy_validation.json`
- `output/runtime-ready/`
