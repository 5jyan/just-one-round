# 엄마, 어디가 — Fixed Terrain Handoff v10

## 변경 요약

- 반복되는 `3×3` 진흙·웅덩이 타일과 수식 기반 갈대 배치를 제거했다.
- `marsh_board_map.png` 한 장에 이어진 진흙길, 여러 칸을 가로지르는 물웅덩이, 갈대·풀숲 군락을 고정 배치했다.
- 습지 지도는 매 실행 동일하며, 경로 생성·점수·목숨·입력 규칙에는 영향을 주지 않는다.
- 홈 미리보기와 3개 가이드 합성본도 새 지형으로 다시 만들었다.

## 런타임 규격

| 에셋 | 파일 | 원본 규격 | 화면 규격 |
| --- | --- | --- | --- |
| 고정 습지 보드 | `marsh_board_map.png` | `180×252` | `360×504` |
| 습지 배경 | `marsh_background.png` | `180×420` | `360×840` |

고정 보드는 월드 `x=0, y=68, width=360, height=504`에 그려진다. 중앙 5×7 입력 셀은 장식적으로만 구분되며 모든 셀은 기존처럼 이동 가능하다.

## 재현

- 원본: `fixed_marsh_terrain_v10/raw-board.png`
- 프롬프트: `fixed_marsh_terrain_v10/prompt-used.txt`
- 프로세서: `tool/process_mama_duck_trail_fixed_terrain_v10.py`
- 계약: `fixed_marsh_terrain_v10/pipeline-meta.json`
- QC: `fixed_marsh_terrain_v10/qc/fixed_marsh_board_runtime.png`, `fixed_marsh_board_4x.png`

## 보존된 동작

경로 생성, 랜덤 출발 열, 경로 길이 증가, 입력 판정, 점수, 콤보, 목숨, 실패 연출, 120초 제한은 유지했다. 제거한 것은 장식용 타일·갈대 무작위 배치뿐이다.
