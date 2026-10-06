# Western Duel Asset Production Contract

## Player-left unified quick-draw foreground (approved 2026-09-25; active v4)

- Keep the duel rules, reaction clock, ranking, saloon background, opponent assignment, and opponent animation assets unchanged. This v4 camera replaces the separate player body/hand v3 presentation only.
- Place the player's waist-up right side at screen-left, facing toward screen-right. Keep the hat and head visible along with shoulder, upper torso, belt, right-hip holster, and the physical right arm/hand/revolver. Do not show legs. The whole body/arm/hand/gun is one six-frame sprite; there is no detached player hand layer.
- Runtime atlas: `assets/images/western_duel/first_person/player_left_upperbody_draw_v4/sheet-transparent.png`; source and prompts live under `assets/source/imagegen/western_duel/v4/player_left_upperbody_draw/`. The raw grid is 3 columns × 2 rows; source cells are 180×280 and display at 360×560 with nearest-neighbor filtering.
- Image normalization deliberately foreshortens the side-profile sheet by `scale_x=0.75`, `scale_y=0.8`, then offsets it by `(30,4)` source pixels. This keeps the entire hat/holster contour inside the screen-left safe area while landing the firing-pose muzzle at source `(160.5,75)`. These values are recorded in `processed_180x280/pipeline-meta.json` and tested; they are a sprite-space transform, not camera motion.
- At 360×720, place the player atlas at `x=-60`, `y=height/2-160`; the player muzzle lands at screen `(261,height/2-10)`. Keep the 112×160 opponent at `x=205`, centered at x=261 with feet baseline y=430. This center-right lane matches the player's real right-hand muzzle while leaving a 43px right safe margin. At 360×640/720/800 the opponent keeps the same relative vertical anchor and all essential player artwork must remain visible.
- Frame order is ready → grip → clear holster → raise/aim → fire → recoil. Frame index 4 begins at the existing `0.21s` visual shot delay. Keep the existing detached muzzle flash; the player atlas contains no flash, smoke, bullet, or impact effects.
- Move opponent nameplate, firing flash, and hit spark with the x=205 opponent lane. Keep the `DRAW!` cue legible above that lane. Gameplay hitboxes, input timing, both-shots-before-impact, score, and result rules do not depend on sprite placement.
- Preserve all v3 and earlier assets for comparison/rollback. Do not delete, overwrite, or change the opponent, background, or detached FX sources.
- Verify all six poses and the resolved screen at 360×640, 360×720, and 360×800; the complete hat, profile, right hand, barrel, belt, and holster must not be unintentionally cropped or occluded. Verify the same layout in iOS Simulator.

## Historical: Right shoulder / waist foreground redesign (approved 2026-09-25; superseded by v4)

- Keep the fixed saloon background, duel rules, reaction clock, ranking, and opponent assignment. For the more distant over-shoulder perspective, show the opponent at 112×160, slightly left of center (x=104, feet y=430 at 360×720); this is visual depth only and does not affect gameplay.
- Change only the player's visual perspective: show a close foreground slice of the player's right shoulder through right waist/holster along the screen's right edge. Do not show the player's head or face. Keep the opponent readable; the right-side body may overlap only the opponent's lower-right silhouette, never the face or nameplate.
- Add a static foreground body panel at source cell `80×240`, rendered `160×480` at nearest-neighbor 2×, placed at `x=200` and bottom-anchored for 360×640/720/800 views. The intentional screen-edge composition must not cut the shoulder, elbow, holster, or other essential contour; only transparent padding may meet the viewport edge.
- Replace the active right-hand action with one six-frame `2×3` sheet, source cells `180×200`, rendered `360×400` at nearest-neighbor 2×. Frame order: ready/hand poised over the hip → grip → clear holster → raise and align → fire → recoil/settle. Keep the static holster on the body layer; the hand sheet contains no holster or belt hardware, and the muzzle flash remains detached. Position the hip poses over the right waist and raise the aim poses so frame 5's muzzle stays near the opponent center in all three supported heights. The forearm may naturally continue beyond the right edge during aim/fire; the muzzle, hand, and revolver must remain fully visible.
- The fifth frame is the firing pose and begins at the existing `0.21s` visual shot delay. The input-time score, 1,500ms reaction window, one-shot FX policy, and both-shots-before-impact rule are unchanged.
- Create source art and prompts under `assets/source/imagegen/western_duel/v3/`; add runtime art only under `assets/images/western_duel/first_person/player_right_body_v3/` and `player_right_hand_draw_v3/`. Keep v1/v2 sources and runtime assets intact for comparison/rollback.
- Validate the full composite at 360×640, 360×720, and 360×800 in ready, every draw frame, fire/flash, recoil, and resolved outcome. Verify opponent face, nickname, DRAW signal, muzzle, hand, holster, and shoulder are not unintentionally clipped or occluded; only the action sleeve may continue off the right/bottom edge. Runtime must read the hand atlas as 3 columns × 2 rows.

