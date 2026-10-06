Use case: stylized-concept
Asset type: single full-body player firing-pose sprite for a first-person Western duel game
Primary request: Create one crisp, body-only firing-pose sprite of the accepted foreground gunslinger, with the revolver aimed at the distant opponent.
Input images:
- Image 1: exact character identity, rear three-quarter view, costume, palette, proportions, and pixel-art style. Preserve it.
- Image 2: pose reference for the connected right-arm/revolver action only. Preserve the full-body character from Image 1 rather than copying any composition or cell layout.
- Image 3: apparent pixel-cluster size and detail-density reference only; do not copy its identity or costume.
Subject: Same adult cowboy from Image 1, dark broad-brim hat, side-profile cheek/beard edge, rust-orange rolled sleeve, brown/taupe vest, dark cartridge belt, right-hip holster, full trousers and both boots. Rear three-quarter view facing screen-right. Physical right hand holds one revolver in a compact trigger-squeeze aiming pose; left hand remains low and relaxed. Anatomically connected arm and weapon.
Style/medium: Crisp, deliberate pixel-art game sprite, clean hard-edged clusters with warm restrained shading comparable to the opponent close sprite at runtime. No painterly blur, soft focus, scattered noise, or tiny fabric microtexture.
Composition/framing: One isolated character only, no grid. Portrait cell ratio 1:2, intended runtime cell 360×720. Keep the whole silhouette inside central bounds x=54..306 and y=108..612. Keep both feet planted at the same baseline as the accepted master. Same camera distance and standing-equivalent size; do not zoom. The gun muzzle should be at about cell-local x=303, y=298 (84% of width and 41% of height), aimed toward screen-right. The arm is bent naturally at the elbow and compact; do not stretch the hand across the cell.
Lighting/mood: Consistent warm late-afternoon Western light.
Constraints: This is the player BODY pose only, for the frame that coincides with a separately rendered shot effect. No muzzle flash, flash glow, smoke, sparks, projectile, dust, extra hands, raised left hand, duplicated revolver, clipped/cropped anatomy, cell border, background scene, text, label, UI, or watermark. Use a perfectly flat solid #FF00FF background for deterministic cleanup.
