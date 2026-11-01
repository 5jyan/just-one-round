# 1:1 코인 대결 설계 v0.2

> 작성 기준: 2026-11-01 로컬 소스. 이번 작업은 설계 문서까지 다루며, DB migration·앱 코드·운영 정책을 적용한 상태를 뜻하지 않는다.

## 1. 문제와 확정 범위

사용자가 상대를 선택하고 게임과 코인 금액을 정해 초대 전용 2인 대기방을 만든다. 두 사람이 방에 입장하고 각각 `READY`를 누르면 서버가 같은 게임을 같은 시각에 시작한다. 각자의 결과를 서버가 검증해 코인을 정산한다.

이번 요청에서 확정된 흐름은 다음과 같다.

- 상대, 게임, 내기 금액을 고른다.
- 금액은 10코인 단위로 올리고 내린다.
- 요청 즉시 초대 전용 2인 방을 만들며 신청자는 자동 입장한다.
- 상대는 알림 또는 대결 목록에서 방에 입장한다. 별도의 수락 버튼은 없다.
- 두 사람이 현재 입장하고 게임 로딩을 끝내면 각자 `READY`를 누를 수 있다.
- 둘째 `READY`가 성공하면 추가 시작 버튼 없이 자동으로 게임을 시작한다.
- 두 실행은 하나의 공통 서버 시각과 같은 seed를 사용한다.
- `wind_darts`(펍 다트)와 `western_duel`(딱 한 발만)은 1차 선택 목록에서 제외한다.

실시간으로 상대 캐릭터를 보거나 입력을 공유하는 게임은 아니다. 실행은 각 기기에서 독립하지만 시작 순간만 공통으로 맞춘다. 물리적으로 완전히 같은 프레임에서 시작한다고 보장하지 않고, 권위는 DB snapshot과 서버 시계에 둔다.

## 2. 권장 초기값과 비목표

다음 값은 제품·경제 승인 전의 추천 초기값이다. 금액 step 10과 방 READY 흐름은 확정 요구이고, 최소·최대·기본 금액은 추천값이다.

| 항목 | 추천 초기값 | 비고 |
|---|---:|---|
| 최소 금액 | 10 코인 | 추천값. 기존 지갑 상한을 자동 확정하지 않음 |
| 최대 금액 | 200 코인 | 추천값. 더 큰 금액은 별도 경제 gate 필요 |
| 기본 금액 | 100 코인 | 추천값 |
| 방 TTL | 10분 | `waiting` 상태에만 적용 |
| 공통 카운트다운 | 3초 | 둘째 READY 커밋 뒤 한 번만 |
| heartbeat | 5초 | 추천 cadence |
| presence lease | 15초 | 추천 lease. stale 기기 거부용 |
| 생성 횟수 | 하루 10건 | 추천값, KST 오전 6시 리셋 |
| 미종결 방 | 계정당 1개 | 추천값, `settled` 전 방 기준 |

`starting` 또는 `playing` 매치는 waiting TTL 만료로 환불하지 않는다. TTL은 아직 둘째 READY가 성공하지 않은 초대 대기방에만 적용한다.

권장 1차 비목표는 자동 매칭, 공개 방, 채팅, 신규 친구 검색·친구 관계, 새 전용 게임 규칙·아트, 리플레이, 자동 재대결, 일일 랭킹·오늘의 도전·연습권·광고 보상·추가 XP 통합이다. 이번 버전에서 상대 캐릭터나 공유 입력을 추가하지 않는다.

## 3. 화면과 방 생명주기

### 만들기

랭킹·미참여 유저의 기존 상대 액션 진입점을 재사용한다. 현재 `_RankActionSheet`는 플레이어에게 찌르기·자랑하기·선물하기를 제공하므로, 여기에 `1:1 대결` 진입을 추가한다 ([랭킹 액션 화면](../lib/features/today/presentation/today_screen.dart)).

신청 화면은 상대, 게임, 내기 금액을 보여준다. 금액은 `−10`, `+10`으로 조정하고 서버가 positive integer이며 10의 배수인지 다시 검사한다. 추천 초기값을 사용할 때 UI 범위는 10~200이지만, 200은 기존 상한을 자동 확정하는 값이 아니다. 사용 가능 잔액에 맞춰 선택 가능한 금액을 클램프하되 상대 잔액은 절대 공개하지 않는다.

