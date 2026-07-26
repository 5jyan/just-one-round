from pathlib import Path

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parent
PARENT = ROOT.parent
CANDIDATE = ROOT / "candidate"
PREVIEWS = ROOT / "previews"
CANDIDATE.mkdir(exist_ok=True)
PREVIEWS.mkdir(exist_ok=True)

DEEP_PLUM = (52, 28, 57, 255)
DARK_VIOLET = (77, 46, 79, 255)
BRUISED_VIOLET = (112, 72, 105, 255)
LIGHT_VIOLET = (145, 96, 125, 255)
MUTED_OLIVE = (104, 126, 48, 255)
SOUR_LIME = (177, 202, 54, 255)
MUTED_CREAM = (194, 180, 105, 255)
DIRTY_CREAM = (255, 239, 157, 255)
TOMATO = (230, 78, 43, 255)

FILL_PALETTE = (
    DEEP_PLUM,
    DARK_VIOLET,
    BRUISED_VIOLET,
    LIGHT_VIOLET,
    MUTED_OLIVE,
    MUTED_CREAM,
    TOMATO,
)
EDGE_PALETTE = FILL_PALETTE + (SOUR_LIME, DIRTY_CREAM)


def distance(left: tuple[int, int, int], right: tuple[int, int, int]) -> int:
    return sum((a - b) ** 2 for a, b in zip(left, right))


def flatten(
    image: Image.Image,
    *,
    palette: tuple[tuple[int, int, int, int], ...],
    transparent: bool,
) -> Image.Image:
    source = image.convert("RGBA")
    output = Image.new("RGBA", source.size, (0, 0, 0, 0))
    for y in range(source.height):
        for x in range(source.width):
            red, green, blue, alpha = source.getpixel((x, y))
            if transparent and alpha < 128:
                continue
            output.putpixel(
                (x, y),
                min(
                    palette,
                    key=lambda color: distance((red, green, blue), color[:3]),
                ),
            )
    return output


def crop_ratio(
    image: Image.Image,
    width_ratio: int,
    height_ratio: int,
    *,
    horizontal_anchor: str = "center",
) -> Image.Image:
    width, height = image.size
    target = width_ratio / height_ratio
    current = width / height
    if current > target:
        crop_width = round(height * target)
        if horizontal_anchor == "right":
            left = width - crop_width
        else:
            left = (width - crop_width) // 2
        return image.crop((left, 0, left + crop_width, height))
    crop_height = round(width / target)
    top = (height - crop_height) // 2
    return image.crop((0, top, width, top + crop_height))


fill_raw = Image.open(ROOT / "fill" / "raw" / "fill.png").convert("RGBA")
fill_crop_size = round(min(fill_raw.size) * 0.38)
fill_crop_origins = []
for row in range(4):
    for column in range(4):
        left = round(
            (fill_raw.width - fill_crop_size) * column / 3,
        )
        top = round(
            (fill_raw.height - fill_crop_size) * row / 3,
        )
        fill_crop_origins.append((left, top))
fill_variants = []
for index, (left, top) in enumerate(fill_crop_origins):
    crop = fill_raw.crop(
        (left, top, left + fill_crop_size, top + fill_crop_size),
    )
    variant = flatten(
        crop.resize((48, 48), Image.Resampling.LANCZOS),
        palette=FILL_PALETTE,
        transparent=False,
    )
    variant.save(CANDIDATE / f"scrap_fill_{index}.png")
    fill_variants.append(variant)

# Compatibility name for a future single-texture fallback.
fill_variants[0].save(CANDIDATE / "scrap_fill.png")

surface_source = Image.open(
    ROOT / "surface" / "transparent-source.png",
).convert("RGBA")
surface_bbox = surface_source.getchannel("A").getbbox()
if surface_bbox is None:
    raise RuntimeError("Surface source is empty.")
