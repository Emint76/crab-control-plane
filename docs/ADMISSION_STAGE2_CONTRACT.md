# Admission Stage 2 Contract

## Purpose

Admission Stage 2 is the universal contract bridge from a reviewed Admission Stage 1 package into the existing harness Phase execution path.

It prepares one machine-readable handoff, `admission_handoff.json`, and binds the existing Phase2 and Phase3 input files needed for admission. It is not an execution framework.

## Input

Stage 2 input is a reviewed Stage 1 package containing `admission_package.json`.

Supported universal admission kinds:

| admission_kind | profile_id | knowledge_profile_id |
|---|---|---|
| `source_capture` | `source_capture.v1` | forbidden / `null` |
| `knowledge_asset` | `knowledge_asset.v1` | required registered extraction profile |

Registered knowledge profile IDs include:

- `product_type_extraction.v1`
- `recipe_formula_extraction.v1`
- `component_extraction.v1`

`component_extraction.v1` is the extraction/profile identifier. The resulting knowledge asset may still be described conceptually as a component profile.

## Output

Stage 2 output is:

```text
admission_handoff.json
```

Schema:

```text
operations/admission/schemas/admission_handoff.v1.schema.json
```

The handoff contains:

- `handoff_version`
- `admission_package_ref`
- `admission_package_sha256`
- `admission_kind`
- `profile_id`
- `asset_id`
- `knowledge_profile_id`
- `review_evidence`
- `placement`
- `phase_inputs`
- `route`

The handoff is not canonical execution evidence.

## Universal Mapping Rules

Stage 2 maps one reviewed Stage 1 package into:

- Phase2 admission/readiness input
- Phase3 `execution_target.json`
- Phase3 `admission_manifest.json`

All references must be repo-contained relative paths. Absolute paths and traversal are invalid.

Stage 2 specifies the mapping. Phase3 validates safe paths, file existence, payload SHA-256 values, overwrite policy, copy results, and canonical evidence.

## Identity Preservation

`asset_id` is preserved exactly from Stage 1.

The same value must be traceable through:

- Stage 1 `admission_package.json`
- Stage 2 `admission_handoff.json`
- Phase2 placement/readiness input
- Phase3 manifest `lineage.asset_id`
- final destination root

Stage 2 must not create another identity system.

## Placement Rules

Placement is domain-first and KB-relative.

For `source_capture`:

```text
<domain-area>/<source-family-id>/sources/<asset-id>/
```

For `knowledge_asset`:

```text
<domain-area>/<source-family-id>/knowledge/<asset-id>/
```

The handoff requires:

- `domain_area`
- `source_family_id`
- `asset_layer`
- `destination_root`
- `placement_policy_id`

`asset_layer` is derived from `admission_kind`:

| admission_kind | asset_layer | placement_policy_id |
|---|---|---|
| `source_capture` | `sources` | `kb_source_domain_first.v1` |
| `knowledge_asset` | `knowledge` | `kb_knowledge_domain_first.v1` |

Knowledge profiles do not create separate storage roots.

## Source Versus Knowledge

Source capture packages preserve producer-prepared source material and route to `sources/`.

Knowledge asset packages preserve reviewed knowledge artifacts and route to `knowledge/`.

Product Type, Recipe Formula, and Component are not admission kinds. They are knowledge profile specializations expressed through `knowledge_profile_id`.

## Knowledge Profile Handling

`knowledge_profile_id` is routing, lineage, and producer-contract metadata.

Universal admission does not execute type-specific extraction logic and must not branch by profile:

```text
if product_type...
elif recipe_formula...
elif component...
```

Profile-specific semantic validation remains outside universal admission. Profile maturity and status are descriptive metadata, not a requirement for a new Stage 2 executable implementation.

Out-of-repo packages using the old `component_profile.v1` identifier require migration to `component_extraction.v1`. No live data migration is part of this PR.

## Phase Ownership

The intended route is:

```text
producer-prepared asset
-> Admission Stage 1 package contract
-> Admission Stage 2 handoff contract
-> Phase2 policy/readiness
-> Phase4 operator-facing wrapper
-> Phase3 kb_admission
-> canonical Phase3 evidence
```

Ownership:

- Admission Stage 1 owns the universal package contract and transitional isolated dry-run validator.
- Admission Stage 2 owns the universal bridge contract and mapping into Phase inputs.
- Phase2 owns policy/readiness validation.
- Phase4 is the normal operator-facing route to Phase3.
- Phase3 is the sole canonical execution and evidence owner.

Stage 2 success does not mean the asset has been admitted.

## Failure Boundaries

Stage 2 can fail when:

- the handoff does not match its schema;
- referenced repo-contained inputs are missing or unsafe;
- Stage 1 identity is not preserved;
- review evidence does not authorize admission;
- placement does not match the domain-first policy;
- the Phase3 target is not `kb_admission`;
- the Phase3 manifest admission type does not match the Stage 1 admission kind.

Stage 2 does not fail or pass payload hashes, copies, overwrite behavior, destination mutation, or canonical run evidence.

## What Stage 2 Does Not Prove

Stage 2 does not prove:

- semantic correctness;
- payload file existence;
- payload SHA-256 correctness;
- safe copy completion;
- overwrite behavior;
- destination mutation;
- Phase4 invocation success;
- canonical admission.

Only Phase3 `kb_admission` evidence can support the claim that an asset was admitted.

## Agent Procedure

1. Receive a reviewed Stage 1 package containing `admission_package.json`.
2. Confirm `review_status: approved`.
3. Classify the package as `source_capture` or `knowledge_asset`.
4. For knowledge, preserve the registered `knowledge_profile_id`.
5. Choose domain-first placement:
   - source: `<domain-area>/<source-family-id>/sources/<asset-id>/`
   - knowledge: `<domain-area>/<source-family-id>/knowledge/<asset-id>/`
6. Prepare `admission_handoff.json` with the Stage 1 package ref, package SHA-256, identity, review evidence, placement, Phase input refs, and route.
7. Prepare the Phase2 readiness input by pointing Phase2 at the handoff.
8. Prepare Phase3 `execution_target.json` using `target_runtime: workspace` and `target_kind: kb_admission`.
9. Prepare Phase3 `admission_manifest.json` with `admission_type` matching Stage 1 and one explicit artifact entry per file:
   - relative input path
   - expected SHA-256
   - relative destination path
   - copy metadata
10. Run the Phase2 admission policy/readiness check.
11. Invoke the normal Phase4 wrapper route to Phase3.
12. Verify Phase3 canonical evidence under the Phase3 run directory.
13. Report the admitted destination paths and Phase3-verified hashes only after Phase3 succeeds.

Do not infer undocumented mappings. If a mapping is missing, stop before Phase execution.

## Future-Profile Extensibility

New knowledge profiles can be registered as `knowledge_profile_id` values without adding new Stage 2 runners.

Any profile-specific semantic validator belongs to the producer or extraction profile boundary, not to universal admission. Remaining cleanup debt includes auditing and simplifying the transitional Stage 1 executable validation and removing historical helper checks after every useful check has a documented owner.
