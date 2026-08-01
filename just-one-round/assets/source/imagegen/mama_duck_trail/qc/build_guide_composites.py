from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[5]
RUNTIME = ROOT / "assets/images/mama_duck_trail"
SOURCE = ROOT / "assets/source/imagegen/mama_duck_trail"
BOARD_X = 0
BOARD_Y = 68
TILE = 72
FOOTPRINT_SIZE = 48
ROUTE = [
    (6, 0, 0),
    (5, 0, 1),
    (5, 1, 0),
    (4, 1, 1),
    (4, 2, 0),
    (3, 2, 1),
    (3, 3, 0),
    (2, 3, 0),
]


def frame(atlas: Image.Image, cell: int, columns: int, cell_size: int) -> Image.Image:
    row, column = divmod(cell, columns)
    return atlas.crop(
        (
            column * cell_size,
            row * cell_size,
            (column + 1) * cell_size,
            (row + 1) * cell_size,
        )
    )


def base_scene() -> tuple[Image.Image, Image.Image]:
    background = Image.open(RUNTIME / "marsh_background.png").convert("RGBA").resize(
        (360, 840), Image.Resampling.NEAREST
    )
    canvas = background.crop((0, 100, 360, 740))
    terrain = Image.open(RUNTIME / "marsh_board_map.png").convert("RGBA")
    footprints = Image.open(RUNTIME / "footprints_atlas.png").convert("RGBA")
    canvas.alpha_composite(
        terrain.resize((TILE * 5, TILE * 7), Image.Resampling.NEAREST),
        (BOARD_X, BOARD_Y),
    )
    return canvas, footprints


def place_prints(
    canvas: Image.Image,
    footprints: Image.Image,
    atlas_row: int,
    count: int,
) -> None:
    inset = (TILE - FOOTPRINT_SIZE) // 2
    for row, column, direction in ROUTE[:count]:
        footprint = frame(
            footprints,
            atlas_row * 4 + direction,
            4,
            FOOTPRINT_SIZE,
        )
        canvas.alpha_composite(
            footprint,
            (
                BOARD_X + column * TILE + inset,
                BOARD_Y + row * TILE + inset,
            ),
        )


def character(name: str, size: int) -> Image.Image:
    return Image.open(RUNTIME / name).convert("RGBA").resize(
        (size, size), Image.Resampling.NEAREST
    )


def cell_sprite_position(row: int, column: int, size: int) -> tuple[int, int]:
    return (
        BOARD_X + column * TILE + (TILE - size) // 2,
        BOARD_Y + row * TILE + (TILE - size) // 2,
    )


def build_guides() -> None:
    destination = ROUTE[-1][:2]

    observe, observe_prints = base_scene()
    place_prints(observe, observe_prints, 0, len(ROUTE))
    observe.alpha_composite(
        character("mother_duck_idle.png", 72),
        cell_sprite_position(*destination, 72),
    )
    observe.save(RUNTIME / "guide_observe.png")

    recall, recall_prints = base_scene()
    place_prints(recall, recall_prints, 1, 4)
    recall.alpha_composite(
        character("mother_duck_idle.png", 72),
        cell_sprite_position(*destination, 72),
    )
    recall.save(RUNTIME / "guide_recall.png")

    failure, failure_prints = base_scene()
    place_prints(failure, failure_prints, 0, len(ROUTE))
    wrong_row, wrong_column = 4, 3
    wrong = frame(failure_prints, 8, 4, FOOTPRINT_SIZE)
    failure.alpha_composite(
        wrong,
        cell_sprite_position(wrong_row, wrong_column, FOOTPRINT_SIZE),
    )
    wolf_sheet = Image.open(RUNTIME / "wolf_failure_sheet.png").convert("RGBA")
    wolf = frame(wolf_sheet, 2, 3, 96)
    failure.alpha_composite(
        wolf,
        cell_sprite_position(wrong_row, wrong_column, 96),
    )
    failure.save(RUNTIME / "guide_failure.png")

    hero, hero_prints = base_scene()
    place_prints(hero, hero_prints, 1, 4)
    hero.alpha_composite(
        character("mother_duck_idle.png", 72),
        cell_sprite_position(*destination, 72),
    )
    hero.save(RUNTIME / "home_gameplay_hero.png")


if __name__ == "__main__":
    build_guides()
