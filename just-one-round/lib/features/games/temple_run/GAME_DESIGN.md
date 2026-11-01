# 집에 좀 가자 (`temple_run` v1)

## 약속

고등학생 주자가 방과 후 골목길을 자동으로 달리며 기기 기울기로 위치를 조절하고, 덮개 자재 사이 좁은 통로·낮은 작업발판·차단대·90도 코너를 읽어 집까지 가는 1인용 러너다. 게임 ID `temple_run`, 규칙 버전 `1`, 최대 시간 300초, 입력·충돌·난이도·점수·시도 수명주기는 기존 계약을 유지한다. 플레이어 점수는 `floor(distanceMeters) + coins * 10`이며 순위는 기존처럼 높은 점수가 우선이다.

## 입력과 위치

- 러너 위치는 연속적인 `0..2` lane 좌표다. 0은 왼쪽, 1은 중앙, 2는 오른쪽이며 `visualLane`이 충돌·픽업·아트에 같은 값을 전달한다. 기울기는 순간이동하지 않고 최대 `4.2 lane/s`로 이동한다.
- `sensors_plus`의 portrait 가속도 X를 사용한다. 카운트다운 동안 중립값을 천천히 보정하고 이동하지 않는다. 중립에서 벗어난 값은 0.85 deadzone과 0.32 smoothing을 거친다. Android 축에서 오른쪽 기울기는 음수 X이므로 음수 보정값이 오른쪽 이동이다. 전체 기울기 입력은 약 `3.0m/s²`에서 최대 반응으로 포화한다.
- 한 손가락 드래그는 지배 축이 논리 좌표 20px을 넘는 순간 한 번만 소비한다. 카운트다운·종료 중에는 무시하며, 오래 누르고 있어도 반복하지 않는다.
- 위는 0.78초 점프, 아래는 0.72초 슬라이드다. 포즈 중 세로 입력 하나만 0.30초 동안 FIFO로 대기하고, 만료·중단·종료 때 버린다.
- 왼쪽·오른쪽 스와이프는 예고된 코너의 예약 창에서만 소비한다. 예약된 입력은 실제 교차점에서 90도 분기를 실행하며, 일반 구간에서는 위치를 바꾸지 않는다.

## 상태와 종료

`countdown → playing → finished` 상태를 사용한다. 카운트다운은 3초이며 거리·점수·픽업·입력은 멈춘다. 카운트다운 첫 프레임부터 카메라는 일반 추격 시점에 고정되고, 추격자 둘은 플레이가 시작될 때까지 숨긴다. 0초 카운트다운도 같은 정상 카메라로 즉시 시작한다. 플레이는 최대 300초에 도달하면 `TIME UP` 결과를 한 번 방출한다. 고체 충돌, 점프하지 않은 차단대, 피하지 못한 덮개 자재, 슬라이드하지 않은 작업발판, 좁은 통로의 안전 띠 이탈, 제한 시간 안에 처리하지 않은 코너는 `GAME OVER` 결과를 한 번 방출한다. 앱 이탈·백그라운드·명시적 `interrupt()`는 결과를 제출하지 않고 시계를 멈춘다.

방패는 고체 장애물 한 번만 막는다. 놓친 코너와 좁은 통로 이탈은 방패가 막지 못한다. 자석은 7초 동안 코인을 끌어오고, 부스트는 2.8초 동안 속도 1.32배와 장애물 통과 보호를 주며 종료 직후 최소 반응 회복 시간을 남긴다. 경제 시스템은 추가하지 않는다.

## 속도와 행동 밀도

정상 속도는 8m/s에서 시작해 30초에 14m/s까지 빠르게 오른 뒤 120초 20m/s, 210초 27m/s를 거쳐 300초에 42m/s까지 네 구간으로 선형 상승한다. 각 구간의 적분·역적분은 같은 속도 곡선을 사용하며, 부스트 중 최대 속도는 55.44m/s다. 300초 정상 주행 거리는 7,080m다. 파워업은 30초마다 총 9개가 나오고 순서대로 자석·방패·부스트를 반복하므로 부스트는 90·180·270초에 한 번씩, 각 2.8초 동안 최대 세 번 제공된다. 서버 거리 검증을 보수적으로 확인할 때는 세 번의 부스트 시간 8.4초를 모두 해당 시점 최고 속도에 더해도 모든 1ms 시점에서 `distance(t) + min(t, 8.4) × 0.32 × speed(t) ≤ 24t + 2`를 만족한다. 300초의 검증 한도와 비교한 최악의 여유는 약 9m이며 서버 계약 변경은 필요 없다.

