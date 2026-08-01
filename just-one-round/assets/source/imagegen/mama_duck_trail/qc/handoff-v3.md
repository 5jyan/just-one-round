# 엄마, 어디가 — Asset Handoff v3

## 변경 요약

- 엄마 오리와 아기 오리를 더 선명하고 디테일한 픽셀 아트로 교체했다.
- 진흙, 풀, 물웅덩이 타일을 3×3 변형으로 확장해 반복감을 줄였다.
- 갈대 6종을 추가하고 보드 가장자리에 불규칙하게 배치했다.
- 달빛 습지 배경을 추가해 HUD와 보드 바깥의 빈 공간을 채웠다.
- LIVES 아래 아기 오리 얼굴을 20×20 원본, 40×40 화면 크기로 확대했다.
- 발자국과 게임 규칙, 이동 경로 생성, 난이도 진행 방식은 변경하지 않았다.

## 런타임 규격

| 에셋 | 파일 | 원본 규격 | 화면 규격 |
| --- | --- | --- | --- |
| 아기 오리 걷기 | `duckling_walk_sheet.png` | 108×72, 36px 셀 2×3 | 72×72 |
| 아기 오리 기쁨 | `duckling_cheer_sheet.png` | 108×72, 36px 셀 2×3 | 72×72 |
| 엄마 오리 걷기 | `mother_duck_walk_sheet.png` | 108×72, 36px 셀 2×3 | 72×72 |
| 엄마 오리 포옹 | `mother_duck_hug.png` | 36×36 | 72×72 |
| 습지 타일 | `marsh_tiles_atlas.png` | 108×108, 36px 셀 3×3 | 72×72 |
| 갈대 | `marsh_reeds_atlas.png` | 72×48, 24px 셀 2×3 | 48×48 |
| 습지 배경 | `marsh_background.png` | 180×320 | 360×640 |
| 목숨 얼굴 | `duckling_life_face.png` | 20×20 | 40×40 |

모든 런타임 에셋은 nearest-neighbor 확대를 전제로 하며, 이미지 자체에 보간이나 흐림 효과를 넣지 않았다.

## 렌더 순서

`습지 배경 → 5×7 타일 → 갈대 → 발자국 → 캐릭터 → 하단 UI`

갈대는 경로와 캐릭터보다 뒤에 그려져 조작 가독성을 해치지 않는다.

## 생성 및 재현

- ImageGen 원본과 실제 프롬프트는 각 `*_v3/raw/` 및 `prompt-used.txt`에 보관했다.
- 투명화, 셀 분리, 팔레트 정리와 QC는 `generate2dsprite.py`로 수행했다.
- 활성 런타임 산출물은 `tool/process_mama_duck_trail_assets_v2.py`로 다시 만들 수 있다.
- 규격 메타데이터는 `asset-contract-v3.json`에 기록한다.

## 검증 자료

- `asset_quality_v3_contact_sheet.png`: 캐릭터, 타일, 갈대, 배경, HUD 얼굴 비교
- `guide_observe.png`: 실제 보드 레이어 구성과 경로 가독성
- `/tmp/mama_duck_v3_gameplay.png`: iOS Simulator 실제 구동 화면