surface_subject = surface_source.crop(surface_bbox)
surface_seed = crop_ratio(surface_subject, 2, 1).resize(
    (24, 12),
    Image.Resampling.LANCZOS,
)
surface_seed = flatten(
    surface_seed,
    palette=EDGE_PALETTE,
    transparent=True,
)
surface = Image.new("RGBA", (48, 12), (0, 0, 0, 0))
surface.alpha_composite(surface_seed, (0, 0))
surface.alpha_composite(ImageOps.mirror(surface_seed), (24, 0))
surface.save(CANDIDATE / "contact_surface.png")

side_source = Image.open(ROOT / "side" / "transparent-source.png").convert("RGBA")
side_bbox = side_source.getchannel("A").getbbox()
if side_bbox is None:
    raise RuntimeError("Side source is empty.")
side_subject = side_source.crop(side_bbox)
side_subject = crop_ratio(
    side_subject,
    1,
    4,
    horizontal_anchor="right",
)
side_right = flatten(
    side_subject.resize((12, 48), Image.Resampling.LANCZOS),
    palette=FILL_PALETTE,
    transparent=True,
)
side_left = ImageOps.mirror(side_right)
side_right.save(CANDIDATE / "scrap_side_right.png")
side_left.save(CANDIDATE / "scrap_side_left.png")

outer_source = Image.open(
    ROOT / "corner" / "transparent-source.png",
).convert("RGBA")
outer_crop = outer_source.crop((680, 180, 1020, 520))
outer_floor_right = flatten(
    outer_crop.resize((12, 12), Image.Resampling.LANCZOS),
    palette=EDGE_PALETTE,
    transparent=True,
)
outer_floor_left = ImageOps.mirror(outer_floor_right)
outer_ceiling_right = ImageOps.flip(outer_floor_right)
outer_ceiling_left = ImageOps.flip(outer_floor_left)

inner_source = Image.open(
    ROOT / "inner_corner" / "transparent-source.png",
).convert("RGBA")
inner_crop = inner_source.crop((360, 600, 900, 1140))
inner_floor_right = flatten(
    inner_crop.resize((12, 12), Image.Resampling.LANCZOS),
    palette=EDGE_PALETTE,
    transparent=True,
)
inner_floor_left = ImageOps.mirror(inner_floor_right)
inner_ceiling_right = ImageOps.flip(inner_floor_right)
inner_ceiling_left = ImageOps.flip(inner_floor_left)

corners = {
    "outer_floor_right": outer_floor_right,
    "outer_floor_left": outer_floor_left,
    "outer_ceiling_right": outer_ceiling_right,
    "outer_ceiling_left": outer_ceiling_left,
    "inner_floor_right": inner_floor_right,
    "inner_floor_left": inner_floor_left,
    "inner_ceiling_right": inner_ceiling_right,
    "inner_ceiling_left": inner_ceiling_left,
}
for name, image in corners.items():
    image.save(CANDIDATE / f"{name}.png")


def make_tiled_region(
    width: int,
    height: int,
    tile: Image.Image,
) -> Image.Image:
    region = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    for y in range(0, height, tile.height):
        for x in range(0, width, tile.width):
            region.alpha_composite(tile, (x, y))
    return region


def paste_fill(
    canvas: Image.Image,
    bounds: tuple[int, int, int, int],
) -> None:
    left, top, right, bottom = bounds
    if right <= left or bottom <= top:
        return
    region = Image.new(
        "RGBA",
        (right - left, bottom - top),
        (0, 0, 0, 0),
    )
    for y in range(0, region.height, 48):
        for x in range(0, region.width, 48):
            world_column = (left + x) // 48
            world_row = (top + y) // 48
            variant_index = (world_column + 7 * world_row) % len(
                fill_variants,
            )
            region.alpha_composite(fill_variants[variant_index], (x, y))
    canvas.alpha_composite(region, (left, top))


