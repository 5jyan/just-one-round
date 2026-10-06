# Net Boat high-fidelity fish production contract

- Scope: the six active runtime fish/water atlases only.
- Source policy: reprocess the approved v3, v7, and v8 high-resolution masters; do not redesign species identities.
- Animation: preserve four-frame loops, order, center anchors, and existing playback rates.
- Rendering: one texture pixel per logical display pixel with nearest-neighbor sampling.
- Runtime cells: sardine 28x28 (2x2), piranha 28x28, marlin 56x38,
  shark fin 74x38, shark wake 72x36, whale 160x106.
- Visual policy: crisp limited palettes, dark readable outlines, transparent margins,
  and the project's chunky two-logical-pixel cluster language.
- Gameplay policy: speed, spawn timing/counts, scores, and collision geometry remain unchanged.
  The sardine visual is normalized from 27.2 to 28 logical pixels; collision remains independent.
- Shark policy: runtime art remains dorsal-fin-only. The fin is derived from the processed
  shark master and kept within the existing approximately 21x14 visual/collision footprint.
- No legacy source or inactive atlas is deleted.

