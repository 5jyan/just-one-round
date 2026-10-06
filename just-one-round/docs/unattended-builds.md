# 무인 장시간 빌드

이 Mac에는 사용자 LaunchAgent `com.justoneround.build-awake`가 설치되어 있다.
`RunAtLoad`와 `KeepAlive`로 로그인할 때 `/usr/bin/caffeinate -s`를 유지한다.
`-s`는 AC 전원에서 시스템 sleep assertion을 유지하며 화면 잠금, 디스플레이 절전,
뚜껑 닫기, 사용자가 직접 선택한 잠자기, 재부팅 후 첫 로그인은 바꾸지 않는다.

## 실행 규칙

장시간 build, Xcode Archive, export, store upload는 프로젝트 루트에서 다음처럼
실행한다.

```sh
tool/with_build_awake.sh -- \
  shorebird release ios \
  --export-options-plist=ios/ExportOptions-Shorebird-AppStore.plist \
  --dry-run
```

Android 서명·배포는 기존 서명 래퍼를 안쪽에 둔다.

```sh
tool/with_build_awake.sh -- \
  tool/with_android_signing.sh -- \
  shorebird release android --artifact aab
```

`tool/with_build_awake.sh`는 macOS에서 `caffeinate -is`로 명령을 감싸고, 다른
운영체제에서는 명령을 그대로 실행한다. `--`는 선택 사항이며 명령이 없으면
종료 코드 64를 반환한다.

## 지속 설정 확인과 제거

현재 사용자 세션의 상태는 다음으로 확인한다.

```sh
launchctl print gui/$(id -u)/com.justoneround.build-awake
pmset -g assertions
```

제거할 때는 먼저 LaunchAgent를 내리고 plist를 삭제한다.

```sh
launchctl bootout gui/$(id -u) \
  "$HOME/Library/LaunchAgents/com.justoneround.build-awake.plist"
rm "$HOME/Library/LaunchAgents/com.justoneround.build-awake.plist"
```

화면이 잠긴 뒤에도 CLI 빌드와 업로드는 계속 실행될 수 있다. Xcode·Simulator·웹
브라우저처럼 화면과 사용자 입력이 필요한 단계는 잠금 화면에서 진행되지 않는다.
재부팅 뒤에는 사용자가 한 번 로그인해야 사용자 LaunchAgent가 시작되고, 뚜껑을
닫거나 전원을 잃으면 `caffeinate -s`만으로 작업을 계속할 수 없다.

## 자격 증명 상태

이 설정은 절전 방지용이다. Apple Developer/App Store Connect 인증, iOS 코드서명,
notarization, Android 키체인 접근 권한과 같은 자격 증명을 자동으로 새로 만들거나
영구적으로 저장하지 않는다. 현재 로그인 키체인은 잠금 시간 제한 없이 설정되어
있고, 프로젝트 전용 Android Keychain 항목의 `/usr/bin/security`를 통한 프로젝트
Android 비밀번호 조회는 이 세션에서 성공했지만 값은 출력하거나 저장하지 않았다.
Apple Distribution 로그인 키체인을 사용한 iOS 코드서명 임시 바이너리 probe도
프롬프트 없이 종료 코드 0으로 끝났다. 이 상태가 스토어 제출 준비를 증명하는
것은 아니다.

App Store Connect UI Integrations API access는 활성화되었다. 딱한판만 전용 API 키는
이름과 App Manager 권한까지 준비했지만, 생성·다운로드하고 CLI에서 검증하는 단계가
남아 있다. Google Play에는 딱한판만 전용 least-privilege API 자격 증명이 없으므로
Android 업로드도 자동으로 준비된 상태라고 간주하지 않는다.
해당 자격 증명이 없거나 만료되었으면 잠금 방지와 무관하게 로그인·키체인 승인 또는
수동 조치가 필요할 수 있다.
