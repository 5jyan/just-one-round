from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
PROCESSED = ROOT / "processed"
QC = ROOT / "qc"
BACKGROUND = ROOT.parents[3] / "images" / "dung_dodge_v2" / "background_map.png"

CONCEPTS = (
    ("A", "concept-a-alpha.png", "concept-a-runtime.png"),
    ("B", "concept-b-alpha.png", "concept-b-runtime.png"),
    ("C", "concept-c-alpha.png", "concept-c-runtime.png"),
)

BASE_CELL = (48, 36)
RUNTIME_SCALE = 2
SUBJECT_LIMIT = (46, 34)


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A").point(lambda value: 255 if value >= 64 else 0)
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("No visible subject found")
    return bbox


def build_runtime_sprite(
    source_path: Path,
    output_path: Path,
    base_cell: tuple[int, int] = BASE_CELL,
    subject_limit: tuple[int, int] = SUBJECT_LIMIT,
    palette_colors: int = 28,
    runtime_scale: int = RUNTIME_SCALE,
    sharpen: bool = False,
) -> Image.Image:
    source = Image.open(source_path).convert("RGBA")
    subject = source.crop(alpha_bbox(source))
    subject.thumbnail(subject_limit, Image.Resampling.LANCZOS)

    # Reduce generated micro-detail to the approved low-resolution palette.
    alpha = subject.getchannel("A").point(lambda value: 255 if value >= 112 else 0)
    rgb = subject.convert("RGB")
    if sharpen:
        rgb = rgb.filter(ImageFilter.UnsharpMask(radius=0.7, percent=110, threshold=2))
    rgb = rgb.quantize(
        colors=palette_colors,
        method=Image.Quantize.MEDIANCUT,
    ).convert("RGB")
    subject = Image.merge("RGBA", (*rgb.split(), alpha))

    base = Image.new("RGBA", base_cell, (0, 0, 0, 0))
    x = (base_cell[0] - subject.width) // 2
    y = (base_cell[1] - subject.height) // 2
    base.alpha_composite(subject, (x, y))
    runtime = base.resize(
        (base_cell[0] * runtime_scale, base_cell[1] * runtime_scale),
        Image.Resampling.NEAREST,
    )
    runtime.save(output_path)
    return runtime


def main() -> None:
    QC.mkdir(parents=True, exist_ok=True)
    background = Image.open(BACKGROUND).convert("RGB")
    sky_crop = background.crop((0, 120, 360, 520))

    runtime_sprites: list[tuple[str, Image.Image]] = []
    for label, source_name, runtime_name in CONCEPTS:
        runtime = build_runtime_sprite(PROCESSED / source_name, PROCESSED / runtime_name)
        runtime_sprites.append((label, runtime))

    build_runtime_sprite(
        PROCESSED / "concept-a-alpha.png",
        PROCESSED / "concept-a-runtime-large.png",
        base_cell=(170, 126),
        subject_limit=(168, 124),
        palette_colors=112,
        runtime_scale=1,
        sharpen=True,
    )

    board = Image.new("RGB", (1080, 400), (34, 45, 54))
    detail = Image.new("RGBA", (1152, 360), (23, 28, 35, 255))
    font = ImageFont.load_default(size=24)

    for index, (label, sprite) in enumerate(runtime_sprites):
        panel = sky_crop.copy()
        # The current embedded pterosaur remains above as the size baseline.
        panel.paste(sprite, (132, 230), sprite)
        draw = ImageDraw.Draw(panel)
        concept_text = f"CONCEPT {label}"
        concept_box = draw.textbbox((0, 0), concept_text, font=font)
        concept_width = concept_box[2] - concept_box[0]
        draw.rounded_rectangle(
            (12, 12, 32 + concept_width, 46),
            radius=8,
            fill=(24, 27, 38, 220),
        )
        draw.text((22, 18), concept_text, font=font, fill=(255, 246, 210))
        current_box = draw.textbbox((0, 0), "CURRENT", font=font)
        current_width = current_box[2] - current_box[0]
        draw.rounded_rectangle(
            (12, 128, 32 + current_width, 162),
            radius=7,
            fill=(24, 27, 38, 210),
        )
        draw.text((22, 134), "CURRENT", font=font, fill=(255, 246, 210))
        board.paste(panel, (index * 360, 0))

        enlarged = sprite.resize((384, 288), Image.Resampling.NEAREST)
        detail.alpha_composite(enlarged, (index * 384, 50))
        detail_draw = ImageDraw.Draw(detail)
        detail_draw.text(
            (index * 384 + 16, 12),
            f"CONCEPT {label}  |  4x PREVIEW",
            font=font,
            fill=(255, 246, 210, 255),
        )

    board.save(QC / "pterosaur-concepts-runtime-scale.png")
    detail.save(QC / "pterosaur-concepts-detail-4x.png")


if __name__ == "__main__":
    main()