게임은 방 생성 후 고정한다. 금액이나 게임을 바꾸려면 기존 방을 취소하고 새 요청을 만든다. 상대 동의를 유지한 채 방 속성을 바꾸는 API는 제공하지 않는다.

방 상세는 서버가 반환한 상태를 단일 source of truth로 그린다. 화면에 보이는 READY·로딩·입장 표시는 낙관적으로 시작할 수 있지만, 자동 시작·차감·결과는 서버 응답이 확인된 경우에만 반영한다.

신청 RPC가 초대 전용 방과 매치를 함께 만든다. 신청자는 자동 입장하고, 두 run의 입장 상태는 아직 `ready`가 아니다. 요청 시점에는 양쪽 코인을 차감하지 않는다.

### 입장

상대는 알림 또는 홈의 `1:1 대결` 목록에서 방에 입장한다. 입장은 수락의 의미이며 별도 `accept` 상태·버튼을 만들지 않는다. 방에는 상대 닉네임, 게임, 각자 내기 S, 총 상금 2S, 두 사람의 입장·로딩·READY 상태를 표시한다.

가이드는 READY 전에 언제든 볼 수 있다. 가이드와 asset preload가 끝나야 해당 플레이어의 READY가 활성화된다. 상대가 아직 입장하지 않았거나 내 로딩이 끝나지 않았으면 READY를 누를 수 없다.

### READY와 자동 시작

각 플레이어의 `set_ready(true)`는 현재 room session, presence lease, room revision, loading 완료를 서버가 확인한다. 첫 READY는 방에 표시되지만 코인을 차감하지 않는다. 시작 확정 전에는 `set_ready(false)`로 READY를 취소할 수 있다.

둘째 READY RPC가 매치와 두 profile을 안정적인 사용자 ID 순서로 잠근다. 양쪽 인증 current-device session lease, 최신 presence, 같은 room revision, 입장·로딩·버전·잔액을 다시 검증한 뒤 다음을 하나의 원자 커밋으로 처리한다.

1. 양쪽 S를 동시에 escrow 차감
2. 공통 server seed와 immutable game/rules/runtime snapshot 발급
3. 두 run 생성
4. `start_at = server_now + 3초` 계산
5. 매치를 `starting`으로 전환하고 start event 발행

이 커밋이 시작 확정 시점이다. 추가 시작 버튼이나 individual start RPC는 없다. 공통 카운트다운 3초는 한 번만 계산하며, 게임별 특별 준비가 필요하면 snapshot에 명시한다. 각 클라이언트의 이벤트 수신 시각으로 개별 시작하지 않는다.

검증 실패·잔액 부족·session stale이면 양쪽 코인을 차감하지 않고 시작하지 않는다. READY 초기화는 예외를 던져 rollback시키지 말고, 정상 실패 응답의 상태 변경으로 커밋한다. 응답에는 실패 이유와 다시 로딩·입장·READY해야 하는 상태를 담는다.

동시에 들어온 마지막 READY, READY 취소, leave 요청은 match lock과 room revision으로 한 번만 결정한다. 한 account에는 유효한 room session 하나만 허용하고 stale device RPC는 거부한다.

### 이탈과 기한

시작 확정 전 명시적 leave, 초대 거절, 취소, waiting TTL 만료는 코인 차감 없이 방을 종료한다. 시작 전 네트워크 lease가 만료되면 두 READY를 해제하고 waiting 방을 TTL 안에 유지한다. 재입장한 두 사람이 다시 로딩한 뒤 새 READY를 눌러야 한다. 이전 session generation·room revision의 늦은 heartbeat·READY packet은 거부한다.

start event가 늦게 도착해도 `start_at` 이전이고 해당 run이 아직 실행 중이 아니면 기존 run으로 참여한다. `start_at`이 지난 뒤 아직 실행되지 않은 run에 늦게 처음 입장하는 것은 허용하지 않으며 새 seed, 시계 초기화, 새 판 발급도 하지 않는다.

공통 `start_at`은 두 run에 동일하다. `submit_deadline = start_at + game_cap + result_reveal_allowance + 120초`로 계산하며 공통 카운트다운은 한 번만 포함한다. 각자의 추가 countdown은 넣지 않는다.

## 4. 게임 후보와 활성화

현재 `GameRegistry`에 등록된 ID는 로컬 소스에서 16개다 ([게임 레지스트리](../lib/features/games/game_registry.dart)). 두 제외 게임을 뺀 코드 후보는 다음 14개다.

