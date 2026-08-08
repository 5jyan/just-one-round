# 개발 및 기기 검증

## 스토어 배포 빌드 규칙

스토어에 올리는 Android/iOS 빌드는 항상 Shorebird를 통해 생성한다. 일반
Flutter 빌드나 Xcode Archive는 Shorebird 업데이트 런타임이 포함되지 않으므로
스토어 업로드에 사용하지 않는다.

```sh
# 새 스토어 기준 버전: 먼저 dry-run으로 검증
shorebird release android --artifact aab \
  --build-name <version-name> --build-number <version-code> --dry-run
shorebird release ios \
  --export-options-plist=ios/ExportOptions-Shorebird-AppStore.plist --dry-run

# 검증 후 같은 명령에서 --dry-run을 제거해 릴리스를 생성하고,
# Shorebird가 출력한 AAB/IPA만 Play Console/App Store Connect에 업로드한다.
```

`flutter build appbundle`, `flutter build ipa`, Xcode Archive는 로컬·서명·실기기
검증용으로만 사용한다. Shorebird 기준 릴리스를 스토어에 배포한 다음 Dart 코드만
수정한 경우에는 해당 기준 버전을 지정해 `shorebird patch`를 실행한다. 새 버전이나
네이티브 코드·Flutter 엔진·에셋 변경은 새 `shorebird release`와 스토어 업데이트가
필요하다.

## 공통 검사

프로젝트의 한글 상위 경로에서 Flutter 3.44.7의 `flutter analyze`가 LSP JSON 파싱 오류를 낼 수 있다. 코드 정적 검사는 다음 명령을 사용한다.

```sh
dart analyze
flutter test
```

Android 및 iOS 빌드는 한글 경로에서도 정상 동작한다.

## 로컬 Supabase 연결

```sh
npm run supabase:start
npm run supabase:reset
```

iOS Simulator도 실제 Supabase 저장소를 사용하며, 기본값인 `http://127.0.0.1:54321`로 로컬 서버에 바로 연결한다. Android Emulator는 호스트 주소가 다르므로 실행할 때 지정한다.

```sh
flutter run -d <android-emulator-id> \
  --dart-define=SUPABASE_URL=http://10.0.2.2:54321
```

실기기는 Mac의 같은 Wi-Fi LAN 주소를 `SUPABASE_URL`로 지정한다. 운영 빌드에서는 반드시 Supabase Cloud의 HTTPS 주소와 publishable key를 지정한다.

별도 값을 전달하지 않은 디버그 빌드는 로컬 Supabase를 사용하고, 릴리스
빌드는 운영 프로젝트 `https://yvowpyeoaexdrycgtyri.supabase.co`와 코드에
포함된 공개 publishable key를 자동 사용한다. 필요하면 기존
`SUPABASE_URL`/`SUPABASE_ANON_KEY` dart-define으로 어느 빌드에서든 덮어쓸 수
있다.

## 카카오 로그인

카카오 로그인은 설정 화면의 `카카오 계정 연결`에서 실행되며, 현재 익명
Supabase 계정의 기록을 유지하면서 Kakao identity를 연결한다.

1. Kakao Developers에서 Android 패키지 `com.justoneround.app`과 iOS
   번들 ID `com.justoneround.app`을 등록하고 Native app key를 발급한다.
2. Kakao Login을 켜고 OpenID Connect와 `openid` 동의항목을 활성화한다.
3. Supabase Dashboard의 Authentication > Providers > Kakao에 REST API key와
   client secret을 등록하고, Authentication 설정에서 manual linking을 켠다.
   로컬 Supabase는 `supabase/config.toml`에 이미 활성화되어 있다.
4. Kakao Developers의 Platform key에 표시된 custom scheme을
   `ios/Flutter/Debug.xcconfig`와 `ios/Flutter/Release.xcconfig`의
   `KAKAO_CUSTOM_SCHEME` 값에 넣는다.

실행 시 Native app key는 dart-define으로 전달한다.

```sh
flutter run -d <device-id> \
  --dart-define=KAKAO_NATIVE_APP_KEY=<native-app-key> \
  --dart-define=KAKAO_CUSTOM_SCHEME=<custom-scheme>
```

Android는 두 dart-define 값을 빌드 manifest에 자동 반영한다. iOS는
`KAKAO_CUSTOM_SCHEME`만 xcconfig에도 설정해야 하며, 앱 키 자체는 서버 비밀이
아니므로 dart-define으로 전달해도 된다. Kakao 계정 연결은 Supabase의
`linkIdentityWithIdToken`을 사용하므로 기존 익명 user ID와 기록이 유지된다.
단, 이미 다른 Supabase 계정에 연결된 카카오 계정이면 해당 계정으로 전환하며
새 익명 세션의 기록은 자동 병합하지 않는다.

