# recipe_formula_extraction template

## Purpose

Template for `recipe_formula_extraction` working candidates, admission-authorized knowledge packages, and future admitted knowledge assets.

This template defines an agreed extraction output structure for agent-led semantic extraction. It is markdown-first documentation. It does not create a schema, validator, Phase behavior, admission mechanic, runtime write, or live KB asset.

## Asset kind semantics

- `knowledge_candidate`: pre-review or working semantic extraction output that is not yet a sanctioned KB asset.
- `knowledge_package`: admission-authorized, KB-ready process concept for the byte-for-byte artifact prepared for Phase admission. This is not a new schema-bound artifact type.
- `knowledge_asset`: sanctioned KB asset after required review and admission path.

A file using this template may start as a working candidate. The file submitted to Phase3 `kb_admission` must be an admission-authorized knowledge package whose bytes and metadata remain true after admission.

## Profile and review gates

- Profile approval = agreed extraction structure.
- Review decision = KB placement authorization.

Do not collapse these gates. Approval or refinement of this template/profile means the agent has an agreed data structure for extraction. It does not mean any prepared candidate is acceptable for KB placement.

## Metadata boundary

Phase3 `kb_admission` copies bytes. It does not rewrite front matter or change workflow status fields inside the artifact.

Transient workflow status belongs in workflow metadata, review decisions, or admission metadata unless it is intended to remain true in the final admitted artifact.

Bad Phase input example:

```yaml
knowledge_status: candidate
```

This is appropriate only for a working pre-review candidate if that same file will not be copied byte-for-byte into `knowledge/...`.

Acceptable illustrative package metadata examples:

```yaml
artifact_type: "knowledge_package"
admission_readiness: "reviewed_for_kb_placement"
```

```yaml
asset_kind: "knowledge_asset"
admission_state: "prepared_for_phase3_admission"
```

These examples are illustrative and do not introduce mandatory schema fields.

## Phase-ready front matter guidance

Use these fields as a minimum shape for an admission-authorized knowledge package prepared for Phase admission:

```yaml
---
asset_id: "<stable-asset-id>"
artifact_type: "knowledge_package"
knowledge_profile_id: "recipe_formula_extraction.v1"
knowledge_type: "<instance-local-knowledge-type>"
domain_area: "<domain-area>"
source_family_id: "<publisher-or-source-family-id>"
publisher: "<publisher-name>"
title: "<knowledge-asset-title>"
source_title: "<source-title>"
source_url: "<canonical-source-url-or-pointer>"
product_type: "<product-or-formula-type>"
use_context: "<intended-use-context-as-stated-or-interpreted>"
water_system: "<water-system-status-or-not-stated>"
kb_family_root: "<domain-area>/<source-family-id>"
source_asset_path: "<workspace-kb-root>/<domain-area>/<source-family-id>/sources/<source-asset-id>/"
knowledge_asset_path: "<workspace-kb-root>/<domain-area>/<source-family-id>/knowledge/<knowledge-type>/<asset-slug>/"
extraction_profile_path: "knowledge/kb/extraction-profiles/<domain>/index.md"
extraction_workflow_path: "<workflow-or-evidence-path-or-not-available>"
source_status: "<captured|source_admitted|reviewed|not_available>"
admission_readiness: "reviewed_for_kb_placement"
review_status: "approved"
claim_scope: "<what-this-package-claims-to-cover>"
validation_scope: "not validated beyond source-stated content unless explicitly reviewed"
formula_summary: "<one-sentence-source-grounded-summary>"
extraction:
  profile_path: "knowledge/kb/extraction-profiles/<domain>/index.md"
  profile_approval_ref: "<profile-approval-or-refinement-ref>"
  prepared_by: "<agent-or-author-id>"
  prepared_at: "<YYYY-MM-DD-or-not-stated>"
  review_decision_id: "<review-decision-id>"
  phase3_kb_admission:
    target_kind: "kb_admission"
    run_id: "<run-id-or-not-applicable>"
    manifest_ref: "<manifest-path-or-not-applicable>"
    evidence_path: "<evidence-path-or-not-applicable>"
---
```

