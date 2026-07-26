#!/usr/bin/env python3
"""Fail when a runtime pixel-art asset violates the shared 3px art grid."""

from pathlib import Path
import sys

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets" / "images"
EXPECTED = {
    "dinosaur_side_left_1_uniform.png": ((24, 24), (72, 72)),
    "dinosaur_side_left_2_uniform.png": ((24, 24), (72, 72)),
    "pixel_cloud_uniform.png": ((57, 22), (171, 66)),
    "pixel_cloud_small_uniform.png": ((46, 17), (138, 51)),
    "pixel_ground_uniform.png": ((120, 29), (360, 87)),
}


def boundary_dark_pixels(image: Image.Image) -> int:
    rgba = image.convert("RGBA")
    width, height = rgba.size
    count = 0
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = rgba.getpixel((x, y))
            if alpha == 0:
                continue
            outside = any(
                nx < 0
                or ny < 0
                or nx >= width
                or ny >= height
                or rgba.getpixel((nx, ny))[3] == 0
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))
            )
            if outside and max(red, green, blue) < 80:
                count += 1
    return count


def main() -> int:
    failures = []
    print("asset | source | render | scale | alpha | dark exterior")
    print("-" * 78)
    for name, (expected_source, rendered) in EXPECTED.items():
        image = Image.open(ASSETS / name).convert("RGBA")
        source = image.size
        scale = (rendered[0] / source[0], rendered[1] / source[1])
        alphas = {pixel[3] for pixel in image.getdata()}
        dark = boundary_dark_pixels(image)
        alpha_status = "binary" if alphas <= {0, 255} else "partial"
        print(
            f"{name} | {source[0]}x{source[1]} | {rendered[0]}x{rendered[1]} "
            f"| {scale[0]:.0f}x/{scale[1]:.0f}x | {alpha_status} | {dark}"
        )
        if source != expected_source:
            failures.append(f"{name}: source size {source} != {expected_source}")
        if scale != (3.0, 3.0):
            failures.append(f"{name}: render scale {scale} != (3, 3)")
        if alpha_status != "binary":
            failures.append(f"{name}: antialiased alpha values found")
        if dark:
            failures.append(f"{name}: {dark} dark exterior pixels found")

    game_source = (ROOT / "lib/features/games/star_dodge/star_dodge_game.dart").read_text()
    obstacle = game_source.split("void _renderObstacle", 1)[1].split("class _GroundComponent", 1)[0]
    if "AppColors.backgroundDeep" in obstacle:
        failures.append("poop renderer: dark exterior color is still referenced")
    if "FilterQuality.none" not in game_source:
        failures.append("runtime renderer: nearest-neighbor filtering is not enabled")
    if "const _artPixel = 3.0" not in game_source:
        failures.append("runtime renderer: shared 3px art unit is missing")

    if failures:
        print("\nFAIL")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print("\nPASS: every runtime bitmap is a binary-alpha 1-cell source rendered at 3x;")
    print("      no near-black exterior boundary pixels were detected.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
