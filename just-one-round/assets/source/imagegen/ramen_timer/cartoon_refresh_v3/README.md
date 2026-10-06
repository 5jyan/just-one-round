# 30초 컵라면 · 2D cartoon refresh

The user approved the recommended crisp 2D cartoon redesign on 2026-09-19.
This is an explicit exception to the project's 2-logical-pixel art grid. Small
pixel sprites are replaced with new generated high-resolution sources, not
smoothed enlargements. Existing rules version 3 and ranking remain unchanged.

## Art contract

- Master: grey tired raccoon, cream muzzle, charcoal mask, butter-yellow shirt,
  loosened teal tie; waist-up view behind a kitchenette counter.
- Palette: navy/teal night interior, warm birch wood and lamp, coral-red noodle
  cup, cream UI. Upper-left key light; restrained shading and clear outlines.
- Background: 720×1600, world `(0,-80,360,800)`; central `(0,0,360,640)` is the
  safe core. Genuine authored wall/cabinet art fills 80 units of top/bottom
  overscan. The background revision is cropped uniformly, never stretched.
- Foreground counter: direct crop of that same background at world y=432.
  This preserves alignment and occludes the raccoon's waist naturally.
- Sprites: 256×256 cells, medium texture filtering; exact grids and reviewed
  source bounds are in `pipeline-meta.json` and `../runtime_manifest.json`.
- Keep the live timer obscured except the existing calibration and peek
  windows. Cooking actions and smoke must not introduce a metronome or gauge.

## Provenance / build

All creative source images were generated using the built-in Image Gen tool.
Exact prompts are beside every `raw.png`; the original master and first
background draft are preserved. The revised background prompt is also stored.

The `generate2dsprite` processor performs chroma cleanup and saves
`processed/raw-sheet-clean.png` plus its metadata. The reviewed subject bounds
in `assemble.py` then recover complete ears, lids and chopsticks where the
generated sheet did not adhere to exact cell boundaries. Connected alpha masks
remove fragments from adjacent cups; they do not paint new art.

Run `python3 assets/source/imagegen/ramen_timer/cartoon_refresh_v3/assemble.py`
from the project root to reproduce the seven runtime assets. Shared family
scales preserve pose differences, Lanczos reduction preserves smooth edges,
and every output cell has transparent margins. Old source directories remain
available; runtime asset names and atlas grids are unchanged.

Validate with the ramen asset, runtime, rules, presentation and visual tests.
Inspect generated QC captures at 320/360-wide short screens, a tall phone, and
the guide's wide slot before accepting a new assembly.
