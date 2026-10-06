#!/usr/bin/env python3
"""Reuse the accepted v12 deterministic cleanup/alignment for v13 art."""

import importlib.util
import json
import sys
from pathlib import Path

from PIL import Image

root = Path(__file__).resolve().parent
project = root.parents[5]
previous = root.parents[1] / "v12/player_forward_fall/build_v12_delivery.py"
spec = importlib.util.spec_from_file_location("western_v12_delivery", previous)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

module.ROOT = root
module.PROJECT = project
module.RAW = root / "raw_generated/player_forward_fall_v13_retry_raw.png"
module.PROMPT = root / "prompt-retry.txt"
module.QC_DIR = root / "qc"
module.DELIVERY = project / "assets/images/western_duel/first_person/player_forward_fall_v13"
module.V11_FRAME = project / "assets/images/western_duel/first_person/player_detail_idle_v11/frame_01.png"
module.IMAGEGEN_SOURCE = Path(
    "/Users/saulpark/.codex/generated_images/01a0e7e9-6965-7fd1-a6b0-3339f3ecf0fe/"
    "exec-b5fe239a-33f2-4dfe-8679-a6dd8294320a.png"
)
module.main()

# The initial square 4x2 sheet cleanly supplies the kneeling first five
# frames, but its long prone poses touch raw-cell edges. Finish from the
# separately generated 2x2 sheet with wider cells and one shared scale/root.
tail_path = root / "raw_generated/player_forward_fall_v13_tail_raw.png"
tail = module.clean_sheet(Image.open(tail_path).convert("RGBA"))[0]
tail.save(root / "tail-sheet-clean.png")
tail_cells = [
    tail.crop((col * tail.width // 2, row * tail.height // 2,
               (col + 1) * tail.width // 2, (row + 1) * tail.height // 2))
    for row in range(2) for col in range(2)
]
tail_bboxes = [module.bbox(cell) for cell in tail_cells]
kneel_bbox = module.bbox(Image.open(module.DELIVERY / "frame_05.png"))
first = tail_bboxes[0]
scale = (kneel_bbox[3] - kneel_bbox[1]) / (first[3] - first[1])
tx = (kneel_bbox[0] + kneel_bbox[2]) / 2 - (first[0] + first[2]) / 2 * scale
ty = kneel_bbox[3] - first[3] * scale
tail_output_bboxes = []
for index, (cell, box) in enumerate(zip(tail_cells[1:], tail_bboxes[1:]), 6):
    x0, y0, x1, y1 = box
    subject = cell.crop(box).resize(
        (round((x1-x0)*scale), round((y1-y0)*scale)), Image.Resampling.NEAREST)
    x = round(tx + x0 * scale)
    y = round(ty + y0 * scale)
    if x < 0 or y < 0 or x + subject.width > module.CELL_W or y + subject.height > module.CELL_H:
        raise ValueError(f"tail frame {index} overflows final cell: {(x,y,subject.size)}")
    output = Image.new("RGBA", (module.CELL_W, module.CELL_H))
    output.alpha_composite(subject, (x, y))
    output.save(module.DELIVERY / f"frame_{index:02d}.png")
    tail_output_bboxes.append(module.bbox(output))

frames = [Image.open(module.DELIVERY / f"frame_{index:02d}.png").convert("RGBA")
          for index in range(1, 9)]
module.write_atlas(frames, module.DELIVERY / "sheet-transparent.png", rows=4, cols=2)
module.write_gif(frames, module.DELIVERY / "animation.gif")
module.write_qc_contact_sheet(frames, module.QC_DIR / "contact-sheet.png")
module.write_gif(frames, module.QC_DIR / "animation.gif")

provenance = root / "provenance.json"
data = json.loads(provenance.read_text())
data["schema"] = "western_duel.player_forward_fall_v13.provenance.v1"
data["source"]["raw_tail_source"] = "/Users/saulpark/.codex/generated_images/01a0e7e9-6965-7fd1-a6b0-3339f3ecf0fe/exec-0789e697-e493-41e8-a716-c8f3e8368b13.png"
data["source"]["copied_tail_raw"] = str(tail_path.relative_to(project))
data["source"]["tail_raw_sha256"] = module.sha256(tail_path)
data["source"]["tail_cleaned_sha256"] = module.sha256(root / "tail-sheet-clean.png")
data["source"]["tail_prompt"] = str((root / "prompt-tail.txt").relative_to(project))
data["source"]["tail_prompt_sha256"] = module.sha256(root / "prompt-tail.txt")
data["layout"]["tail_source_grid"] = [2, 2]
data["layout"]["delivery_sources"] = ["retry_4x2"] * 5 + ["tail_2x2"] * 3
data["anchors"]["tail_source_bboxes"] = [list(box) for box in tail_bboxes]
data["anchors"]["tail_output_bboxes"] = [list(box) for box in tail_output_bboxes]
data["anchors"]["tail_common_scale"] = scale
data["anchors"]["tail_translation"] = [tx, ty]
data["anchors"]["output_bboxes"][5:] = [list(box) for box in tail_output_bboxes]
data["qc"]["source_edge_touch_frames"] = []
data["qc"]["output_edge_touch_frames"] = []
data["qc"]["output_widths"] = [module.bbox(frame)[2] - module.bbox(frame)[0] for frame in frames]
data["qc"]["output_heights"] = [module.bbox(frame)[3] - module.bbox(frame)[1] for frame in frames]
data["qc"]["max_output_width"] = max(data["qc"]["output_widths"])
data["qc"]["min_horizontal_margin"] = min(
    min(module.bbox(frame)[0], module.CELL_W - module.bbox(frame)[2])
    for frame in frames
)
data["qc"]["frame_sha256"] = [module.sha256(module.DELIVERY / f"frame_{index:02d}.png") for index in range(1,9)]
data["runtime"]["frame_duration_ms"] = [80, 80, 100, 160, 220, 100, 120, 100]
data["runtime"]["placement"]["fall_display_scale"] = 0.65
data["runtime"]["placement"]["fall_scale_anchor_source"] = [270, 306]
data["runtime"]["fall_travel"] = {"x": 45, "y": 40}
data["runtime"]["visual_contract"] = "kneel, hold, then collapse with arms trailing behind"
encoded = json.dumps(data, indent=2)
provenance.write_text(encoded)
(module.DELIVERY / "pipeline-meta.json").write_text(encoded)
