# KNOWLEDGE_ASSET_TYPES

## Purpose

Registry of proposed knowledge asset output types produced by agent-led extraction.

This registry is documentation only. It does not create schemas, validators, Phase behavior, admission mechanics, runtime writes, or live KB assets. A type marked `defined` has a documented markdown template in this repository. A type marked `placeholder` is reserved for future definition and must not be treated as a complete asset contract.

## Naming note

PR85 used `*_distillation` wording. This corrective PR replaces that framing with `*_extraction` to make the ownership boundary explicit: the agent prepares semantic extraction outputs; Phase admits already reviewed, KB-ready artifacts only.

## Registry

| Asset type | Purpose | Typical source inputs | Expected output shape | Template path | Status |
|---|---|---|---|---|---|
| `recipe_formula_extraction` | Extract a formula, recipe, or product-making procedure into a provenance-bearing working candidate that can be reviewed and finalized as a knowledge package, with formula phases, component functions, substitutions, agent interpretation, and explicit validation boundaries. | Source-bearing recipe pages, formula articles, source captures, reviewed ingredient/procedure evidence. | Markdown asset with required front matter, phase table, component/function table, method notes, provenance, source-stated claims, agent interpretation, inferred content, not-stated / not-validated content, and admission evidence fields. | `knowledge/kb/asset-templates/recipe-formula-extraction.md` | defined |
| `component_profile` | Describe a material, ingredient, software component, subsystem, or other component-level subject with role, properties, constraints, and provenance. | Source-bearing reference pages, specs, notes, product documentation, reviewed source packages. | Placeholder. Expected to include identity, role, properties, constraints, related assets, source-stated claims, agent interpretation, inferred content, and review boundary. | Not defined in this PR. | placeholder |
| `protocol_extraction` | Extract a procedure, experimental protocol, operating method, or repeatable workflow into structured steps and constraints. | Protocol articles, operating procedures, reviewed source captures, evidence packages. | Placeholder. Expected to include prerequisites, steps, decision points, required evidence, limits, source-stated content, agent interpretation, and review boundary. | Not defined in this PR. | placeholder |
| `article_extraction` | Extract an article or long-form source into reusable claims, context, findings, and limitations. | Articles, essays, documentation pages, source-bearing captures. | Placeholder. Expected to include source frame, claim map, evidence excerpts or pointers, agent interpretation, inferred content, and unresolved/not-stated areas. | Not defined in this PR. | placeholder |
| `process_analysis_asset` | Analyze a process, operational flow, or system behavior using provenance-bearing inputs. | Logs, reports, process descriptions, workflow documents, source-bearing operational evidence. | Placeholder. Expected to include process frame, steps, observations, risks, assumptions, and evidence boundary. | Not defined in this PR. | placeholder |
| `comparison_asset` | Compare multiple sources, products, methods, components, or decisions while preserving source-specific claims. | Multiple reviewed source-bearing assets, source captures, candidate knowledge assets. | Placeholder. Expected to include comparison scope, dimensions, item-by-item evidence, source-stated claims, inferred differences, and not-validated areas. | Not defined in this PR. | placeholder |
| `decision_record` | Record a durable knowledge-facing decision with rationale, alternatives, provenance, and consequences. | Review decisions, policy discussions, source evidence, architecture notes. | Placeholder. Expected to include decision, context, options, rationale, consequences, provenance, and review boundary. | Not defined in this PR. | placeholder |

## Status semantics

- `defined`: this repository contains a concrete markdown template for the asset type.
- `placeholder`: this repository reserves the type name and intended use only; no complete template or validation surface exists.

## Candidate, package, and admission boundary

A registered type does not authorize KB admission. A completed template may produce a working candidate. After review authorization, the KB-ready Phase input is a knowledge package.

`knowledge package` is a documentation/process concept here, not a new schema-bound artifact type.

Phase 3 `kb_admission` admits the knowledge package byte-for-byte as `admission_type: knowledge_asset`. Phase does not rewrite metadata, so transient workflow status must not be embedded in the package unless that status is intended to remain true after admission.

Profile approval or refinement means the extraction structure is agreed. It does not replace the review decision required for KB placement.