def lime_row(image: Image.Image) -> int:
    scores = []
    for y in range(image.height):
        score = sum(
            1
            for x in range(image.width)
            if image.getpixel((x, y)) == SOUR_LIME
        )
        scores.append(score)
    return max(range(len(scores)), key=scores.__getitem__)


def place_corner(
    canvas: Image.Image,
    image: Image.Image,
    x: int,
    contact_y: int,
) -> None:
    canvas.alpha_composite(image, (x, contact_y - lime_row(image)))


def place_side(
    canvas: Image.Image,
    side: Image.Image,
    x: int,
    top: int,
    bottom: int,
) -> None:
    if bottom <= top:
        return
    region = make_tiled_region(side.width, bottom - top, side)
    canvas.alpha_composite(region, (x, top))


background = Image.open(PARENT / "candidate" / "space_background.png").convert(
    "RGBA",
)
preview = background.resize((360, 640), Image.Resampling.NEAREST)
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
    paste_fill(preview, (x, 0, x + 48, ceiling_bottom))
    paste_fill(preview, (x, floor_top, x + 48, 640))
    preview.alpha_composite(ImageOps.flip(surface), (x, ceiling_bottom - 12))
    preview.alpha_composite(surface, (x, floor_top))

for index in range(len(profiles) - 1):
    _, left_ceiling, left_floor = profiles[index]
    right_x, right_ceiling, right_floor = profiles[index + 1]

    if left_floor < right_floor:
        place_side(
            preview,
            side_right,
            right_x - 12,
            left_floor,
            right_floor,
        )
        place_corner(
            preview,
            outer_floor_right,
            right_x - 12,
            left_floor,
        )
        place_corner(
            preview,
            inner_floor_right,
            right_x - 12,
            right_floor,
        )
    elif right_floor < left_floor:
        place_side(
            preview,
            side_left,
            right_x,
            right_floor,
            left_floor,
        )
        place_corner(
            preview,
            outer_floor_left,
            right_x,
            right_floor,
        )
        place_corner(
            preview,
            inner_floor_left,
            right_x,
            left_floor,
        )

    if left_ceiling > right_ceiling:
        place_side(
            preview,
            side_right,
            right_x - 12,
            right_ceiling,
            left_ceiling,
        )
        place_corner(
            preview,
            inner_ceiling_right,
            right_x - 12,
            right_ceiling - 1,
        )
        place_corner(
            preview,
            outer_ceiling_right,
            right_x - 12,
            left_ceiling - 1,
        )
    elif right_ceiling > left_ceiling:
        place_side(
            preview,
            side_left,
            right_x,
            left_ceiling,
            right_ceiling,
        )
        place_corner(
            preview,
            inner_ceiling_left,
            right_x,
            left_ceiling - 1,
        )
        place_corner(
            preview,
            outer_ceiling_left,
            right_x,
            right_ceiling - 1,
        )

player_sheet = Image.open(PARENT / "candidate" / "player_sheet.png").convert(
    "RGBA",
)
player = player_sheet.crop((0, 0, 24, 24)).resize(
    (48, 48),
    Image.Resampling.NEAREST,
)
preview.alpha_composite(player, (68, 416))
preview.save(PREVIEWS / "scrap-platform-screen.png")
preview.resize((720, 1280), Image.Resampling.NEAREST).save(
    PREVIEWS / "scrap-platform-screen-2x.png",
)

fill_contact_sheet = Image.new("RGBA", (192, 192), DEEP_PLUM)
for index, variant in enumerate(fill_variants):
    fill_contact_sheet.alpha_composite(
        variant,
        ((index % 4) * 48, (index // 4) * 48),
    )
fill_contact_sheet.resize((768, 768), Image.Resampling.NEAREST).save(
    PREVIEWS / "scrap-fill-variants-8x.png",
)
surface.resize((384, 96), Image.Resampling.NEAREST).save(
    PREVIEWS / "contact-surface-8x.png",
)
