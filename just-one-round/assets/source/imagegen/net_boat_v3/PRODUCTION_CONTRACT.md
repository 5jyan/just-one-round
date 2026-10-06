# Net Boat V3 Creature Production Contract

- Approved on 2026-08-17: piranha `24×24`, marlin `48×32`, shark `64×48`, whale `144×96`.
- Each creature was generated separately as a four-frame `2×2` swim grid on solid `#FF00FF` and processed with the bundled sprite QC pipeline.
- Runtime atlases are deterministic four-frame horizontal strips with center anchors and nearest-neighbor rendering.
- Existing V2 sea, boat, reef, net, and capture assets remain unchanged.
- Master style references: V2 boat/shark, then the accepted V3 piranha and marlin specimens.
- Apparent foreground art pixel remains approximately `2×2` logical pixels on a 360-wide viewport.
- The whale is an approved game-specific size exception: it occupies `144×96`, about 46% of the 312px-wide playfield.
- Raw images, exact prompts, processed sheets, GIFs, frames, and QC metadata are preserved per creature folder.
- The rejected dark-background marlin and shark generations were not copied into the project.
