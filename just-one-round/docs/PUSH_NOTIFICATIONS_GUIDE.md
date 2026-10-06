# 한국어 푸시 알림 운영 가이드 (일반 앱 기준)

이 문서는 iOS와 Android를 함께 지원하는 일반 모바일 앱에서 푸시 알림을
설계·구현·출시·운영할 때 지켜야 할 기준을 정리한다. 예시는 Firebase Cloud
Messaging(FCM)을 공통 전송 계층으로 사용하고, iOS에서는 APNs를 거치는
구성을 전제로 한다.

푸시 알림은 “서버가 메시지를 보냈다”와 “사용자가 알림을 봤다”가 같은
사건이 아니다. 앱의 사용자 설정, OS 권한, Android 채널, 설치별 토큰,
서버 큐, Apple/Google의 전달 상태를 별개의 상태로 관리하고, 각 단계의
실패를 앱 안의 대체 경험과 운영 지표로 연결해야 한다.

## 1. 먼저 고정할 일반 원칙

### 1.1 앱 토글과 OS 권한은 서로 다른 계약이다

앱 설정의 “알림 받기” 토글은 서비스가 어떤 종류의 알림을 보내도 되는지에
대한 제품 수준의 선택이다. iOS의 알림 권한과 Android 13 이상의
`POST_NOTIFICATIONS` 권한은 운영체제가 해당 앱의 알림 표시를 허용하는지에
대한 시스템 수준의 선택이다. Android의 알림 채널은 그보다 더 세분화된
시스템 설정이다.

따라서 다음을 하나의 Boolean 값으로 합치지 않는다.

| 상태 축 | 대표 상태 | 관리 주체 | 의미 |
| --- | --- | --- | --- |
| 앱 선호 | `on`, `off` | 앱·백엔드 | 이 계정/알림 종류에 대해 서비스가 전송을 시도해도 되는가 |
| iOS OS 권한 | `notDetermined`, `authorized`, `provisional`, `denied` | iOS | 배너·소리·배지 등의 표시를 허용하는가 |
| Android OS 권한 | `unknown`, `granted`, `denied`, `blocked` | Android 13+ | 앱 알림을 시스템 서랍에 표시할 수 있는가 |
| Android 채널 | `notCreated`, `enabled`, `disabled`, 중요도 설정 | 사용자·Android | 특정 종류의 알림을 어떤 방식으로 표시할 것인가 |
| 설치 토큰 | `missing`, `pending`, `active`, `stale`, `invalid`, `revoked` | 앱·백엔드·FCM | 어느 앱 설치 인스턴스로 보낼 것인가 |
| 전송 구성 | `ready`, `notConfigured`, `degraded` | 빌드·서버 운영 | Firebase, APNs, worker가 전송할 준비가 되었는가 |

일반적인 전송 허용 조건은 다음과 같다.

```text
전송 가능
  = 앱 선호가 on
  ∧ OS 권한이 허용 상태
  ∧ (Android라면 대상 채널이 차단되지 않음)
  ∧ 해당 설치의 토큰이 active
  ∧ 서버·provider 구성이 ready
```

서버가 OS의 최신 권한과 채널 상태를 항상 알 수 있는 것은 아니다. 그러므로
앱은 권한 상태를 확인할 때마다 서버에 알려야 하고, 서버는 최소한 앱 선호와
활성 토큰을 전송 직전에 다시 확인해야 한다. 앱 선호를 끄면 OS 권한이
허용되어 있어도 보내지 않는다. 반대로 앱 선호를 켠다고 OS 권한을 우회할 수
없으며, 사용자가 OS 설정에서 차단한 상태를 앱 토글만으로 “켜짐”이라고
표시해서도 안 된다.

### 1.2 권한 요청 UX

- 첫 실행 직후 무조건 시스템 권한 창부터 띄우지 말고, 어떤 알림을 언제
  받을 수 있는지 짧게 설명한 뒤 사용자가 기능을 선택한 맥락에서 요청한다.
- 앱 토글을 켰지만 OS 권한이 `denied` 또는 `blocked`라면 “앱 설정은 켜져
  있지만 시스템에서 차단됨”을 구분해 표시하고 시스템 설정으로 이동하는
  경로를 제공한다.
- 사용자가 거부한 권한을 앱 시작 때마다 반복 요청하지 않는다. 제품이
  다시 설명할 합리적인 시점을 정하고, 이후에는 설정 이동을 안내한다.
- 마케팅·소셜·거래·보안 등 목적이 다른 알림은 가능한 한 앱 토글과
  Android 채널을 목적별로 분리한다. 필수 고지처럼 법적·계약상 예외가
  있다면 그 근거와 사용자 고지 방식을 별도로 문서화한다.

