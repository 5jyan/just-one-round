import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw" / "player-game-over-chroma.png"
PROCESSED = ROOT / "processed"
QC = ROOT / "qc"
RUNTIME = (
    ROOT.parents[3]
    / "images"
    / "gravity_switch_v2"
    / "player_game_over.png"
)

PALETTE = (
    (52, 28, 57, 255),
    (77, 46, 79, 255),
    (112, 145, 48, 255),
    (177, 202, 54, 255),
    (207, 224, 82, 255),
    (255, 239, 157, 255),
    (244, 85, 43, 255),
    (177, 54, 38, 255),
)


def is_magenta(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, _ = pixel
    return (
        red > 150
        and blue > 150
        and green < 110
        and abs(red - blue) < 110
        and min(red, blue) > green * 2
    )


def nearest_palette(pixel: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    red, green, blue, alpha = pixel
    if alpha < 128:
        return (0, 0, 0, 0)
    return min(
        PALETTE,
        key=lambda color: (
            (red - color[0]) ** 2
            + (green - color[1]) ** 2
            + (blue - color[2]) ** 2
        ),
    )


def main() -> None:
    PROCESSED.mkdir(parents=True, exist_ok=True)
    QC.mkdir(parents=True, exist_ok=True)
    RUNTIME.parent.mkdir(parents=True, exist_ok=True)

    raw = Image.open(RAW).convert("RGBA")
    keyed = Image.new("RGBA", raw.size)
    keyed.putdata(
        [
            (0, 0, 0, 0) if is_magenta(pixel) else pixel
            for pixel in raw.getdata()
        ]
    )
    alpha_box = keyed.getchannel("A").getbbox()
    if alpha_box is None:
        raise RuntimeError("The generated source contains no visible subject.")

    subject = keyed.crop(alpha_box)
    target_width = 38
    target_height = max(1, round(subject.height * target_width / subject.width))
    if target_height > 28:
        target_height = 28
        target_width = max(1, round(subject.width * target_height / subject.height))
    subject = subject.resize(
        (target_width, target_height),
        Image.Resampling.NEAREST,
    )
    subject = Image.new("RGBA", subject.size)
    subject.putdata(
        [
            nearest_palette(pixel)
            for pixel in keyed.crop(alpha_box)
            .resize((target_width, target_height), Image.Resampling.NEAREST)
            .getdata()
        ]
    )

    runtime = Image.new("RGBA", (48, 48))
    paste_x = (48 - target_width) // 2
    paste_y = (48 - target_height) // 2
    runtime.alpha_composite(subject, (paste_x, paste_y))
    runtime.save(RUNTIME)
    runtime.save(PROCESSED / "player-game-over.png")
    runtime.resize((384, 384), Image.Resampling.NEAREST).save(
        QC / "player-game-over-8x.png"
    )

    alpha = runtime.getchannel("A")
    bounds = alpha.getbbox()
    colors = {
        pixel for pixel in runtime.getdata() if pixel[3] > 0
    }
    partial_alpha = sum(1 for value in alpha.getdata() if 0 < value < 255)
    report = {
        "runtime_asset": str(RUNTIME.relative_to(ROOT.parents[3])),
        "source_size": list(raw.size),
        "runtime_size": list(runtime.size),
        "subject_bounds": list(bounds) if bounds else None,
        "subject_size": [target_width, target_height],
        "paste_position": [paste_x, paste_y],
        "opaque_palette_colors": len(colors),
        "partial_alpha_pixels": partial_alpha,
        "output_edge_touch": bool(
            bounds
            and (
                bounds[0] == 0
                or bounds[1] == 0
                or bounds[2] == 48
                or bounds[3] == 48
            )
        ),
        "display_size": [48, 48],
        "anchor": "center",
        "filter_quality": "none",
    }
    (QC / "runtime-qc.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
