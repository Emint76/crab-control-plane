# Cosmetics and household chemistry extraction profile

## Scope

This is the first proposed Domain Extraction Profile for agent-led knowledge extraction in the cosmetics and household chemistry domain.

It defines the agreed data structure for extracting knowledge candidates about DIY formulas, product formulas, ingredients/components, methods, processes, comparisons, and decision records in this domain. It does not authorize source admission, knowledge admission, KB placement, runtime writes, or live KB corpus changes.

Required rule block:

```text
Domain Extraction Profile does not authorize KB admission.
It defines the agreed data structure for agent-led extraction.
Admission still requires review/admission path.
```

## Domain/task scope

This profile applies when a user or reviewer asks the agent to extract reusable knowledge candidates from admitted, reviewed, or otherwise provenance-bearing sources in the cosmetics and household chemistry domain.

For formula and recipe tasks, the default output type is `recipe_formula_extraction`.

## Source families

This profile may be used with source families in the `cosmetics-household-chemistry` domain area when source evidence is available and provenance is sufficient for candidate preparation.

Source-family-specific override documents are not defined in this PR. Future overrides may live under:

```text
knowledge/kb/extraction-profiles/cosmetics-household-chemistry/source-families/<source-family-id>.md
```

Do not treat the presence of this profile as approval for any specific publisher, source family, source asset, or extracted candidate.

## Expected extracted entities

For recipe/formula extraction, the agent should extract these entities when source evidence supports them:

- product or formula;
- product purpose / short description;
- source family and source document;
- formula phase;
- component / ingredient;
- component amount;
- component percentage;
- component function;
- process step;
- substitution;
- limit / caution;
- source-stated claim;
- agent interpretation;
- inferred content;
- not-stated / not-validated item;
- related source-bearing asset;
- review/admission evidence reference.

## Allowed output asset types

Initial allowed output asset types for this domain:

- `recipe_formula_extraction`
- `component_extraction.v1` (placeholder extraction profile; resulting asset may be a component profile)
- `protocol_extraction` (placeholder)
- `article_extraction` (placeholder)
- `process_analysis_asset` (placeholder)
- `comparison_asset` (placeholder)
- `decision_record` (placeholder)

Only `recipe_formula_extraction` has a concrete template in this PR.

## Default asset type for recipes

Default asset type for DIY/product formulas: `recipe_formula_extraction`.

Template path:

```text
knowledge/kb/asset-templates/recipe-formula-extraction.md
```

## Required fields by asset type

