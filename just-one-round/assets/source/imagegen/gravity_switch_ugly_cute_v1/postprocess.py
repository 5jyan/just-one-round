from pathlib import Path

from PIL import Image, ImageEnhance, ImageOps


ROOT = Path(__file__).resolve().parent
CANDIDATE = ROOT / "candidate"
PREVIEWS = ROOT / "previews"
CANDIDATE.mkdir(exist_ok=True)
PREVIEWS.mkdir(exist_ok=True)

PALETTE = (
    (52, 28, 57, 255),    # deep plum
    (77, 46, 79, 255),    # dark violet
    (112, 72, 105, 255),  # bruised violet
    (177, 202, 54, 255),  # sour lime
    (112, 145, 48, 255),  # olive
    (181, 220, 181, 255), # dusty mint
    (128, 177, 151, 255), # muted mint
    (255, 239, 157, 255), # dirty cream
    (244, 85, 43, 255),   # tomato orange
    (82, 196, 186, 255),  # dusty turquoise
)
PLAYER_PALETTE = (
    PALETTE[0],
    PALETTE[1],
    PALETTE[3],
    PALETTE[4],
    PALETTE[7],
    PALETTE[8],
    PALETTE[9],
)
IMPACT_PALETTE = (
    PALETTE[0],
    PALETTE[1],
    PALETTE[3],
    PALETTE[7],
    PALETTE[8],
    PALETTE[9],
)
FILL_PALETTE = (
    (45, 25, 51, 255),
    (67, 39, 70, 255),
    (91, 57, 91, 255),
    (122, 76, 105, 255),
    (112, 145, 48, 255),
)


def distance(left: tuple[int, int, int], right: tuple[int, int, int]) -> int:
    return sum((a - b) ** 2 for a, b in zip(left, right))


def flatten(
    image: Image.Image,
    *,
    transparent: bool,
    palette: tuple[tuple[int, int, int, int], ...] = PALETTE,
    alpha_threshold: int = 128,
) -> Image.Image:
    source = image.convert("RGBA")
    output = Image.new("RGBA", source.size, (0, 0, 0, 0))
    for y in range(source.height):
        for x in range(source.width):
            red, green, blue, alpha = source.getpixel((x, y))
            if transparent and alpha < alpha_threshold:
                continue
            output.putpixel(
                (x, y),
                min(
                    palette,
                    key=lambda color: distance((red, green, blue), color[:3]),
                ),
            )
    return output


def crop_ratio(image: Image.Image, width_ratio: int, height_ratio: int) -> Image.Image:
    width, height = image.size
    target = width_ratio / height_ratio
    current = width / height
    if current > target:
        crop_width = round(height * target)
        left = (width - crop_width) // 2
        return image.crop((left, 0, left + crop_width, height))
    crop_height = round(width / target)
    top = (height - crop_height) // 2
    return image.crop((0, top, width, top + crop_height))


background_raw = Image.open(ROOT / "background" / "raw" / "background.png")
background = crop_ratio(background_raw, 9, 16).resize(
    (180, 320),
    Image.Resampling.LANCZOS,
)
background = flatten(background, transparent=False).convert("RGB")
background.save(CANDIDATE / "space_background.png")

player_source = Image.open(ROOT / "player" / "processed" / "sheet-transparent.png")
player = flatten(player_source, transparent=True, palette=PLAYER_PALETTE)
player.save(CANDIDATE / "player_sheet.png")

impact_source = Image.open(
    ROOT / "landing_impact" / "processed" / "sheet-transparent.png",
)
impact = flatten(
    impact_source,
    transparent=True,
    palette=IMPACT_PALETTE,
    alpha_threshold=32,
)
impact.save(CANDIDATE / "landing_impact_sheet.png")

surface_source = Image.open(
    ROOT / "platform_surface" / "transparent-source.png",
).convert("RGBA")
surface_bbox = surface_source.getchannel("A").getbbox()
if surface_bbox is None:
    raise RuntimeError("Platform surface became empty after chroma removal.")
