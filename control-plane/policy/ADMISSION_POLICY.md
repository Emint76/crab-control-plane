# ADMISSION_POLICY

## Purpose
Define the threshold for allowing assets into the KB and distinguish source-bearing assets from knowledge assets.

Admission means accepting a prepared asset into the KB.

Admission Stage 1 and Admission Stage 2 do not themselves admit an asset. Stage 1 defines the universal package contract and transitional dry-run validator. Stage 2 defines the universal handoff contract into Phase2, Phase4, and Phase3. Canonical admission requires successful Phase3 `kb_admission` evidence.

## Scope
Applies to all proposed KB entries, including source capture packages, curated source-bearing assets, and approved knowledge assets.

For the live KB corpus, the KB target is the OpenClaw workspace KB root configured at runtime, not the `crab-control-plane` repository. Existing `repo_admission` behavior remains a bounded repository admission surface for repo-owned layout discipline and curated examples; it is not the storage path for the full live KB corpus.

## Allowed behavior
- Admit a **source-bearing asset** when it preserves external source provenance in stable form.
- Admit a **knowledge asset** when it expresses reusable understanding and is supported by sufficient provenance for its claims.
- Store collections that organize sanctioned assets without becoming operational workflow objects.
- Keep knowledge assets linked to relevant source-bearing assets where applicable.

## Forbidden behavior
- Admitting raw task packets, result packets, review queue rows, or other workflow objects into the KB.
- Admitting semantic drafts that have not passed review.
- Admitting source-bearing assets without canonical pointer, retrieval status, retrieval timestamp, content type, stable representation, and human identifier.
- Treating Notion or Obsidian as the canonical KB.
- Treating `repo_admission` as the live KB corpus storage path.
- Storing the full live KB corpus in this repository unless an asset is explicitly curated as an example.

## Required checkpoints
1. Classify the candidate as `source-bearing` or `knowledge`.
2. Validate the candidate against its contract or KB asset expectations.
3. Confirm provenance minimums.
4. Confirm a review decision authorizes KB placement.
5. Confirm the asset is expressed in stable representation rather than transient workflow form.
6. Confirm live-corpus storage targets the runtime-configured workspace KB root unless the asset is explicitly curated as a repository example.

## Interaction with adjacent layers
- **Notion:** tracks the admission request and review status, but not the sanctioned asset itself.
- **Obsidian:** may hold draft semantic notes that later mature into KB knowledge assets.
- **Contracts:** source capture package and knowledge note contract provide admission inputs.
- **Runtime integration:** identifies the workspace KB root configuration surface for live corpus storage.
- **Retrieval:** admitted assets become preferred retrieval sources over drafts.

## Examples
- Admit a captured web page package with stable archived content and provenance metadata as a source-bearing asset.
- Admit an approved architecture synthesis note as a knowledge asset after review confirms source linkage and reusable value.
- Reject a task packet export even if it contains useful text because it is an operational object, not a KB asset.

## Failure modes / common mistakes
- Confusing "contains knowledge" with "is a knowledge asset." Task traffic may contain useful text but still fails admission.
- Omitting stable representation and leaving only a volatile URL.
- Admitting a draft Obsidian note directly into KB without review.
- Losing linkage between knowledge assets and the sources that justify them.
- Confusing repository examples or repo admission discipline with the live workspace KB corpus.