### 1.3 알림 메시지 계약

각 알림 종류마다 다음을 미리 정한다.

- 목적과 수신 대상, 앱 선호 키 및 OS 채널
- 제목·본문·언어·시간대와 잠금 화면에 보일 정보
- `notification_id`, 타입, 버전, 안전한 내부 목적지 같은 최소 payload
- 탭했을 때의 목적지와 데이터가 만료되거나 삭제된 경우의 fallback
- 중복 합치기(collapse), 보존 기간, quiet hours, 사용자별 rate limit
- foreground, background, terminated 각각의 표시·처리 방식

payload의 route, action, URL을 클라이언트가 그대로 신뢰하지 않는다. 서버가
허용 목록을 사용하고, 탭 시 최신 권한과 리소스 상태를 다시 확인한다.

## 2. iOS: APNs와 FCM 연결

### 2.1 Apple capability·entitlements·provisioning

1. Apple Developer의 해당 App ID/Bundle ID에서 Push Notifications capability를
   활성화한다.
2. Xcode target의 **Signing & Capabilities**에서 **Push Notifications**를
   활성화한다. 이 설정은 `aps-environment` entitlement가 앱에 포함되는
   출발점이다.
3. 개발·배포 provisioning profile이 같은 Bundle ID를 가리키고 Push
   Notifications entitlement를 포함하는지 확인한다. development profile은
   보통 `aps-environment=development`, App Store와 TestFlight용 profile은
   `production`을 사용한다. archive의 서명된 entitlement를 실제로
   확인하고, profile 이름만 믿지 않는다.
4. silent/background 데이터 처리가 필요할 때만 Xcode의 **Background Modes >
   Remote notifications**를 추가하고, 해당 payload와 처리 시간이 OS
   정책에 맞는지 검증한다. 단순한 사용자 표시 알림과 백그라운드 데이터
   갱신은 요구사항을 구분한다.
5. Firebase에 등록한 iOS 앱의 Bundle ID, Xcode target, provisioning profile의
   Bundle ID가 모두 정확히 일치해야 한다. `GoogleService-Info.plist`도
   같은 Firebase 앱에서 발급한 파일을 사용한다.

Apple은 앱 설치마다, 그리고 앱·기기·복원 상태가 바뀔 때 APNs device token을
발급할 수 있다. 앱 시작 시 APNs 등록을 수행하고, 성공한 token을 FCM SDK에
전달한 뒤 FCM registration token을 서버에 등록한다. APNs token을 영구
캐시하거나 FCM token 대신 서버의 유일한 키로 취급하지 않는다.

### 2.2 APNs `.p8` 키를 FCM에 등록

1. Apple Developer에서 Push Notifications를 사용할 APNs Authentication Key를
   만든다. Key ID와 Team ID를 별도로 기록한다.
2. Firebase Console의 프로젝트 설정에서 **Cloud Messaging > iOS app
   configuration > APNs authentication key**로 이동한다.
3. `.p8` 파일, Key ID, Team ID를 등록하고 Firebase의 iOS 앱 Bundle ID와
   대상 환경을 다시 확인한다. `.p8` 원본은 저장소나 이슈·로그에 넣지 않고
   비밀 저장소에서 관리한다.
4. 개발 빌드와 TestFlight/App Store 빌드가 서로 다른 Bundle ID나 Firebase
   프로젝트를 사용한다면 각각의 매핑을 명시적으로 관리한다. 개발 token으로
   production 앱을 검증하거나 반대로 검증하지 않는다.

FCM을 쓰더라도 Apple 쪽 capability, entitlement, profile, APNs key가 모두
맞아야 한다. FCM 콘솔의 앱 등록만으로 iOS 서명 설정이 완성되는 것은 아니다.

### 2.3 런타임 순서와 iOS 테스트

권장 순서는 다음과 같다.

1. 앱이 사용자에게 알림 목적을 설명하고 `UNUserNotificationCenter` 권한을
   요청한다.
2. 허용 결과가 `authorized` 또는 제품 정책상 허용한 `provisional`일 때만
   `registerForRemoteNotifications()`를 호출한다.
3. APNs token 수신을 기다린 뒤 FCM token을 조회한다. token이 아직 없으면
   실패로 확정하지 말고 앱 재개, 네트워크 회복, token refresh 이벤트에서
   다시 시도한다.
4. FCM token과 설치 식별자, 앱 버전, 권한 상태를 TLS로 백엔드에 upsert한다.
5. token refresh 또는 권한·계정 변경 시 같은 등록 경로를 재사용한다.

다음은 반드시 실제 iPhone/iPad에서 확인한다.

