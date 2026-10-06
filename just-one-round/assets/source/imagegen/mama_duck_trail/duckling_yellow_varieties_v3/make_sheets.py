"""Fit generated scarf and mud details to each accepted duckling pose."""

from pathlib import Path

from PIL import Image


SOURCE = Path(__file__).resolve().parent
RUNTIME = SOURCE.parents[3] / "images/mama_duck_trail"
CELL = 72


def detail(path: Path, crop: tuple[int, int, int, int], size: tuple[int, int]) -> Image.Image:
    image = Image.open(path).convert("RGBA").crop(crop)
    image = image.resize(size, Image.Resampling.NEAREST)
    image.putalpha(image.getchannel("A").point(lambda alpha: 255 if alpha >= 128 else 0))
    return image


scarf = detail(SOURCE / "scarf_raw.png", (470, 519, 784, 740), (12, 8))
mud_source = SOURCE.parent / "duckling_yellow_varieties_v2/mud_raw.png"
cheek = detail(mud_source, (610, 410, 775, 540), (4, 3))
wing = detail(mud_source, (800, 540, 970, 695), (6, 4))

# Coordinates are cell-local. Body and wing poses differ between actions.
SCARF_POSITIONS = {
    "walk": [(30, 49), (29, 49), (30, 49), (30, 49), (29, 49), (30, 49)],
    "cheer": [(30, 49), (30, 49), (30, 48), (30, 48), (30, 49), (30, 49)],
}
MUD_POSITIONS = {
    "walk": [
        ((24, 43), (43, 49)), ((23, 43), (43, 49)), ((24, 43), (43, 49)),
        ((24, 43), (42, 48)), ((23, 43), (43, 49)), ((24, 43), (42, 49)),
    ],
    "cheer": [
        ((24, 43), (43, 49)), ((23, 43), (48, 44)), ((24, 43), (50, 42)),
        ((24, 43), (51, 41)), ((24, 43), (48, 45)), ((24, 43), (43, 49)),
    ],
}


def mud_on_yellow(cell: Image.Image, mark: Image.Image, xy: tuple[int, int]) -> None:
    """Keep the generated mark on yellow feathers, never in empty space."""
    left, top = xy
    for y in range(mark.height):
        for x in range(mark.width):
            r, g, b, a = mark.getpixel((x, y))
            if a == 0:
                continue
            target = cell.getpixel((left + x, top + y))
            if not (target[3] and target[0] > 185 and target[1] > 115 and target[2] < 165):
                continue
            # Muted ochre brown, derived from the generated mud source.
            cell.putpixel((left + x, top + y), (round(r * .82 + 40), round(g * .73 + 34), round(b * .7 + 10), 255))


for action in ("walk", "cheer"):
    base = Image.open(RUNTIME / f"duckling_{action}_sheet.png").convert("RGBA")
    for variant in ("grubby", "scarf"):
        result = Image.new("RGBA", base.size)
        for frame in range(6):
            x, y = frame % 3 * CELL, frame // 3 * CELL
            cell = base.crop((x, y, x + CELL, y + CELL))
            if variant == "scarf":
                cell.alpha_composite(scarf, SCARF_POSITIONS[action][frame])
            else:
                cheek_xy, wing_xy = MUD_POSITIONS[action][frame]
                mud_on_yellow(cell, cheek, cheek_xy)
                mud_on_yellow(cell, wing, wing_xy)
            result.paste(cell, (x, y))
        result.save(RUNTIME / f"duckling_{variant}_{action}_sheet.png")