surface_subject = surface_source.crop(surface_bbox)
surface_seed = crop_ratio(surface_subject, 2, 1).resize(
    (24, 12),
    Image.Resampling.LANCZOS,
)
surface_seed = flatten(surface_seed, transparent=True, palette=PLAYER_PALETTE)
surface = Image.new("RGBA", (48, 12), (0, 0, 0, 0))
surface.alpha_composite(surface_seed, (0, 0))
surface.alpha_composite(ImageOps.mirror(surface_seed), (24, 0))
surface.save(CANDIDATE / "platform_surface.png")
side_left = surface.transpose(Image.Transpose.ROTATE_90)
side_right = ImageOps.mirror(side_left)
side_left.save(CANDIDATE / "platform_side_left.png")
side_right.save(CANDIDATE / "platform_side_right.png")

fill_raw = Image.open(ROOT / "platform_fill" / "raw" / "platform-fill.png")
fill_seed = crop_ratio(fill_raw, 1, 1).resize(
    (12, 12),
    Image.Resampling.LANCZOS,
)
fill_seed = ImageEnhance.Contrast(fill_seed.convert("RGB")).enhance(2.4)
fill_seed = flatten(
    fill_seed,
    transparent=False,
    palette=FILL_PALETTE,
)
fill = Image.new("RGBA", (24, 24), (0, 0, 0, 255))
fill.alpha_composite(fill_seed, (0, 0))
fill.alpha_composite(ImageOps.mirror(fill_seed), (12, 0))
fill.alpha_composite(ImageOps.flip(fill_seed), (0, 12))
fill.alpha_composite(ImageOps.flip(ImageOps.mirror(fill_seed)), (12, 12))
fill.convert("RGB").save(CANDIDATE / "platform_fill.png")

player.resize((384, 384), Image.Resampling.NEAREST).save(
    PREVIEWS / "player-sheet-8x.png",
)
impact.resize((256, 256), Image.Resampling.NEAREST).save(
    PREVIEWS / "landing-impact-8x.png",
)


def tile_fill(canvas: Image.Image, bounds: tuple[int, int, int, int]) -> None:
    left, top, right, bottom = bounds
    for y in range(top, bottom, 24):
        for x in range(left, right, 24):
            canvas.alpha_composite(fill, (x, y))


preview = background.resize((360, 640), Image.Resampling.NEAREST).convert("RGBA")
profiles = (
    (0, 128, 512),
    (48, 128, 512),
    (96, 128, 464),
    (144, 176, 464),
    (192, 176, 512),
    (240, 128, 512),
    (288, 176, 464),
    (336, 128, 512),
)
for x, ceiling_bottom, floor_top in profiles:
    tile_fill(preview, (x, 0, x + 48, ceiling_bottom))
    tile_fill(preview, (x, floor_top, x + 48, 640))
    ceiling_surface = ImageOps.flip(surface)
    preview.alpha_composite(ceiling_surface, (x, ceiling_bottom - 12))
    preview.alpha_composite(surface, (x, floor_top))

for index in range(len(profiles) - 1):
    left_x, left_ceiling, left_floor = profiles[index]
    right_x, right_ceiling, right_floor = profiles[index + 1]
    boundary_x = right_x

    if left_floor < right_floor:
        for y in range(left_floor, right_floor, 48):
            preview.alpha_composite(side_right, (boundary_x - 12, y))
    elif right_floor < left_floor:
        for y in range(right_floor, left_floor, 48):
            preview.alpha_composite(side_left, (boundary_x, y))

    if left_ceiling > right_ceiling:
        for y in range(right_ceiling, left_ceiling, 48):
            preview.alpha_composite(side_right, (boundary_x - 12, y))
    elif right_ceiling > left_ceiling:
        for y in range(left_ceiling, right_ceiling, 48):
            preview.alpha_composite(side_left, (boundary_x, y))

player_frame = player.crop((0, 0, 24, 24)).resize(
    (48, 48),
    Image.Resampling.NEAREST,
)
preview.alpha_composite(player_frame, (68, 416))
impact_frame = impact.crop((16, 16, 32, 32)).resize(
    (48, 48),
    Image.Resampling.NEAREST,
)
preview.alpha_composite(impact_frame, (68, 428))
preview.save(PREVIEWS / "gravity-switch-concept-screen.png")
preview.resize((720, 1280), Image.Resampling.NEAREST).save(
    PREVIEWS / "gravity-switch-concept-screen-2x.png",
)
