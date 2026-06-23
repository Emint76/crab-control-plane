# Admission Stage 2 Contract

## Purpose

Admission Stage 2 is the universal contract bridge from a reviewed Admission Stage 1 package into the existing harness Phase execution path.

It prepares one machine-readable handoff, `admission_handoff.json`, and maps the reviewed package to existing Phase3 target and manifest inputs. It is not an execution framework.

Admission Stage 1 and Admission Stage 2 are contract-layer labels. They are not harness Phases, runtime stages, or a second canonical evidence framework.

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

`review_evidence.approval_ref` points to the canonical review decision document for the reviewed package. Standalone admission policy preflight resolves that repo-contained reference and validates it against:

```text
control-plane/contracts/schemas/review_decision.schema.json
```

For Stage 2 KB admission, standalone admission policy preflight requires:

- `decision: approve`
- `artifact_id` matching the handoff `asset_id`
- `approved_destination: kb`

The Stage 2 handoff field `review_evidence.review_status` is not sufficient by itself; the referenced canonical review decision is authoritative. This is pre-Phase policy proof, not generic Phase2 bundle evidence and not canonical admission evidence.

## Universal Mapping Rules

Stage 2 maps one reviewed Stage 1 package into:

- Phase3 `execution_target.json`
- Phase3 `admission_manifest.json`

All references must be repo-contained relative paths. Absolute paths and traversal are invalid.

Stage 2 specifies the mapping. Phase3 validates runtime input paths, file existence, payload SHA-256 values, overwrite policy, copy results, and canonical evidence.

Stage 1 `payload_path` and Phase3 `input_workspace_path` are different path domains:

- Stage 1 `payload_path` is package-relative and identifies the producer-prepared payload inside the reviewed Stage 1 package.
- Phase3 `input_workspace_path` is relative to the configured runtime workspace KB root.
- Before Phase3 execution, the producer/preparation process must materialize the reviewed payload at the declared workflow staging path.
- Stage 2 maps and declares this relationship but does not perform the staging itself.
- If the runtime staging file is absent, Phase3 fails closed.
- Example hashes are illustrative and must be replaced with the actual hash of the staged runtime file before execution.

Phase3 manifest inputs must use the current domain-first workflow layout, for example:

```text
<domain-area>/<source-family-id>/workflow/<run-id>/<asset-id>/payload/<filename>
```

They must not use repository paths such as `operations/...`, `docs/...`, or `control-plane/...` as runtime workspace inputs.

## Identity Preservation

`asset_id` is preserved exactly from Stage 1.

The same value must be traceable through:

- Stage 1 `admission_package.json`
- Stage 2 `admission_handoff.json`
- standalone admission policy preflight
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

Profile-specific semantic validation remains outside universal admission. Profile maturity and status is descriptive metadata, not evidence of a profile-specific admission implementation.

Stage 2 contains no profile-specific executable implementation, and adding a new registered knowledge profile must not require new Stage 2 admission code.

Out-of-repo packages using the old `component_profile.v1` identifier require migration to `component_extraction.v1`. No live data migration is part of this PR.

## Phase Ownership

The intended route is:

```text
producer-prepared asset
-> Admission Stage 1 package contract
-> Admission Stage 2 handoff contract
-> standalone admission policy preflight
-> existing accepted reusable Phase2 baseline
-> Phase4 operator-facing wrapper
-> Phase3 kb_admission
-> canonical Phase3 evidence
```

Ownership:

- Admission Stage 1 owns the universal package contract.
- Admission Stage 2 owns the universal bridge contract and mapping into Phase inputs.
- Standalone admission policy preflight owns review-decision validation, package binding, identity consistency, source-versus-knowledge classification, placement validation, profile registration checks, and target/manifest mapping checks.
- Phase2 owns reusable repo/control-plane baseline validation and generic render/apply-plan/runtime-ready/handoff readiness.
- Phase4 is the normal operator-facing route to Phase3.
- Phase3 is the sole canonical execution and evidence owner.

Stage 2 success and standalone preflight success do not mean the asset has been admitted.

The generic Phase2 bundle does not consume, approve, freeze, or prove a specific admission handoff. One accepted Phase2 baseline may be reused while the relevant repo/control-plane baseline remains unchanged. Absence of a first-class checked-handoff-to-Phase2-run binding is an accepted boundary, not a wiring defect.

## Failure Boundaries

Standalone admission policy preflight over the Stage 2 handoff can fail when:

- the handoff does not match its schema;
- referenced repo-contained inputs are missing or unsafe;
- Stage 1 identity is not preserved;
- review evidence does not authorize admission;
- placement does not match the domain-first policy;
- the Phase3 target is not `kb_admission`;
- the Phase3 manifest admission type does not match the Stage 1 admission kind.

Stage 2 and standalone preflight do not fail or pass runtime payload-file hashes, copies, overwrite behavior, destination mutation, or canonical run evidence.

## What Stage 2 Does Not Prove

Stage 2 and standalone preflight do not prove:

- semantic correctness;
- payload file existence;
- payload SHA-256 correctness;
- safe copy completion;
- overwrite behavior;
- destination mutation;
- Phase4 invocation success;
- canonical admission.
- that the generic Phase2 bundle consumed a specific handoff;
- the whole pre-Phase review/governance trail as canonical evidence.

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
7. Run standalone admission policy preflight against the handoff.
8. Reuse an existing accepted Phase2 baseline while the repo/control-plane baseline is unchanged, or run the generic Phase2 bundle only to establish a new baseline.
9. Prepare Phase3 `execution_target.json` using `target_runtime: workspace` and `target_kind: kb_admission`.
10. Prepare Phase3 `admission_manifest.json` with `admission_type` matching Stage 1 and one explicit artifact entry per file:
   - runtime-KB-root-relative workflow input path
   - expected SHA-256
   - relative destination path
   - copy metadata
11. Invoke the normal Phase4 wrapper route to Phase3.
12. Verify Phase3 canonical evidence under the Phase3 run directory.
13. Report the admitted destination paths and Phase3-verified hashes only after Phase3 succeeds.

Do not infer undocumented mappings. If a mapping is missing, stop before Phase execution.

## Future-Profile Extensibility

New knowledge profiles can be registered as `knowledge_profile_id` values without adding new Stage 2 runners or profile-specific Stage 2 admission code.

Any profile-specific semantic validator belongs to the producer or extraction profile boundary, not to universal admission. Remaining cleanup debt includes auditing and simplifying the transitional Stage 1 executable validation and removing historical helper checks after every useful check has a documented owner.

## Hash Ownership

| Hash/check | Owner |
|---|---|
| Stage 1 package binding hash used by the handoff | admission preparation / standalone policy preflight |
| Runtime staged payload file hashes | Phase3 |
| Destination/copied-result hashes | Phase3 |
| Copy and overwrite evidence | Phase3 |

Standalone admission policy preflight verifies `admission_package_sha256` only to bind the handoff to the exact reviewed Stage 1 package. It does not hash runtime staged payload files; those checks remain Phase3-owned.

Operational batch runners may execute standalone preflight and Phase invocation sequentially and retain their own logs or operational state. Those logs are not a second canonical Phase evidence surface.
