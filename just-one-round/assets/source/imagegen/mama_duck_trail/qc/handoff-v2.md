# Mama Duck Trail Asset Quality V2

- Canonical viewport: `360x640`
- Canonical art pixel: `2x2` logical pixels
- Runtime filtering: nearest neighbor, antialiasing disabled
- Runtime paths: `assets/images/mama_duck_trail/`
- Generated sources and prompts: `assets/source/imagegen/mama_duck_trail/`
- Deterministic processor: `tool/process_mama_duck_trail_assets_v2.py`

## Character families

- Baby duck idle: `36x36`, displayed `72x72`
- Baby duck walk: `2x3`, `36x36` cells, displayed `72x72`
- Baby duck cheer: `2x3`, `36x36` cells, displayed `72x72`
- Cheer timing: `0.125s` per frame, two loops, `1.5s` total
- Mother idle/hug: `36x36`, displayed `72x72`
- Mother walk: `2x3`, `36x36` cells, displayed `72x72`
- Wolf idle/failure: `48x48` cells, displayed `96x96`

Baby and mother walk/cheer raw art was generated with built-in ImageGen on a
solid `#FF00FF` background, processed with `generate2dsprite`, then hard-alpha
cleaned and palette-quantized. The wolf retained its accepted silhouette and
was palette-cleaned.

## Environment and UI families

- Marsh atlas: `3x3`, `36x36` cells, displayed `72x72`
- Footprints: `3x4`, `24x24` cells, displayed `48x48`
- Life face: `16x16`, displayed `32x32`
- Feather poof: `2x2`, `32x32` cells, displayed `64x64`

The terrain was generated with built-in ImageGen and deterministically cropped,
edge-normalized, quantized, and assembled. Footprints were reprocessed from
their preserved high-resolution raw source at the new base cell.

## QC

- Strict sprite processor QC passed for baby walk, baby cheer, mother walk,
  mother hug, and footprints.
- Transparent edges are binary alpha and runtime assets use restrained
  palettes.
- Runtime composite inspected at `360x640`:
  `/tmp/mama_duck_trail_runtime_v2.png`
- Contact sheet:
  `assets/source/imagegen/mama_duck_trail/qc/asset_quality_v2_contact_sheet.png`
- Targeted static analysis: no issues.
- Targeted gameplay and asset tests: passed.
- Full Flutter suite: `154` tests passed.

`flutter analyze` itself encountered an analysis-server JSON transport crash
caused by the workspace's percent-encoded Korean path. Targeted `dart analyze`
completed successfully with no issues.