| 시간 | 속도 | 콤보 행동 수 | 행동 목표 간격 |
|---|---:|---:|---:|
| 0–45초 | 8→15m/s | 첫 코너 4.2–4.6초, 회전 직후 수직 장애물, 이후 3m/1.5m 좁은 통로 | 0.90초(5초)→0.60초(45초) |
| 45–120초 | 15→20m/s | 좁은 통로·차단대·작업발판을 묶고 코너로 마무리 | 0.60초(45초)→0.54초(90초) |
| 120–210초 | 20→27m/s | 같은 조작을 더 잦은 장애물 묶음으로 연결 | 0.54초(120초)→0.50초(180초)→0.46초(210초) |
| 210–300초 | 27→42m/s | 가장 촘촘한 장애물 묶음과 빈번한 90° 코너 | 0.46초(210초)→0.46초(300초), 부스트 중에도 보호·회복 창 유지 |

각 코스는 코너 전 장애물을 1–5개로 다양하게 묶은 뒤 좌우 중 무작위 90° 코너를 놓아 조작 연쇄를 만든다. 첫 코너는 4.2–4.6초이고, 회전 직후 첫 장애물은 항상 수직 장애물로 시작한다. 좁은 통로는 그 다음 콤보부터 3m 또는 1.5m 길이로 등장한다. 초반에는 1개 16%, 2개 46%, 3개 28%, 4개 9%, 5개 1%로 짧은 묶음을 섞고, 시간이 지날수록 1·2개 비율을 낮추고 4·5개 연쇄를 늘린다(300초 기준 1개 10%, 2개 30%, 3개 32%, 4개 19%, 5개 9%). 장애물 반응 하한은 0.74초에서 후반 0.44초까지 줄여 정상 주행에서도 연속 입력을 요구한다. 서로 다른 수직 장애물(점프→슬라이드 또는 슬라이드→점프)은 자세 시간이 겹치지 않도록 최소 0.88초의 전환 여유를 두고, 같은 자세 장애물과 좁은 통로는 더 촘촘하게 이어진다. 생성기와 테스트는 부스트 최고 속도로도 각 코스가 도달 가능한지 확인하며, 같은 시드는 같은 장애물·코너 경로를 만든다.

장애물 종류는 7개 행동마다 좁은 통로 2개, 수직 장애물 5개를 넣어 기울이기보다 점프·슬라이드 장애물이 정확히 2.5배 많이 나온다. 코너 전 마지막 장애물 뒤 회복 간격도 0.82초에서 0.42초까지 줄어들어 후반에는 장애물을 통과하자마자 다음 90° 입력을 예약해야 한다. 좁은 통로 길이는 기존 6m 구간을 제거하고 3m(기준의 1/2)와 1.5m(기준의 1/4)를 번갈아 사용한다. 코너 뒤 첫 장애물 추가 간격은 0.18초로 줄여 장애물→턴→장애물 연쇄를 만든다. 회전 직후 첫 장애물은 항상 수직 장애물로 배치해 기울이기 입력이 회전 애니메이션과 겹치지 않는다.

목표 액션 간격 외에도 장애물 반응·기동·코너 간격의 최솟값을 별도로 둔다. 생성기는 장애물 사이 간격을 55.44m/s 부스트 속도로 나눠도 시간 하한을 지키는지 확인하고, 좁은 통로의 1.5m/3m 점유 길이, 점프·슬라이드 동작 시간, 버퍼 입력, 코너 예약 창과 회전 애니메이션을 포함해 안전 간격을 조정한다. 코너 뒤 첫 장애물에는 추가 0.18초를 주고, 코너 사이에는 카메라가 방향을 읽을 직선 구간을 남긴다. 좁은 통로는 길이 전체에서 lane 0 또는 2의 연속 안전 띠만 통과 가능하며 점프·슬라이드·방패로 우회할 수 없다. 렌더러는 그 안전 띠 바깥에 충돌 폭과 맞는 덮개 자재를 이어 그린다.

