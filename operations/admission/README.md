# Admission

`operations/admission/` contains universal Admission Stage contracts.

These Stage labels are contract-layer labels, not harness Phases and not a second admission runtime.

Stage 1 defines the universal `admission_package.json` contract for:

- `source_capture.v1`
- `knowledge_asset.v1`

Stage 2 defines `admission_handoff.json` as a static contract bridge into existing Phase3 target and manifest inputs. It is not a runner, CLI, admission engine, wrapper, orchestration framework, or evidence system.

The operational route is:

```text
prepared asset
-> universal admission package contract
-> Phase3 manifest and execution target preparation
-> universal admission handoff contract
-> standalone admission policy preflight
-> existing accepted reusable Phase2 baseline
-> Phase4 thin wrapper by default
-> Phase3 kb_admission
-> canonical Phase3 evidence
```

The standalone policy preflight is implemented by `operations/harness-phase2/bin/check_admission_policy.py`. It is repo-native preflight, not the generic Phase2 bundle and not canonical admission evidence.

## Dependencies

Admission contract validation uses Python and the standard `jsonschema` package with Draft 2020-12 through the repository validation requirements.
No custom or fallback JSON Schema validator exists.

## Stage 2

Schema:

```text
operations/admission/schemas/admission_handoff.v1.schema.json
```

Examples:

```text
operations/admission/examples/stage2/
```

Placement policies:

```text
operations/admission/placement-policies/registry.v1.json
```

Phase3 remains the sole canonical execution/admission evidence owner.
