# 홈런왕 7구 강타자 v2

Built-in Image Gen edited the v1 action sheets with the accepted v2 idle as the
identity reference. The prompts locked each original action sequence and grid,
and requested broader shoulders and heavier legs, a midnight-navy jersey, red
sleeves, and a gold number 4 while retaining the red helmet, cream pants, navy
cleats, white gloves, and gold bat. Original generated files are preserved as
`<action>/raw-alpha.png`; `raw.png` is the deterministic magenta composite.

| Action | Grid | Generated raw | Runtime |
|---|---:|---|---|
| idle | 2×3 | `exec-6d27c0e6-c613-4f77-ab7d-6ebc917901e2.png` | `batter_slugger_idle_v2.png` |
| swing | 4×4 | `exec-297945a5-0e5f-4ac0-a5e9-4ac350a5d381.png` | `batter_slugger_swing_v2.png` |
| whiff | 4×3 | `exec-9e23ef25-21a7-44f3-9e23-9b7ae86c97f2.png` | `batter_slugger_whiff_v2.png` |
| result | 4×2 | `exec-fcd129ff-6b63-4d00-ad3d-c22fae4c4c57.png` | `batter_slugger_result_v2.png` |

Processing: `generate2dsprite.py process` with 240px cells, 0.88 fit,
feet alignment, shared scale, largest component, four-pixel trim, three-pixel
edge cleanup, strict QC and reviewed raw-edge allowance. The generated source
for the swing/result/whiff used transparency instead of requested solid magenta;
the retained alpha was deterministically composited over #FF00FF. The final
processed sheets have a 226px visible foot baseline, no output-edge touches,
no missing frames, and no visible magenta-fringe pixels. The finite cleanup
pass is in `tool/process_ten_pitch_slugger_v2.py`. Original v1 sheets remain.

The actual iPhone 16 Plus Simulator gameplay composite was inspected at the
7th-pitch entrance: the large red title, radial burst, heavier uniformed batter,
field, HUD, and no magical ball trail are visible together.