50개 시드, 각 300초 코스를 실제 생성해 잰 중간 간격이다. 부스트 값은 같은 코스 거리를 정상 주행과 연속 1.32배 주행으로 환산한 비교치다.

| 시간대 | 코너→코너 (정상) | 연속 장애물 (정상) | 전체 행동 (정상) |
|---|---:|---:|---:|
| 5–45초 | 3.48초 | 0.86초 | 0.81초 |
| 45–90초 | 3.01초 | 0.77초 | 0.71초 |
| 90–150초 | 2.82초 | 0.70초 | 0.64초 |
| 150–210초 | 2.70초 | 0.66초 | 0.60초 |
| 210–300초 | 3.38초 | 0.64초 | 0.57초 |

같은 측정에서 양방향 코너가 모두 나오고, 장애물만 놓고 보면 기울이기 외 장애물 대 좁은 통로 비율은 50개 시드 합산 2.49:1이었다. 좁은 통로 길이는 두 짧은 변형만 사용하며, 회전 직후 첫 장애물은 모든 시드에서 수직 장애물이다. 장애물→장애물 중간 간격은 초반 약 0.86초에서 180초 이후 약 0.64초로 줄고, 장애물→턴 회복 간격도 기존 곡선을 유지해 초반 약 0.77초에서 후반 약 0.70초로 줄었다. 코너 전 클러스터 크기는 1–5 모두 나타나며, 코너 간격은 90초 이후에도 늘지 않고 계속 줄어든다.

코인은 약 3.5초마다 3개씩 전체 300초에 걸쳐 배치하고, 파워업은 장애물 개수가 아니라 약 30초 시간 간격으로 등장한다. 픽업은 주자가 아이템의 앞쪽 창에 들어왔을 때 옆 lane에 있다는 이유만으로 폐기하지 않는다. 주자가 ±1.65m 코인·파워업 창을 벗어나면 놓친 아이템으로 만료하고, 성공·만료 아이템은 즉시 화면에서 숨긴다. 성공한 코인은 주자 상체 근처에서 0.50초 동안 금빛 다이아몬드·8방향 반짝임과 읽을 수 있는 `+10` 팝업을 보이고, 파워업은 종류별 glyph(자석·방패·번개), 색 링·방사 파편과 `MAGNET`·`SHIELD`·`BOOST` 라벨을 보인다. 이 피드백은 아이템이 사라진 뒤에도 자체 수명만큼 남고, 수집 집합이 바뀔 때 한 번만 생성되며, 동시 효과는 최대 6개로 제한한다. 동시 창에 들어온 여러 아이템은 각각 한 번만 처리한다.

코스 생성과 서브스텝, 안전 여유, 시드 재현성은 `TempleRunCourseGenerator(Random)`에서 관리한다. 같은 시드는 같은 콤보·코너 방향·수집품 경로를 만들며, 좁은 통로 lane은 좌우로 번갈아 나온다.

## 32비트 픽셀 아트 계약

최종 런타임 아트는 `assets/images/homebound_run/`에 두고, `assets/images/temple_run/`의 기존 원본 이미지는 보존한다. 모든 비트맵은 `FilterQuality.none`으로 그리며, foreground 위치는 가능한 한 논리 픽셀에 맞춘다.