| ID | 표시 이름 |
|---|---|
| `dung_dodge_v2` | 똥피하기 |
| `gravity_switch` | 중력 스위치 |
| `apple_game_v2` | 사과게임 |
| `number_rush` | 탭50 |
| `mole_reaction` | 친구 두더지 반응속도 |
| `mama_duck_trail` | 엄마, 어디가 |
| `midnight_snake` | 야식털이 뱀 |
| `beat_the_dealer` | 블랙잭 |
| `ten_pitch_slugger` | 홈런왕 |
| `ramen_timer` | 30초 컵라면 |
| `bathhouse_sort` | 남탕! 여탕! |
| `lily_frog` | 빙글개굴 |
| `net_boat` | 만선호 |
| `temple_run` | 집에 좀 가자 |

이 표는 등록 후보이지 출시 목록이 아니다. 신청 화면은 신청자 클라이언트가 지원하고 서버가 `active`와 `duel_enabled`를 켠 게임만 보여준다. 상대의 최신 capability가 없거나 stale이면 방 입장과 READY 시점에 다시 검증한다. 상대가 같은 game/version/runtime revision을 지원하지 않으면 READY를 완료하지 않고 업데이트 안내를 표시한다.

서버 최종 조건은 `active` + `duel_enabled` + 서버 점수 검증 지원 + 양쪽 클라이언트의 동일 runtime revision이다. 등록 코드와 운영 활성화가 별도라는 원칙은 [게임 문서 색인](../docs/games.md)에 있다. `mole_reaction`과 `temple_run`은 로컬 migration에서 비활성 또는 테스트 staged일 수 있으므로 1차 운영 목록이라고 단정하지 않는다.

## 5. 공정한 실행과 점수

서버는 두 run에 같은 seed, `attempt_ordinal = 1`, game ID/version, duel rules revision, runtime revision, 규칙 snapshot, 공통 `start_at`을 발급한다. seed와 상대 raw score는 READY·Realtime payload·푸시에서 노출하지 않는다.

현재 `MiniGameSeed.forAttempt`는 날짜·게임·버전 기반이고 ([공통 시드 계산](../lib/features/games/domain/mini_game_seed.dart)), `beat_the_dealer`는 런타임에서 매번 random seed를 사용한다. 대결은 서버 seed override를 추가하고 블랙잭의 fresh random 경로를 우회해야 한다. 게임 버전 숫자만 같아도 규칙 검증이 바뀔 수 있으므로 revision을 함께 고정한다.

정상 게임오버와 정상 0점은 `valid`다. 예를 들어 탭50의 제한 시간 종료 raw score `0`은 valid 후보지만, 두더지 반응속도의 현재 timeout 미등록 계약은 `no_result`로 분리한다. 게임마다 `valid_zero`, `no_result`, `forfeit`를 명시한 duel validator를 두고 공통 sentinel 하나로 합치지 않는다.

두 valid 결과는 raw score가 높은 쪽이 승리한다. 동점은 제출 시각을 타이브레이크로 쓰지 않고 양쪽을 환불한다. 한쪽 valid와 상대 forfeit면 valid 쪽이 승리한다. 한쪽 valid, 상대 미제출이면 상대 submit deadline 후 valid 쪽이 승리한다. 둘 다 forfeit/no-result면 환불한다.

현재 공통 정책에 따라 명시적인 앱 background, 런타임 중단, 강제 종료는 forfeit다. 경기 중 heartbeat 단절만으로 즉시 기권시키지 않는다. 네트워크만 끊겨 게임이 계속되면 결과를 durable queue에 보관하고 deadline 내 동일 run·동일 결과만 재전송한다. 응답이 끝내 없으면 서버 deadline으로 종결한다. 시작 확정 후 강제 종료한 뒤 새 경기로 같은 run을 재시작하지 않는다.

서버 장애, 지원 중단, snapshot 불일치처럼 사용자 행동과 무관한 경우는 `void`로 감사 사유를 남기고 양쪽을 환불한다.

## 6. 경제와 정산

요청·입장·첫 READY에서는 코인을 차감하지 않는다. 둘째 READY RPC에서만 match와 두 profile을 lock하고 양쪽 S를 동시에 escrow로 옮긴다. 검증 실패 시 양쪽 무차감이다.

