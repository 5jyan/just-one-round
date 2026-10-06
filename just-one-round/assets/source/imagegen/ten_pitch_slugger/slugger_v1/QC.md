# 홈런왕 강타자 v1 provenance and QC

## Generation provenance

Each action was generated separately with the built-in `image_gen` tool using
the existing regular rear-3/4 sheet for motion/frame order and the accepted
slugger idle for identity/scale. The prompt used for each action is next to its
raw input in `batter_slugger_<action>/prompt-used.txt`.

| action | selected raw output | grid | runtime output |
|---|---|---:|---|
| idle | `exec-7714e848-9c43-4bcc-a6bd-cfa6a64fc44b.png` | 2×3 / 6 | `batter_slugger_idle_v1.png` |
| swing | `exec-d9cf8909-f29f-4cc3-8268-5ae425af1606.png` | 4×4 / 16 | `batter_slugger_swing_v1.png` |
| whiff | `exec-090ea360-cd2c-4ddd-88e1-0240fc1f2808.png` | 4×3 / 12 | `batter_slugger_whiff_v1.png` |
| result | `exec-ec5c8135-1f43-494c-a364-6731878644e2.png` | 4×2 / 8 | `batter_slugger_result_v1.png` |

The generated RGBA files are retained as `raw-alpha.png`. A deterministic
flat `#FF00FF` composite is retained as `raw.png` for the required chroma-key
processor input; runtime sheets are transparent PNGs from `sheet-transparent.png`.

## Processor contract

All sheets use 240×240 cells, `align=feet`, nearest-neighbor output, largest
component selection, 4px trim, 3px edge cleanup, and strict QC. Idle reuses
the accepted `slugger-scale-profile.json` with `scale_strategy=preserve`; the
other actions use the fixed 0.88 fit profile because their weapon poses need
action-specific safe containment. The authored feet/source anchor remains
`(120,226)`; QC allows only the documented generated-source edge exception.

| action | output size | body scale CV | anchor-y std | output edge touch | clamp |
|---|---:|---:|---:|---:|---:|
| idle | 480×720 | 0.00364 | 0.00701 | 0 | 0 |
| swing | 960×960 | 0.09145* | 0.00810 | 0 | 0 |
| whiff | 960×720 | 0.03304 | 0.02442 | 0 | 0 |
| result | 960×480 | 0.00694 | 0.00138 | 0 | 0 |

`*` Swing preserves the accepted regular swing's wider contact-pose variation;
frame 8 has a reviewed source-cell edge touch, while the processed runtime
frame has no edge touch or clipping. The swing contact pixel at frame index 8,
cell-local `(215,136)`, is opaque. All actions were visually inspected after
processing; every frame is populated, contained, and keeps the helmet/uniform/
sleeves/shoes/gold-bat palette and rear 3/4 silhouette.

## Grounding post-process

The processed transparent sheets and runtime copies apply a deterministic
per-cell vertical translation using visible alpha `>8` to the authored feet
baseline `y=226`. Idle, whiff, and result frames now land exactly on `226`;
swing frames do too except for contact frame 8, which remains at `224` so its
authored bat-tip coordinate `(215,136)` is unchanged. The resulting cross-action
drift is at most 2 px, recorded in each `processed/pipeline-meta.json` under
`postprocess_visible_baseline` and enforced by the asset test.

Post-process fringe check: whiff and result were scanned for strong magenta
(`R>170, B>130, G<100`) among visible pixels. Whiff had 0; result had 3
generated fringe pixels, which were cleared deterministically in the processed
transparent sheet and runtime copy. The final four runtime sheets have 0 strong
magenta-fringe pixels.