| 역할 | 런타임 파일 | 원본 크기 | 표시 기준 |
|---|---|---:|---:|
| 골목 배경 | `alley_background.png` | 864×1920 | 기본 0.5배, 원본 y=940 지평선; 매우 높은 뷰포트는 화면과 지평선까지 덮도록 비율을 유지해 확대 |
| 도로 타일 | `asphalt.png` | 512×512 | 투영 XZ quad의 반복 UV |
| 골목 벽 | `wall_plaster_a.png`, `wall_plaster_b.png`, `wall_window.png`, `wall_door.png`, `wall_mural.png`, `street_house_brick.png`, `street_house_sage.png`, `street_shopfront.png`, `wall_schoolfront.png`, `wall_constructionfront.png` | 각 1024×768 | `street_*` 세 장은 한 장이 한 건물 전체를 덮는 5.5m·약 7.33m full-bleed 전면이며 32 logical px가 약 0.9167m가 되도록 nearest 반복한다. 건물 family마다 0.12–0.42m의 clean masonry 상부 extension을 별도로 닫아 자연스러운 skyline 높이를 만든다. 누적 wallArc 20슬롯은 house 12(60%), shop 4(20%), 실제 wall 4(20%)로 구성한다. 기존 `wall_house_*`, `wall_shopfront.png` partial plate는 provenance/reference로 보존하고 active street facade로 사용하지 않는다. |
| 주자 달리기 | `student_run.png` | 768×288 | 4×192×288, 96×144 표시, 모든 frame alpha-bottom 기준선 272 |
| 주자 포즈 | `student_jump.png`, `student_slide.png` | 각 192×288 | 원본 종횡비 유지, alpha-bottom 기준선 272에 실제 발 정렬 |
| 추격자 | `pursuers_run.png` (3×2, frame 512×384; 전체 1536×768), `pursuers.png` (기존 원본 보존) | atlas 1536×768 | 전신 등 모습의 두 추격자를 125ms/frame, 8fps로 달리게 한다. 두 명은 lane 입력과 독립적으로 화면 하단 중앙에 함께 남고, 작은 발밑 그림자로 접지를 보강한다. 런타임은 atlas를 필수 에셋으로 로드한다. 추격자는 카운트다운과 도착 게이트에서 숨긴다. |
| 장애물 | `streetscape_barricade.png`, `obstacle_jump_variant.png`, `streetscape_scaffold_crossbeam.png`, `obstacle_slide_variant.png`, `streetscape_covered_pallet_materials.png` (기존 obstacle 원본은 fallback/provenance) | 512×256 jump family, 512×512 slide family, 512×384 pallet atlas | barricade와 콘·체인 jump variant는 점프용 고정 높이 0.45m, scaffold와 녹색 차양 slide variant는 바닥 opening 1.0m를 남긴 고정 높이 2.9m, pallet은 피하는 front/side/top cuboid 재질로 고정 높이 1.25m·깊이 0.75m를 사용한다. generated obstacle id에 따라 두 새 실루엣을 교차 배치하고 id 0 수동 fixture는 기존 에셋을 유지한다. 좁은 통로 bank는 충돌상 도달 가능한 안전 띠 바깥쪽에 2m 단위로 이어 그린다. lane 0/2에서는 법적 이동 범위 밖의 얇은 바깥 sliver만 생략하고, 두 bank가 필요한 중앙 lane 수동 코스는 그대로 유지한다. |
| 아이템 | `coin.png`, `magnet.png`, `shield.png`, `boost.png` | 각 64×64 | 정사각형 픽업 |
| 도착 | `home_gate.png` | 512×512 | 300초 종료 시 시각 전환, 투명 하단 24px 보정 |

