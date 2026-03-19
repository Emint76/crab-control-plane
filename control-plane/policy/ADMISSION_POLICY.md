# ADMISSION_POLICY

## Purpose
Define the threshold for allowing assets into the KB and distinguish source-bearing assets from knowledge assets.

## Scope
Applies to all proposed KB entries, including source capture packages, curated source-bearing assets, and approved knowledge assets.

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

## Required checkpoints
1. Classify the candidate as `source-bearing` or `knowledge`.
2. Validate the candidate against its contract or KB asset expectations.
3. Confirm provenance minimums.
4. Confirm a review decision authorizes KB placement.
5. Confirm the asset is expressed in stable representation rather than transient workflow form.

## Interaction with adjacent layers
- **Notion:** tracks the admission request and review status, but not the sanctioned asset itself.
- **Obsidian:** may hold draft semantic notes that later mature into KB knowledge assets.
- **Contracts:** source capture package and knowledge note contract provide admission inputs.
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
