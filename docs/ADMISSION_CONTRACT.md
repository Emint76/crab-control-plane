# Admission Contract

## Purpose

Stage 1 admission is a repo-native dry-run validation surface for package admissibility.
It validates generic package structure before later canonicalization or execution stages.

Stage 1 does not perform canonical placement, Phase execution, canonical writes, hash sealing, final manifests, migration, or producer integration.

## Responsibility Boundary

Producers own capture and extraction semantics.
Semantic profiles own type-specific structure and meaning.
Admission owns only generic package admissibility in Stage 1.

Admission does not validate Product Type vocabulary, recipe structure, component profile structure, or semantic truth.
`review_status: approved` records that producer-side semantic review has already happened before the package is submitted.

## Supported Package Classes

Stage 1 supports two universal admission profiles:

- `admission_kind: source_capture`, `profile_id: source_capture.v1`
- `admission_kind: knowledge_asset`, `profile_id: knowledge_asset.v1`

Knowledge assets also carry a registered `knowledge_profile_id`.
Stage 1 uses that ID only for admission-level enablement and payload-kind policy.
It does not load type-specific schemas or validators.

## CLI

Stable external interface:

```bash
bash operations/admission/bin/run_admission.sh \
  --package <package-directory> \
  --dry-run
```

The command prints only the JSON result to stdout.
Diagnostics and dependency errors go to stderr.
Successful dry-run validation returns `0`; validation failures return non-zero.

The wrapper selects `ADMISSION_PYTHON_BIN`, then `PYTHON`, then `python3`.
It does not require manual `PYTHONPATH`.

## Dependencies

Admission uses the standard Python `jsonschema` package and Draft 2020-12 schemas.
The repo-owned dependency declaration is `operations/harness-phase2/requirements.txt`.

If `jsonschema` is unavailable, the CLI fails closed with a non-zero exit code, writes no files, and does not claim validation success.
There is no custom or fallback JSON Schema validator.

## Package Convention

Each package directory contains:

```text
admission_package.json
```

`payload_path` must be relative to the package directory.
Absolute paths and traversal through `..` are rejected.
The referenced payload must exist.

Payload kind rules:

- `source_capture.v1`: directory
- `knowledge_asset.v1`: file or directory
- a registered knowledge profile may narrow payload kind through the registry

## Common Envelope

All packages contain:

- `admission_kind`
- `profile_id`
- `asset_id`
- `payload_path`
- `review_status`
- `provenance`

The only admission-ready review status is `approved`.

For `source_capture.v1`, `knowledge_profile_id` and `profile_data` are forbidden.

For `knowledge_asset.v1`, `knowledge_profile_id` and non-empty object `profile_data` are required.
`profile_data` is opaque producer-owned content.

Knowledge assets must include:

- `provenance.source_id`
- `provenance.source_asset_path`

Stage 1 preserves `source_id` exactly as supplied.
It does not open canonical Source packages, verify Source package contents, fix historical IDs, or create another source identifier system.

## Knowledge Profile Registry

`operations/admission/knowledge-profiles/registry.v1.json` is an admission-runtime registry.
It contains only:

- `enabled_for_admission`
- `payload_kind`
- `placement_policy_id`
- `status`

Stage 1 entries:

- `product_type_extraction.v1`: enabled
- `recipe_formula_extraction.v1`: disabled placeholder
- `component_profile.v1`: disabled placeholder

The registry must not contain semantic validators, type-specific schema references, extraction instructions, or template execution rules.

## Result

Dry-run success returns a schema-valid result with:

- `validation_status: pass`
- `admission_status: not_run`
- `mode: dry_run`
- `proposed_target_path: null`
- empty `blockers`
- `evidence.phase_invoked: false`
- `evidence.canonical_write_performed: false`

Validation failure returns:

- `validation_status: fail`
- `admission_status: not_run`
- non-empty stable blockers
- no Phase invocation
- no canonical write

## Out Of Scope

Stage 1 does not implement Stage 2 blockers:

- canonical placement
- Phase bridge
- Phase3 manifests
- final admission evidence
- hash sealing
- producer integration
- migration of existing assets