The `knowledge_profile_id` identifies the agent extraction profile. The `knowledge_type` value is an instance-local placement taxonomy segment selected from outside-repository local taxonomy configuration. Do not use `knowledge_type: recipe_formula_extraction` as a substitute for the profile ID.

The `knowledge_asset_path` example uses the Stage 2 typed placement shape. Its `<knowledge-type>` segment comes from instance-local KB taxonomy configuration and is placement metadata, not semantic validation and not `asset_id`.

For a working pre-review candidate, candidate status may be recorded in workflow metadata or in a non-admitted draft copy. Do not submit candidate-status bytes to Phase if those bytes would become false after admission.

## Status boundaries

- A source-bearing asset is not a knowledge asset.
- Captured source material is not semantic extraction.
- A knowledge candidate is not a sanctioned KB asset.
- A knowledge package is admission-authorized and KB-ready, but not yet admitted.
- Agent extraction does not mean semantic review.
- Semantic review does not mean cosmetic safety, stability, preservative challenge, regulatory, GMP, or manufacturing validation.
- Phase 3 `kb_admission` admits already prepared knowledge packages byte-for-byte.
- Phase evidence proves controlled execution/admission, not semantic correctness.
- `knowledge_asset` status requires the applicable review and admission path.

## Source / provenance requirements

The asset must identify the evidence it depends on.

Required provenance fields or section entries:

- source family ID;
- publisher;
- source title;
- source URL or canonical pointer;
- source asset path when available;
- retrieval or capture status when available;
- content hashes or stable representation identifiers when available;
- extraction profile path and approval/refinement reference when available;
- extraction workflow path or evidence reference when available;
- review decision reference when available.

Claims must be supported by provenance or explicitly marked as source-stated, agent-interpreted, inferred, not stated, or not validated.

## Formula by phase requirements

Use source grams and percentages if present.

If grams, percentages, pH, shelf life, safety limits, packaging, or process details are absent, explicitly say `not stated in source`.

Minimum phase table columns:

| Phase | Component | Amount / grams | Percentage | Source wording / pointer | Agent-interpreted function | Notes |
|---|---|---|---|---|---|---|
| `<phase>` | `<component>` | `<grams-or-not-stated>` | `<percent-or-not-stated>` | `<source-pointer>` | `<function>` | `<notes>` |

## Component/function table requirements

Each listed component must have a source-grounded or explicitly inferred function.

Minimum component/function table columns:

| Component | Source-stated function | Agent interpretation | Inferred content | Evidence pointer | Not stated / not validated |
|---|---|---|---|---|---|
| `<component>` | `<function-or-not-stated>` | `<interpretation-or-none>` | `<inference-or-none>` | `<source-pointer>` | `<boundary>` |

## Required markdown sections

Use these sections in this order.

## Status and review boundary

- Artifact status: `<working_candidate|admission_authorized_knowledge_package|admitted_knowledge_asset>`
- Admission readiness: `<not_ready|reviewed_for_kb_placement|admitted>`
- Profile approval/refinement: `<ref-or-not-approved>`
- Review status: `<not_reviewed|in_review|approved|returned|held|rejected>`
- Phase evidence: `<none|phase3-kb-admission/run reference>`

State explicitly:

```text
Profile approval means agreed extraction structure, not KB placement authorization.
Review decision authorizes KB placement when admission requirements are met.
Phase evidence proves controlled admission of prepared artifacts, not semantic correctness.
Phase copies bytes and does not rewrite artifact metadata.
```

## Source / provenance

- Source family ID: `<source_family_id>`
- Publisher: `<publisher>`
- Source title: `<source_title>`
- Source URL / canonical pointer: `<source_url>`
- Source asset path: `<source_asset_path>`
- Source capture / admission status: `<source_status>`
- Hashes / stable representation IDs: `<hashes-or-not-available>`
- Extraction profile path: `<extraction_profile_path>`
- Extraction workflow path: `<extraction_workflow_path>`

