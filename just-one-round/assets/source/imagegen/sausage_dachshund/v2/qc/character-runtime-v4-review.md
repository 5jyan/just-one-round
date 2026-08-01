# Dachshund V4 Runtime Review

## Active contract

- Creative source: V3 96×96-frame dachshund atlases
- Runtime head walk/eat and tail: 128×128, 4 directions × 4 frames
- Runtime body: 64×96, 3 rows × 2 connector modules
- Runtime frame and display cell: 32×32 at 1:1 scale
- Filtering: nearest-neighbor
- Board: 9×15 at `(36, 112, 288, 480)`

## Deterministic adaptation

- Processor: `process_character_runtime_v4.py`
- Metadata: `character-runtime-v4.json`
- Every source cell is cropped and resized independently, preventing adjacent
  atlas cells from bleeding into one another.
- Every open body, neck, and rump edge receives the same two-pixel coat
  cross-section.
- A coat-colored line with a darker outline is rendered beneath the modular
  sprites during interpolation. It is hidden at rest and only fills temporary
  gaps while consecutive modules travel around a turn.

## Visual review

- The dog is 14.3% larger than V3 in the 360-wide gameplay viewport.
- The board uses one fewer column and row, increasing every tile from 28 to 32
  logical pixels.
- Head, straight body, corner, and tail remain within their own grid cells at
  rest.
- Straight and turning body paths remain visually connected in the captured
  360×640 runtime state.
- Four legs remain limited to the head and tail modules.

## Runtime evidence

- Widget runtime capture: `runtime-v4-widget.png`
- iPhone 17 Pro turn capture: `ios-simulator-v4-turn.png`
- Focused rule, asset, and runtime tests pass.
- The installed iOS simulator build shows a continuous head-to-corner-to-tail
  path while moving upward from the opening straight line.
