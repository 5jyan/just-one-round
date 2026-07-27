#!/usr/bin/env python3
"""Apply the approved `딱` brand icon to iOS and Android launchers."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (
    ROOT
    / "assets/source/brand/ttak-logo-20260727"
    / "ttak-01-current-brand.png"
)

IOS_ICON_DIR = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
IOS_SIZES = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

ANDROID_SIZES = {
    "mipmap-mdpi/ic_launcher.png": 48,
    "mipmap-hdpi/ic_launcher.png": 72,
    "mipmap-xhdpi/ic_launcher.png": 96,
    "mipmap-xxhdpi/ic_launcher.png": 144,
    "mipmap-xxxhdpi/ic_launcher.png": 192,
}


def save_resized(source: Image.Image, output: Path, size: int) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    source.resize(
        (size, size),
        resample=Image.Resampling.LANCZOS,
    ).convert("RGB").save(output, optimize=True)


def main() -> None:
    if not SOURCE.is_file():
        raise SystemExit(f"Missing approved icon source: {SOURCE}")

    with Image.open(SOURCE) as icon:
        source = icon.convert("RGB")
        for filename, size in IOS_SIZES.items():
            save_resized(source, IOS_ICON_DIR / filename, size)
        for relative_path, size in ANDROID_SIZES.items():
            save_resized(
                source,
                ROOT / "android/app/src/main/res" / relative_path,
                size,
            )


if __name__ == "__main__":
    main()
