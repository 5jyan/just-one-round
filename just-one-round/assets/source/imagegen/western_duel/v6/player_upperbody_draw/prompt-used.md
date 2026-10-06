# Western Duel Player Upper-body Atlas v6

Source image: `raw-sheet-v2-with-background.png`, generated with the built-in ImageGen tool on 2026-09-28.

References: the v5 high-detail player identity/action atlas and the v4 approved first-person close-up composition. The v4 asset remains unchanged as the framing reference.

## Final generation prompt

Create a coherent 3-column by 2-row sheet of six upper-body draw/shoot poses, with equal square cells. Keep the same right-facing cowboy identity: brown broad-brim hat, profile face, rust-red sleeve, tan-brown vest, belt, right hand, revolver, and right-hip holster. High-detail crisp 16-bit pixel art, bold dark pixel outlines, warm Western colors. Each cell has the same apparent camera distance and scale.

Match the old left-side close-up. Show the complete cowboy upper body from hat through the entire right-hip holster. Do not include trousers or legs. Keep every part of every pose inside a central safe region with clear margins; do not crop the holster, hand, or gun barrel. Top row poses: ready with hand near the holster, grip, draw. Bottom row: aim horizontally right, fire horizontally right, subtle after-shot recoil angled slightly up-right. Keep each pose distinct and aligned.

Use a flat pure-magenta background for deterministic foreground extraction. No scene, shadows, muzzle flash, smoke, sparks, text, dividers, or watermark.

## Processing and runtime contract

- macOS Vision `VNGenerateForegroundInstanceMaskRequest` isolated exactly six instances from the generated sheet; masks and per-pose cutouts are retained beside this file.
- `tool/assemble_western_duel_v6_atlas.py` validates source alpha bounds, maps the six frames into 560×560 cells, and writes the transparent 3×2 runtime atlas.
- Runtime draws each 560×560 source cell into 360×560 logical pixels at `(-60, height/2-160)`, matching the v4 close-up placement.
- Frame 5 muzzle anchor is `(499,150)` in the source cell and approximately `(261, height/2-10)` on screen.
- Lower-body content is absent from the generated character silhouettes. Hat, hand, revolver barrel, belt, and complete holster are retained.
