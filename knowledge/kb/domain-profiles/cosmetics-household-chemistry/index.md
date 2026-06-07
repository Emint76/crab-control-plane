# Cosmetics and household chemistry domain profile

## Scope

This is the first proposed Domain Knowledge Profile for knowledge distillation candidates in the cosmetics and household chemistry domain.

It applies to proposed knowledge candidates about DIY formulas, product formulas, ingredients/components, methods, processes, comparisons, and decision records in this domain. It does not authorize source admission, knowledge admission, KB placement, runtime writes, or live KB corpus changes.

Required rule block:

```text
Domain Knowledge Profile does not authorize KB admission.
It defines candidate structure and semantic distillation expectations.
Admission still requires review/admission path.
```

## Source families

This profile may be used with source families in the `cosmetics-household-chemistry` domain area when a source family has sufficient provenance to support a knowledge candidate.

Source-family-specific override documents are not defined in this PR. Future overrides may live under:

```text
knowledge/kb/domain-profiles/cosmetics-household-chemistry/source-families/<source-family-id>.md
```

Do not treat the presence of this profile as approval for any specific publisher, source family, or source asset.

## Allowed knowledge asset types

Initial allowed asset types for this domain:

- `recipe_formula_distillation`
- `component_profile` (placeholder)
- `protocol_distillation` (placeholder)
- `article_distillation` (placeholder)
- `process_analysis_asset` (placeholder)
- `comparison_asset` (placeholder)
- `decision_record` (placeholder)

Only `recipe_formula_distillation` has a concrete template in this PR.

## Default asset type for recipes

Default asset type for DIY/product formulas: `recipe_formula_distillation`.

Template path:

```text
knowledge/kb/asset-templates/recipe-formula-distillation.md
```

## Distillation rules by asset type

### recipe_formula_distillation

For formula, recipe, and product-making sources, require:

- product purpose / short description;
- formula overview;
- formula table by phase;
- percentages if source provides them;
- grams/amounts if source provides them;
- component/function table;
- manufacturing/process notes;
- source-stated substitutions;
- constraints/cautions;
- directly stated in source;
- distilled interpretation;
- not stated / not validated;
- source/provenance/hashes;
- explicit distinction between source asset, knowledge candidate, Phase-admitted asset, semantically reviewed asset, and domain-expert-validated asset.

### component_profile

Placeholder. Future definition should require component identity, source-stated role, properties, use constraints, source-stated cautions, inferred functions, and not-stated / not-validated boundaries.

### protocol_distillation

Placeholder. Future definition should require prerequisites, source-stated steps, process controls, evidence pointers, limits, and not-stated / not-validated boundaries.

### article_distillation

Placeholder. Future definition should require source frame, source-stated claims, distilled interpretation, claim evidence, omissions, and review boundary.

### process_analysis_asset

Placeholder. Future definition should require process frame, source evidence, observations, risks, assumptions, and review boundary.

### comparison_asset

Placeholder. Future definition should require comparison scope, dimensions, item-by-item source evidence, inferred differences, and not-validated areas.

### decision_record

Placeholder. Future definition should require decision, context, options, rationale, consequences, provenance, and review boundary.

## Required fields by asset type

### recipe_formula_distillation

Required front matter follows:

```text
asset_id
asset_kind
knowledge_type
domain_area
source_family_id
publisher
title
source_title
source_url
product_type
use_context
water_system
kb_family_root
source_asset_path
knowledge_asset_path
distillation_workflow_path
source_status
knowledge_status
review_status
claim_scope
validation_scope
formula_summary
distillation
```

Required sections follow:

```text
Status and review boundary
Source / provenance
Product frame
Formula overview
Formula by phase
Components and functions
Method / technological process
Source-stated substitutions
Limits and cautions
Directly stated in source
Distilled interpretation
Not stated / not validated
Related assets
Admission / evidence
```

Other asset types are placeholders and have no complete field requirements in this PR.

## Domain-specific cautions

For this domain, knowledge candidates must clearly state applicable cautions:

- cosmetic safety not validated;
- stability not validated;
- preservative challenge not validated;
- regulatory/GMP/manufacturing not validated.

A candidate must not imply that a semantic review validates cosmetic safety, formulation stability, preservative efficacy, regulatory compliance, GMP fitness, scaling, packaging compatibility, or manufacturing readiness.

## Source-stated / inferred / not-stated boundary

Candidates must separate:

- directly source-stated content;
- distilled interpretation grounded in the source;
- inferred content;
- not-stated content;
- not-validated content.

If the source does not state grams, percentages, pH, shelf life, safety limits, packaging, processing details, substitutions, or validation outcomes, the candidate must say `not stated in source` or `not validated` in the relevant field or section.

## Review boundary

A Domain Knowledge Profile does not approve a candidate for KB placement.

Review states must distinguish:

- source asset: admitted or reviewed source-bearing evidence;
- knowledge candidate: prepared semantic distillation, not sanctioned;
- Phase-admitted asset: controlled execution/admission evidence, not semantic correctness;
- semantically reviewed asset: reviewed for source-grounded semantic structure, not domain expert validation;
- domain-expert-validated asset: only valid when a qualified domain expert review path explicitly records that validation.

Review decision authorizes KB placement only when admission policy, placement policy, provenance, and the candidate asset expectations are satisfied.

## Source / provenance requirements

Recipe/formula candidates must include:

- source family ID;
- publisher;
- source title;
- source URL or canonical pointer;
- source asset path when available;
- retrieval or capture status when available;
- content hashes or stable representation identifiers when available;
- distillation workflow path or evidence reference when available;
- review decision reference when available.

Claims without source support must be removed, narrowed, or marked as not stated / not validated.

## Example live KB paths

These are illustrative path shapes only. They are not live KB writes and are not repository storage targets.

Domain/source-family-first source-bearing asset path:

```text
<workspace-kb-root>/cosmetics-household-chemistry/<source-family-id>/sources/<asset-slug>-<YYYYMMDD>/
```

Domain/source-family-first knowledge asset path:

```text
<workspace-kb-root>/cosmetics-household-chemistry/<source-family-id>/knowledge/<asset-id>/
```

Domain/source-family-first collection path:

```text
<workspace-kb-root>/cosmetics-household-chemistry/<source-family-id>/collections/<collection-id>/
```

Domain/source-family-first workflow evidence path:

```text
<workspace-kb-root>/cosmetics-household-chemistry/<source-family-id>/workflow/<run-id>/
```