배경에는 도로를 포함하지 않으며, 원본 y=940의 도시 지붕선을 카메라 지평선에 맞춘 뒤 아래를 asphalt ground plane으로 잇는다. 기본 배경 배율은 0.5이고, 매우 높은 뷰포트에서는 원본 비율을 유지한 채 화면과 계산된 지평선을 함께 덮도록 확대한다. 지평선은 실제 주자 접점을 유지하는 카메라 투영에서 파생한다. 지면과 도로를 불투명한 벽보다 먼저 그리고, 도로는 월드 좌표에 고정된 asphalt UV를 투영 XZ quad에 연속해서 매핑한다. 각 turn에는 양쪽 도로 strip을 이어 주는 실제 텍스처 junction/miter polygon을 채워 외곽 lane의 빈 사각형이 생기지 않게 한다. 도로 가장자리에는 playable edge 2.2m 바깥으로 0.15m gutter와 0.30m curb를 두고, curb부터 wall front까지 quiet concrete sidewalk plane을 이어 벽과 아스팔트가 떨어져 보이지 않게 한다. turn의 안쪽 edge leg는 offset-line miter까지 잘라 개구부 안으로 L자 curb가 뻗지 않게 한다. 벽은 전체 계획 route node를 먼저 만들고 카메라 표시 범위에 맞춰 clip/fade하므로 완료된 회전이나 화면 경계가 코너 연결을 끊지 않는다. 표시 전용 벽·curb는 현재 route leg와 이전·다음 leg(±1)만 그려 먼 미래 벽이 활성 도로를 가로막지 않게 한다. 양쪽 벽의 누적 wallArc로 5.5m base·약 7.33m 폭의 full-bleed street tile을 고정하고, family별 clean masonry 상부 extension으로 높이를 0.12–0.42m만 변형한다. 20슬롯은 house 12슬롯(60%), shop 4슬롯(20%), 실제 wall 4슬롯(20%)으로 구성한다. 실제 wall 네 칸은 warm mural·school·construction·neutral gray/brick material을 각각 한 칸씩 사용해 흰 벽이 기계적으로 반복되지 않게 한다. houseGarden 슬롯은 별도 흰 inset plate가 아니라 street_house_sage의 호환 변형으로 렌더한다. Full-bleed house·shop 타일은 `plasterA`를 뒤에 깔지 않으며, brick은 wall plane보다 0.35m, sage는 0.55m, shop은 0.40m 도로 쪽으로 이동한다. 인접 타일의 누적 arc 경계에서 setback이 달라질 때만 하나의 return을 만들고, 더 도로 쪽으로 나온 타일의 자체 masonry material을 32×32 logical px 패치로 반복해 사용한다. 같은 setback에서는 앞면을 같은 평면으로 이어 추가 return을 만들지 않는다. 건물 앞면과 경계 return은 각 타일의 자체 material을 쓰며 공통 white frame을 추가하지 않는다. 코너 guard 1.2m 안의 타일은 offset을 baseline으로 되돌리되 full-bleed material과 miter는 유지한다. 텍스처 사각형은 source plane homography로 투영하며 near/far clip은 source U를 보간해 처리한다. 각 90도 junction에서 양쪽 벽 면의 offset-line intersection으로 끊김 없는 모서리를 만든다. 시야 카메라 높이는 기존 자연 높이의 최댓값 5m로 제한해 5.5m base와 작은 extension top을 과도하게 올려다보지 않게 한다. 카메라는 렌더된 주자 중심선에서 시작해 incoming→outgoing heading을 공유하는 180ms cubic ease-out으로 정확히 90도 회전한다. 주자와 카메라는 같은 회전된 right basis를 사용하므로 lane offset이 회전 중에도 화면에서 튀지 않는다. 기본 boom은 6m이며, 코너에서는 relief와 0.35m 시야 여유를 뺀 실제 local wall span에 대한 backward-ray 첫 교차점으로 짧아지고, 주자가 진행해 교차점이 사라지면 다시 6m까지 회복한다. 미입력 turn grace 중 화면은 junction 거리에서 잠시 기다리고, 늦은 turn 입력이 성공하면 같은 180ms 동안 화면 거리 debt만 따라잡는다. 게임 진행거리·충돌·HUD는 실제 거리를 계속 사용한다. 벽은 코스 거리 진행에 따라 schedule만 순환하며 장애물 규칙과 충돌 좌표를 바꾸지 않는다. 좁은 통로는 안전 띠 밖에 덮개 자재 bank를 1.5m 또는 3m 동안 반복하고, lane 0/2의 도달 불가능한 바깥 bank 조각은 생략하지만 중앙 lane 수동 코스의 양쪽 bank는 유지한다. Arch는 낮은 작업발판, hurdle은 낮은 차단대로 보인다. 도착 게이트와 두 추격자는 시각 전용이다.

반복적인 full-height seam bar 대신 wall module 자체가 실제 건물의 전체 front를 담당한다. 일반 plaster 타일에는 추가 feature를 그리지 않는다. House·shop·rare의 active facade는 각 property의 색·하부·상단을 가진 한 장의 full-bleed tile이며 `plasterA`를 강제로 둘러 붙이지 않는다. 차양·계량기·선택된 창턱은 최신 에셋에서 실측한 UV metadata에 맞춰 원래 source footprint를 한 번 잘라 bounded volume으로 확장한다. 계량기 앞면이 옆면에 중복되지 않도록 옆면은 해당 물체의 단색 재질을 쓰고, 아랫면도 실제 source footprint의 하단에서 닫는다. Garden은 sage material family 안에서만 변형한다. 건물 front는 brick/sage/shop 전체 타일을 사용하고, 서로 다른 setback 경계의 단일 return은 더 도로 쪽인 건물의 32×32 logical px clean patch를 반복한다. 모든 face는 side별 winding/cull, .12m near clip, 1m 이하 painter band, shared facade occluder를 함께 사용한다. 돌출 구조는 총 roadward depth 1.2m 이하로 유지해 playable edge 2.2m 안으로 들어오지 않으며, 5.5m base와 extension의 닫힌 top/return face가 지붕이나 하늘색 빈 면을 드러내지 않는다. 주자 달리기·점프·슬라이드 이미지는 같은 복장과 팔레트로 다시 생성하고 272px 접지 기준선에 정렬했다.