- 새 설치에서 권한 허용·거부·나중에 결정하지 않음 각각의 상태
- 개발 서명 빌드와 TestFlight production entitlement의 전달
- 앱 foreground, background, terminated 상태의 표시
- 알림 탭으로 cold start했을 때의 초기 route와 로그인 만료 처리
- 기기 복원·재설치·앱 업데이트 후 APNs/FCM token 갱신
- Apple Developer App ID, Team ID, Key ID, Firebase iOS 앱, Bundle ID가
  서로 다른 조합으로 섞이지 않았는지

시뮬레이터는 UI와 일부 앱 흐름을 확인하는 데 쓸 수 있지만, APNs/FCM
production smoke test의 통과 근거로 사용하지 않는다. 최종 출시는 실제
기기와 TestFlight에서 검증한다.

## 3. Android: FCM, Android 13 권한, notification channel

### 3.1 Firebase 구성

- Firebase에 등록한 Android 앱의 package name이 실제 `applicationId`와
  일치해야 한다.
- `google-services.json`은 해당 Firebase 앱에서 내려받아 앱 모듈의
  기대 위치에 둔다. debug/release, flavor별 Firebase 프로젝트가 다르면
  파일과 빌드 변형을 함께 분리한다.
- Google Services Gradle plugin과 Firebase Messaging SDK가 실제 release
  variant에 적용되는지 확인한다. 로컬에서 파일이 없을 때 앱이 조용히
  “푸시를 지원하는 것처럼” 보이지 않도록 빌드 검증을 둔다.
- FCM token은 설치 인스턴스별로 서버에 등록하고 token refresh callback을
  놓치지 않는다.

### 3.2 Android 13+ `POST_NOTIFICATIONS`

Android 13(API 33) 이상에서는 일반 알림에 runtime permission이 필요하다.

1. manifest에 `android.permission.POST_NOTIFICATIONS`를 선언한다.
2. 사용자에게 필요한 이유를 설명한 뒤 적절한 화면에서 runtime permission을
   요청한다. 새로 설치한 앱은 사용자가 허용하기 전까지 알림이 꺼진 상태로
   취급한다.
3. `granted`, `denied`, 사용자가 다시 묻지 않도록 막은 `blocked`를 앱 상태와
   서버 등록 상태에 반영한다. 거부했다고 앱 토글 자체를 임의로 끄지 않는다.
4. 앱 설정에서 토글을 켰는데 시스템 권한이 없으면 Android 앱 알림 설정으로
   이동할 수 있게 한다.

Android 12L 이하에서는 같은 runtime permission 흐름이 없더라도 앱 전체
알림 설정과 채널 설정을 확인한다. OS 버전 업그레이드·앱 복원으로 권한이
자동 승계되는 경우가 있으므로 매 실행 시 현재 상태를 읽는다.

### 3.3 notification channel

Android 8.0(API 26) 이상에서 알림은 channel에 속해야 한다.

- 앱 시작 또는 background message가 도착하기 전 `NotificationChannel`을
  생성한다. channel ID는 안정적으로 유지하고 사용자에게 보이는 이름과
  설명은 목적을 명확히 쓴다.
- FCM payload의 `channel_id`가 실제 기기에 존재하는 ID인지 확인한다. 없는
  ID를 보내면 의도한 중요도·표시가 적용되지 않거나 알림이 표시되지 않을
  수 있으므로 기본 channel도 준비한다.
- 중요도, 소리, 진동은 channel 생성 시 정해지고 사용자가 시스템 설정에서
  변경할 수 있다. 이미 생성된 channel의 동작을 코드로 강제하지 않는다.
  정책을 바꾸려면 새 channel ID와 마이그레이션 안내를 검토한다.
- 소셜·거래·마케팅처럼 사용자가 구분해야 하는 종류는 channel을 분리한다.
  단, 종류를 지나치게 잘게 나누어 설정 화면을 복잡하게 만들지 않는다.
- 앱 토글은 서버 전송 여부를 결정하고, channel은 로컬 표시 방법을
  결정한다. channel이 켜져 있다는 이유로 앱 토글이 꺼진 사용자에게
  전송하지 않는다.

## 4. 토큰 lifecycle, 다중 기기, 권한 거부

### 4.1 토큰 저장 모델

토큰은 계정 하나에 하나만 저장하지 말고 설치 인스턴스 단위로 저장한다. 최소
필드는 다음과 같다.

