# harness-phase2

## Purpose

`operations/harness-phase2/` provides the Phase 2 repo-native check/render surface for `crab-control-plane`.

It contains two profiles:

- `check-layer-strict`: audit-only validation profile.
- `repo-native-scaffold`: scaffold-only package/handoff preparation profile for Phase 3 intake.

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

## Profiles

| Profile | Entrypoint | Meaning |
| --- | --- | --- |
| `check-layer-strict` | `bin/run_phase2_check_layer.sh` | strict external check layer only; no render, no runtime-ready, no handoff |
| `repo-native-scaffold` | `bin/run_phase2_bundle.sh` | existing scaffold bundle; renders decision artifacts, runtime-ready package, conformance, report, handoff readiness |

The strict check-layer profile is the closest repo-native equivalent of the earlier VPS Phase 2 harness.

The repo-native scaffold profile is intentionally broader and must not be mistaken for the strict external check layer.

## Which Phase 2 profile should I run?

Phase 2 has two profiles. They are profiles of the same phase, not separate phases.

| Need | Run | Why |
|---|---|---|
| Check repo hygiene, contracts, policies, wrong-root hazards, and fixture smoke without rendering a package | `check-layer-strict` | Audit-only profile. It does not render `runtime-ready/`, does not produce handoff readiness, and does not prepare execution input. |
| Prepare a repo-native package for Phase 3 intake | `repo-native-scaffold` | Package/handoff profile. It produces decisions, `apply_plan.json`, `output/runtime-ready/`, conformance, reports, and `handoff_ready.json`. |
| Prove canonical execution ownership | Phase 3 | Phase 3 owns execution evidence, canonical reports, and final exit status. |
| Provide an operator-facing wrapper | Phase 4 | Phase 4 wraps Phase 3 and does not own canonical execution outputs. |

`handoff_ready.json` means ready for Phase 3 intake only. It does not mean live-runtime-ready, deploy-ready, or launch-ready.

## Run directory invariants

Phase 2 validates `RUN_ID` and canonical run-dir containment before creating run artifacts.

Both Phase 2 profiles emit `checks/run_dir_invariants.json` for valid runs.

## Strict profile evidence pack

The `check-layer-strict` profile produces a repo-native equivalent of the earlier VPS Phase 2 audit pack:

- `PHASE2_TREE.txt`
- `PREFLIGHT_RESULT.txt`
- `SMOKE_OUTPUT.txt`
- `CREATED_PATHS.txt`
- `FINAL_REPORT.md`

## Fixture smoke suite

```bash
bash operations/harness-phase2/tests/run_fixture_smoke.sh
```

- checks schema-positive and schema-negative contract fixtures from `control-plane/contracts/schemas/`
- rejects a KB placement fixture that violates the Phase 2 placement policy
- rejects admission fixtures with missing source capture evidence
- proves semantic fail-closed behavior when `placement.artifact_type` is not `source-capture-package`

## Standalone check tools

```bash
bash operations/harness-phase2/bin/validate_json_against_schema.sh <schema> <json-file>
python operations/harness-phase2/bin/check_placement_policy.py <repo-root> <placement-json>
python operations/harness-phase2/bin/check_admission_policy.py <repo-root> <admission-fixture-json>
```

These are small Phase 2 external-check-layer utilities. They validate schema, placement policy, and admission fixture semantics without performing runtime writes.

## Observability sample emitter

```bash
python operations/harness-phase2/bin/emit_observability_record.py <repo-root> <run-id>
```

- writes JSONL only under `operations/harness-phase2/reports/`
- does not write to global `observability/`
- is a sample external-check-layer observability emitter, not runtime instrumentation

## Strict profile outputs

- `run_meta.json`
- `exit_code`
- `checks/run_dir_invariants.json`
- `checks/wrong_root_preflight.txt`
- `checks/contracts_validation.json`
- `checks/policy_validation.json`
- `checks/fixture_smoke.txt`
- `PHASE2_TREE.txt`
- `PREFLIGHT_RESULT.txt`
- `SMOKE_OUTPUT.txt`
- `CREATED_PATHS.txt`
- `FINAL_REPORT.md`

## Repo-native scaffold outputs

- `run_meta.json`
- `exit_code`
- `apply_plan.json`
- `validation_report.json`
- `admission_decision.json`
- `placement_decision.json`
- `handoff_ready.json`
- `report.json`
- `report.md`
- `checks/*`
- `output/runtime-ready/`
