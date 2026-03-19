# KB_ROLE_CONTRACT

## Purpose
Define the KB as the store for sanctioned source-bearing assets, sanctioned knowledge assets, and curated collections over those assets.

## Scope
Applies to all assets admitted into the KB and to the minimum provenance and review discipline for those assets.

## Allowed behavior
- Store source-bearing assets with stable representations and provenance metadata.
- Store knowledge assets that passed review and are fit for downstream retrieval.
- Store collections that organize sanctioned assets for retrieval or navigation.
- Preserve identifiers linking sanctioned assets back to review and source context.

## Forbidden behavior
- Storing raw task packets, result packets, queue exports, or mutable workflow state.
- Admitting assets without provenance minimums.
- Treating collection structure as a hidden workflow board.
- Using KB storage as a scratchpad for draft semantic notes.

## Required checkpoints
1. Classify every asset as source-bearing, knowledge, or collection support.
2. Confirm approval and admission state before ingestion.
3. Confirm provenance and stable representation.
4. Confirm the asset is intelligible without requiring hidden operational context.

## Interaction with adjacent layers
- **Admission policy:** determines entry threshold.
- **Review decision:** authorizes or blocks KB placement.
- **Obsidian:** may provide draft precursors to knowledge assets.
- **Retrieval:** KB is the preferred source for sanctioned reusable material.

## Examples
- A curated HTML snapshot with provenance metadata as a source-bearing asset.
- An approved architecture brief as a knowledge asset.
- A collection grouping all approved architecture assets.

## Failure modes / common mistakes
- Ingesting source packages that only contain a link and no stable representation.
- Copying Notion workflow exports into KB because they seem informative.
- Storing draft working notes without clear approval.
- Losing linkage between knowledge assets and the source-bearing assets that support them.
