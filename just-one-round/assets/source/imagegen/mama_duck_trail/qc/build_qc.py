from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[5]
RUNTIME = ROOT / "assets/images/mama_duck_trail"
OUTPUT = Path(__file__).with_name("mama_duck_trail_5x7_qc.png")

canvas = Image.new("RGBA", (360, 640), (23, 45, 56, 255))
tiles = Image.open(RUNTIME / "marsh_tiles_atlas.png").convert("RGBA")
prints = Image.open(RUNTIME / "footprints_atlas.png").convert("RGBA")
duckling = Image.open(RUNTIME / "duckling_idle.png").convert("RGBA")
mother = Image.open(RUNTIME / "mother_duck_idle.png").convert("RGBA")
wolf = Image.open(RUNTIME / "wolf_idle.png").convert("RGBA")

tile_size = 48
board_x = 60
board_y = 154
tile_order = [
    0, 1, 2, 3, 4,
    2, 3, 4, 0, 5,
    1, 4, 0, 6, 2,
    3, 0, 7, 1, 4,
    4, 1, 2, 0, 5,
    2, 3, 0, 6, 1,
    3, 4, 1, 2, 8,
]

for index, tile_index in enumerate(tile_order):
    row, col = divmod(index, 5)
    source_row, source_col = divmod(tile_index, 3)
    tile = tiles.crop(
        (
            source_col * 24,
            source_row * 24,
            (source_col + 1) * 24,
            (source_row + 1) * 24,
        )
    ).resize((tile_size, tile_size), Image.Resampling.NEAREST)
    canvas.alpha_composite(tile, (board_x + col * tile_size, board_y + row * tile_size))

route = [
    (6, 0, 0),
    (6, 1, 1),
    (5, 1, 0),
    (4, 1, 1),
    (4, 2, 1),
    (4, 3, 0),
    (3, 3, 0),
    (2, 3, 1),
    (2, 4, 0),
    (1, 4, 0),
]
for row, col, direction_col in route:
    footprint = prints.crop(
        (direction_col * 16, 0, (direction_col + 1) * 16, 16)
    ).resize((32, 32), Image.Resampling.NEAREST)
    x = board_x + col * tile_size + 8
    y = board_y + row * tile_size + 8
    canvas.alpha_composite(footprint, (x, y))

canvas.alpha_composite(
    mother.resize((64, 64), Image.Resampling.NEAREST),
    (70, 70),
)
canvas.alpha_composite(
    wolf.resize((96, 96), Image.Resampling.NEAREST),
    (215, 45),
)
canvas.alpha_composite(
    duckling.resize((64, 64), Image.Resampling.NEAREST),
    (72, 508),
)

canvas.save(OUTPUT)