전날 플레이를 완료한 익명 계정이 다음 날 첫 판을 시작하려면 카카오 계정 연결이
필수다. 연결하지 않은 상태에서는 홈의 기본 플레이 버튼이 프로필 화면을 열고,
서버의 `claim_daily_attempt` RPC도 Kakao identity가 없으면 거부한다. 보상형 광고
추가 플레이는 익명 계정에도 열려 있으며, `prepare_rewarded_ad`/
`claim_rewarded_attempt` RPC는 Kakao 여부와 무관하게 AdMob 서버 검증과 일일
시도 제한을 적용한다.

하드코딩된 미리보기 저장소가 필요할 때만 다음 플래그를 명시한다.

```sh
flutter run -d <device-id> --dart-define=USE_PREVIEW_REPOSITORY=true
```

## iOS Simulator

```sh
flutter build ios --simulator
xcrun simctl install <simulator-id> build/ios/iphonesimulator/Runner.app
xcrun simctl launch <simulator-id> com.justoneround.app
```

게임 중 홈 전환은 Simulator의 Home 버튼으로, 강제 종료는 다음 명령으로 재현한다.

```sh
xcrun simctl terminate <simulator-id> com.justoneround.app
```

홈 전환·전화 수신·다른 시스템 UI 노출로 앱이 `inactive`, `hidden`, `paused` 상태가 되면 진행 중인 판은 즉시 중단한다. 강제 종료로 만료 요청을 전송하지 못한 경우에도 서버에 남은 `issued` 시도를 다음 실행에서 `expired`로 복구하므로 같은 기회를 다시 사용할 수 없다.

### Supabase 중단·복구 검증

점수 제출 직전에 로컬 Supabase를 중지한 뒤, 결과 화면에서 전송 실패 안내가 보이는지 확인한다. 완료 점수는 기기에 보관되며, 스택을 다시 시작하고 홈으로 돌아오거나 `지금 다시 전송`을 누르면 자동 복구된다.

```sh
npm run supabase:stop
npm run supabase:start
```

같은 시도 결과를 두 번 보내도 `scores`에는 한 건만 남고 동일한 순위 결과가 반환되어야 한다.

### 날짜 변경 일정 검증

`daily_games`에 없는 미래 날짜를 대상으로 `ensure_daily_game`을 호출하면 활성 게임 하나가 배정된다. 같은 날짜를 다시 호출해도 동일한 `game_id`, `game_version`이 반환되어야 한다.

일일 게임은 한국 시간 오전 6시에 변경된다. `current_play_date`는 오전
`05:59:59`까지 전날을, `06:00:00`부터 당일을 반환해야 한다.
전날 점수 제출은 오전 6시 10분에 마감되고, 이후
`get_unseen_previous_daily_result`가 NPC 포함 최종 결과를 한 번 반환해야 한다.

```bash
docker exec -i supabase_db_just-one-round psql -U postgres -d postgres \
  -c "select public.current_play_date('2026-07-26 20:59:59+00'), public.current_play_date('2026-07-26 21:00:00+00');"
```

### 실제 기기 테스트 모드

일반 계정에서 설정 화면 아래의 앱 버전을 4초 안에 7회 누르면 테스터 PIN 입력창이 열린다.
PIN은 `activate_test_mode` RPC에서만 검증하며 앱에는 저장하지 않는다. 잘못된
PIN을 5회 입력하면 해당 계정의 인증이 15분간 잠긴다. 테스트 계정은 같은 위치를
7회 누르면 PIN 없이 `deactivate_test_mode` RPC를 호출해 일반 모드로 돌아간다.

```sh
docker exec supabase_db_just-one-round psql -U postgres -d postgres \
  -c "select * from public.ensure_daily_game(current_date + 30);"
```

## Android 실기기

```sh
flutter run -d <android-device-id>
```

디버그 APK만 만들 때는 다음을 사용한다.

```sh
flutter build apk --debug
```

## iOS 실기기

### Flutter가 연결된 디버그 실행

```sh
flutter run -d <ios-device-id>
```

iOS 14 이상에서 Flutter debug 빌드는 Flutter 도구 또는 Xcode 디버거 연결 없이 홈 화면에서 단독 실행할 수 없다. `flutter run --no-resident`로 설치한 뒤 앱만 직접 실행하는 방식은 정상 검증으로 간주하지 않는다.

### 디버거 없는 단독 실행 검증

사용자가 홈 화면에서 직접 실행하는 동작을 확인할 때는 profile 빌드를 사용한다.

```sh
flutter build ios --profile
xcrun devicectl device install app \
  --device <core-device-id> \
  build/ios/iphoneos/Runner.app
xcrun devicectl device process launch \
  --device <core-device-id> \
  --terminate-existing \
  com.justoneround.app
```

무선 iOS 디버깅은 빌드가 끝난 뒤 VM Service 연결 단계에서 오래 대기할 수 있다. 앱 자체 실행 검증이 목적이면 profile 방식을 우선하고, hot reload가 필요할 때는 USB 연결을 우선한다.

## 완료 판정

- 빌드 성공만으로 실기기 실행 성공으로 판정하지 않는다.
- 앱 설치 여부를 확인한다.
- 앱을 실제로 실행한다.
- 실행 프로세스가 몇 초 뒤에도 유지되는지 확인한다.
- 가능하면 화면을 직접 확인하거나 캡처한다.
