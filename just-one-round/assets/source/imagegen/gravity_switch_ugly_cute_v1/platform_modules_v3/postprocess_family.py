from pathlib import Path
import random

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
KEYED = ROOT / "keyed"
PROCESSED = ROOT / "processed"
PREVIEWS = ROOT / "previews"
MASTER = (
    ROOT
    / "unit_1x1_01"
    / "processed"
    / "scrap_module_1x1_01.png"
)
PROCESSED.mkdir(exist_ok=True)
PREVIEWS.mkdir(exist_ok=True)

DEEP_PLUM = (48, 27, 52, 255)
DARK_VIOLET = (67, 39, 69, 255)
BRUISED_VIOLET = (96, 61, 91, 255)
LIGHT_VIOLET = (135, 88, 117, 255)
DARK_OLIVE = (78, 96, 39, 255)
MUTED_OLIVE = (112, 132, 48, 255)
SOUR_LIME = (171, 195, 54, 255)
DIRTY_CREAM = (232, 218, 133, 255)
TOMATO = (226, 76, 38, 255)
SHEET_BACKGROUND = (25, 20, 35, 255)
LABEL = (232, 218, 133, 255)

PALETTE = (
    DEEP_PLUM,
    DARK_VIOLET,
    BRUISED_VIOLET,
    LIGHT_VIOLET,
    DARK_OLIVE,
    MUTED_OLIVE,
    SOUR_LIME,
    DIRTY_CREAM,
    TOMATO,
)

SPECS = {
    "scrap_module_1x1_02": (1, 1),
    "scrap_module_1x1_03": (1, 1),
    "scrap_module_1x1_04": (1, 1),
    "scrap_module_2x1_01": (2, 1),
    "scrap_module_2x1_02": (2, 1),
    "scrap_module_3x1_01": (3, 1),
    "scrap_module_3x1_02": (3, 1),
    "scrap_module_1x2_01": (1, 2),
    "scrap_module_1x2_02": (1, 2),
    "scrap_module_1x3_01": (1, 3),
    "scrap_module_1x3_02": (1, 3),
    "scrap_module_2x2_01": (2, 2),
    "scrap_module_2x2_02": (2, 2),
    "scrap_module_3x2_01": (3, 2),
    "scrap_module_2x3_01": (2, 3),
}


def distance(
    left: tuple[int, int, int],
    right: tuple[int, int, int],
) -> int:
    return sum((a - b) ** 2 for a, b in zip(left, right))


def flatten(image: Image.Image) -> Image.Image:
    source = image.convert("RGBA")
    output = Image.new("RGBA", source.size, DEEP_PLUM)
    for y in range(source.height):
        for x in range(source.width):
            red, green, blue, alpha = source.getpixel((x, y))
            if alpha < 128:
                continue
            output.putpixel(
                (x, y),
                min(
                    PALETTE,
                    key=lambda color: distance(
                        (red, green, blue),
                        color[:3],
                    ),
                ),
            )
    return output


master = Image.open(MASTER).convert("RGBA")
if master.size != (48, 48):
    raise RuntimeError("The approved master must remain 48x48.")

master.save(PROCESSED / "scrap_module_1x1_01.png")
top_connector = master.crop((0, 0, 48, 3))
bottom_connector = master.crop((0, 45, 48, 48))
left_connector = master.crop((0, 0, 3, 48))
right_connector = master.crop((45, 0, 48, 48))
corners = {
    "top_left": master.crop((0, 0, 3, 3)),
    "top_right": master.crop((45, 0, 48, 3)),
    "bottom_left": master.crop((0, 45, 3, 48)),
    "bottom_right": master.crop((45, 45, 48, 48)),
}


def apply_connectors(
    image: Image.Image,
    units_wide: int,
    units_high: int,
) -> None:
    width, height = image.size
    for column in range(units_wide):
        x = column * 48
        image.paste(top_connector, (x, 0))
        image.paste(bottom_connector, (x, height - 3))
    for row in range(units_high):
        y = row * 48
        image.paste(left_connector, (0, y))
        image.paste(right_connector, (width - 3, y))
    image.paste(corners["top_left"], (0, 0))
    image.paste(corners["top_right"], (width - 3, 0))
    image.paste(corners["bottom_left"], (0, height - 3))
    image.paste(corners["bottom_right"], (width - 3, height - 3))


for name, (units_wide, units_high) in SPECS.items():
    source = Image.open(KEYED / f"{name}.png").convert("RGBA")
    bounds = source.getchannel("A").getbbox()
    if bounds is None:
        raise RuntimeError(f"{name} contains no opaque subject.")
    subject = source.crop(bounds)
    target = (
        units_wide * 48,
        units_high * 48,
    )
    module = flatten(subject.resize(target, Image.Resampling.LANCZOS))
    apply_connectors(module, units_wide, units_high)
    module.save(PROCESSED / f"{name}.png")


def load(name: str) -> Image.Image:
    return Image.open(PROCESSED / f"{name}.png").convert("RGBA")


