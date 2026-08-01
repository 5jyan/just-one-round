# Sausage Dachshund runtime asset manifest

## Runtime files

| File | Grid | Cell / size | Frame order |
|---|---:|---:|---|
| `dog_head_walk_atlas.png` | 4 × 2 | 32 × 32 | down A/B, left A/B, right A/B, up A/B |
| `dog_head_eat_atlas.png` | 4 × 2 | 32 × 32 | down bite/chew, left, right, up |
| `dog_body_atlas.png` | 2 × 3 | 32 × 32 | horizontal, vertical, left-bottom, top-right, right-bottom, top-left |
| `dog_tail_walk_atlas.png` | 4 × 2 | 32 × 32 | down A/B, left A/B, right A/B, up A/B |
| `sausage_idle_sheet.png` | 2 × 2 | 32 × 32 | steam start, rise, peak, settle |
| `bite_fx_sheet.png` | 2 × 2 | 32 × 32 | contact, crescent, burst, fade |
| `kitchen_tiles_atlas.png` | 2 × 3 | 32 × 32 | clean, light, worn, scuff, warm reflection, dark |
| `kitchen_background.png` | — | 360 × 640 | static full-screen perimeter background |

All sprite sheets are RGBA PNGs. Runtime should use nearest-neighbor sampling.

## Provenance

- Character, food, FX, tiles, and background artwork: generated with built-in ImageGen.
- Transparency, cell splitting, alignment, and 32 px normalization: `generate2dsprite.py`.
- Body straight modules: a center cross-section from the accepted generated body strip was
  repeated along its travel axis so adjacent cells do not reveal dark repetition seams.
- Body corner variants: the accepted generated elbow was aligned to the two cell-edge
  connectors and deterministically rotated by 90 degrees, without repainting, so all four
  directions share identical width, color, and bend geometry.
- Background: deterministically downscaled from the generated 9:16 source to 360 × 640.
- Existing project assets were used only to calibrate pixel density and display scale; no
  existing sprite artwork was copied into this set.

## Locked visual rules

- Smooth-haired chestnut dachshund, no clothes or collar.
- Exactly two front legs in the head module and two rear legs in the tail module.
- No legs or protrusions on middle body modules.
- Straight runs dominate; bends are compact one-cell 90-degree elbows only.
- Sausage is unwrapped grilled meat with blunt ends and dark grill marks.