| 필드 | 용도 |
| --- | --- |
| `user_id` | 현재 계정과의 연결 |
| `installation_id` | 앱 설치·기기 인스턴스 구분. 앱 재설치 시 바뀔 수 있음 |
| `platform`, `provider` | `ios`/`android`, `fcm` 등 전송 경로 |
| `token` | 현재 FCM registration token. 암호화 전송·접근 제한 |
| `environment` | development, TestFlight/production 등 전송 환경 |
| `app_version`, `build` | 장애 재현과 점진적 차단 |
| `permission_status`, `channel_snapshot` | 마지막으로 확인한 로컬 상태 |
| `last_seen_at`, `token_updated_at` | stale 정리와 health 판단 |
| `enabled`, `disabled_reason` | 전송 대상 여부와 비활성 사유 |

실제 schema가 다르더라도 다음 lifecycle을 지원해야 한다.

- 최초 로그인·앱 재개: 현재 token과 권한 상태를 upsert한다.
- FCM token refresh: 새 token을 즉시 등록하고 이전 token을 더 이상 해당
  설치의 active token으로 사용하지 않는다.
- APNs token 변경: FCM SDK가 새 FCM token을 내도록 초기화·등록 순서를
  재실행한다.
- 로그아웃·계정 전환: 이전 계정에서 설치를 비활성화하거나 새 계정으로
  원자적으로 재연결한다. 한 token이 두 계정의 active 대상이 되지 않게 한다.
- OS 권한 거부·channel 차단: 앱은 서버에 상태를 동기화하고 전송 대상에서
  보수적으로 제외한다. 사용자가 설정에서 다시 허용하고 앱이 재개되면
  token과 상태를 다시 upsert한다.
- FCM/APNs가 영구 실패를 반환: token을 즉시 `invalid`/`disabled`로 만들고
  계속 재시도하지 않는다.
- 장기간 미접속: `last_seen_at` 기준의 stale 정책으로 비활성화하고, 다시
  앱이 열리면 새 등록으로 복구한다.

### 4.2 다중 기기와 권한 거부의 사용자 경험

한 사용자가 여러 기기를 쓰는 것은 정상이다. 사용자의 active installation을
모두 대상으로 fan-out하되, 같은 token의 중복 row는 unique 제약으로
합친다. 특정 기기만 끄는 기능을 제공한다면 계정 전체의 앱 선호와 별도의
기기별 선호를 구분한다.

OS 권한 거부는 오류 화면이 아니라 정상적인 상태다.

- 시스템 알림을 표시할 수 없다는 사실을 앱 설정에서 설명한다.
- 알림 내용을 앱 내 inbox, badge가 아닌 앱 내 상태, 이메일 등 승인된
  대체 경로로 제공한다.
- 권한을 허용하지 않았다는 이유로 사용자의 핵심 기능을 임의로 막지 않는다.
- 설정 변경 후 앱으로 돌아오면 권한을 다시 조회하고 token 등록을 재시도한다.

## 5. 백엔드 delivery contract

### 5.1 durable outbox

도메인 이벤트를 만든 트랜잭션과 알림 outbox row 생성을 가능한 한 같은
트랜잭션으로 묶는다. 요청 처리 중 바로 FCM을 호출하면 DB 성공·전송 실패가
엇갈리고 재처리 근거가 사라진다.

outbox와 token별 delivery에 다음 정보를 둔다.

```text
outbox:
  id, event_id, recipient_id, notification_type, payload/template
  idempotency_key, status, created_at, next_attempt_at

delivery:
  outbox_id, installation_id, token_snapshot, status, attempt_count
  lease_id, lease_until, provider_message_id, last_error
  sent_at, disabled_reason
```

`event_id + recipient_id + notification_type`처럼 제품 의미가 같은 사건을
식별하는 idempotency key에 unique 제약을 둔다. webhook 재전송, cron 재실행,
클라이언트 재시도로 outbox가 중복 생성되어도 한 사건이 여러 메시지로
불어나지 않아야 한다. 한 outbox가 여러 기기로 fan-out된다면 성공·실패를
token별 delivery로 기록한다.

### 5.2 claim lease와 동시성

webhook worker와 주기적인 retry worker가 동시에 실행될 수 있다는 전제로
설계한다.

1. `pending`/`retry`이고 `next_attempt_at <= now()`이며 lease가 없거나
   만료된 delivery를 transaction 안에서 선택한다.
2. `FOR UPDATE SKIP LOCKED` 또는 동등한 원자 claim으로 row를 잡고,
   랜덤 `lease_id`와 짧은 `lease_until`을 기록한다.
3. transaction을 commit한 뒤 외부 provider를 호출한다. lease를 오래 잡은
   DB transaction 안에서 네트워크 요청을 하지 않는다.
4. 성공·영구 실패·재시도 결과를 `where lease_id = ...` 조건으로 기록한다.
   worker가 죽으면 lease 만료 후 다른 worker가 회수한다.

