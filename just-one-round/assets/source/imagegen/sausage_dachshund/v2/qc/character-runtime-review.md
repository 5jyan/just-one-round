# Dachshund V3 Runtime Review

## Active contract

- Creative master: `master_dachshund/master-transparent.png`
- Runtime head walk/eat and tail: 384×384, 4 directions × 4 frames
- Runtime body: 192×288, 3 rows × 2 connector modules
- Source frame: 96×96
- Display cell: 28×28 at whole logical coordinates
- Direction order: down, left, right, up
- Dog filtering: medium
- Map filtering: nearest-neighbor
- Movement transition: render-only ease-out, maximum 0.18 seconds

## Deterministic adaptation

- Processor: `process_character_runtime.py`
- Metadata: `character-runtime-v3.json`
- Removed all detected magenta, green, and blue chroma fringe.
- Preserved transparent alpha, silhouette, anatomy, frame layout, and connector
  geometry.
- Lifted neutral charcoal midtones only. Near-black outline and warm-tan
  markings remain intact.

## Visual review

- Exactly two front legs remain on the head module and two rear legs on the
  tail module. Middle modules have no legs.
- Head, neck, straight body, corners, rump, and tail remain connected in
  straight and 90-degree paths.
- Left/right/up/down heads face the logical movement direction.
- The torso remains mostly straight. Corners use one-cell bends without an
  S-curve or intestine-like multi-cell curve.
- No character pixels are visible outside the occupied 28×28 module cells at
  rest.
- Tan face and paws, raised charcoal coat, and black outline remain readable on
  the teal kitchen floor.
- No chroma halo, clipped face, detached ear, extra leg, clothing, or
  candy-like body artifact was found.
- At long lengths the torso is intentionally stylized and stretched by the
  game rule; it should not be interpreted as anatomically rigid realism.

## Runtime evidence

- Initial straight state: `ios-simulator-v3-initial.png`
- Turning state: `ios-simulator-v3-turn.png`
- Final simulator state after interpolation integration:
  `ios-simulator-v3-final.png`
- iPhone 17 Pro simulator debug build and launch succeeded.
- Rule, asset, runtime, visual, registry, presentation, and shared game-screen
  tests: 50 passed.
- Movement progress test confirms the visual position advances between grid
  ticks while logical state remains deterministic.
- Static analysis could not complete because the local Dart analysis server
  repeatedly exited while parsing a truncated LSP JSON message. The changed
  Dart sources compiled in all tests and in the iOS simulator debug build.

## Behavior preservation

- Board remains 10×16 at `(40, 128, 280, 448)`.
- Controls, scoring, duration, spawn seed/reachability, collision order,
  haptics, termination, and result submission are unchanged.
