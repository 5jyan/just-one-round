"""Turn the generated six-pose worm strip into a crisp runtime atlas."""
from pathlib import Path
from PIL import Image

SOURCE = Path(__file__).with_name("raw-generated-sheet.png")
OUTPUT = Path(__file__).with_name("worm_crawler_sheet.png")
FRAME_COUNT = 6
SOURCE_FRAME = (2172 // FRAME_COUNT, 724)
RUNTIME_FRAME = (96, 48)
ART_CROP_TOP = 250
ART_CROP_BOTTOM = 480

image = Image.open(SOURCE).convert("RGBA")
if image.size != SOURCE_FRAME[:1] + (SOURCE_FRAME[1],):
    expected = (SOURCE_FRAME[0] * FRAME_COUNT, SOURCE_FRAME[1])
    if image.size != expected:
        raise ValueError(f"expected {expected}, got {image.size}")

atlas = Image.new("RGBA", (RUNTIME_FRAME[0] * FRAME_COUNT, RUNTIME_FRAME[1]), (0, 0, 0, 0))
for index in range(FRAME_COUNT):
    frame = image.crop(
        (
            index * SOURCE_FRAME[0],
            ART_CROP_TOP,
            (index + 1) * SOURCE_FRAME[0],
            ART_CROP_BOTTOM,
        )
    )
    # Crop away the generator's oversized transparent gutters so the worm has
    # enough vertical presence at runtime. The same crop is used for every
    # pose, preserving the visible up/down motion between frames.
    frame = frame.resize(RUNTIME_FRAME, Image.Resampling.LANCZOS)
    atlas.alpha_composite(frame, (index * RUNTIME_FRAME[0], 0))
atlas.save(OUTPUT, optimize=True)
print(OUTPUT)