lease는 중복 실행을 줄여 주지만 외부 전송의 exactly-once를 보장하지 않는다.
provider 호출이 성공한 뒤 응답을 저장하기 전에 worker가 죽으면 재시도에서
중복 표시가 생길 수 있다. 따라서 payload에 stable `notification_id`를 넣고
클라이언트 inbox와 analytics에서 중복을 제거하며, 제품상 중복이 치명적인
알림은 provider의 collapse 기능과 별도 dedupe 정책을 함께 사용한다.

### 5.3 재시도와 backoff

결과를 영구 실패와 일시 실패로 분류한다.

| 결과 | 처리 |
| --- | --- |
| 2xx/명시적 성공 | `sent_at` 기록, lease 종료 |
| 429, timeout, network error, provider 5xx | retryable. `Retry-After`가 있으면 우선 사용 |
| 인증서·service account 만료, 설정 오류 | token을 지우지 말고 lease를 풀어 운영 알림을 발생 |
| token 미등록·만료·unregistered·bad device token | permanent. token 비활성화 후 같은 token으로 재시도하지 않음 |
| payload 형식 오류·허용되지 않은 route | permanent 또는 quarantine. 원인 수정 전 무한 재시도 금지 |

재시도는 exponential backoff와 jitter를 사용하고 최대 횟수·최대 보존
시간을 둔다. 예를 들어 1분, 5분, 30분, 2시간처럼 증가시키되 서비스의
SLO와 provider rate limit에 맞춰 조정한다. 최종 실패는 dead-letter 또는
운영 대기 상태로 남겨 원인과 마지막 시각을 조회할 수 있게 한다.

### 5.4 invalid token cleanup

provider가 token을 더 이상 알 수 없다고 응답하면 해당 설치의 token을
`disabled`로 만들고 사유·provider code·시각을 기록한다. 같은 token을 매번
큐에 다시 넣지 않는다. 앱이 다음 실행에서 새 token을 올리면 upsert로
복구한다. cleanup은 사용자 계정 전체를 삭제하는 동작이 아니라 해당 설치
등록만 정리하는 동작이어야 한다.

### 5.5 strict opt-out

앱 토글을 끈 사용자는 이미 큐에 들어간 알림도 새로 provider에 보내지 않는
것을 기본 정책으로 한다.

- 이벤트를 만들 때 앱 선호를 확인한다.
- worker가 claim할 때 앱 선호와 알림 종류별 선호를 다시 확인한다.
- 토글 변경 transaction은 아직 보내지 않은 delivery를 `suppressed`로
  전환하고 `next_attempt_at` 대상에서 제외한다.
- claim row에는 선호 버전 또는 `opted_out_at`을 함께 기록하고, provider
  호출 직전에도 버전이 바뀌지 않았는지 확인한다.
- 이미 provider에 전달된 요청은 회수할 수 없으므로, opt-out 이후에는
  재시도하지 않고 진행 중인 lease를 취소한다. 법적·계약상 “엄격한 차단”이
  요구되면 선호 변경과 send reservation의 잠금 순서를 별도로 검토한다.

앱 토글을 클라이언트에서만 검사하는 것은 strict opt-out이 아니다. 서버가
최종 전송 gate를 소유해야 한다.

### 5.6 secret management

다음 값은 코드, Markdown 예시의 실제 값, git history, issue, 로그, URL
query string에 넣지 않는다.

- Firebase service account 또는 FCM HTTP v1 credential
- Apple APNs `.p8`, Key ID·Team ID 조합의 비밀 관리 정보
- Supabase service role key, worker 인증 secret, webhook signing secret
- 사용자 식별 정보가 포함된 원본 payload와 device token

배포 환경의 secret manager 또는 CI secret store에서 주입하고, worker에는
최소 권한만 준다. 발급자·사용처·만료·교체 담당자를 기록하고 주기적으로
rotate한다. 운영 로그에는 `user_id`, `outbox_id`, 설치 hash, provider code와
같은 비식별화된 진단 정보만 남기며 raw token과 본문은 마스킹한다.

### 5.7 webhook·cron·observability

권장 흐름은 “outbox insert database webhook으로 빠른 wake-up + 짧은 주기의
cron으로 누락·재시도 회수”다. webhook은 전송 결과를 기다리지 말고 검증된
요청을 queue worker에 전달한다. cron은 webhook이 유실되거나 worker가
중단되어도 lease 만료 row를 다시 처리한다. 두 경로 모두 idempotency와
lease를 사용한다.

최소 관측 항목은 다음과 같다.

- queue depth, oldest age, pending/retry/suppressed/dead-letter 수
- claim 성공·lease 만료·중복 claim 차단 수
- provider 성공률, 429/5xx/timeout, permanent invalid token 수
- 평균·p95 전송 지연, 알림 종류·플랫폼·앱 버전별 성공률
- opt-out suppression 수와 사용자 탭/앱 내 fallback 사용량
- webhook HTTP 오류, cron 실행 누락, secret/auth 실패