## Product frame

- Product type: `<product_type>`
- Use context: `<use_context>`
- Water system: `<water_system>`
- Claim scope: `<claim_scope>`
- Validation scope: `<validation_scope>`

## Formula overview

Summarize only what the source supports. Include formula purpose, product description, and high-level structure.

If exact formula percentages, grams, pH, shelf life, safety limits, packaging, or process details are absent, say so here or in the relevant section.

## Formula by phase

| Phase | Component | Amount / grams | Percentage | Source wording / pointer | Agent-interpreted function | Notes |
|---|---|---|---|---|---|---|
| `<phase>` | `<component>` | `<grams-or-not-stated>` | `<percent-or-not-stated>` | `<source-pointer>` | `<function>` | `<notes>` |

## Components and functions

| Component | Source-stated function | Agent interpretation | Inferred content | Evidence pointer | Not stated / not validated |
|---|---|---|---|---|---|
| `<component>` | `<function-or-not-stated>` | `<interpretation-or-none>` | `<inference-or-none>` | `<source-pointer>` | `<boundary>` |

## Method / technological process

Describe source-stated process steps in order.

If heat, timing, mixing order, equipment, pH adjustment, packaging, sanitation, preservation, or storage conditions are absent, mark each absent item as `not stated in source`.

## Source-stated substitutions

List only substitutions directly stated by the source.

| Original component | Source-stated substitute | Conditions / limits | Evidence pointer |
|---|---|---|---|
| `<component>` | `<substitute>` | `<conditions-or-not-stated>` | `<source-pointer>` |

## Limits and cautions

Include source-stated cautions and required domain cautions.

For cosmetics and household chemistry formulas, state when applicable:

- cosmetic safety not validated;
- stability not validated;
- preservative challenge not validated;
- regulatory/GMP/manufacturing not validated.

Do not invent safety, shelf-life, regulatory, or manufacturing claims.

## Directly stated in source

List source-stated claims only. Each item must include a source pointer.

- `<claim>` - `<source-pointer>`

## Agent interpretation

List agent interpretations grounded in the source. Each item must explain its evidence basis.

- `<interpretation>` - evidence: `<source-pointer-or-section>`

## Inferred content

List inferences separately from source-stated claims and agent interpretation. Each item must be marked as inferred and tied to evidence or omitted.

- `<inference>` - evidence basis: `<source-pointer-or-section>`

## Not stated / not validated

Use this section to prevent unsupported claims from entering the candidate or package.

Minimum entries to check:

- exact grams: `<stated|not stated in source>`
- exact percentages: `<stated|not stated in source>`
- pH: `<stated|not stated in source>`
- shelf life: `<stated|not stated in source>`
- safety limits: `<stated|not stated in source>`
- packaging: `<stated|not stated in source>`
- process details: `<stated|not stated in source>`
- cosmetic safety: `<validated|not validated>`
- stability: `<validated|not validated>`
- preservative challenge: `<validated|not validated>`
- regulatory/GMP/manufacturing: `<validated|not validated>`

## Related assets

- Source-bearing asset: `<source_asset_path>`
- Related knowledge candidates: `<paths-or-none>`
- Related knowledge packages: `<paths-or-none>`
- Related admitted knowledge assets: `<paths-or-none>`
- Related extraction profiles: `<paths-or-none>`
- Related review decisions: `<ids-or-none>`

## Admission / evidence

- Review decision ID: `<review-decision-id-or-not-reviewed>`
- Approved destination: `<approved-destination-or-not-approved>`
- Admission path: `<admission-path-or-not-admitted>`
- Phase 3 `kb_admission` manifest: `<manifest-path-or-not-applicable>`
- Phase 3 evidence path: `<phase-evidence-path-or-not-applicable>`
- KB target path if admitted: `<knowledge_asset_path>`

State explicitly whether this file is a working candidate, an admission-authorized knowledge package prepared for Phase admission, or an admitted sanctioned KB asset.
