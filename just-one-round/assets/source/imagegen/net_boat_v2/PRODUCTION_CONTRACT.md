# Net Boat V2 Production Contract

- Approved direction: higher-detail project-native ugly-cute pixel art with a consistent effective 2-logical-pixel cluster grid.
- Gameplay safe core: `0,0–360,640`; collision playfield: `24,112–336,616`.
- Authored background: `360×960`, rendered 1:1 at world position `0,-160`, with 160 px visual overscan above and below the safe core.
- Boat navigation: `384×256`, 64 px cells, rows N/E/S/W, columns four sail frames then two clockwise-turn frames.
- Boat result: `256×128`, 64 px cells, success row then failure row.
- Fish: `128×96`, 32 px cells, three species rows and four swim frames.
- Shark: `192×96`, 48 px cells, swim row then warning-fin row.
- Reefs: `192×96`, 48 px cells, eight distinct modules.
- Net FX: `256×128`, 64 px cells, capture row then cut row.
- Runtime filtering: nearest-neighbor only; visual anchors are cell center; collision radii and game rules remain unchanged.
- Source-edge exceptions in the boat and FX raw generations were visually reviewed: the complete silhouettes are intact, processed output has zero edge contact and zero paste clamping.
- Raw built-in Image Gen outputs are preserved under `raw/`; processor metadata and extracted frames are preserved under `processed/`.
