# Full kitchen gameplay scene — 2026-09-10

User approved full-screen reference: `codex-clipboard-633a30d0-abac-4ec4-a54e-995e4358c584.png`.
Built-in Image Gen edited that image into `clean-kitchen-master.png`.

Prompt: Precise-object-edit. Prepare the exact approved image as a clean
production background. Remove only the yellow snake, pizza, top HUD text and
numbers, and white exit symbol. Inpaint underlying kitchen and tiles. Preserve
portrait proportions, kitchen, board exterior coordinates, bottom cabinet trim,
rug, four cream arrow keys and their arrow symbols. No phone frame or margins.

`prepare_playfield.py` downsamples with nearest-neighbor to 360×764 and adapts
the existing apartment floor at source (36,112)-(324,592) to destination
(48,108)-(312,576). This preserves nine columns and fifteen rows matching the
game rules, instead of inheriting the reference illustration's sixteen rows.

Runtime output: `assets/images/midnight_snake/kitchen_playfield.png`.
Kitchen, board frame, lower cabinet, controls, and rug occupy one continuous
scene. Runtime sprites and HUD are independent live layers. Existing source
and apartment background remain available for the current guide/preview.
