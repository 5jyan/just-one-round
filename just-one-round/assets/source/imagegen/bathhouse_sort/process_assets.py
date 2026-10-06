from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets/source/imagegen/bathhouse_sort"
RUNTIME = ROOT / "assets/images/bathhouse_sort"
SPECIES_V7 = SOURCE / "animal_species_roster_v7_face_variety/processed"


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("asset frame is empty")
    return bbox


def keep_largest_component(source: Image.Image) -> Image.Image:
    source = source.convert("RGBA")
    alpha = source.getchannel("A")
    width, height = source.size
    visited: set[tuple[int, int]] = set()
    largest: list[tuple[int, int]] = []
    for y in range(height):
        for x in range(width):
            if alpha.getpixel((x, y)) == 0 or (x, y) in visited:
                continue
            component: list[tuple[int, int]] = []
            stack = [(x, y)]
            visited.add((x, y))
            while stack:
                px, py = stack.pop()
                component.append((px, py))
                for ny in range(max(0, py - 1), min(height, py + 2)):
                    for nx in range(max(0, px - 1), min(width, px + 2)):
                        point = (nx, ny)
                        if point in visited or alpha.getpixel(point) == 0:
                            continue
                        visited.add(point)
                        stack.append(point)
            if len(component) > len(largest):
                largest = component
    if not largest:
        raise ValueError("asset frame is empty")
    mask = Image.new("L", source.size, 0)
    mask_pixels = mask.load()
    for x, y in largest:
        mask_pixels[x, y] = alpha.getpixel((x, y))
    cleaned = Image.new("RGBA", source.size, (0, 0, 0, 0))
    cleaned.paste(source, mask=mask)
    return cleaned


def fit_frame(source: Image.Image, size: tuple[int, int], padding: int) -> Image.Image:
    source = source.convert("RGBA")
    subject = source.crop(alpha_bbox(source))
    limit_w = size[0] - padding * 2
    limit_h = size[1] - padding * 2
    scale = min(1.0, limit_w / subject.width, limit_h / subject.height)
    if scale < 1.0:
        subject = subject.resize(
            (max(1, round(subject.width * scale)), max(1, round(subject.height * scale))),
            Image.Resampling.NEAREST,
        )
    frame = Image.new("RGBA", size, (0, 0, 0, 0))
    x = (size[0] - subject.width) // 2
    y = size[1] - padding - subject.height
    frame.alpha_composite(subject, (x, y))
    return frame


def build_background() -> None:
    source = Image.open(SOURCE / "background/raw-background.png").convert("RGB")
    crop_width = source.height // 2
    left = (source.width - crop_width) // 2
    cropped = source.crop((left, 0, left + crop_width, source.height))
    cropped.resize((180, 360), Image.Resampling.NEAREST).save(
        RUNTIME / "bathhouse_background.png"
    )


def build_ryokan_environment() -> None:
    source = Image.open(
        SOURCE / "ryokan_corridor/raw-background.png"
    ).convert("RGB")
    if source.width * 2 != source.height:
        crop_width = source.height // 2
        left = (source.width - crop_width) // 2
        source = source.crop((left, 0, left + crop_width, source.height))
    source.resize((180, 360), Image.Resampling.NEAREST).save(
        RUNTIME / "bathhouse_ryokan_background.png"
    )

    noren = Image.open(
        SOURCE / "noren/processed/sheet-transparent.png"
    ).convert("RGBA")
    if noren.size != (240, 160):
        raise ValueError(f"unexpected noren atlas size: {noren.size}")
    noren.save(RUNTIME / "bathhouse_noren_atlas.png")


def build_three_bay_environment() -> None:
    source = Image.open(
        SOURCE / "ryokan_three_bay/raw-background.png"
    ).convert("RGB")
    if source.width * 2 != source.height:
        crop_width = source.height // 2
        left = (source.width - crop_width) // 2
        source = source.crop((left, 0, left + crop_width, source.height))
    source.resize((180, 360), Image.Resampling.NEAREST).save(
        RUNTIME / "bathhouse_corridor_background.png"
    )

    noren = Image.open(
        SOURCE / "noren_hanja/processed/sheet-transparent.png"
    ).convert("RGBA")
    if noren.size != (240, 160):
        raise ValueError(f"unexpected hanja noren atlas size: {noren.size}")
    noren.save(RUNTIME / "bathhouse_hanja_noren_atlas.png")


def build_guests() -> None:
    frames = []
    for index in range(8):
        frame = fit_frame(
            Image.open(SPECIES_V7 / f"idle-{index + 1}.png").convert("RGBA"),
            (112, 224),
            padding=2,
        )
        frames.append(frame)
    atlas = Image.new("RGBA", (448, 448), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        atlas.alpha_composite(frame, ((index % 4) * 112, (index // 4) * 224))
    atlas.save(RUNTIME / "bathhouse_guests_atlas.png")


def build_doors() -> None:
    source = Image.open(SOURCE / "doors/raw-sheet-clean.png").convert("RGBA")
    atlas = Image.new("RGBA", (128, 96), (0, 0, 0, 0))
    for index in range(2):
        left = round(index * source.width / 2)
        right = round((index + 1) * source.width / 2)
        raw_frame = source.crop((left, 0, right, source.height))
        frame = fit_frame(keep_largest_component(raw_frame), (64, 96), padding=1)
        atlas.alpha_composite(frame, (index * 64, 0))
    atlas.save(RUNTIME / "bathhouse_doors_atlas.png")


def build_feedback() -> None:
    atlas = Image.new("RGBA", (128, 96), (0, 0, 0, 0))
    rows = (("success", "success"), ("error", "error"), ("steam", "steam"))
    for row, (folder, prefix) in enumerate(rows):
        for column in range(4):
            frame = Image.open(
                SOURCE / f"fx/{folder}/{prefix}-{column + 1}.png"
            ).convert("RGBA")
            atlas.alpha_composite(frame, (column * 32, row * 32))
    atlas.save(RUNTIME / "bathhouse_feedback_fx_atlas.png")


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    build_background()
    build_ryokan_environment()
    build_three_bay_environment()
    build_guests()
    build_doors()
    build_feedback()


if __name__ == "__main__":
    main()
