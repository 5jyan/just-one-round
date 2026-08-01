# Integrated Kitchen Runtime Review

- Runtime background: `assets/images/sausage_dachshund/kitchen_background_v2.png`
- Runtime size: 360×640 RGB
- Creative base: built-in Image Gen using `environment/user-reference.png`
- Pixel contract: 180×320 authored base, nearest-neighbor 2× display
- Board rectangle: x=40, y=128, width=280, height=448
- Grid: 10 columns × 16 rows, 28 logical pixels per cell
- Layering: one integrated background; no repeated runtime tile layer
- Archived candidates retained: `kitchen_background.png`,
  `kitchen_tiles_atlas.png`

## Visual inspection

- The teal ceramic floor reads as part of the surrounding kitchen.
- Sink, refrigerator, counters, plants, appliances, and rug remain outside the
  collision-bearing board.
- Refrigerator lighting is confined to the top-right board edge and does not
  obscure the character or sausage.
- The board has exact straight seams and intersections without perspective
  drift.
- Empty source contains no dog, sausage, HUD, text, logo, or watermark.
- Actual iPhone 17 Pro simulator composite:
  `ios-simulator-gameplay.png`

## Verification

- Targeted asset and game tests: 5 passed.
- iOS simulator debug build and runtime launch: passed.
- Gameplay composite inspected: sprites occupy the same 28×28 cells as the
  baked grid; no separate floor layer or furniture overlap is visible.
- `flutter analyze` could not complete because the local Dart analysis server
  exited while parsing a truncated LSP message. The same changed Dart sources
  compiled in widget tests and in the iOS simulator debug build.