모든 로그와 지표에 `outbox_id`/`delivery_id`/correlation ID를 연결하되
token·본문·credential은 기록하지 않는다. queue age와 auth 실패에는 알람을
두고, provider 성공률만으로 “사용자가 실제로 읽었다”고 해석하지 않는다.

## 6. foreground·background·terminated·tap UX

| 앱 상태 | 기본 표시 경로 | 앱 구현 원칙 |
| --- | --- | --- |
| Foreground | 앱 안 banner/inbox 또는 명시한 OS banner 한 가지 | SDK callback과 OS presentation을 동시에 켜 duplicate banner를 만들지 않는다 |
| Background | 권한이 있으면 OS가 notification payload를 표시 | 본문 표시를 위해 앱 코드가 깨어나야 한다고 가정하지 않는다. data-only는 best effort로 취급한다 |
| Terminated | 표시 가능한 alert payload는 OS가 보관·표시하고 탭 시 앱을 시작 | 초기화 전에 payload를 잃지 않게 `getInitialMessage`에 해당하는 cold-start 경로를 처리한다 |
| Tap | 인증 후 허용된 목적지로 이동하고 해당 inbox 내용을 확인 | payload를 검증하고 대상이 삭제·만료되었으면 inbox나 안전한 홈으로 보낸다. 읽음 처리는 사용자가 앱 안의 확인을 누른 뒤 수행한다 |

구현 세부사항은 SDK마다 다르지만 다음 흐름은 공통이다.

- foreground callback에서 앱 상태를 갱신하고, 알림을 읽음 처리할 때 서버
  중복 요청을 idempotent하게 만든다.
- background handler에서는 UI navigation을 시도하지 않는다. 짧은 저장·동기화
  후 종료하며, 오래 걸리는 작업이나 필수 비즈니스 로직을 push 도착에
  의존하지 않는다.
- terminated cold start에서는 navigator/auth/session이 준비될 때까지
  tap payload를 잠시 보관한다. 같은 payload가 callback과 initial message로
  두 번 들어오면 `notification_id`로 한 번만 처리한다.
- 알림 탭 자체를 구매·삭제·게임 시작 같은 irreversible action으로 취급하지
  않는다. 탭은 안전한 화면으로 이동시킨 뒤 해당 inbox 내용을 보여주고,
  최종 행동과 읽음 처리는 앱 안에서 사용자가 확인하도록 한다.
- iOS 사용자가 앱을 강제 종료했거나 Android에서 앱을 시스템 설정으로
  force-stop한 경우 background 동작이 제한될 수 있다. 이를 우회하는
  비공식 방법을 전제로 제품 약속을 만들지 않는다.

## 7. 보안·개인정보·quiet hours·rate limits

### 7.1 보안과 개인정보

- 잠금 화면에서 제3자가 볼 수 있는 제목·본문에는 비밀번호, 인증코드,
  결제 세부정보, 민감한 사회관계·건강정보를 직접 넣지 않는다. 필요하면
  “새 소식이 있습니다”처럼 최소화하고 앱에서 인증 후 상세 내용을 조회한다.
- device token은 계정과 설치를 연결하는 식별자다. TLS 전송, 저장 접근제어,
  보존 기간, 계정 삭제 시 정리, 운영자 조회 감사를 적용한다.
- FCM/APNs credential은 서버 전용이다. 클라이언트 설정 파일과 server
  credential을 같은 secret으로 재사용하지 않는다.
- notification payload의 action·URL·사용자 ID를 서버가 허용 목록과 권한으로
  검증한다. 클라이언트가 “앱 토글이 켜졌다”고 보내는 값만으로 전송하지 않는다.
- 개인정보 처리방침과 앱 권한 설명에 수집하는 token의 목적, 보존·삭제,
  제3자 전송(FCM/APNs)을 실제 운영과 일치하게 반영한다.

### 7.2 quiet hours

- 사용자의 locale/timezone을 기준으로 quiet hours를 계산한다. 서버 지역
  시간이나 고정 UTC 시간만 사용하지 않는다.
- DST와 timezone 변경을 처리하고, 조용한 시간에 도착한 알림은 discard할지
  다음 허용 시간에 한 번만 요약할지 알림 종류별로 정한다.
- 긴급·보안 알림을 quiet hours 예외로 둘 수 있다면 별도 동의·채널·법적
  근거를 명시한다. 일반 소셜·마케팅 알림을 긴급으로 포장하지 않는다.

### 7.3 rate limits와 중복 방지

