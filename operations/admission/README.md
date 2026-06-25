# Admission

`operations/admission/` contains universal Admission Stage contracts.

These Stage labels are contract-layer labels, not harness Phases and not a second admission runtime.

Stage 1 defines the universal `admission_package.json` contract for:

- `source_capture.v1`
- `knowledge_asset.v1`

Stage 2 defines `admission_handoff.json` as a static contract bridge into existing Phase3 target and manifest inputs. It is not a runner, CLI, admission engine, wrapper, orchestration framework, or evidence system.

Stage 2 keeps `asset_id` and `asset_slug` distinct. `asset_id` is the stable globally traceable identity; `asset_slug` is the source-family-local placement segment used in `destination_root`.

For knowledge assets, Stage 2 also requires `placement.knowledge_type` and uses the typed destination shape:

```text
<domain-area>/<source-family-id>/knowledge/<knowledge-type>/<asset-slug>/
```

`knowledge_type` is instance-local placement taxonomy, not identity or lineage. The repository defines the contract and validation interface; real KB instances own concrete allowed values and profile-to-type mappings.

Concrete `knowledge_profile_id` values are also instance-defined. The repository owns the generic `knowledge_extraction.v1` contract and profile/registry templates, not an active concrete profile catalog.

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

Instance-local KB taxonomy config schema:

```text
operations/admission/schemas/kb_taxonomy_config.v1.schema.json
```

Standalone policy preflight loads real local taxonomy config from `ADMISSION_KB_TAXONOMY_CONFIG` for `knowledge_asset` handoffs. The variable is an explicit instance-supplied config path. Absolute paths are accepted, and relative paths resolve against the repository root supplied to the standalone checker. Preflight fails closed when the path is missing, nonexistent, not a file, invalid JSON, schema-invalid, or does not allow the selected `knowledge_profile_id` and selected `knowledge_type` pair. Physical filesystem containment is not enforced by the checker.

Standalone policy preflight also requires `ADMISSION_KNOWLEDGE_PROFILE_REGISTRY` for `knowledge_asset` handoffs. That instance-supplied registry selects concrete profile IDs using `profile_contract_id: knowledge_extraction.v1`; relative `instruction_ref` and `output_template_ref` values resolve from the registry file's directory. Preflight validates only the selected profile entry, so unrelated draft or incomplete entries do not block a valid selected profile. Source admissions do not require this registry.

Phase3 remains the sole canonical execution/admission evidence owner.