투명 장애물 캔버스의 하단 여백은 장애물 종류별 원본 alpha footprint 기준으로 보정한다(덮개 자재·차단대 16px, 작업발판·게이트 24px). 따라서 이미지의 전체 캔버스 종횡비를 충돌 폭이나 접지선으로 사용하지 않는다.

## 진입점과 프리뷰

실제 `TempleRunGame` registry 진입점은 `useImageAssets: true`로 최종 bundle을 카운트다운 전에 preload한다. `TempleRunGame` 생성자의 기본값 `false`는 기존 테스트·디버그용 primitive branch로 남긴다. 홈 카드와 5개 가이드 페이지는 `TempleRunArt`를 공유하고 같은 image map을 비동기로 준비한 뒤 실제 주자·도로·장애물·파사드를 보여 준다. 가이드 문구는 `덮개 자재 사이 좁은 통로`, `작업발판`, `차단대`를 사용하며 입력·점수·실패 원인은 런타임과 일치한다.

## 검증 계약

- 같은 시드의 코스가 동일하고, 기존 reachability·look-ahead·턴 간격·300초 주행 검사가 통과한다.
- 새 bundle의 파일 존재·dimensions·주자 4-frame strip·추격자 3×2 run atlas·non-square display ratio를 확인한다.
- image mode에서 nearest filtering, 실제 asphalt quad texture, wallArc route alignment, 20-slot house 12/shop 4/actual-wall 4 budget, street_house_brick·street_house_sage·street_shopfront full-bleed bounds, per-material return/top/base continuity, detached-prop source cuts, no-white-frame coverage, narrow bank의 reachable-side geometry와 collision footprint 정렬, narrow-path/hurdle/arch mapping, student feet baseline, animated pursuer and home gate rendering을 확인한다.
- 왼쪽·오른쪽 turn에 대해 commit 전 heading이 유지되고, commit 후 45ms·90ms·180ms에 shared cubic turn이 진행되어 180ms에 정확히 ±90°가 되는지 확인한다. short/tall viewport와 세 lane에서 runner footprint가 실제 road/junction polygon 안에 있고, camera backward-ray sightline이 inset facade span을 침범하지 않는지 확인한다.
- 카운트다운 첫 프레임과 플레이 시작 경계의 카메라 위치가 동일한 정상 chase 시점이며, 3초 카운트다운 동안 추격자는 숨겨지는지 확인한다. 플레이 중 전신 run atlas가 125ms 주기로 바뀌고 발 그림자가 접지감을 주며, 두 추격자가 중앙에 유지되어 양방향 turn의 전·중·후, 짧고 긴 viewport, 세 player lane에서 주자·장애물을 가리지 않는지 캡처로 확인한다.
- straight tile join과 plaster/house/shop/rare full-bleed wall capture, own-material return seam, blank/window/door/mural feature capture, mixed-family transition, no forced white backing, 네 시드×8/90/250초의 non-turn tile-boundary 연속 프레임, `J−6`, `J−2` outer lane, `J−.1`, commit, `.045s`, `.09s`, `.18s`, `.35s`의 좌우 turn capture를 short/tall viewport에서 보관한다. 수집 직후 coin `+10`·power-up ring/label capture도 유지한다.
- primitive debug branch와 image branch가 같은 `TempleRunRules`, 입력, 충돌, 점수, 결과 exactly-once lifecycle을 사용한다.
- 홈 프리뷰와 5개 가이드 페이지를 short/canonical/tall portrait 슬롯에서 렌더하고, 비동기 asset load 완료 후 실제 image key와 HUD가 보이는지 확인한다.