## Close opponent and right-hand quick-draw pass (approved 2026-09-25)

- Keep the existing first-person camera, saloon background, controls, 1,500 ms reaction window, tap-time score, opponent assignment, and ranking rules. This pass changes visual scale and the draw/fire presentation only.
- Reprocess the preserved opponent idle, draw/fire, and hit/fall raw sheets into new `opponent_*_close` atlases: 128×184 source cell displayed at 128×184 logical pixels with nearest-neighbor filtering. At 360 logical width, place the opponent at x=116, feet y=430 (y=246 at 360×720); this is roughly 15% larger than the previous 112×160 presentation.
- Replace the active two-hand player foreground with one right hand and one holstered period revolver. Create a separate waiting frame and a continuous six-frame grip → draw → aim → fire → recoil → recover action. Use 180×100 source cells displayed at 360×200, anchored to the bottom of the viewport; keep the left half clear while waiting. Store new prompts and raw generations under `assets/source/imagegen/western_duel/v2/right_hand/` and runtime atlases under `assets/images/western_duel/first_person/player_right_hand_*`.
- A tap still records reaction time immediately. The draw and muzzle flash are visual follow-through; show the flash at the firing frame and delay any impact until both visual shots have appeared. Preserve the existing old opponent and player sprites for comparison/rollback; do not delete them.
- Verify 360×640/720/800 compositions and a real Simulator capture: the name and DRAW! signal must not cover the opponent's face, and the new right-hand sprite must not cover the central opponent lane before firing.

## Opponent face-clarity pass (2026-09-24)

- User-approved exception to the 2-logical-pixel foreground grid: the opponent's eyes, nose, and moustache may use finer 1-logical-pixel marks so the face reads at its existing on-screen size. The saloon, player foreground, and effects keep their original pixel scale.
- Reprocess the preserved high-resolution `first_person/opponent_idle`, `opponent_draw_fire`, and `opponent_hit_fall` raw sheets with the existing nearest-neighbor processor into `assets/images/western_duel/first_person/opponent_*_detail/`. Each new source cell is 112×160 and each runtime frame remains 112×160; the runtime target rectangle, position, feet anchor, frame count/order, timing, hitbox, and duel rules do not change.
- The original 56×80 runtime sheets remain intact for comparison and rollback. The three `*_detail` sheets are the active gameplay assets.

- Approved: 2026-09-24
- Creative source: ChatGPT Images web UI fallback. The requested `chatgpt-web-image-mcp` connector was available but returned an automation error for generation; prompts and raw outputs are preserved under `assets/source/imagegen/western_duel/v1/`.
- Direction: serious, cinematic classic Western; this game uses an adult, grounded visual language instead of the project's usual mascot-like house direction.
- View: fixed 2D first-person duel on a 360-logical-pixel-wide portrait screen. The opponent is a centered, front-facing full-body figure; the player's hands and revolver occupy the lower foreground; the saloon is a front-facing background.
- Foreground art pixel: approximately 2×2 logical pixels. Use nearest-neighbor filtering for every raster layer.
- First-person source root: `assets/source/imagegen/western_duel/v1/first_person/`. Keep the previous `master_character/` specimen as reference only; do not overwrite or delete it.
- Opponent runtime cell: 56×80 source pixels displayed at 112×160. Anchor at bottom center; feet baseline remains stable across grounded actions.
- Opponent base pose: adult, front-facing toward the camera. No runtime pose reversal or role swap is permitted.
- Opponent body sheets: idle 2×2/4, draw-fire 2×4/8, hit-fall 2×3/6, result 2×2/4. Each grid cell is exactly 56×80 source pixels.
- Player foreground runtime cell: 96×80 source pixels displayed at 192×160. Anchor at bottom center; wrists and revolver stay within the lower foreground safe area.
- Player foreground sheets: ready 1×2/2, draw 2×2/4, fire-recoil 2×3/6, result 2×2/4. Each grid cell is exactly 96×80 source pixels.
- Detached effects: separate opponent/player muzzle-flash, hit, miss, and dust FX sheets. Muzzle flash for each shooter must be an independently addressable one-shot event and render exactly once per round.
- Background: 180×480 source displayed at 360×960. Safe core `[0,0,360,640]`; authored world rectangle `[0,-160,360,960]`; target viewports 360×640, 360×720, and 360×800. Compose a centered saloon door/sign and an unobstructed central lane for the opponent.
- Composition anchors at 360×720: opponent center x=`180`, feet baseline y=`430`; player foreground bottom y=`720`; `DRAW!` center must not cover the opponent's face or the revolver.
- Layer contract: `background → opponent → nameplate/signal → bullet/flash/hit FX → player foreground → result HUD`. Camera position, zoom, and rotation are fixed through measurement and both muzzle flashes; defeat tilt is allowed only after both shots and the outcome are resolved.
- Palette: faded ochre, dusty brown, rust red, muted teal; dark plum-brown outline; strong dry noon light.
- Forbidden: juvenile or mascot-like proportions, comedic expression, any orientation other than front-facing toward the camera, runtime pose reversal, fantasy gear, modern weapons, painterly smoothing, 3D rendering, vector rendering, text baked into raster art.
- Existing `mole_reaction` assets remain untouched. No active asset is replaced or deleted.

