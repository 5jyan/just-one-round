# Temple Run asset closeout QC

Checked from the saved ImageGen sources and deterministic processor outputs on 2026-10-16.

## Runtime contract

| Asset group | Runtime files | Dimensions | Result |
| --- | --- | --- | --- |
| Environment | `jungle_background.png` | 720×1280 RGB | PASS |
| Runner | `runner_run.png` | 512×192 RGBA sheet (4×128×192) | PASS |
| Runner actions | `runner_jump.png`, `runner_slide.png` | 128×192 RGBA each | PASS |
| Obstacles | `obstacle_hurdle.png`, `obstacle_arch.png`, `obstacle_rubble.png` | 256×256 RGBA each | PASS |
| Collectibles | `coin.png`, `magnet.png`, `shield.png`, `boost.png` | 128×128 RGBA each | PASS |
| Guardian | `guardian.png` | 256×256 RGBA | PASS |
| Path | `temple_path.png` | 512×512 RGB | PASS |

## Visual and alpha checks

- The final background is the environment-only plate: its center is a clear misty valley with the distant temple gate and no baked road, runner, or guardian.
- The final obstacle set uses the dedicated v2 outputs. Hurdle is a solid beam, arch has low slide clearance, and rubble has safe transparent margins.
- All transparent runtime sprites have no alpha at the outer cell edge at threshold 24. No opaque black or magenta rectangle remains in jump, slide, or obstacle outputs.
- Runner frames are four distinct phases in order: left contact, left passing, right contact, right passing. Per-frame alpha boxes are `[24,14,104,184]`, `[24,14,104,184]`, `[22,14,106,184]`, and `[22,14,106,184]`; all share baseline `y=184` and center `x=64`.
- Jump and slide also share baseline `y=184`; their vertical translations are `17` and `23` pixels respectively. Runtime can use the same feet anchor with eight transparent pixels below the visible art.
- `temple_path.png` has exact opposite-edge equality (`max LR diff=0`, `max TB diff=0`) for repeat use.
- `processed/runner_run.gif` is 128×192, four frames at 110 ms, with transparent corners. Contact sheet, green-background runner strip, transparent preview, and 3×3 path preview were visually inspected.

## Validation

- `python3 -m py_compile assets/source/imagegen/temple_run/process_assets.py` — PASS
- `python3 -m json.tool` on `asset-contract.json`, `pipeline-meta.json`, and `qc/qc-manifest.json` — PASS
- `flutter test test/features/games/temple_run` — 29 passed, 1 failed in the existing runtime test `the same swipe path works on a tall portrait viewport` (`temple_run_game_test.dart:248`, expected `2`, actual `1`). This is outside the asset-owned files and needs the runtime/integration owner to resolve.
- `flutter analyze lib/features/games/temple_run` — BLOCKED by the local Dart analysis server returning `FormatException: Unexpected end of input` while parsing its LSP JSON capabilities response; this occurred twice and is an environment/tooling failure rather than an asset validation failure.

Detailed machine-readable values are in `qc-manifest.json`; visual previews are in `temple_run_assets_contact.png`, `runner_run_on_green_8x.png`, `transparent_assets_on_green.png`, and `path_tile_3x3.png`.