기존 `coin_transactions`의 사용자·reference key unique 원장을 재사용한다 ([경제 원장 migration](../supabase/migrations/20260802000600_player_economy.sql)). reference key는 `duel:match_id:kind:user_id:part`처럼 매치·종류·분할 순번을 인코딩한다. 별도 `(match_id, user_id, kind)` unique 컬럼을 중복 생성하지 않는다. escrow, refund, payout 모두 XP delta는 0이다.

지갑 잔액 상한 때문에 partial credit이 필요할 수 있다. 정산 결과를 먼저 확정하고 `owed_amount`, `credited_amount`를 보관한다. match/run lock 아래 `owed_amount - credited_amount`를 계산해 상한 안에서 지급하고, 분할마다 고유 reference key와 순번을 사용해 같은 분할만 중복 방지한다. 남은 금액은 수령 대기로 표시하고 재접속·worker가 공용 credit helper로 재시도한다. 수수료 0 추천 기준 보존식은 `참가자 지갑 잔액 합 + 미정산 보관금 + 미수령 채권(owed_amount - credited_amount) = 최초 총액`이다. 이 경제 gate를 해결하기 전에는 추천 최대 200을 운영 상한으로 확정하지 않는다.

계정 삭제나 테스트 계정 전환은 foreign-key cascade에 맡기지 않는다. 관련 waiting/starting/playing 매치를 내부 void 정산으로 먼저 환불해 상대 지분을 보호한 뒤 상태를 변경한다. 실제 삭제 업무와 테스트 전환 트리거는 별도 구현 접점으로 남긴다. 테스트 격리는 [social isolation migration](../supabase/migrations/20261011000400_test_social_isolation.sql)을 따르고, 차단 endpoint는 제거된 상태다 ([차단 endpoint 제거 migration](../supabase/migrations/20260821000400_remove_user_report_and_block_endpoints.sql)).

## 7. 데이터와 RPC

`duel_matches`는 `waiting`, `starting`, `playing`, `settled`, `declined`, `cancelled`, `expired`, `voided`, room revision, waiting TTL, common `start_at`, seed reference, game/rules snapshot, outcome과 audit 시각을 저장한다.

`duel_runs`는 match/player unique pair, entry/presence, session generation, lease, loading, ready, 실행 상태, submitted/forfeited, server submit deadline, raw score, validated result, terminal reason을 저장한다. 실행 seed와 private result는 participant 전용 RPC로만 읽는다.

최소 RPC는 `get_duel_options`, `get_duels`, `get_duel`, `create_duel`, `join_duel`, `heartbeat_duel`, `set_duel_ready`, `leave_duel`, `submit_duel_result`, `forfeit_duel`다. 별도 수락·시작 RPC는 두지 않는다. 만료·정산은 내부 `expire_and_settle_duel`과 주기 worker, mutating RPC의 lazy settle로 처리한다.

create/join/heartbeat/ready/submit는 idempotent해야 한다. stale session generation, 다른 room revision, 다른 device lease의 요청은 거절한다. match row와 두 profile을 안정적인 user ID 순서로 잠가 동시 마지막 READY·leave·정산을 한 번만 결정한다.

RLS는 private seed/result 직접 SELECT·INSERT를 막는다. `SECURITY DEFINER` 함수는 `auth.uid()`, participant, current-device lease를 검사하고 고정된 `search_path`를 사용한다. 서버 정산 worker만 상대 결과를 비교하고 지급한다.

## 8. 앱 런타임과 일일 모드 분리

현재 `PlayAttempt`에는 게임 ID·버전·기간은 있지만 대결 seed/context가 없고 ([오늘 상태 모델](../lib/features/today/domain/today_state.dart)), `GameScreen`은 일일 시작·제출 RPC에 직접 연결돼 있다 ([게임 화면](../lib/features/gameplay/presentation/game_screen.dart)). 대결은 일일 attempt를 재사용하지 않는다.

`features/duels/domain`, `data`, `presentation`에 room snapshot, presence/READY, common clock, seed override, run callback을 둔다. 기존 게임 factory·순수 rules·가이드를 재사용하며 거대한 새 게임 프레임워크는 만들지 않는다.

게임은 READY 전에 asset preload를 끝내 둘째 READY 뒤 추가 로딩을 최소화한다. Realtime room presence, READY, start event로 UI를 즉시 갱신하지만 권위는 DB snapshot/server clock이다. 이벤트가 유실되면 `get_duel` 재조회와 짧은 polling으로 복구한다.

