# First-person player, left-side unified draw animation

Generated with ImageGen and inspected before processing. The action sheet uses the approved player master as a visual identity reference. Each pose remains one connected upper-body character; the muzzle flash is intentionally supplied by the existing separate game effect. The master prompt below is the art direction captured from an iterative reference edit, not a verbatim transcript of the original master-generation call.

## Master specimen prompt

Create a transparent-background pixel-art character master for a first-person Western duel game. An original cowboy viewed from a slightly elevated three-quarter rear-side angle, standing on screen-left and facing screen-right. Show his dark broad-brim hat, small visible right-facing profile, rust-orange shirt, fitted tan/brown coat, belt, and revolver in the right-hip holster. Show one connected upper-body silhouette from hat to waist/holster, with the physical right hand resting near the holster. Keep the torso compact on the left, leaving room on the right for the arm and revolver to extend into an aim. Serious cinematic 16-bit Western pixel art, stepped dark outlines, warm ochre highlights, transparent background, no scenery, text, effects, or extra characters.

## Final six-frame sheet prompt

Revise the attached six-frame cowboy action sheet for a FIRST-PERSON foreground game sprite. Preserve the same serious cinematic brown/ochre pixel art, same cowboy identity, hat/head/profile facing screen-right, same fitted coat/orange sleeve, same right hand and revolver. Retain a transparent background and exact 3-column by 2-row arrangement with six equally sized cells, no gutters or labels. Preserve the six action poses and the previous corrections (NO flash, no smoke, no sparks, no projectiles).

IMPORTANT CROPPING AND COMPOSITION: This game shows only the player's right-side upper body. In every cell show from the hat/head down through shoulder, chest, right arm, belt, and right-hip holster. Crop the artwork just below the bottom of the holster at the upper hip. Remove all pants, legs, knees, crotch, feet, and lower body; do not show any thigh below the holster. The full hat, face profile, shoulder, hand, full revolver barrel, belt and holster must all fit with transparent margin and must not be cut off. Keep body mass confined mainly to the left half of each cell; the bent/raised right arm and revolver may extend to the right, but remain inside its own cell. Use one consistent head size, shoulder line, baseline, and crop across all six poses.

The whole shoulder/torso/right arm/hand/revolver is one continuous body silhouette, never a separate floating hand. Keep left arm quiet and mostly hidden. Action order: top row ready, grip revolver, draw revolver; bottom row raise and aim horizontally right, tiny body-connected firing recoil (no visible flash), then subtle after-shot recoil with barrel angled slightly up-right. No scene, floor, shadow, other character, UI, or additional props. Keep each cell a complete single pose, isolated from neighboring cells. No effects at all.

## Provenance

- Selected master raw image: `player-left-upperbody-master-raw.png` (1024×1536 RGBA).
- Selected six-pose raw sheet: `player-left-upperbody-action-raw.png` (1160×1355 RGBA; 3×2 grid, one-pixel uneven divisions handled by proportional boundaries in the processor).
- Runtime contract: 6 frames, 3 columns × 2 rows; source cell 180×280, nearest-neighbor display at 360×560.
- Applied sprite-space perspective fit after frame extraction: `x × 0.75`, `y × 0.8`, offset `(30,4)` source pixels. This narrows the profile while preserving the head and holster and brings the fifth frame's muzzle to `(160.5,75)` in the normalized cell.
- The player origin `(-60, height/2-160)` maps that muzzle to `(261, height/2-10)`. The opponent is centered at x=261, matching the aimed shot without changing any timing or scoring behavior.
- Final processor manifest: `processed_180x280/pipeline-meta.json`; runtime atlas: `assets/images/western_duel/first_person/player_left_upperbody_draw_v4/sheet-transparent.png`.
