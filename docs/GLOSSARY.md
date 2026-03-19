# GLOSSARY

## Control plane
Versioned source of truth for governance artifacts: policy, contracts, schemas, templates, and architecture decisions.

## Runtime
The executing harness and tool environment that consumes control-plane artifacts but is not stored in this repo as live state.

## Orchestrator
The coordinating runtime component that receives intake, decides delegation, applies policy, and collects results.

## Subtask execution
A bounded delegated unit of work performed against a task packet with explicit scope, constraints, and expected outputs.

## Task packet
Structured request object that defines a delegated unit of work, its evidence inputs, constraints, expected outputs, and acceptance conditions.

## Result packet
Structured completion object that reports what was produced, what remains unresolved, what evidence supports the output, and where the output should go next.

## Operational plane
Workflow state for intake, assignment, review, and handoff. In this architecture it is represented in Notion rather than in markdown notes.

## Semantic plane
Human-readable note layer for concepts, synthesis, comparisons, and source-linked understanding. In this architecture it is represented in Obsidian.

## Sanctioned asset
An asset that passed admission and review checks and is allowed to live in the KB as reusable knowledge or curated source material.

## Source-bearing asset
An asset whose primary function is to preserve provenance to an external source, such as a captured page, transcript, or source package.

## Knowledge asset
An asset whose primary function is to express reusable understanding, synthesis, reference structure, or conclusions.

## Admission
The decision process that determines whether an artifact is allowed into the KB and under what asset role.

## Placement
The routing decision that determines which layer should store an artifact based on its current role, maturity, and provenance.

## Provenance
The minimum trace needed to justify origin, capture conditions, and source linkage for later review and reuse.

## Stable representation
A durable stored form of a captured source or artifact that can be referenced again without depending on volatile live state.

## Observability
Logs, run records, eval outputs, and reports used to inspect how the system behaved rather than to define canonical policy or knowledge.

## Evolution loop
A future bounded process that may propose changes to policy, prompts, or templates based on observed outcomes, but cannot self-apply those changes without review.

## Policy surface
The set of normative documents that define allowed behavior, forbidden behavior, checkpoints, and layer boundaries.

## Source of truth
The authoritative location for a given class of information. Each layer has one source of truth and mirrors must not override it.

## Working note
A semantic note that is useful for thinking and synthesis but is not yet a sanctioned KB asset and must not be treated as final knowledge.
