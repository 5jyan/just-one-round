# 딱한판만 작업 규칙

- 작업 루트는 `just-one-round/`이며 앱 식별자는 딱한판만, 패키지는
  `com.justoneround.app`이다.
- Android 서명·배포 작업은 먼저 [Android 서명 및 배포 런북](docs/android-release.md)을
  읽는다. `android/key.properties`가 없는 것은 정상이며 blocker로 취급하지 않는다.
- 서명 fallback 순서는 완전한 `android/key.properties`, 비어 있지 않은
  `ANDROID_UPLOAD_STORE_PASSWORD` 계열 환경변수, 프로젝트 전용 macOS Keychain
  항목(service `just-one-round-android-upload-key-20260731`, account `upload`)이다.
  기본 keystore는 `android/app/upload-keystore.jks`, alias는 `upload`다.
- Dart-only Shorebird Android OTA에서 표준 서명 helper가 Keychain 조회 실패(exit 51)로
  끝나면 사용자에게 Android keystore 비밀번호를 다시 묻지 말고
  `tool/with_shorebird_ota_signing.sh -- shorebird patch --platforms=android ...`를
  사용한다. 이 helper는 실행 중 임시 keystore를 만들고 종료 시 삭제한다. 이는 기존
  Play Console 업로드 키를 대체하지 않으며 `shorebird release android`, Play Console용
  AAB, native/asset 변경 배포에는 사용하지 않는다.
- iOS와 Android OTA를 함께 요청받으면 같은 base release와 `stable` track을 사용해 두
  플랫폼의 dry-run을 먼저 완료한 뒤 실제 patch를 모두 게시한다. iOS 코드서명이 막힌
  Dart-only patch는 `--no-codesign`을 사용해 계속 진행하고, 한 플랫폼만 성공한 상태로
  완료 보고하지 않는다.
- 비밀번호·키 내용은 출력하거나 파일에 저장하지 않는다. 기존 작업 변경은 보존하고
  담당 파일만 패치한다. `git reset`, `git checkout`, `git clean`은 사용하지 않는다.
- `Shook` 프로젝트는 절대 열거나 수정하지 않는다.

## 장시간 빌드

- 장시간 빌드·Archive·export·upload는 항상 `tool/with_build_awake.sh -- ...`로 실행해 작업 중 시스템 절전을 방지한다(배터리에서도 명령 실행 동안 적용). 이 래퍼는 화면 잠금이나 키체인 인증을 우회하지 않는다.
- Android 서명·배포 명령은 빌드 래퍼 안에 `tool/with_android_signing.sh -- ...`를 중첩한다. 자세한 운영 방법은 [무인 빌드](docs/unattended-builds.md)를 따른다.
