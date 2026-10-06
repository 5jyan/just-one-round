# Net Boat native-pixel fish remaster

- Scope: sardine, piranha, and marlin active runtime atlases.
- Identity: preserve the approved v8 sardine and v3 piranha/marlin silhouettes,
  palettes, facing directions, expressions, and four-frame swim loops.
- Runtime contract: sardine 28x28 in a 2x2 sheet; piranha 28x28 strip;
  marlin 56x38 strip. Display size equals the source cell size.
- Pixel contract: effective 2-logical-pixel clusters, limited opaque palettes,
  hard edges, no fractional alpha, no smoothing, center anchors.
- Gameplay contract: no changes to speed, spawn timing/counts, score, collision,
  controls, animation timing, or any other game behavior.
- Provenance: creative source generated from the accepted local masters with
  built-in ImageGen; deterministic chroma cleanup, extraction, palette cleanup,
  alpha hardening, and atlas assembly follow locally.

