"""Prepare the reviewed heavyweight hitter sheets for Sprite Forge."""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/imagegen/ten_pitch_slugger/slugger_v3"
GENERATED = Path.home() / ".codex/generated_images/01a0c149-8b79-78c1-b3f6-ab9d38d50ec4"
FILES = {
    "idle": ("exec-39ad4866-77fe-4a09-bc63-ac7703669c95.png", 2, 3),
    "swing": ("exec-57f29d95-968d-455f-8071-62a8ac561479.png", 4, 4),
    "whiff": ("exec-3113ad6f-4090-4223-89d2-9f4c7deb69e8.png", 4, 3),
    "result": ("exec-dc454e47-dc0e-4da0-a89a-eeca86be012a.png", 4, 2),
}
RUNTIME = ROOT / "assets/images/ten_pitch_slugger"
BASELINE = 226

for action, (filename, columns, rows) in FILES.items():
    directory = SOURCE / action
    directory.mkdir(parents=True, exist_ok=True)
    image = Image.open(GENERATED / filename).convert("RGBA")

    # Image Gen occasionally returns a half-pixel grid. Center-crop only the
    # remainder so every source cell is an exact integer rectangle.
    width = image.width - image.width % columns
    height = image.height - image.height % rows
    left = (image.width - width) // 2
    top = (image.height - height) // 2
    image = image.crop((left, top, left + width, top + height))
    image.save(directory / "raw-alpha.png")

    magenta = Image.new("RGBA", image.size, (255, 0, 255, 255))
    magenta.alpha_composite(image)
    magenta.convert("RGB").save(directory / "raw.png")

    processed = directory / "processed/sheet-transparent.png"
    if not processed.exists():
        continue

    sheet = Image.open(processed).convert("RGBA")
    cell_width = sheet.width // columns
    cell_height = sheet.height // rows
    grounded = Image.new("RGBA", sheet.size)
    for index in range(columns * rows):
        x = index % columns * cell_width
        y = index // columns * cell_height
        frame = sheet.crop((x, y, x + cell_width, y + cell_height))
        alpha_box = frame.getchannel("A").point(
            lambda value: 255 if value > 8 else 0
        ).getbbox()
        if alpha_box is None:
            raise ValueError(f"empty {action} frame {index}")
        shift_y = BASELINE - alpha_box[3]
        grounded.alpha_composite(frame, (x, y + shift_y))

    pixels = grounded.load()
    for y in range(grounded.height):
        for x in range(grounded.width):
            red, green, blue, alpha = pixels[x, y]
            if (
                alpha > 8
                and red > 170
                and blue > 130
                and green < 100
                and blue > red * 0.65
            ):
                pixels[x, y] = (red, green, blue, 0)

    grounded.save(processed)
    grounded.save(RUNTIME / f"batter_slugger_{action}_v3.png")