대결 결과는 pending queue에 mode, match_id, run_id, room revision, raw result, duration을 보관한다. 기존 일일 중심 모델은 대결 필드를 추가하되 구형 decoding을 보존한다 ([대기 점수 제출 모델](../lib/features/gameplay/data/pending_score_submission.dart)). `submit_daily_score`를 대결에서 그대로 호출하지 않고 게임별 순수 검증을 공유 모듈로 추출한다. 추출 후 일일 score SQL 회귀 테스트를 실행한다.

## 9. 알림과 개인정보

알림 action은 `duel_room_invite`, `duel_room_joined`, `duel_result`로 확장하고 payload에는 match ID와 안전한 room route만 넣는다. 현재 push route는 홈으로 안전 fallback하므로 ([푸시 라우팅](../lib/core/notifications/push_notification_route.dart)), stale/not-participant이면 홈이나 대결 목록으로 보낸다. 알림을 눌렀다고 자동 입장·READY·게임 시작하지 않는다.

기존 social RPC는 알림 전체 발신 건수로 일일 한도를 계산할 수 있다 ([소셜 액션 migration](../supabase/migrations/20260821000600_nickname_colors_social_actions.sql)). duel room/result 알림은 찌르기·자랑하기 한도에서 분리한다. 푸시 실패에도 대결 목록과 inbox가 남아야 한다.

상대 잔액, seed, private raw score는 상대에게 노출하지 않는다. 자기 자신·NPC·테스트 격리 규칙에 걸린 계정은 후보에서 제외한다. 테스트 계정끼리와 일반 계정 사이의 방·푸시·결과를 기존 isolation 정책과 함께 검증한다.

## 10. 구현 순서와 acceptance

1. 서버 schema/RPC: room revision, presence lease, 둘째 READY 원자 escrow, common clock, expiry/settle, RLS를 SQL 테스트로 만든다.
2. 런타임 seam: 대결 context, seed override, common start_at, durable result retry를 만들고 일일 경로 회귀를 확인한다.
3. UI/Realtime: 신청·방 입장·가이드·로딩·READY·자동 시작·결과와 event loss polling fallback을 붙인다.
4. 활성화: 서버 검증이 끝난 게임 한두 개만 `duel_enabled`로 켜고 실기기에서 동시 READY·background·재접속·정산을 확인한다.

출시 gate는 다음을 모두 통과해야 한다.

- 금액 step 10, positive integer, 서버 범위·잔액 검증이 UI와 일치한다.
- 요청·입장·첫 READY에서는 무차감이고 둘째 READY만 양쪽 동시 escrow 차감한다.
- 동시 마지막 READY·READY 취소·leave·늦은 heartbeat가 한 번만 결정된다.
- 둘째 READY 검증 실패는 정상 응답으로 READY를 초기화하고 무차감이다.
- 한 account 한 room session, stale device와 room revision 요청이 거절된다.
- common `start_at`과 3초 countdown을 두 run이 공유하며 늦은 이벤트가 시계를 재설정하지 않는다.
- waiting TTL은 10분만 적용하고 starting/playing을 초대 만료로 환불하지 않는다.
- 정상 0점, no-result, forfeit, tie가 게임별 계약대로 분리된다.
- 네트워크 단절은 즉시 기권시키지 않고 durable retry와 submit deadline으로 복구한다.
- 대결이 일일 랭킹·도전권·XP·광고 사용량을 바꾸지 않는다.
- 동시성·재시도에도 coin ledger와 partial payout이 중복되지 않는다.
- 계정 삭제·테스트 전환 전에 pending escrow와 상대 지분이 void 정산된다.
- seed/private score/잔액이 Realtime·푸시·비참가자 조회로 누출되지 않는다.
- `duel_enabled`를 끈 게임은 신규 방을 만들 수 없고 이미 시작한 방은 정산된다.

## 11. 남은 제품 결정

다음은 추천값을 확정할 때 결정할 항목이다.

1. 최소 10·최대 200·기본 100 코인과 계정당 미종결 방 1개를 채택할 것인가?
2. waiting 방 TTL 10분, 공통 countdown 3초, heartbeat 5초·lease 15초를 채택할 것인가?
3. 1:1 요청 수신 허용 toggle과 신고·차단 정책을 이번 출시 범위에 포함할 것인가?
4. partial payout을 허용할 경제 상한과 미수령 채권 UI를 출시 전에 확정할 것인가?

이 버전의 시작 계약은 두 READY 원자 커밋과 공통 `start_at`으로만 발생한다.
