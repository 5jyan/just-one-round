# 홈런왕 강타자 v3 QC

The regular batter v3/v4 sheets were the authoritative anatomy and pose
references. Built-in Image Gen changed only the build and uniform: about 30%
wider shoulders and legs, a 35% wider barrel torso, thick arms, and a blank
midnight-navy/red jersey. Every generated action was inspected before the next
one was produced. A rejected whiff draft with isolated shoulder circles was not
used; the selected whiff was regenerated from the regular sheet and accepted
swing identity.

| action | selected output | grid | runtime |
|---|---|---:|---|
| idle | `exec-39ad4866-77fe-4a09-bc63-ac7703669c95.png` | 2x3 | `batter_slugger_idle_v3.png` |
| swing | `exec-57f29d95-968d-455f-8071-62a8ac561479.png` | 4x4 | `batter_slugger_swing_v3.png` |
| whiff | `exec-3113ad6f-4090-4223-89d2-9f4c7deb69e8.png` | 4x3 | `batter_slugger_whiff_v3.png` |
| result | `exec-dc454e47-dc0e-4da0-a89a-eeca86be012a.png` | 4x2 | `batter_slugger_result_v3.png` |

Processor contract: 240px cells, 0.90 shared fit, feet alignment, largest
component, 4px trim, 3px edge cleanup, strict QC, and reviewed source-edge
allowance. Deterministic finishing moves each visible foot baseline to y=226
and clears strong magenta fringe. Final checks: all 42 frames populated; no
output-edge touch or paste clamp; every baseline is 226; no strong magenta
fringe; swing contact frame 8 remains opaque at cell-local (215,136).

Visual anatomy review covered every frame from both shoulders through sleeves,
elbows, wrists, separate gloves, and the bat handle. The jersey has no number,
letter, logo, badge, or yellow mark. Original v1/v2 assets remain preserved.
