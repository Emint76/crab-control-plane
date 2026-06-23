# Admission Contract

## Purpose

Admission Stage 1 is the universal package contract for package admissibility.
Admission Stage labels are contract-layer labels, not harness Phases and not a second runtime framework.

Admission Stage 1 does not perform canonical placement, Phase execution, canonical writes, hash sealing, final manifests, migration, or producer integration.
Admission Stage 2 is the universal contract bridge into existing Phase inputs; see `docs/ADMISSION_STAGE2_CONTRACT.md`.

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
Stage 1 uses that ID only for registry, payload-kind, placement-policy, and lineage metadata.
It does not load type-specific schemas or validators.

## Dependencies

Admission contract validation uses the standard Python `jsonschema` package and Draft 2020-12 schemas.
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

`operations/admission/knowledge-profiles/registry.v1.json` is contract metadata.
It contains only:

- `payload_kind`
- `placement_policy_id`
- `status`

Current registered knowledge profile entries:

- `product_type_extraction.v1`: registered
- `recipe_formula_extraction.v1`: registered placeholder
- `component_extraction.v1`: registered placeholder

`component_extraction.v1` is the extraction/profile identifier. The resulting knowledge asset type may still be described conceptually as a component profile.

The registry must not contain semantic validators, type-specific schema references, extraction instructions, or template execution rules.

## Out Of Scope

Admission Stage 1 does not implement Admission Stage 2 or Phase-owned checks:

- canonical placement
- Phase bridge
- Phase3 manifests
- final admission evidence
- hash sealing
- producer integration
- migration of existing assets

Later cleanup may simplify or remove redundant executable Stage 1 validation after ownership coverage is audited.
