# Ramen Timer UI Refresh v2

Approved on 2026-08-08 as a visual-only refresh.

- Gameplay-safe core: `[0, 0, 360, 640]`
- Authored world: `[0, -80, 360, 800]`
- Camera center: `[180, 320]`
- Foreground source pixel: `1px -> 2 logical pixels`
- Raccoon frame: `48x48`, displayed at `96x96`
- Result frame: `64x64`, displayed at `128x128`
- Pixel filtering: nearest-neighbor
- Preserved behavior: pointer-down input, 3.0s clock visibility, 3.2s unlock,
  10/20/30 second targets, 250ms input lock, 45s timeout, score encoding,
  interruption policy, and 8s detailed-result hold.

The original source folders remain untouched. Runtime atlases are assembled by
`../../assemble_runtime_assets.py` from the accepted v2 processed frames.

