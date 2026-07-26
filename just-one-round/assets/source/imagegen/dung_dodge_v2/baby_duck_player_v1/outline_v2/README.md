# Player visibility outline v2

- Method: deterministic one-source-pixel exterior alpha dilation
- Outline color: `#2A1938`
- Input and output sheet size: 128×128 px
- Frame layout: 2×2 with 64×64 px cells
- Runtime display size: 64×64 logical px
- Runtime collision radius: unchanged at 16 logical px
- Internal colors, facial features, poses, anchors, and animation timing are unchanged

The added pixels sit behind the accepted source art. Inputs are preserved in
`input/` and runtime-ready outputs are preserved in `output/`.
