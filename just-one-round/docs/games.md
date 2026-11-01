# 게임 문서 색인

2026-10-13 로컬 소스 기준. 게임 문서는 현재 코드의 규칙·조작·종료 조건·점수 인코딩을 설명한다. 문서의 갱신 날짜는 스토어 공개나 운영 DB 적용 완료를 의미하지 않는다.

## 문서 확인 기준

- 실행 가능 여부와 지원 버전: [`GameRegistry`](../lib/features/games/game_registry.dart)
- 플레이어 가이드: 각 게임의 `presentation/*_presentation.dart`와 [`GamePresentationRegistry`](../lib/features/games/presentation/game_presentation_registry.dart)
- 수치·점수 변환: 각 게임의 `domain/*_rules.dart`
- 일일 일정·불변 서버 규칙: [`supabase/migrations`](../supabase/migrations)
- 구현을 검증하는 테스트: [`test/features/games`](../test/features/games)와 [`supabase/tests`](../supabase/tests)

게임별 문서는 승인된 설계 이력을 보존한다. 현재 구현과 다른 과거 내용은 기록으로 표시하고, 테스트가 존재한다는 사실과 실제 검증을 통과했다는 사실을 구분한다. 실사용자 점수 분포로 확인하지 않은 난이도 목표는 가설이다.

## 공통 계약

- 게임마다 종료 조건과 시간 상한이 다르다. 반응 게임·라운드 게임·고정 시간 게임을 모두 2~5분으로 간주하지 않는다.
- 공식 도전은 서버가 발급한 게임 ID·버전·시드·규칙 스냅샷을 따른다. 연습 점수는 공식 랭킹에 반영하지 않는다.
- 순위는 제출된 원시 점수가 높은 순이다. 시간이 짧을수록 좋은 게임도 순수 규칙 모듈에서 높은 값이 좋은 정수로 인코딩한다.
- 테스트 계정과 NPC의 랭킹 취급, 일일 기회, 재전송·중단 처리는 [제품 정의](product.md)와 [기술 구조](architecture.md)를 따른다.
- 홈의 게임 ID, 가이드, 발급 시도, 런타임이 일치해야 한다. 등록된 코드가 있어도 운영 활성화는 별도 출시 절차다.

## 게임별 문서

현재 `GameRegistry.registeredIds`는 15개다. **현재 규칙**은 규칙 모듈의 최신 계약이고, **지원 버전**은 레지스트리가 허용하는 시도 버전이다. 구버전 지원 표기는 별도 구버전 런타임이 있다는 뜻이 아니며, 실제 호환 동작은 해당 게임 문서와 테스트를 따른다.