- 사용자·설치·알림 종류·발신자별 분당/일일 한도를 둔다.
- 같은 사건은 idempotency key와 stable notification ID로 한 번만 만들고,
  짧은 시간의 여러 업데이트는 collapse 또는 digest로 합친다.
- FCM/APNs 429와 앱 내 abuse를 모두 고려한다. 서버 worker concurrency,
  provider quota, webhook 재시도 폭주를 함께 제한한다.
- rate limit에 걸린 알림은 조용히 유실하지 말고 `suppressed`/`collapsed`와
  사유를 운영 지표에 남긴다.

## 8. 출시 전 실기기 매트릭스

최종 pass는 시뮬레이터가 아니라 실제 기기·실제 서명 artifact·실제
배포형 worker에서 얻는다. 테스트 계정과 테스트용 알림 payload를 사용하고,
운영 사용자에게 시험 알림을 보내지 않는다.

| 영역 | 최소 조합 | 확인할 것 |
| --- | --- | --- |
| iOS 개발 | 실제 iPhone/iPad + development profile | capability, `aps-environment`, 권한 허용/거부, token 등록 |
| iOS 배포 | TestFlight + App Store signing | production APNs, Firebase `.p8`, release Bundle ID, cold start |
| Android 구버전 | 지원하는 API 32 이하 실제 기기 | Firebase config, 앱 알림 설정, background/terminated |
| Android 13+ 신규 설치 | API 33 이상 실제 기기 | `POST_NOTIFICATIONS` prompt, allow/deny/설정 복귀 |
| Android channel | API 26 이상 | channel 생성 전/후, channel별 차단·중요도·소리 |
| 다중 기기 | 동일 계정의 iOS + Android 또는 2대 | fan-out, 중복 token, 한 기기 로그아웃 |
| 앱 선호 | 앱 토글 on → off → on | pending outbox suppression, 재활성화 후 새 token/전송 |
| 앱 상태 | foreground/background/terminated | 표시 경로, duplicate 방지, tap route, auth 만료 |
| lifecycle | 재설치·앱 복원·업데이트·token refresh | 이전 token cleanup, 새 token upsert |
| 운영 장애 | 네트워크 차단, 429/5xx, worker 중지 | lease 만료 회수, backoff, dead-letter, 알람 |
| 안전성 | 만료된 알림·삭제된 리소스·잘못된 route | 안전한 fallback, irreversible action 미실행 |

각 조합에서 “서버 outbox 생성 → claim → provider 응답 → device 표시 →
탭 후 앱 상태”를 correlation ID 하나로 추적한다. 단순히 provider API가
200을 반환한 것만으로 pass 처리하지 않는다.

## 9. 장애 진단표

| 증상 | 우선 확인할 원인 | 진단·조치 |
| --- | --- | --- |
| iOS에 APNs token이 없음 | 권한, 실제 기기 여부, capability/profile 불일치 | 현재 `authorizationStatus`, registration error, signed entitlement, Bundle ID와 profile을 확인하고 네트워크 회복 후 재등록 |
| 개발 빌드는 되지만 TestFlight가 안 됨 | production entitlement 또는 Firebase APNs key 매핑 오류 | archive의 `aps-environment`, App ID, TestFlight Bundle ID, Firebase `.p8` Key ID/Team ID를 대조 |
| iOS FCM token 요청이 너무 빠름 | APNs token 도착 전 `getToken()` 호출 | APNs 등록 완료·token refresh 이벤트 뒤 FCM token을 조회하고 timeout 후 재시도 |
| Android 13+에서 prompt·알림이 없음 | manifest 누락, runtime 거부, `blocked` 상태 | `POST_NOTIFICATIONS`, target SDK, 현재 앱 권한과 설정 화면을 확인 |
| Android 특정 종류만 안 보임 | channel ID 누락·오타·사용자 차단 | 기기에 channel이 생성됐는지, payload ID가 일치하는지, channel importance가 0이 아닌지 확인 |
| background는 보이지만 foreground가 안 보임 | foreground callback/presentation 정책 | foreground에서 한 가지 표시 경로만 선택했는지 확인. callback은 도착했는지 로그로 분리 |
| 탭해도 올바른 화면이 안 열림 | initial message 누락, navigator/auth 준비 전 route 실행 | terminated용 initial 경로와 background tap stream을 모두 처리하고, 준비 후 한 번만 route |
| 앱 토글을 껐는데 계속 옴 | 서버 최종 gate 부재, 이미 active인 다른 기기, 오래된 queue | preference와 delivery를 worker 직전 재확인하고 pending을 suppress하며 모든 설치를 조회 |
| 같은 알림이 여러 번 옴 | 중복 outbox, lease 만료 후 unknown provider result, client dedupe 부재 | idempotency unique key, lease ownership, stable notification ID와 inbox dedupe를 점검 |
| invalid token 로그가 누적됨 | provider 영구 실패를 retryable로 분류 | `unregistered`/bad token을 즉시 비활성화하고 다음 앱 실행의 token refresh로 복구 |
| worker가 401/403 | service account/APNs credential/secret 오류 | token을 삭제하지 말고 secret manager·권한·만료·시계·환경을 확인한 뒤 알람 |
| worker가 429/5xx | quota·동시성·provider 장애 | `Retry-After`, exponential backoff, concurrency, oldest queue age를 확인 |
| queue row가 남아 전송되지 않음 | webhook 유실, cron 미실행, lease가 오래됨 | webhook 응답과 cron 실행 시각, `lease_until`, `next_attempt_at`, dead-letter를 확인 |
| 알림은 왔지만 내용이 오래됨 | payload에 전체 내용을 고정, tap 후 refresh 부재 | payload는 ID·최소 표시만 두고 탭 후 서버에서 최신 상태를 조회 |

