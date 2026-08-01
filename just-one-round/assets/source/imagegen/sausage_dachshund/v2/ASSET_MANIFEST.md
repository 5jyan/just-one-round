# Sausage Dachshund V2 Character Assets

## Scope

This source bundle rebuilds the dachshund character and the integrated kitchen
playfield. The sausage, bite effect, and game rules remain unchanged.

## Accepted identity

- Master: `master_dachshund/master-transparent.png`
- User reference: `master_dachshund/user-reference.png`
- View: four-direction orthographic game character
- Style: clean HD 2D cel animation
- Coat: charcoal black with restrained warm-tan points
- Anatomy: one connected neck and torso, exactly two front legs and two rear
  legs, no legs on repeatable middle-body modules

## Active runtime assets

| File | Dimensions | Layout |
|---|---:|---|
| `assets/images/sausage_dachshund/dog_head_walk_atlas_v4.png` | 128×128 | 4 directions × 4 walk frames |
| `assets/images/sausage_dachshund/dog_head_eat_atlas_v4.png` | 128×128 | 4 directions × 4 bite frames |
| `assets/images/sausage_dachshund/dog_body_atlas_v4.png` | 64×96 | 3 rows × 2 connector modules |
| `assets/images/sausage_dachshund/dog_tail_walk_atlas_v4.png` | 128×128 | 4 tail directions × 4 walk frames |
| `assets/images/sausage_dachshund/kitchen_background_v3.png` | 360×640 | integrated 9×15 playfield |

Every active character frame is 32×32 and renders 1:1 in one 32×32 logical
board cell with nearest-neighbor filtering. V3 remains the accepted
high-resolution creative source. V4 downsamples each 96×96 frame independently
and applies one shared two-pixel connector cross-section to every open edge.

Directional row order is:

1. down
2. left
3. right
4. up

Body module order is:

1. left-right
2. up-down
3. left-down
4. up-right
5. right-down
6. left-up

## Generation provenance

All creative raster sources were produced with built-in Image Gen on a flat
magenta chroma-key background. The accepted master and user reference locked
identity, anatomy, palette, outline, and detail density. Separate Image Gen
calls produced:

- right, up, and down front walk modules
- right, up, and down rear walk modules
- right and down bite modules
- six raw torso connector candidates

Left-facing front and rear modules are deterministic mirrors of the accepted
right-facing modules. The up-facing bite row reuses the up-facing walk row
because the jaw is not visible from behind.

## Deterministic processing

- `generate2dsprite.py process` performs chroma cleanup, 2×2 or 3×2 frame
  extraction, shared scaling, alignment, transparent export, GIF export, and
  strict QC.
- `tools/normalize_open_edges.py` removes generated cap lines and extends only
  accepted fur pixels to modular connector edges.
- `tools/apply_connector_profile.py` applies one canonical horizontal and one
  canonical vertical generated coat cross-section to every open edge.
- The accepted left-down corner is rotated or mirrored to produce the other
  three corners. Rejected directionally incorrect generated corners are not
  used.

## QC

- No empty processed frames
- No processed output-edge clipping before intentional modular-edge extension
- Transparent atlas corners
- Stable 96×96 frame contract
- Straight and turning assembly inspected
- Four-frame straight walk preview:
  `qc/dog-straight-walk.gif`
- Final assembly preview:
  `qc/dog-kit-preview-final-v2.png`

## Integrated environment

- Master reference: `environment/user-reference.png`
- Raw Image Gen output: `environment/raw/kitchen-background-v2.png`
- Runtime background: `assets/images/sausage_dachshund/kitchen_background_v3.png`
- Runtime board rectangle: `(36, 112, 288, 480)`
- Grid: 9 columns × 15 rows, 32 logical pixels per cell
- Authored base: 180×320, displayed at 360×640 with nearest-neighbor scaling
- Exact seams and intersections are baked deterministically into the single
  background; the old `kitchen_tiles_atlas.png` is retained only as an archive
  candidate and is no longer loaded or rendered.

## Integration state

The integrated V3 environment and V4 character atlases are active. Runtime
uses all four walk and bite frames per direction. Each logical grid step
receives a short render-only interpolation of at most 0.18 seconds, with a
sprite-underlay seam guard that keeps the body visually continuous during
turns. Collision, input timing, spawning, and state transitions remain
grid-based. The smaller board changes the maximum score from 156 to 131.
