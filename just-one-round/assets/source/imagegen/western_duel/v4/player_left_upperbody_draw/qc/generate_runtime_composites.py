#!/usr/bin/env python3
"""Compose the six runtime player poses over the approved duel viewport."""

from pathlib import Path
import math

from PIL import Image


ROOT = Path(__file__).resolve().parents[7]
PLAYER = ROOT / "assets/images/western_duel/first_person/player_left_upperbody_draw_v4/sheet-transparent.png"
OPPONENT = ROOT / "assets/images/western_duel/first_person/opponent_idle_close/frame_01.png"
BACKGROUND = ROOT / "assets/images/western_duel/background/saloon_day_180x480.png"
FLASH = ROOT / "assets/images/western_duel/fx/muzzle_flash/frame_04.png"
OUTPUT = Path(__file__).resolve().parent


def main() -> None:
    player_atlas = Image.open(PLAYER).convert("RGBA")
    background = Image.open(BACKGROUND).convert("RGB").resize(
        (360, 960), Image.Resampling.NEAREST
    )
    opponent = Image.open(OPPONENT).convert("RGBA").resize(
        (112, 160), Image.Resampling.NEAREST
    )
    flash = Image.open(FLASH).convert("RGBA").resize(
        (56, 56), Image.Resampling.NEAREST
    )
    player_x_offsets = (-66, -48, -30, -12, 0, 0)
    player_y_progress = (1, 0.8, 0.6, 0.3, 0, 0)

    for height in (640, 667, 720, 738, 780, 800):
        background_top = (960 - height) // 2
        opponent_y = 270 + (height - 720) // 2
        contact = Image.new("RGBA", (360 * 3, height * 2), (0, 0, 0, 0))
        for frame_index in range(6):
            row, column = divmod(frame_index, 3)
            cell = player_atlas.crop(
                (column * 180, row * 280, (column + 1) * 180, (row + 1) * 280)
            ).resize((360, 560), Image.Resampling.NEAREST)
            view = background.crop((0, background_top, 360, background_top + height))
            view = view.convert("RGBA")
            view.alpha_composite(opponent, (205, opponent_y))
            original_bottom = height // 2 - 160 + 226 * 2
            ready_drop = math.floor(
                max(0, height - original_bottom - 16) / 2
            ) * 2
            player_offset_y = math.floor(
                ready_drop * player_y_progress[frame_index] / 2 + 0.5
            ) * 2
            player_y = math.floor(height / 2 - 160 + player_offset_y + 0.5)
            view.alpha_composite(
                cell, (-60 + player_x_offsets[frame_index], player_y)
            )
            if frame_index == 4:
                view.alpha_composite(
                    flash,
                    (round(261 - flash.width / 2), round(height / 2 - 10 - flash.height / 2)),
                )
            contact.alpha_composite(view, (column * 360, row * height))

        contact.save(OUTPUT / f"western_duel_v4_360x{height}.png")


if __name__ == "__main__":
    main()
