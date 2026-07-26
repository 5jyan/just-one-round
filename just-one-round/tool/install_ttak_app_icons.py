#!/usr/bin/env python3
"""Install the approved Ttak logo into the existing iOS and Android icon sets."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = PROJECT_ROOT / "assets/source/brand/ttak-logo-20260727"
MASTER_PATH = SOURCE_DIR / "ttak-01-current-brand.png"
IOS_DIR = PROJECT_ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
ANDROID_RES_DIR = PROJECT_ROOT / "android/app/src/main/res"
FONT_PATH = PROJECT_ROOT / "assets/fonts/Galmuri11-Bold.ttf"

ANDROID_SIZES = {
    "mipmap-mdpi/ic_launcher.png": 48,
    "mipmap-hdpi/ic_launcher.png": 72,
    "mipmap-xhdpi/ic_launcher.png": 96,
    "mipmap-xxhdpi/ic_launcher.png": 144,
    "mipmap-xxxhdpi/ic_launcher.png": 192,
}


def expected_ios_sizes() -> dict[str, int]:
    contents = json.loads((IOS_DIR / "Contents.json").read_text())
    targets: dict[str, int] = {}
    for item in contents["images"]:
        filename = item.get("filename")
        if not filename:
            continue
        logical_size = float(item["size"].split("x")[0])
        scale = int(item["scale"].removesuffix("x"))
        pixel_size = round(logical_size * scale)
        previous = targets.setdefault(filename, pixel_size)
        if previous != pixel_size:
            raise ValueError(
                f"Conflicting dimensions for {filename}: "
                f"{previous} and {pixel_size}"
            )
    return targets


def install_icon(master: Image.Image, path: Path, size: int) -> None:
    if size == master.width:
        output = master.copy()
    else:
        output = master.resize((size, size), Image.Resampling.LANCZOS)
    if output.mode != "RGB":
        output = output.convert("RGB")
    output.save(path, format="PNG", optimize=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


def validate(path: Path, expected_size: int) -> dict[str, object]:
    with Image.open(path) as image:
        if image.size != (expected_size, expected_size):
            raise ValueError(
                f"{path} is {image.size}; expected "
                f"{expected_size}×{expected_size}"
            )
        if image.mode != "RGB":
            raise ValueError(f"{path} must be opaque RGB; got {image.mode}")
        corner = image.getpixel((0, 0))
        for point in (
            (0, 0),
            (expected_size - 1, 0),
            (0, expected_size - 1),
            (expected_size - 1, expected_size - 1),
        ):
            if image.getpixel(point) != corner:
                raise ValueError(f"Unexpected corner color at {point}: {path}")
        if corner != (16, 24, 39):
            raise ValueError(f"Unexpected background color in {path}: {corner}")
    return {
        "path": str(path.relative_to(PROJECT_ROOT)),
        "size": [expected_size, expected_size],
        "mode": "RGB",
        "sha256": sha256(path),
    }


def make_qc_board(
    master: Image.Image,
    all_sizes: list[int],
) -> None:
    unique_sizes = sorted(set(all_sizes), reverse=True)
    card_width = 260
    card_height = 300
    columns = 5
    rows = (len(unique_sizes) + columns - 1) // columns
    board = Image.new(
        "RGB",
        (columns * card_width, rows * card_height),
        "#E8E4DA",
    )
    draw = ImageDraw.Draw(board)
    label_font = ImageFont.truetype(FONT_PATH, 24)

    for index, size in enumerate(unique_sizes):
        column = index % columns
        row = index // columns
        cell_x = column * card_width
        cell_y = row * card_height
        icon = master.resize((size, size), Image.Resampling.LANCZOS)
        preview_size = min(size, 192)
        if size != preview_size:
            icon = icon.resize(
                (preview_size, preview_size),
                Image.Resampling.LANCZOS,
            )
        preview = icon.resize(
            (preview_size * 4, preview_size * 4),
            Image.Resampling.NEAREST,
        )
        preview.thumbnail((220, 220), Image.Resampling.NEAREST)
        x = cell_x + (card_width - preview.width) // 2
        y = cell_y + 18 + (220 - preview.height) // 2
        board.paste(preview, (x, y))
        label = f"{size} px"
        label_box = draw.textbbox((0, 0), label, font=label_font)
        draw.text(
            (
                cell_x + (card_width - (label_box[2] - label_box[0])) / 2,
                cell_y + 252,
            ),
            label,
            font=label_font,
            fill="#101827",
        )

    board.save(SOURCE_DIR / "qc-installed-icon-sizes.png", optimize=True)


def main() -> None:
    with Image.open(MASTER_PATH) as source:
        master = source.convert("RGB")
    if master.size != (1024, 1024):
        raise ValueError(f"Master must be 1024×1024: {MASTER_PATH}")

    ios_targets = expected_ios_sizes()
    records = []
    for filename, size in ios_targets.items():
        path = IOS_DIR / filename
        install_icon(master, path, size)
        records.append(validate(path, size))

    for relative_path, size in ANDROID_SIZES.items():
        path = ANDROID_RES_DIR / relative_path
        install_icon(master, path, size)
        records.append(validate(path, size))

    make_qc_board(
        master,
        list(ios_targets.values()) + list(ANDROID_SIZES.values()),
    )

    report = {
        "selected_variant": "01-current-brand",
        "master": str(MASTER_PATH.relative_to(PROJECT_ROOT)),
        "master_sha256": sha256(MASTER_PATH),
        "resampling": "Pillow LANCZOS from the approved 1024×1024 master",
        "background": "#101827",
        "fill": "#FFF4D6",
        "shadow": "#B87714",
        "ios_file_count": len(ios_targets),
        "android_file_count": len(ANDROID_SIZES),
        "outputs": records,
    }
    (SOURCE_DIR / "integration-qc.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
