#!/usr/bin/env python3
"""Build nearest-neighbor viewport composites for visual asset QA."""

from __future__ import annotations

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[6]
BACKGROUND = ROOT / "assets/images/western_duel/background/saloon_day_180x480.png"
OPPONENT = ROOT / "assets/images/western_duel/first_person/opponent_idle/frame_01.png"
PLAYER = ROOT / "assets/images/western_duel/first_person/player_action_recoil/frame_01.png"
OUTPUT = ROOT / "assets/source/imagegen/western_duel/v1/qc"


def main() -> None:
    bg = Image.open(BACKGROUND).convert("RGB").resize((360, 960), Image.Resampling.NEAREST)
    opponent = Image.open(OPPONENT).convert("RGBA").resize((112, 160), Image.Resampling.NEAREST)
    player = Image.open(PLAYER).convert("RGBA").resize((192, 160), Image.Resampling.NEAREST)
    OUTPUT.mkdir(parents=True, exist_ok=True)

    for height in (640, 720, 800):
        top = (960 - height) // 2
        frame = bg.crop((0, top, 360, top + height)).convert("RGBA")
        opponent_y = 270 + (height - 720) // 2
        frame.alpha_composite(opponent, (124, opponent_y))
        player_y = height - 160
        frame.alpha_composite(player, (84, player_y))
        frame.convert("RGB").save(OUTPUT / f"western_duel_first_person_360x{height}.png")


if __name__ == "__main__":
    main()
