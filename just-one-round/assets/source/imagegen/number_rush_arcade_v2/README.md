# Number Rush Arcade V2

Built with the built-in ImageGen workflow after approval of the Number Rush
arcade-cabinet asset contract.

- `frame/`: cabinet material and construction master. It is a style reference
  because generated geometry does not match the fixed gameplay hit grid.
- `cabinet/`: connected full-machine body with marquee, side pillars, control
  deck, coin door, and base. The normalized body is used behind gameplay.
- `buttons/`: six generated button states, normalized into the runtime atlas.
- `fx/`: eight generated electric effects, normalized into the runtime atlas.
- `exit_button/`: generated two-state cabinet EXIT button preserved as
  `224×224` runtime masters and displayed at `56×56` at logical position
  `(33, 523)`.
- `pipeline-meta.json`: source bounds, runtime rectangles, frame order, and
  display contract.

The fixed 360×640 gameplay canvas, 5×5 hit grid, scoring, timing, and haptics
remain unchanged.
