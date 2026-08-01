# Midnight Snake Asset Manifest

## Decision

All active character and environment art is newly generated for
`midnight_snake`. The old dachshund files are retained as inactive archive
material and are not loaded by the new runtime.

## Source to runtime

| Source | Runtime | Contract |
| --- | --- | --- |
| `background/raw-background.png` | `apartment_background.png` | 360×640 opaque, baked 9×15 floor |
| `unified_head/slither/processed/sheet-transparent.png` | `snake_head_slither_atlas.png` | 4×4, 32px open-neck head caps |
| `unified_head/eat/processed/sheet-transparent.png` | `snake_head_eat_atlas.png` | 4×4, 32px open-neck bite caps |
| `scale_pattern_candidate/snake_scale_pattern_candidate.png` | `snake_scale_pattern.png` | 32×32 transparent seamless body overlay |
| `food/processed/sheet-transparent.png` | `midnight_food_atlas.png` | 2×6, 32px cells |
| `crumb/processed/sheet-transparent.png` | `crumb_burst_sheet.png` | 2×2, 32px cells |

Direction row order is down, left, right, up. Sprite sheets were chroma-keyed,
cropped, normalized, and QC processed with the local `generate2dsprite`
pipeline. `process_static_assets.py` deterministically creates the pixel-scale
room and baked board. The runtime draws one continuous golden body path; its
round endpoint is the tail, and the open-neck head cap overlaps the other end.
The generated scale overlay is repeated over the continuous golden body path.
The previous tail atlas and low-contrast skin tile remain archived and are not
loaded.
