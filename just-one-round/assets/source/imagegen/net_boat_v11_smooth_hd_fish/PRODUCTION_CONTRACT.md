# Net Boat smooth high-density fish contract

- Scope: sardine, piranha, and marlin only.
- Preserve the accepted v10 identities, four-frame swim order, center anchors,
  on-screen sizes, animation timing, and all gameplay behavior.
- Runtime display sizes remain sardine 28x28, piranha 28x28, marlin 56x38.
- Source cells are exactly 3x dense: sardine 84x84, piranha 84x84,
  marlin 168x114.
- Preserve full source color and fractional alpha. Do not palette-quantize or
  harden alpha. Render these three species with high-quality interpolation.
- Shark, whale, wake, boat, reef, FX, collisions, speed, scoring, and spawning
  remain unchanged.
- Creative masters are reused from v10; this version is a deterministic
  high-density reprocess and runtime integration, not a redesign.

