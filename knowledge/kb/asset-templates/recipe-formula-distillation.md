# recipe_formula_distillation template

## Purpose

Template for `recipe_formula_distillation` knowledge candidates and future admitted knowledge assets.

This template is markdown-first documentation. It does not create a schema, validator, admission mechanic, runtime write, or live KB asset.

## Asset kind semantics

- `knowledge_candidate`: prepared semantic distillation that is not yet a sanctioned KB asset.
- `knowledge_asset`: sanctioned KB asset after required review and admission path.

A file using this template starts as `knowledge_candidate` unless a review decision and admission path explicitly authorize KB placement.

## Required front matter

Use these fields at minimum:

```yaml
---
asset_id: "<stable-asset-id>"
asset_kind: "knowledge_candidate"
knowledge_type: "recipe_formula_distillation"
domain_area: "<domain-area>"
source_family_id: "<publisher-or-source-family-id>"
publisher: "<publisher-name>"
title: "<knowledge-candidate-title>"
source_title: "<source-title>"
source_url: "<canonical-source-url-or-pointer>"
product_type: "<product-or-formula-type>"
use_context: "<intended-use-context-as-stated-or-derived>"
water_system: "<water-system-status-or-not-stated>"
kb_family_root: "<domain-area>/<source-family-id>"
source_asset_path: "<workspace-kb-root>/<domain-area>/<source-family-id>/sources/<source-asset-id>/"
knowledge_asset_path: "<workspace-kb-root>/<domain-area>/<source-family-id>/knowledge/<asset-id>/"
distillation_workflow_path: "<workflow-or-evidence-path-or-not-available>"
source_status: "<captured|source_admitted|reviewed|not_available>"
knowledge_status: "candidate"
review_status: "not_reviewed"
claim_scope: "<what-this-candidate-claims-to-cover>"
validation_scope: "not validated beyond source-stated content unless explicitly reviewed"
formula_summary: "<one-sentence-source-grounded-summary>"
distillation:
  profile_path: "knowledge/kb/domain-profiles/<domain>/index.md"
  skill_path: "<distillation-skill-or-procedure-path-or-not-specified>"
  prepared_by: "<author-or-process-id>"
  prepared_at: "<YYYY-MM-DD-or-not-stated>"
  review_decision_id: "<review-decision-id-or-not-reviewed>"
  phase_evidence:
    phase: "<phase-name-or-not-applicable>"
    run_id: "<run-id-or-not-applicable>"
    evidence_path: "<evidence-path-or-not-applicable>"
    admitted_result_path: "<phase-admitted-result-path-or-not-applicable>"
---
```

## Status boundaries

- Phase-admitted does not mean semantic review.
- Semantic review does not mean cosmetic safety, stability, preservative challenge, regulatory, GMP, or manufacturing validation.
- A source-bearing asset is not a knowledge asset.
- Captured source material is not semantic distillation.
- A knowledge candidate is not a sanctioned KB asset.
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
- distillation workflow path or evidence reference when available;
- review decision reference when available.

Claims must be supported by provenance or explicitly marked as not stated, inferred, or not validated.

## Formula by phase requirements

Use source grams and percentages if present.

If grams, percentages, pH, shelf life, safety limits, packaging, or process details are absent, explicitly say `not stated in source`.

Minimum phase table columns:

| Phase | Component | Amount / grams | Percentage | Source wording / pointer | Function | Notes |
|---|---|---|---|---|---|---|
| `<phase>` | `<component>` | `<grams-or-not-stated>` | `<percent-or-not-stated>` | `<source-pointer>` | `<function>` | `<notes>` |

## Component/function table requirements

Each listed component must have a source-grounded or explicitly inferred function.

Minimum component/function table columns:

| Component | Source-stated function | Distilled / inferred function | Evidence pointer | Not stated / not validated |
|---|---|---|---|---|
| `<component>` | `<function-or-not-stated>` | `<interpretation-or-none>` | `<source-pointer>` | `<boundary>` |

## Required markdown sections

Use these sections in this order.

## Status and review boundary

- Asset kind: `<knowledge_candidate|knowledge_asset>`
- Knowledge status: `<candidate|admitted>`
- Review status: `<not_reviewed|in_review|approved|returned|held|rejected>`
- Phase evidence: `<none|phase/run reference>`

State explicitly:

```text
Phase-admitted does not mean semantic review.
Semantic review does not mean cosmetic safety, stability, preservative challenge, regulatory, GMP, or manufacturing validation.
```

## Source / provenance

- Source family ID: `<source_family_id>`
- Publisher: `<publisher>`
- Source title: `<source_title>`
- Source URL / canonical pointer: `<source_url>`
- Source asset path: `<source_asset_path>`
- Source capture / admission status: `<source_status>`
- Hashes / stable representation IDs: `<hashes-or-not-available>`
- Distillation workflow path: `<distillation_workflow_path>`

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

| Phase | Component | Amount / grams | Percentage | Source wording / pointer | Function | Notes |
|---|---|---|---|---|---|---|
| `<phase>` | `<component>` | `<grams-or-not-stated>` | `<percent-or-not-stated>` | `<source-pointer>` | `<function>` | `<notes>` |

## Components and functions

| Component | Source-stated function | Distilled / inferred function | Evidence pointer | Not stated / not validated |
|---|---|---|---|---|
| `<component>` | `<function-or-not-stated>` | `<interpretation-or-none>` | `<source-pointer>` | `<boundary>` |

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

## Distilled interpretation

List interpretations grounded in the source. Each item must explain its evidence basis.

- `<interpretation>` - evidence: `<source-pointer-or-section>`

## Not stated / not validated

Use this section to prevent unsupported claims from leaking into the asset.

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
- Related admitted knowledge assets: `<paths-or-none>`
- Related review decisions: `<ids-or-none>`

## Admission / evidence

- Review decision ID: `<review-decision-id-or-not-reviewed>`
- Approved destination: `<approved-destination-or-not-approved>`
- Admission path: `<admission-path-or-not-admitted>`
- Phase evidence path: `<phase-evidence-path-or-not-applicable>`
- KB target path if admitted: `<knowledge_asset_path>`

State explicitly whether this file is still a candidate or has been admitted as a sanctioned KB asset.
