from pathlib import Path
import json

from PIL import Image


ROOT = Path(__file__).resolve().parent
APPROVED_MASTER = (
    ROOT
    / "basic_1x1_01"
    / "processed"
    / "scrap_basic_1x1_01.png"
)
KEYED = ROOT / "generated_family" / "keyed"
PROCESSED = ROOT / "processed"
PREVIEWS = ROOT / "previews"
PROCESSED.mkdir(exist_ok=True)
PREVIEWS.mkdir(exist_ok=True)

CELL = 48
BLACK_PLUM = (31, 18, 36, 255)
DEEP_PLUM = (44, 27, 48, 255)
DARK_VIOLET = (59, 37, 62, 255)
BRUISED_VIOLET = (77, 49, 77, 255)
MUTED_OLIVE = (79, 84, 34, 255)
PALETTE = (
    BLACK_PLUM,
    DEEP_PLUM,
    DARK_VIOLET,
    BRUISED_VIOLET,
    MUTED_OLIVE,
)

SPECS = [
    ("scrap_basic_1x1_01", 1, 1, "approved imagegen master"),
    ("scrap_basic_1x1_02", 1, 1, "individual imagegen source"),
    ("scrap_basic_1x1_03", 1, 1, "individual imagegen source"),
    ("scrap_basic_1x1_04", 1, 1, "individual imagegen source"),
    ("scrap_basic_1x2_01", 1, 2, "individual imagegen source"),
    ("scrap_basic_1x2_02", 1, 2, "individual imagegen source"),
    ("scrap_basic_2x1_01", 2, 1, "individual imagegen source"),
    ("scrap_basic_2x1_02", 2, 1, "individual imagegen source"),
    ("scrap_basic_2x2_01", 2, 2, "individual imagegen source"),
    ("scrap_basic_2x2_02", 2, 2, "individual imagegen source"),
    ("scrap_basic_3x1_01", 3, 1, "individual imagegen source"),
    ("scrap_basic_3x1_02", 3, 1, "individual imagegen source"),
    ("scrap_basic_1x3_01", 1, 3, "individual imagegen source"),
    ("scrap_basic_1x3_02", 1, 3, "individual imagegen source"),
    ("scrap_basic_3x2_01", 3, 2, "individual imagegen source"),
]


def distance(
    left: tuple[int, int, int],
    right: tuple[int, int, int],
) -> int:
    return sum((a - b) ** 2 for a, b in zip(left, right))


def flatten(image: Image.Image) -> Image.Image:
    source = image.convert("RGBA")
    output = Image.new("RGBA", source.size, BLACK_PLUM)
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


def apply_generated_source(
    source: Image.Image,
    units_wide: int,
    units_high: int,
) -> Image.Image:
    bounds = source.getchannel("A").getbbox()
    if bounds is None:
        raise RuntimeError("Generated source has no opaque module.")
    subject = source.crop(bounds)
    target = (units_wide * CELL, units_high * CELL)
    return flatten(subject.resize(target, Image.Resampling.LANCZOS))


master = Image.open(APPROVED_MASTER).convert("RGBA")
if master.size != (CELL, CELL):
    raise RuntimeError(f"Unexpected master size: {master.size}")

# These three-pixel strips are the only family-wide deterministic redraw.
# They come from the approved ImageGen master and make independently generated
# modules meet on the same edge language without changing their interiors.
top_connector = master.crop((0, 0, CELL, 3))
bottom_connector = master.crop((0, CELL - 3, CELL, CELL))
left_connector = master.crop((0, 0, 3, CELL))
right_connector = master.crop((CELL - 3, 0, CELL, CELL))


def apply_connectors(
    module: Image.Image,
    units_wide: int,
    units_high: int,
) -> None:
    for column in range(units_wide):
        x = column * CELL
        module.paste(top_connector, (x, 0))
        module.paste(bottom_connector, (x, module.height - 3))
    for row in range(units_high):
        y = row * CELL
        module.paste(left_connector, (0, y))
        module.paste(right_connector, (module.width - 3, y))