| 게임 문서 / ID | 현재 규칙 · 지원 버전 | 세션·종료 조건 | 제출 점수 기준 |
|---|---|---|---|
| [똥피하기](../lib/features/games/dung_dodge_v2/GAME_DESIGN.md) · `dung_dodge_v2` | 1 · `{1}` | 충돌 또는 300초 | 생존시간 ms |
| [중력 스위치](../lib/features/games/gravity_switch/GAME_DESIGN.md) · `gravity_switch` | 1 · `{1}` | 충돌 또는 300초 | 생존시간 ms |
| [사과게임](../lib/features/games/apple_game_v2/GAME_DESIGN.md) · `apple_game_v2` | 2 · `{1,2}` | 보드 클리어 또는 140초 | 제거 사과 수 |
| [탭50](../lib/features/games/number_rush/GAME_DESIGN.md) · `number_rush` | 1 · `{1}` | 50까지 클리어 또는 공식 180초 | `3,600,000 − 클리어 ms`; timeout `0` |
| [친구 두더지 반응속도](../lib/features/games/mole_reaction/GAME_DESIGN.md) · `mole_reaction` | 2 · `{2}` | 준비 1회·실전 1회; wall-clock 180초 | `1,000,000 − 가중 반응시간 ms`; timeout은 미등록 |
| [딱 한 발만](../lib/features/games/western_duel/GAME_DESIGN.md) · `western_duel` | 1 · `{1}` | 단판 반응 대결; 레지스트리 30초 | `1,000,000 − 반응 ms`; 조기 발사는 미등록 |
| [펍 다트](../lib/features/games/wind_darts/GAME_DESIGN.md) · `wind_darts` | 4 · `{4}` | 7발; 75초 안전 상한 | 황금 다트 배율을 반영한 합산 점수 |
| [엄마, 어디가](../lib/features/games/mama_duck_trail/GAME_DESIGN.md) · `mama_duck_trail` | 1 · `{1}` | 오리 3마리 소진 또는 120초 | 성공 라운드·길이·콤보 합산 |
| [야식털이 뱀](../lib/features/games/midnight_snake/GAME_DESIGN.md) · `midnight_snake` | 3 · `{3}` | 충돌·보드 완료 또는 300초 | 먹이 합산 `0~145` |
| [블랙잭](../lib/features/games/beat_the_dealer/GAME_DESIGN.md) · `beat_the_dealer` | 4 · `{3,4}` | 10라운드·코인 5 미만 또는 180초 | 최종 게임 내 코인 `0~925` |
| [홈런왕](../lib/features/games/ten_pitch_slugger/GAME_DESIGN.md) · `ten_pitch_slugger` | 8 · `{7,8}` | 7구; watchdog 300초 | 구별 점수와 7구 배율 합산 `0~16,875` |
| [30초 컵라면](../lib/features/games/ramen_timer/GAME_DESIGN.md) · `ramen_timer` | 4 · `{3,4}` | 10·20·30초 체크포인트; 활성 상한 45초 | 총 절대 오차 기반 높은 값이 좋은 정수 |
| [남탕! 여탕!](../lib/features/games/bathhouse_sort/GAME_DESIGN.md) · `bathhouse_sort` | 11 · `{11}` | 60초 분류 점수전 | 올바른 분류·콤보 합산 |
| [빙글개굴](../lib/features/games/lily_frog/GAME_DESIGN.md) · `lily_frog` | 5 · `{3,5}` | 낙하·충돌 또는 150초 | 착지와 보너스 합산 |
| [만선호](../lib/features/games/net_boat/GAME_DESIGN.md) · `net_boat` | 3 · `{3}` | 충돌 또는 300초 | 생물 포획·동시 포획 보너스 합산 |

- 탭50의 직접 생성 기본 제한 120초와 레지스트리의 공식 제한 180초는 구분한다.
- 홈런왕의 watchdog, 컵라면의 목표 시각, 서버의 시도 유효기간은 서로 다른 시간 개념이다. 카운트다운·결과 연출 포함 여부는 각 문서를 따른다.
- 게임 내 블랙잭 코인은 점수용 자원이며 사용자의 상점 지갑 코인과 별도다.

## 보관된 게임 문서

| 문서 / ID | 상태 | 보관 규칙 |
|---|---|---|
| [소시지 먹는 닥스훈트](../lib/features/games/sausage_dachshund/GAME_DESIGN.md) · `sausage_dachshund` | 현재 런타임·가이드 레지스트리에서 제외 | v1, 150초, 소시지 개수 점수. 소스와 이전 점수 포맷은 남아 있다. |

`star_dodge`, `dung_dodge`, `apple_game`, `failed_bakery`처럼 과거 점수 포맷만 처리하는 ID는 현재 등록 게임 목록에 포함하지 않는다.

## 문서 갱신 범위

이번 갱신은 16개 게임 계약을 실제 규칙·런타임·가이드·레지스트리·서버 검증과 대조한 문서 변경이다. 새 게임 규칙이나 애셋을 승인·배포한 작업이 아니다. 기기별 입력 지연과 실사용 점수 분포 같은 밸런스 검증은 각 문서의 가설·확인 항목으로 남긴다.