rows = [
    ("1x1", [f"scrap_module_1x1_{index:02d}" for index in range(1, 5)]),
    ("2x1", [f"scrap_module_2x1_{index:02d}" for index in range(1, 3)]),
    ("3x1", [f"scrap_module_3x1_{index:02d}" for index in range(1, 3)]),
    ("1x2", [f"scrap_module_1x2_{index:02d}" for index in range(1, 3)]),
    ("1x3", [f"scrap_module_1x3_{index:02d}" for index in range(1, 3)]),
    ("2x2", [f"scrap_module_2x2_{index:02d}" for index in range(1, 3)]),
    ("large", ["scrap_module_3x2_01", "scrap_module_2x3_01"]),
]
row_gap = 12
asset_gap = 8
label_width = 44
row_heights = [max(load(name).height for name in names) for _, names in rows]
sheet_width = 368
sheet_height = 12 + sum(row_heights) + row_gap * (len(rows) - 1) + 12
sheet = Image.new("RGBA", (sheet_width, sheet_height), SHEET_BACKGROUND)
draw = ImageDraw.Draw(sheet)
y = 12
for (label, names), row_height in zip(rows, row_heights):
    draw.text((8, y + 2), label, fill=LABEL)
    x = label_width
    for name in names:
        asset = load(name)
        sheet.alpha_composite(asset, (x, y))
        x += asset.width + asset_gap
    y += row_height + row_gap
sheet.save(PREVIEWS / "all_modules_sheet.png")
sheet.resize(
    (sheet.width * 2, sheet.height * 2),
    Image.Resampling.NEAREST,
).save(PREVIEWS / "all_modules_sheet_2x.png")

# A deterministic exact 8x6 packing. Every module appears at least once; the
# four extra cells repeat the small fallback units.
wall = Image.new("RGBA", (8 * 48, 6 * 48), DEEP_PLUM)
placements = [
    ("scrap_module_3x2_01", 0, 0),
    ("scrap_module_2x3_01", 3, 0),
    ("scrap_module_2x2_01", 5, 0),
    ("scrap_module_1x3_01", 7, 0),
    ("scrap_module_3x1_01", 0, 2),
    ("scrap_module_2x1_01", 5, 2),
    ("scrap_module_2x2_02", 0, 3),
    ("scrap_module_1x3_02", 2, 3),
    ("scrap_module_1x2_01", 3, 3),
    ("scrap_module_1x2_02", 4, 3),
    ("scrap_module_3x1_02", 5, 3),
    ("scrap_module_2x1_02", 5, 4),
    ("scrap_module_1x1_01", 7, 4),
    ("scrap_module_1x1_02", 0, 5),
    ("scrap_module_1x1_03", 1, 5),
    ("scrap_module_1x1_04", 3, 5),
    ("scrap_module_1x1_01", 4, 5),
    ("scrap_module_1x1_02", 5, 5),
    ("scrap_module_1x1_03", 6, 5),
    ("scrap_module_1x1_04", 7, 5),
]
for name, column, row in placements:
    wall.alpha_composite(load(name), (column * 48, row * 48))
wall.save(PREVIEWS / "mixed_join_test.png")
wall.resize(
    (wall.width * 2, wall.height * 2),
    Image.Resampling.NEAREST,
).save(PREVIEWS / "mixed_join_test_2x.png")

# Runtime atlas: a deterministic 24x12 exact packing. The atlas is wider than
# three logical screens, so the scenery does not visibly repeat every viewport.
runtime_specs = {
    "scrap_module_1x1_01": (1, 1),
    **SPECS,
}
grid_width = 24
grid_height = 12
occupied = [
    [False for _ in range(grid_width)]
    for _ in range(grid_height)
]
runtime_atlas = Image.new(
    "RGBA",
    (grid_width * 48, grid_height * 48),
    DEEP_PLUM,
)
rng = random.Random(20260724)
usage = {name: 0 for name in runtime_specs}

for row in range(grid_height):
    for column in range(grid_width):
        if occupied[row][column]:
            continue
        candidates = []
        weights = []
        for name, (units_wide, units_high) in runtime_specs.items():
            if column + units_wide > grid_width:
                continue
            if row + units_high > grid_height:
                continue
            if any(
                occupied[y][x]
                for y in range(row, row + units_high)
                for x in range(column, column + units_wide)
            ):
                continue
            candidates.append((name, units_wide, units_high))
            area = units_wide * units_high
            weights.append(
                (area * area) / ((usage[name] + 1) ** 3),
            )
        name, units_wide, units_high = rng.choices(
            candidates,
            weights=weights,
            k=1,
        )[0]
        runtime_atlas.alpha_composite(
            load(name),
            (column * 48, row * 48),
        )
        for y in range(row, row + units_high):
            for x in range(column, column + units_wide):
                occupied[y][x] = True
        usage[name] += 1

assert all(all(row) for row in occupied)
runtime_atlas.save(PREVIEWS / "runtime_atlas.png")
runtime_atlas.resize(
    (runtime_atlas.width // 2, runtime_atlas.height // 2),
    Image.Resampling.NEAREST,
).save(PREVIEWS / "runtime_atlas_overview.png")
