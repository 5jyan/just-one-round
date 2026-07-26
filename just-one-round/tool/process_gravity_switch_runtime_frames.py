from pathlib import Path
from typing import List, Optional, Tuple

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
FRAME_ROOT = (
    ROOT / "assets/source/runtime_capture/gravity_switch/frames"
)
RUNTIME_ROOT = ROOT / "assets/images/gravity_switch_v2"
FONT_PATH = ROOT / "assets/fonts/Galmuri11-Bold.ttf"

FRAME_DURATION_MS = 100
MAIN_CROP = (0, 80, 360, 542)
GUIDE_CROP = (0, 250, 360, 518)
OBSTACLE_CROP = (0, 80, 360, 348)
LATE_CROP = (0, 80, 360, 348)


def load_frames(
    scenario: str, *, limit: Optional[int] = None
) -> List[Image.Image]:
    paths = sorted((FRAME_ROOT / scenario).glob("*.png"))
    if limit is not None:
        paths = paths[:limit]
    if not paths:
        raise ValueError(f"No runtime frames found for {scenario}.")
    return [Image.open(path).convert("RGB") for path in paths]


def crop_frames(
    frames: List[Image.Image], box: Tuple[int, int, int, int]
) -> List[Image.Image]:
    return [frame.crop(box) for frame in frames]


def add_main_hud(frames: List[Image.Image]) -> List[Image.Image]:
    font = ImageFont.truetype(str(FONT_PATH), 29)
    result: List[Image.Image] = []
    for index, source in enumerate(frames):
        frame = source.copy()
        draw = ImageDraw.Draw(frame)
        label = f"{index / 10:.2f}"
        bounds = draw.textbbox((0, 0), label, font=font, stroke_width=0)
        width = bounds[2] - bounds[0]
        x = (frame.width - width) // 2
        draw.text(
            (x + 3, 17 + 3),
            label,
            font=font,
            fill=(2, 6, 23),
        )
        draw.text((x, 17), label, font=font, fill="white")
        result.append(frame)
    return result


def add_loop_fade(
    frames: List[Image.Image], count: int = 4
) -> List[Image.Image]:
    if len(frames) < count * 2:
        return frames
    result = [frame.copy() for frame in frames]
    for index in range(count):
        start_alpha = int(180 * (count - index - 1) / count)
        end_alpha = int(180 * (index + 1) / count)
        result[index] = Image.blend(
            Image.new("RGB", result[index].size, "black"),
            result[index],
            start_alpha / 255,
        )
        end_index = len(result) - count + index
        result[end_index] = Image.blend(
            result[end_index],
            Image.new("RGB", result[end_index].size, "black"),
            end_alpha / 255,
        )
    return result


def add_collision_result(frames: List[Image.Image]) -> List[Image.Image]:
    title_font = ImageFont.truetype(str(FONT_PATH), 30)
    detail_font = ImageFont.truetype(str(FONT_PATH), 13)
    final_pixels = frames[-1].tobytes()
    collision_index = next(
        index
        for index, frame in enumerate(frames)
        if frame.tobytes() == final_pixels
    )
    result: List[Image.Image] = []
    for index, source in enumerate(frames):
        frame = source.copy()
        if index >= collision_index:
            overlay = Image.new("RGBA", frame.size, (255, 53, 101, 54))
            frame = Image.alpha_composite(frame.convert("RGBA"), overlay).convert(
                "RGB"
            )
            draw = ImageDraw.Draw(frame)
            title = "GAME OVER"
            title_bounds = draw.textbbox((0, 0), title, font=title_font)
            title_x = (frame.width - (title_bounds[2] - title_bounds[0])) // 2
            draw.text(
                (title_x + 3, 44 + 3),
                title,
                font=title_font,
                fill=(110, 18, 62),
            )
            draw.text(
                (title_x, 44),
                title,
                font=title_font,
                fill=(255, 216, 74),
            )
            detail = "한 번 닿으면 즉시 종료"
            detail_bounds = draw.textbbox((0, 0), detail, font=detail_font)
            detail_x = (
                frame.width - (detail_bounds[2] - detail_bounds[0])
            ) // 2
            draw.text(
                (detail_x, frame.height - 29),
                detail,
                font=detail_font,
                fill="white",
            )
        result.append(frame)
    return result


def save_animation(name: str, frames: List[Image.Image]) -> None:
    output = RUNTIME_ROOT / name
    frames[0].save(
        output,
        save_all=True,
        append_images=frames[1:],
        duration=FRAME_DURATION_MS,
        loop=0,
        lossless=True,
        quality=100,
        method=0,
    )
    print(f"{output.relative_to(ROOT)}: {len(frames)} frames")


def main() -> None:
    RUNTIME_ROOT.mkdir(parents=True, exist_ok=True)

    control = load_frames("control")
    obstacle = load_frames("obstacle")
    hard = load_frames("hard")
    collision = load_frames("collision")

    save_animation(
        "gravity_runtime_main.webp",
        add_loop_fade(add_main_hud(crop_frames(control, MAIN_CROP))),
    )
    save_animation(
        "gravity_runtime_control.webp",
        add_loop_fade(crop_frames(control, GUIDE_CROP)),
    )
    save_animation(
        "gravity_runtime_obstacle.webp",
        add_loop_fade(crop_frames(obstacle[4:], OBSTACLE_CROP)),
    )
    save_animation(
        "gravity_runtime_hard.webp",
        add_loop_fade(crop_frames(hard[8:], LATE_CROP)),
    )
    save_animation(
        "gravity_runtime_collision.webp",
        add_loop_fade(add_collision_result(crop_frames(collision, GUIDE_CROP))),
    )


if __name__ == "__main__":
    main()