### recipe_formula_extraction

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
extraction_profile_path
extraction_workflow_path
source_status
knowledge_status
review_status
claim_scope
validation_scope
formula_summary
extraction
```

Other asset types are placeholders and have no complete field requirements in this PR.

## Required tables by asset type

### recipe_formula_extraction

The candidate must include:

- formula table by phase;
- component/function table;
- source-stated substitutions table when substitutions are present;
- related assets / evidence references.

The formula table must include phase, component, amount/grams, percentage, source wording or pointer, agent-interpreted function, and notes.

The component/function table must separate source-stated function, agent interpretation, inferred content, evidence pointer, and not-stated / not-validated boundaries.

## Relationships between extracted objects

A recipe/formula candidate should preserve these relationships:

- product/formula belongs to `domain_area` and `source_family_id`;
- product/formula is derived from one or more source-bearing assets or provenance-bearing sources;
- formula phase contains components;
- component may have amount, percentage, source-stated function, agent-interpreted function, and inferred function;
- process step may reference one or more phases or components;
- substitution links an original component to a source-stated substitute;
- caution links to a source-stated warning, agent interpretation, inferred risk, or not-validated boundary;
- review decision may authorize KB placement;
- Phase 3 `kb_admission` may admit the prepared candidate after review authorization.

## Extraction rules by asset type

### recipe_formula_extraction

For formula, recipe, and product-making sources, require:

- product purpose / short description;
- formula overview;
- formula by phase;
- percentages if source provides them;
- grams/amounts if source provides them;
- component/function table;
- process notes;
- substitutions;
- limits/cautions;
- directly stated in source;
- agent interpretation;
- inferred content, if any;
- not stated / not validated;
- source/provenance/hashes.

The agent must distinguish source asset, knowledge candidate, Phase-admitted asset, semantically reviewed asset, and domain-expert-validated asset.

### component_extraction.v1

Placeholder. Future definition should require component identity, source-stated role, properties, use constraints, source-stated cautions, agent interpretation, inferred functions, and not-stated / not-validated boundaries.

### protocol_extraction

Placeholder. Future definition should require prerequisites, source-stated steps, process controls, evidence pointers, limits, agent interpretation, inferred content, and not-stated / not-validated boundaries.

### article_extraction

Placeholder. Future definition should require source frame, source-stated claims, agent interpretation, inferred content, claim evidence, omissions, and review boundary.

### process_analysis_asset

Placeholder. Future definition should require process frame, source evidence, observations, risks, assumptions, and review boundary.

### comparison_asset

Placeholder. Future definition should require comparison scope, dimensions, item-by-item source evidence, inferred differences, and not-validated areas.

### decision_record

Placeholder. Future definition should require decision, context, options, rationale, consequences, provenance, and review boundary.

## Provenance rules

Recipe/formula candidates must include:

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

Claims without source support must be removed, narrowed, or marked as inferred, not stated, or not validated.

## Source-stated / agent-interpreted / inferred / not-stated boundary

Candidates must separate:

- directly source-stated content;
- agent interpretation grounded in the source;
- inferred content;
- not-stated content;
- not-validated content.

If the source does not state grams, percentages, pH, shelf life, safety limits, packaging, processing details, substitutions, or validation outcomes, the candidate must say `not stated in source` or `not validated` in the relevant field or section.

## Structure approval boundary

User or reviewer approval/refinement of this profile means the extraction data structure is agreed for agent use.

It does not mean:

- any source has been admitted;
- any candidate has been reviewed;
- any candidate is approved for KB placement;
- any domain expert validation has occurred;
- any authorization to move semantic extraction into Phase;

## Review boundary

A Domain Extraction Profile does not approve a candidate for KB placement.

Review states must distinguish:

- source asset: admitted or reviewed source-bearing evidence;
- knowledge candidate: agent-prepared semantic extraction output, not sanctioned;
- Phase-admitted asset: controlled byte-for-byte admission evidence, not semantic correctness;
- semantically reviewed asset: reviewed for source-grounded semantic structure, not domain expert validation;
- domain-expert-validated asset: only valid when a qualified domain expert review path explicitly records that validation.

Review decision authorizes KB placement only when admission policy, placement policy, provenance, and the candidate asset expectations are satisfied.

## Phase boundary

Phase 3 `kb_admission` starts after candidate preparation and review authorization. It freezes inputs, validates paths/manifests, verifies hashes, copies byte-for-byte, emits evidence, and fails closed.

Phase does not perform semantic extraction, validate semantic correctness, or validate domain expertise.

## Domain-specific cautions

For this domain, knowledge candidates must clearly state applicable cautions:

- cosmetic safety not validated;
- stability not validated;
- preservative challenge not validated;
- regulatory/GMP/manufacturing not validated.

A candidate must not imply that semantic review validates cosmetic safety, formulation stability, preservative efficacy, regulatory compliance, GMP fitness, scaling, packaging compatibility, or manufacturing readiness.

## Example live KB paths

These are illustrative path shapes only. They are not live KB writes and are not repository storage targets.

Domain/source-family-first source-bearing asset path:

```text
<workspace-kb-root>/cosmetics-household-chemistry/<source-family-id>/sources/<asset-slug>-<YYYYMMDD>/
```

Domain/source-family-first knowledge asset path:

```text
<workspace-kb-root>/cosmetics-household-chemistry/<source-family-id>/knowledge/<knowledge-type>/<asset-slug>/
```

`<knowledge-type>` is an instance-local placement taxonomy segment selected through local KB taxonomy configuration. It is not a repository-defined canonical taxonomy and is not the stable asset identity.

Domain/source-family-first collection path:

```text
<workspace-kb-root>/cosmetics-household-chemistry/<source-family-id>/collections/<collection-id>/
```

Domain/source-family-first workflow evidence path:

```text
<workspace-kb-root>/cosmetics-household-chemistry/<source-family-id>/workflow/<run-id>/
```
