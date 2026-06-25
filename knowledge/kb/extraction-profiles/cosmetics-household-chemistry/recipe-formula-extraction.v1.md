# recipe_formula_extraction.v1

## Purpose

`recipe_formula_extraction.v1` is an agent instruction profile for extracting recipe, formula, and product-making knowledge candidates from accepted provenance-bearing sources in the cosmetics and household chemistry domain.

This document is instruction metadata. It is not a JSON Schema, semantic validator, parser, Phase check, admission engine, or canonical taxonomy definition.

## Applies When

Use this profile when all of the following are true:

- the source is accepted provenance-bearing material;
- the task asks for reusable recipe/formula knowledge intended for KB admission;
- the source contains formula, recipe, ingredient, phase, method, substitution, or product-making content;
- the target `knowledge_profile_id` is exactly `recipe_formula_extraction.v1`.

Stop before extraction when the source identity, source path, provenance, or accepted-source status is missing.

## Output Template

Use this output-shape template:

```text
knowledge/kb/asset-templates/recipe-formula-extraction.md
```

Do not duplicate the full template into this instruction profile. The template defines the markdown sections and tables expected for the candidate and final admission-authorized package.

## Required Extraction Decisions

The agent must decide and record:

- whether the source supports a recipe/formula extraction;
- the stable knowledge `asset_id`;
- the source-family-local `asset_slug` used only for placement;
- the source family, publisher, source title, and canonical source pointer;
- the product/formula frame;
- formula phases and components when source evidence supports them;
- component amounts, percentages, and functions when stated;
- substitutions when stated;
- process steps, limits, and cautions when stated;
- what is directly source-stated;
- what is agent interpretation;
- what is inferred;
- what is not stated;
- what is not validated.

The agent must not present inferred content as source-stated fact.

## Provenance Requirements

Every candidate and admission-authorized package must preserve:

- source asset or accepted source reference;
- exact accepted source placement path copied from accepted source provenance, not reconstructed from the source `asset_id`;
- source family ID;
- domain area;
- source title;
- source URL or canonical pointer;
- source capture/admission status when available;
- source evidence pointers for claims;
- extraction profile reference to this document;
- admission authorization reference when prepared for admission.

If a claim cannot be tied to the source, remove it, narrow it, or mark it as inferred, not stated, or not validated.

## Claim Boundaries

The candidate must separate:

- directly source-stated material;
- agent interpretation grounded in the source;
- inferred content;
- not stated;
- not validated.

For cosmetics and household chemistry formulas, explicitly mark these as not validated unless the accepted source provides suitable evidence:

- cosmetic safety;
- formulation stability;
- preservative challenge;
- regulatory/GMP/manufacturing fitness;
- shelf life;
- packaging compatibility;
- scale-up suitability.

Do not invent safety, regulatory, manufacturing, shelf-life, or expert validation claims.

## Candidate And Package Status

A working candidate is not a sanctioned KB asset.

An admission-authorized knowledge package is a byte-stable artifact approved for the controlled admission path. The authorization is a placement/admission gate, not proof that semantic review happened.

Phase3 `kb_admission` copies bytes. Before Phase invocation, remove or relocate temporary candidate-only status that would become false after admission.

## Required Sections And Tables

Use the template sections for:

- status and review boundary;
- source/provenance;
- product frame;
- formula overview;
- formula by phase;
- components and functions;
- method / technological process;
- source-stated substitutions;
- limits and cautions;
- directly stated in source;
- agent interpretation;
- inferred content;
- not stated / not validated;
- related assets;
- admission / evidence.

Minimum tables:

- formula by phase;
- component/function table;
- source-stated substitutions table when substitutions are present.

## Placement Boundary

This profile does not define `knowledge_type`.

For admission, `knowledge_profile_id` remains:

```text
recipe_formula_extraction.v1
```

`knowledge_type` is an instance-local placement taxonomy segment selected from outside-repository local taxonomy config:

```text
ADMISSION_KB_TAXONOMY_CONFIG=/absolute/outside-repository/kb-taxonomy-config.json
```

The repository must not define concrete canonical knowledge types such as recipe, component, formulation, or product type.

## Stop Conditions

Stop before Phase execution when:

- source identity or provenance is missing;
- accepted source status cannot be established;
- the selected profile ID is not `recipe_formula_extraction.v1`;
- the candidate contains unsupported claims presented as source facts;
- final bytes still contain temporary candidate-only status;
- admission authorization is missing;
- local taxonomy config is missing, invalid, relative, inside the repository, or does not allow the selected profile/type mapping;
- typed destination is unresolved;
- expected hashes are missing or inconsistent;
- exact-HEAD Phase2 baseline is unavailable and cannot be created;
- Phase4 or Phase3 prerequisites are unresolved.

## Phase Boundary

Phase2, Phase3, and Phase4 do not validate recipe semantics.

Phase3 remains the sole canonical execution and evidence owner. Phase evidence proves controlled byte-for-byte admission behavior, not semantic correctness.