## 10. 프로젝트 적용 메모: `just-one-round`

이 절부터는 위 일반 원칙을 현재 저장소에 매핑한 내용이다. 일회성 Firebase,
Apple Developer, Supabase secret과 배포 명령은 별도
[프로젝트별 푸시 설정 런북](PUSH_NOTIFICATIONS_SETUP.md)을 기준으로 한다.

- 현재 `social_notifications`는 **앱 선호**다. 프로필의
  `social_notifications_enabled`와 앱 설정의 “소셜 푸시 알림” 토글이 이
  상태를 표현하며, APNs 권한·Android `POST_NOTIFICATIONS`·Android channel
  상태와 같은 값이 아니다. 서버의 소셜 알림 생성·outbox 전송 gate는 이
  선호를 최종적으로 존중해야 한다.
- 클라이언트 Firebase 초기화는 `ENABLE_FIREBASE_PUSH` compile-time flag로
  켜진다. 로컬·테스트에서 명시적으로 켜려면
  `--dart-define=ENABLE_FIREBASE_PUSH=true`를 사용한다. release/profile
  기본값과 Firebase client config의 존재 여부, 실제 배포 artifact 검증은
  위 설정 런북을 따른다.
- 현재 데이터 흐름은 소셜 알림 row, `push_notification_outbox`, 설치별
  FCM token 등록, `send-social-push` worker, 외부 webhook/cron으로 이어진다.
  outbox claim lease, retry, invalid token cleanup의 실제 명령과 배포 전제는
  일반 원칙을 이 프로젝트의 schema·worker에 맞춘 설정 런북에 기록한다.
- iOS와 Android 앱 식별자는 `com.justoneround.app` 기준으로 관리한다.
  `JustOneRound` capability·Bundle ID·signing profile·Firebase 앱을 서로
  일치시키고, TestFlight/App Store profile과 development profile을 섞지
  않는다.
- 현재 외부 연결 검증 결과 Apple Developer의 `com.justoneround.app`에는
  Push Notifications capability가 켜져 있고, 개발·App Store profile이
  존재한다. Firebase `just-one-round`의 iOS 앱에는 같은 Team ID의 APNs
  authentication key가 개발·프로덕션으로 등록되어 있다. 키를 새로 만들거나
  기존 키를 삭제하는 작업은 필요하지 않다.
- `Shook` 프로젝트·Bundle ID·signing credential은 이 앱과 분리한다.
  외부 터널 도메인이 설정 문서에 등장하더라도 Shook의
  Apple/Android 서명 자산이나 앱 식별자를 이 프로젝트의 푸시 구성에
  재사용하지 않는다.
- 알림 탭은 한정된 플레이 기회를 탭만으로 소비하지 않는 안전한 홈으로
  연결하고, OS 권한을 거부한 사용자는 앱 내 소셜 inbox를 fallback으로
  사용한다. 이 동작을 변경할 때는 route payload 검증과 cold-start 테스트를
  함께 갱신한다.

## 공식 참고 문서

- [Apple: Registering your app with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)
- [Apple: APS Environment Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment)
- [Firebase: Get started with FCM in Apple platform apps](https://firebase.google.com/docs/cloud-messaging/ios/get-started)
- [Firebase: Best practices for FCM registration management](https://firebase.google.com/docs/cloud-messaging/manage-tokens)
- [Android Developers: Notification runtime permission](https://developer.android.com/develop/ui/views/notifications/notification-permission)
- [Android Developers: Create and manage notification channels](https://developer.android.com/develop/ui/compose/notifications/channels)
- [Firebase: Receive messages in Flutter apps](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages)
