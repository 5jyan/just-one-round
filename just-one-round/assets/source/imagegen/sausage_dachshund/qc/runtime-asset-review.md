# Runtime asset QC — 2026-07-29

- [x] Every sprite sheet uses exact 32 × 32 cells.
- [x] Head and tail atlases contain four directions and two frames per direction.
- [x] Dog has exactly two front legs and two rear legs; no middle-body legs.
- [x] Head, straight body, corners, and tail share a broad chestnut connector.
- [x] Body atlas contains horizontal, vertical, and all four elbow orientations.
- [x] Straight head-to-tail assembly has no transparent gaps or broken neck connection.
- [x] Closed loop assembly has no transparent gaps at straight/corner boundaries.
- [x] Non-connector anatomy remains inside its own cell.
- [x] Sausage reads as grilled meat rather than wrapped candy at native size.
- [x] Background center is empty and low-contrast for runtime grid/sprite layers.
- [x] Six floor variants remain subordinate to the player and pickup palette.
- [x] Runtime PNG dimensions and alpha modes match the asset manifest.

Known implementation note: connector pixels intentionally meet their own cell edge so
adjacent modules tile continuously. Runtime must place modules on exact integer 32 px
coordinates with nearest-neighbor filtering and no per-module fractional scale.
