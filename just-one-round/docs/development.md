# 개발 및 기기 검증

## 공통 검사

프로젝트의 한글 상위 경로에서 Flutter 3.44.7의 `flutter analyze`가 LSP JSON 파싱 오류를 낼 수 있다. 코드 정적 검사는 다음 명령을 사용한다.

```sh
dart analyze
flutter test
```

Android 및 iOS 빌드는 한글 경로에서도 정상 동작한다.

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
