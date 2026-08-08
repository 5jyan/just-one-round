# Ten Pitch Slugger Asset QC

- V3 scene decision pack approved: 2026-08-08
- V4 ball, impact, and batter swing decision packs approved: 2026-08-08
- Regulation field V4 decision pack approved: 2026-08-08
- Player-scale batter-box allowance approved: 2026-08-08
- Enlarged home plate and dirt-only foul-guide composition approved: 2026-08-08
- Runtime safe core: 360×640
- Authored background: hitter-view V4, 360×720 with 80px bottom overscan
- Preview background: dedicated 360×460 crop, no stretch
- Runtime filtering: nearest-neighbor / `FilterQuality.none`
- Character apparent pixel scale: 2×
- Character count: pitcher 1, batter 1; no catcher, umpire, crowd, or other figures

## Runtime files

| File | Size | Contract |
|---|---:|---|
| `background_hitter_v4.png` | 360×720 | V3 scenery with regulation-projected 18-foot mound; 80px overscan |
| `background_preview_v4.png` | 360×460 | Exact y=105 gameplay-camera crop, no stretch |
| `batter_rear_idle_v3.png` | 480×720 | 2×3, 240px cells |
| `batter_rear_swing_v4.png` | 960×960 | 4×4, 240px cells; contact index 8 |
| `batter_rear_whiff_v3.png` | 960×720 | 4×3, 240px cells |
| `batter_rear_result_v3.png` | 960×480 | 4×2, 240px cells |
| `pitcher_front_idle_v3.png` | 192×288 | 2×3, 96px cells |
| `pitcher_front_pitch_v3.png` | 384×288 | 4×3, 96px cells |
| `pitcher_front_magic_v3.png` | 384×384 | 4×4, 96px cells |
| `ball_spin_v4.png` | 72×48 | 3×2, 24px cells; cream leather, navy outline, brick-red stitches |
| `hit_fx_v4.png` | 384×192 | 4×2, 96px cells; 8 non-empty impact frames |
| `trail_fx_v3.png` | 256×128 | 4×2, 64px cells |

## Checks

- All raw raster art originated from ImageGen and prompt text is retained beside each source.
- Character sheets were chroma-key cleaned, feet-aligned, and processed with shared per-character scale profiles.
- Strict processor QC passed for the V3 retained sheets and the V4 ball, impact, and swing sheets. The V4 impact sheet has eight non-empty, contained frames; the V4 ball has six aligned rotation frames with no paste clamp or output-edge contact.
- The V4 swing has 16 valid non-empty frames, zero output-edge contacts, zero paste clamps, body-scale CV `0.0158`, and profile scale drift `0.0916`. Its raw anchor-Y deviation `0.0595` is accepted against an action-specific `0.07` gate because the authored knee lift and follow-through change the detected supporting foot; every processed frame still shares output baseline `y=226`.
- The purple trail uses a hard 36-point chroma key and a deterministic purple palette restoration after frame extraction; this avoids magenta-key despill darkening the magic accent.
- Runtime sheets were inspected at native size; alpha, grid order, anchors, and containment are valid.
- The mound and pitching rubber retain the MLB dimensions recorded in `field_v4/geometry-contract.json`. The foreground home plate uses an approved 1.6× visual scale with a 4px extrusion and 2px bevel. The batter boxes retain the six-foot regulation length but use an approved 63-inch player-scale width and four-inch gap around the enlarged plate.
- The batter, strike zone, and presentation contact point move left together by 12 logical pixels. Contact index 8 still maps its opaque bat tip exactly to the ball at world `(182, 474)`; scoring and timing remain unchanged.
- Stylized foul guides start at the far-edge midpoint of each batter box and terminate at `(0, 454)` and `(360, 454)`, keeping the complete 4px chalk stroke on the authored foreground dirt instead of crossing the grass.
- Batter-box and foul-line chalk uses two 2px art cells for a 4-logical-pixel stroke with antialiasing disabled.
- Alpha-mask geometry validation across all six idle frames found zero foot pixels outside the left batter box and zero foot pixels intersecting the 4px chalk; minimum visible clearance is 2.11px in the tightest frame.
- After the 12px batter shift, a second alpha-mask pass again found zero outside foot pixels in all six idle frames. Sampling 5,525 background pixels beneath each widened foul guide found zero grass-like pixels; both complete 4px strokes remain on dirt.
- The V4 mound reuses the accepted V3 dirt texture inside the exact projected 18-foot circle. The oversized V3 mound was replaced with perspective-matched grass sampled from the same background; no new generated scenery was introduced.
- Legacy side-view PNGs remain in the repository as non-runtime reference assets.
- Runtime captures: `qc/runtime-first-pitch-360x640.png`, `qc/runtime-perfect-contact-360x640.png`, and `qc/runtime-v4-long-hit-360x640.png`.
- Contact index 8 is selected at 0.12s. Its opaque bat-tip coordinate `(215, 136)` maps to world `(182, 474)`, matching the shifted code-native contact point exactly.
- The pitcher progresses through release, follow-through, recovery, and idle during ball flight; it never holds the last delivery frame.
- Ball flight uses monotonic perspective easing, rotating ball frames, late break that returns to the contact point, and a visual-only final 70ms correction on successful timing. Scoring rules remain unchanged.
- Successful contact uses a presentation-only 55ms hit stop, warm 40ms flash, judgement-scaled 0.22s shake, eight-frame impact, and three afterimages. The launched ball follows a quality-scaled 0.92s path of 320~530 logical pixels while shrinking from 30px to 3px; scoring and timing windows are unchanged.
- V3 ball and impact files remain available for visual comparison and rollback, but active runtime and preview references use V4.
- The old floating strike-zone rectangle is not rendered. Active foreground geometry consists of the enlarged beveled home plate, two perspective batter boxes, a pitching rubber, and dirt-only first-/third-base guides that fan outward from the far-edge midpoint of each box.
- The V3 swing remains available for comparison and rollback. Active runtime and preview references use the 16-frame V4 swing, retain the contact pose for the 55ms hit stop, and complete the follow-through before entering recovery art.
