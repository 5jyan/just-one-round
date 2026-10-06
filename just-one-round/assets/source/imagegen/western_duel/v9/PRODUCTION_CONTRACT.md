# Western Duel player v9 production contract

- Approved scope: new high-detail player idle and action sprite variants only.
- Master reference: the accepted v9 neutral specimen generated from the v8 identity and the opponent detail style.
- Source cell: 540x1080 delivery cell; runtime display is 540x1080 at 1x nearest-neighbor.
- Composition: preserve the full-body source, place the player at runtime x=-254 and y=height-680, and let the viewport crop the lower-left exposure.
- Neutral master bounds: `[115, 306, 424, 1040]`; head/feet and body root stay fixed.
- Idle: 2x2, four exact repeats of the accepted master. The runtime may apply the existing subtle breath timing.
- Action: 2x3, ordered ready, grip hold, draw hold, aim, fire, recoil hold. Frames 1-3 use the accepted neutral master; frames 4-6 use the accepted compact aim/fire specimen. No per-frame bbox fitting or generative body drift.
- Action anchors: muzzle approximately `[410, 365]`, breech/hand approximately `[381, 404]`, with muzzle x `<434` and a compact lower-left to upper-right barrel ray.
- Style: fine controlled pixel clusters matching the accepted opponent detail family, warm brown/red/tan palette, crisp colored dark outline, no blurry upscale, no pure-black outline, no baked muzzle flash or projectile.
- Preserved behavior: no game rules, scoring, controls, spawn, timing, or hitbox changes are included in this asset-only package.

The first two generated 3x2 grid candidates were retained as source references but rejected for delivery because their arm and barrel became a long side-facing extension. They are not used by runtime.
