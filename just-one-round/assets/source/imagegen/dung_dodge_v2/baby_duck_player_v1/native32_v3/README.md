# Native 32 px player remaster v3

- Inputs: accepted 64×64-cell idle and run sheets before the temporary exterior-outline pass
- Source delivery: 2×2 sheets with native 32×32 px cells
- Runtime delivery: 64×64 px sheets
- Runtime display: exactly 64×64 logical px (`2×`, nearest-neighbor)
- Opaque palette: 9 locked colors plus transparency
- Outline: one native source pixel in `#2A1938`
- Alpha: hard binary alpha with no soft fringe
- Collision radius: unchanged at 16 logical px
- Animation timing: idle 280 ms, run 150 ms

The remaster preserves the accepted identity and animation poses while reducing
color noise and enforcing one deliberate pixel scale.