## First-person sheet contract

| Asset | Frame cell (source) | Grid / frames | Runtime frame | Anchor and invariant |
|---|---:|---:|---:|---|
| `opponent_idle` | 56×80 | 2×2 / 4 | 112×160 | bottom-center at x=180, feet baseline y=430; front-facing adult silhouette |
| `opponent_draw_fire` | 56×80 | 2×4 / 8 | 112×160 | same feet baseline; hand-to-revolver motion must read without changing body scale |
| `opponent_hit_fall` | 56×80 | 2×3 / 6 | 112×160 | fall remains within the opponent lane; no frame may touch the player foreground |
| `opponent_result` | 56×80 | 2×2 / 4 | 112×160 | outcome pose preserves the same head and feet anchors |
| `player_ready` | 96×80 | 1×2 / 2 | 192×160 | bottom-center; revolver stays below the central opponent torso |
| `player_draw` | 96×80 | 2×2 / 4 | 192×160 | hands rise from the lower edge without covering `DRAW!` |
| `player_fire_recoil` | 96×80 | 2×3 / 6 | 192×160 | one fire trigger maps to one muzzle-flash event; recoil does not move the camera |
| `player_result` | 96×80 | 2×2 / 4 | 192×160 | foreground may tilt only after both shots and outcome resolution |
| `muzzle_flash_opponent/player` | 16×16 | 2×2 / 4 | 32×32 | detached, independently triggered, exactly once for each shooter |
| `hit`, `miss_dust` | 16–32px square | 2×2–2×4 | 32–64px | hit only after both shots; miss lands on a non-character saloon prop |

Every sheet must use a flat solid `#FF00FF` chroma background in the raw source, retain transparent-safe padding inside its cell, and pass nearest-neighbor extraction without fractional coordinates. The legacy `master_character/` specimen remains an audit/reference artifact only; it is not a runtime input for this contract.

## Production order

1. Generate and approve one first-person opponent master specimen plus one player hands/revolver foreground specimen under `first_person/`.
2. Use the accepted specimens as identity and scale references for the separate action grids.
3. Generate the full-screen authored saloon background and detached FX.
4. Chroma-key, extract, align, and inspect all sheets with strict QC. Verify that each shooter's muzzle flash has one triggerable event and no duplicate frame playback.
5. Produce 360×640, 360×720, and 360×800 first-person composite previews before runtime integration.

## Generated first-person pack

- Opponent master, idle, draw/fire, and hit/fall sheets are exported under `assets/images/western_duel/first_person/`. Their original generated images and prompts are retained under `assets/source/imagegen/western_duel/v1/first_person/`.
- The player master and six-frame ready→aim→fire→recover sequence are exported under `assets/images/western_duel/first_person/`; the sequence is one atlas, with action clips selected by frame index rather than duplicated files.
- The saloon source plate is preserved at `assets/source/imagegen/western_duel/v1/background/saloon_raw.png`; its centered 180×480 nearest-neighbor crop is `assets/images/western_duel/background/saloon_day_180x480.png`.
- Four-frame detached muzzle-flash, hit-spark, and miss-dust atlases are under `assets/images/western_duel/fx/`. Both shooters can trigger the same flash art at their own muzzle anchors as separate one-shot events.
- All generated character/effect atlases pass extraction checks for expected frame count, empty frames, and output edge contact. Background dimensions and target aspect also pass. QA composites for 360×640, 360×720, and 360×800 are under `assets/source/imagegen/western_duel/v1/qc/`.
- The v1 runtime now loads the background, opponent idle/draw/fall, player foreground/recoil, and three detached FX atlases. The future `mole_reaction` slot replacement is expressed in the migration while historical mole IDs and art remain intact.
- Separate opponent/player result atlases are deferred for v1. The existing draw and final fall frames cover the initial result states; defeat uses a camera tilt only after both firing events. Asset QA composites are staged art proofs, not direct runtime captures.
