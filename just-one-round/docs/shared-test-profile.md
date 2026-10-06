# 공용 개발 테스트 프로필

시뮬레이터와 개인 iPhone의 로컬 개발 빌드는 아래 한 계정으로 통일한다.

- Supabase 사용자 UUID: `b732c7b5-5f66-4c84-8740-8726a59719cd`
- 이메일: `shared-device-test@justoneround.local`
- 닉네임: `공용테스트`
- 용도: iOS Simulator·개인 iPhone 공용 로컬 테스트 계정
- 로컬 Supabase: Simulator는 `http://127.0.0.1:54321`, iPhone은 `https://jor-api.shook.party` 터널을 사용하며 같은 DB를 바라본다.

비밀번호는 커밋하지 않는다. 저장소 루트의 gitignored 파일
`.shared-test-profile.json`에만 둔다. 이 파일에는
`USE_SHARED_TEST_PROFILE`, `SHARED_TEST_PROFILE_EMAIL`,
`SHARED_TEST_PROFILE_PASSWORD`를 저장한다.

## 실행 원칙

- 시뮬레이터와 iPhone에서 개발 게임을 확인할 때는 항상
  `tool/run_shared_test_profile.sh --game-id <game-id> <device-id>`를 사용한다.
- 직접 `flutter run` 또는 `flutter build ios`를 실행할 때는 반드시
  `--dart-define-from-file=.shared-test-profile.json`을 포함한다.
- 실기기 자동 배포는 `deploy-just-one-round-ios` 절차가 이 파일과 위 UUID를 자동으로 사용한다.
- `tool/ensure_shared_test_profile.sh`가 로컬 DB 초기화 뒤에도 같은 UUID와 자격 증명을 다시 만든다.
- 위 준비 스크립트는 공개 로테이션용 마이그레이션을 바꾸지 않고 `--game-id`로 명시한 개발 게임만 로컬 DB에서 활성화한다. 게임을 생략하면 기존 선택을 보존한다.
- `USE_SHARED_TEST_PROFILE`을 전달하지 않은 일반·운영 빌드는 기존 익명 로그인 동작을 유지한다.
- 로컬 DB를 초기화한 경우 실행 래퍼나 배포 절차가 같은 UUID의 계정을 자동 복구한다.

## 물리 기기별 분리 계정

Android와 iOS를 서로 다른 일반 계정으로 확인해야 할 때는 저장소 루트의
`device-profiles/android.json`, `device-profiles/ios.json`을 사용한다. 두 파일은
`.gitignore`에 포함되어 있어 비밀번호를 커밋하지 않는다.

- Android USB: `device-profiles/android.json` → `안드로이드 일반계정`
- iOS Wi‑Fi: `device-profiles/ios.json` → `iOS 일반계정`

실행할 때는 기존 공용 프로필 대신 각 파일을 넘긴다.

```sh
flutter run --profile -d <android-device-id> \
  --dart-define-from-file=device-profiles/android.json \
  --dart-define=ENABLE_FIREBASE_PUSH=true

flutter run --profile -d <ios-device-id> \
  --dart-define-from-file=device-profiles/ios.json \
  --dart-define=ENABLE_FIREBASE_PUSH=true \
  --dart-define=SUPABASE_URL=https://yvowpyeoaexdrycgtyri.supabase.co
```

두 계정 모두 `is_test_account=false`인 이메일 계정이며, 현재 물리 기기 세팅은
각각 코인 5,000개·연습권 10장·도전권 10장이다. 공용 테스트 계정과 이 분리
계정을 혼동하지 않도록 iOS 배포 runbook의 canonical profile 자동 설정은 이
요청처럼 사용자가 분리를 명시한 경우에만 우회한다.

## 확인 쿼리

```sql
select id, nickname, is_test_account, test_game_id
from public.profiles
where id = 'b732c7b5-5f66-4c84-8740-8726a59719cd';
```