modules: dict[str, Image.Image] = {}
for name, units_wide, units_high, provenance in SPECS:
    if provenance == "approved imagegen master":
        module = master.copy()
    else:
        source_path = KEYED / f"{name}.png"
        module = apply_generated_source(
            Image.open(source_path).convert("RGBA"),
            units_wide,
            units_high,
        )
        apply_connectors(module, units_wide, units_high)
    module.save(PROCESSED / f"{name}.png")
    modules[name] = module

# Catalog with preview-only gutters. Every module is displayed at native size.
groups = [
    [name for name, width, height, _ in SPECS if (width, height) == size]
    for size in ((1, 1), (1, 2), (2, 1), (2, 2), (3, 1), (1, 3), (3, 2))
]
gutter = 12
row_heights = [max(modules[name].height for name in group) for group in groups]
sheet_width = max(
    sum(modules[name].width for name in group) + gutter * (len(group) + 1)
    for group in groups
)
sheet_height = sum(row_heights) + gutter * (len(groups) + 1)
sheet = Image.new("RGBA", (sheet_width, sheet_height), (255, 0, 255, 255))
y = gutter
for group, row_height in zip(groups, row_heights):
    x = gutter
    for name in group:
        sheet.alpha_composite(modules[name], (x, y))
        x += modules[name].width + gutter
    y += row_height + gutter
sheet.save(PREVIEWS / "all_basic_modules_sheet.png")
sheet.resize((sheet.width * 2, sheet.height * 2), Image.Resampling.NEAREST).save(
    PREVIEWS / "all_basic_modules_sheet_2x.png",
)

# Exact-footprint contact test. Modules are placed only at their complete
# dimensions; none are cropped, stretched, or partially pasted.
placements = [
    ("scrap_basic_3x2_01", 0, 0),
    ("scrap_basic_2x2_01", 3, 0),
    ("scrap_basic_1x3_01", 5, 0),
    ("scrap_basic_1x1_02", 6, 0),
    ("scrap_basic_1x2_01", 7, 0),
    ("scrap_basic_1x1_03", 6, 1),
    ("scrap_basic_3x1_01", 0, 2),
    ("scrap_basic_2x1_02", 3, 2),
    ("scrap_basic_1x1_04", 6, 2),
    ("scrap_basic_2x2_02", 0, 3),
    ("scrap_basic_3x1_02", 2, 3),
    ("scrap_basic_1x1_01", 5, 3),
    ("scrap_basic_2x1_01", 6, 3),
]
mosaic = Image.new("RGBA", (8 * CELL, 5 * CELL), BLACK_PLUM)
for name, cell_x, cell_y in placements:
    module = modules[name]
    right = cell_x * CELL + module.width
    bottom = cell_y * CELL + module.height
    if right > mosaic.width or bottom > mosaic.height:
        raise RuntimeError(f"Placement would crop {name}.")
    mosaic.alpha_composite(module, (cell_x * CELL, cell_y * CELL))
mosaic.save(PREVIEWS / "full_shape_placement_test.png")
mosaic.resize((mosaic.width * 2, mosaic.height * 2), Image.Resampling.NEAREST).save(
    PREVIEWS / "full_shape_placement_test_2x.png",
)

contract = {
    "cellPixels": CELL,
    "assetRole": "opaque collision-ground modules; no separate fill layer",
    "family": "quiet dark ImageGen base modules",
    "preservesExistingV3": True,
    "creativeSourcePolicy": (
        "each non-master asset has its own built-in ImageGen source; "
        "no procedurally drawn interiors"
    ),
    "allowedPostprocess": [
        "chroma removal",
        "alpha-bounds crop",
        "resize to exact whole-cell dimensions",
        "five-color palette quantization",
        "three-pixel connector normalization from approved master",
    ],
    "placementRulesForRuntime": [
        "place a module only when its complete cell footprint fits",
        "never clip or crop a module",
        "fall back to a smaller fitting module",
        "avoid edge-adjacent repetition of the same asset id when alternatives fit",
    ],
    "palette": [list(color) for color in PALETTE],
    "assets": [
        {
            "name": name,
            "units": [units_wide, units_high],
            "pixels": [units_wide * CELL, units_high * CELL],
            "provenance": provenance,
        }
        for name, units_wide, units_high, provenance in SPECS
    ],
}
(ROOT / "basic-family-contract.json").write_text(
    json.dumps(contract, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
