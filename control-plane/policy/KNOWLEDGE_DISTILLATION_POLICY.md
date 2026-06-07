# KNOWLEDGE_DISTILLATION_POLICY

## Purpose

Define the policy for transforming admitted sources, reviewed source-bearing assets, or other provenance-bearing evidence into knowledge candidates.

This is a proposed control-plane extension. It defines candidate structure and semantic distillation expectations only. It does not create a live ingestion path, runtime write path, source-admission path, knowledge-admission path, validator, schema, or Phase behavior.

## Scope

This policy applies when source material or provenance-bearing evidence is prepared for possible later knowledge admission.

Allowed inputs include:

- admitted source-bearing assets;
- reviewed source-bearing assets;
- captured source packages with provenance evidence;
- other evidence-bearing materials explicitly allowed by an applicable review path.

Outputs under this policy are knowledge candidates unless and until a review decision and admission path authorize KB placement.

## Non-goals

This policy does not:

- perform source admission;
- perform knowledge admission;
- authorize KB writes;
- define runtime behavior;
- define Phase runner behavior;
- add schemas or validators;
- migrate or re-home existing assets;
- write to the live KB corpus.

The live KB corpus belongs under the runtime-configured workspace KB root, not this repository.

## Core invariants

- A source-bearing asset is not a knowledge asset.
- Captured source material is not semantic distillation.
- A knowledge candidate is not a sanctioned KB asset.
- Phase-admitted does not mean semantically reviewed.
- Semantic review does not mean domain expert validation.
- Domain Knowledge Profile does not authorize KB admission.
- Domain Knowledge Profile defines candidate structure and semantic distillation expectations only.
- Admission still requires the applicable review and admission path.
- Review decision authorizes KB placement.
- Phase proves controlled execution/admission evidence, not semantic correctness.
- Source-stated, distilled interpretation, inferred, and not-stated content must be separated.
- Claims must be supported by provenance or explicitly marked as not stated, inferred, or not validated.
- Live KB corpus storage belongs under the runtime-configured workspace KB root, not this repository.

## Canonical formula

```text
Policy/Profile defines candidate/result correctness.
Skill executes the distillation procedure.
Review decision authorizes KB placement.
Phase proves controlled execution/admission evidence.
KB asset is the admitted sanctioned result.
```

## Asset state meanings

### Source-bearing asset

A source-bearing asset preserves external source material and provenance in stable form. It may be admitted to the KB as source evidence, but it is not itself semantic distillation.

### Knowledge candidate

A knowledge candidate is prepared semantic distillation. It may follow a knowledge asset template and a Domain Knowledge Profile, but it is not a sanctioned KB asset until review and admission authorize placement.

### Knowledge asset

A knowledge asset is the admitted sanctioned result after required review and admission. It is fit for the KB role defined by KB policy and layout discipline.

### Domain Knowledge Profile

In this proposed extension, a Domain Knowledge Profile is a documentation profile that constrains candidate structure, required fields, source handling, and domain cautions for a domain area.

It does not authorize KB admission, prove semantic correctness, replace review decisions, or validate domain-expert claims.

## Distillation expectations

A distillation procedure must preserve the difference between:

- directly stated source content;
- distilled interpretation grounded in the source;
- inferred content;
- content not stated by the source;
- content not validated by the review path.

A knowledge candidate must not blur these categories for convenience. If source evidence does not state grams, percentages, thresholds, process conditions, dates, claims, or validation outcomes, the candidate must say so explicitly.

## Provenance expectations

Each knowledge candidate must identify the source evidence it depends on.

Minimum provenance expectations are:

- source family or publisher identifier;
- source title or human-readable source identifier;
- source URL or canonical pointer when applicable;
- source-bearing asset path when available;
- retrieval or capture status when available;
- hashes or stable representation identifiers when available;
- distillation workflow path or evidence reference when available.

Unsupported claims must be removed, constrained to the available evidence, or marked as not stated / not validated.

## Review and admission boundary

Semantic review may determine that a knowledge candidate is coherent, correctly separated by claim type, and supported by available provenance. Semantic review does not mean domain expert validation.

A review decision is the artifact that authorizes KB placement when the candidate also satisfies admission policy and placement policy. A Phase result or successful controlled execution does not replace that review decision.

## Phase boundary

Phase evidence may prove that a controlled process executed, produced expected artifacts, or satisfied admission evidence requirements. It does not prove semantic correctness, scientific correctness, regulatory fitness, manufacturing fitness, or domain expert validation.

A Phase-admitted artifact may still require semantic review and may still be rejected as a knowledge asset.

## Repository boundary

This repository may contain:

- policies;
- asset type registries;
- asset templates;
- domain profiles;
- curated examples if explicitly marked as examples.

This repository must not contain the full live KB corpus, live runtime writes, source-admission output, knowledge-admission output, or runtime workspace KB payloads.
