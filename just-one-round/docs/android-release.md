# Android 서명 및 배포 런북

이 문서는 딱한판만 Android 릴리스를 한 흐름으로 처리하는 자동 런북이다.
모든 명령은 `just-one-round/`에서 실행한다. 대상 앱은 딱한판만
(`com.justoneround.app`), Shorebird app id는
`3dd8845d-0de5-4362-b06a-ad463b923e54`다.

## 서명 설정과 fallback

`android/key.properties`는 선택사항이다. 파일이 없는 것이 정상이며, 파일이
없거나 불완전해도 blocker가 아니다. 파일을 사용하는 경우 `storeFile`,
`storePassword`, `keyAlias`, `keyPassword`가 모두 비어 있지 않고 keystore
파일이 실제로 있어야만 파일 전체를 사용한다. 하나라도 빠지거나 경로가
틀리면 다음 fallback으로 넘어간다.

fallback 순서는 다음과 같다.

1. 완전한 `android/key.properties`
2. 비어 있지 않은 `ANDROID_UPLOAD_STORE_PASSWORD`와 선택적
   `ANDROID_UPLOAD_KEY_PASSWORD`, `ANDROID_UPLOAD_KEYSTORE`,
   `ANDROID_UPLOAD_KEY_ALIAS` 환경변수
3. macOS Keychain generic password 항목
   - service: `just-one-round-android-upload-key-20260731`
   - account: `upload`

환경변수 값이 빈 문자열이거나 공백뿐이면 미설정으로 처리한다. fallback 기본값은
`android/app/upload-keystore.jks`와 alias `upload`다. `ANDROID_UPLOAD_KEY_PASSWORD`가
비어 있지 않으면 key password만 override하며, 없으면 store password를 사용한다.
Keychain에는 store password만 두고 key 내용은 다루지 않는다. 완전한
`key.properties`가 있으면 Keychain을 조회하지 않는다.

민감정보를 출력하거나 파일에 저장하지 않는다. `set -x`, `echo`로 비밀번호를
보여 주는 명령, `security ... -w`의 출력 방치는 금지한다. 안전한 점검은 다음처럼
출력을 버린다.

```sh
test -f android/key.properties
test -f android/app/upload-keystore.jks
test -n "${ANDROID_UPLOAD_STORE_PASSWORD:-}"
/usr/bin/security find-generic-password \
  -s just-one-round-android-upload-key-20260731 -a upload -w >/dev/null
```

직접 Gradle을 실행해도 `build.gradle.kts`가 같은 Keychain fallback을 수행한다.
래퍼를 사용하면 keystore 경로를 절대 경로로 지정하고 Keychain 비밀번호를
비출력으로 주입한다.

## Shorebird OTA용 임시 서명 fallback

macOS Keychain이 비밀번호 조회를 거부하거나(`security` exit 51), `key.properties`와
환경변수도 사용할 수 없는 경우에는 Dart-only Android OTA에 한해 임시 서명을 사용한다.
Android keystore 비밀번호를 추출하거나 추측할 수는 없으므로 이 경로는 사용자에게
비밀번호를 반복해서 묻지 않고도 OTA를 완료하기 위한 표준 fallback이다.

프로젝트의 `tool/with_shorebird_ota_signing.sh`가 실행 중 `/tmp` 아래에 권한 제한된
임시 keystore와 무작위 비밀번호를 만들고, 전달한 `shorebird patch`가 끝나면 keystore와
임시 디렉터리를 삭제한다. 비밀번호는 출력하거나 파일에 저장하지 않는다.

먼저 기존 base release에 대한 dry-run을 실행한다.

```sh
tool/with_shorebird_ota_signing.sh -- \
  shorebird patch --platforms=android \
  --release-version=<version-name>+<version-code> \
  --track=stable --dry-run
```

dry-run이 통과하면 같은 명령에서 `--dry-run`만 제거해 실제 OTA를 게시한다.

이 fallback은 `shorebird patch --platforms=android`에만 허용한다. 다음 작업에는 절대
사용하지 않는다.

- `shorebird release android` 또는 새 store release 생성
- `flutter build appbundle` 결과물의 Google Play Console 업로드
- native/engine 변경이나 새 Android 리소스를 포함한 배포

위 작업은 Play Console에 등록된 실제 업로드 키가 필요하다. 임시 서명 patch가
Shorebird에서 거부되면 임의의 새 키를 기존 `android/app/upload-keystore.jks`에 복사하거나
`android/key.properties`를 만들지 말고, Keychain Access 인증을 사용한 실제 키 복구로
전환한다.

## 서명 검증과 AAB

먼저 사용자에게 묻지 않고 실행할 수 있는 안전한 검증을 수행한다.

```sh
env -u ANDROID_UPLOAD_STORE_PASSWORD \
  -u ANDROID_UPLOAD_KEYSTORE \
  JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
  ./android/gradlew -p android :app:verifyReleaseSigning

tool/with_android_signing.sh -- \
  ./android/gradlew -p android :app:verifyReleaseSigning
```

Shorebird 스토어 기준 릴리스는 먼저 dry-run으로 확인한 뒤 같은 서명 래퍼로
실행한다. 버전은 현재 `pubspec.yaml`의 버전을 사용하거나 릴리스 직전에
명시적으로 지정한다.

```sh
tool/with_android_signing.sh -- \
  shorebird release android --artifact aab --dry-run

tool/with_android_signing.sh -- \
  shorebird release android --artifact aab
```

생성된 Shorebird AAB만 검증한다. 경로가 다르면 Shorebird가 출력한 AAB 경로를
사용한다.

```sh
test -f build/app/outputs/bundle/release/app-release.aab
jarsigner -verify -verbose:summary build/app/outputs/bundle/release/app-release.aab
```

Android App Bundle에는 `JarInputStream` 기준으로 일부 메타데이터가 서명되지
않았다는 경고가 표시될 수 있다. `jar verified`가 나오고 명령이 성공하면 정상이며,
이 번들에 `-strict`를 붙여 경고를 오류로 승격하지 않는다.

Dart 코드만 바뀌고 이미 스토어에 배포된 기준 릴리스에 패치하는 경우에도
Android 서명 래퍼를 사용한다.

```sh
tool/with_android_signing.sh -- \
  shorebird patch --platforms=android --release-version=<version-name>+<version-code>
```

네이티브 코드, Flutter 엔진, 새 asset 변경은 patch가 아니라 새
`shorebird release android --artifact aab` 대상이다. 필요하면 다음으로 Shorebird
릴리스가 앱에 등록되었는지 확인한다.

```sh
shorebird releases list
```

## Google Play 최종 확인

Play Console에서 다음 대상을 고정한다.

- 앱: `딱한판만`
- 패키지: `com.justoneround.app`
- 기본 트랙: 프로덕션
- 테스트 트랙: 사용자가 명시적으로 요청한 경우에만 비공개 테스트(Alpha/private testing)
- 국가/지역: 요청된 국가만 타겟팅하며, 이번 공개는 대한민국 1개
- 업로드 파일: 위의 `shorebird release android`가 생성한 AAB 또는 Play Console 라이브러리에서 검증한 동일 AAB

로컬 서명 검증, Gradle `verifyReleaseSigning`, Shorebird dry-run, AAB 파일 존재
확인, `jarsigner` 검증, 버전 code 중복 확인은 사용자에게 묻지 않고 진행한다.
최종 Play 제출 직전에는 다음 항목을 직접 확인한다. 사용자가 해당 공개 출시 또는 제출을 이미 승인했다면 같은 승인을 다시 요청하지 않는다.

- 앱 이름과 패키지가 `딱한판만` / `com.justoneround.app`인지
- 신규 업로드이면 code가 중복되지 않는지, 기존 번들 승격이면 선택한 code가 정확한지
- Shorebird AAB를 선택했는지
- 대상 트랙이 프로덕션인지(테스트 요청이면 Alpha인지)와 국가/테스터 공개 범위가 맞는지
- 출시 노트와 staged rollout 여부가 의도와 맞는지

이 확인 후 Play Console의 최종 제출을 수행한다. 비밀값은 문서, 로그,
커밋, AAB 경로 외의 파일에 기록하지 않는다.

2026년 9월 17일 실제 공개 제출 확인:

- 프로덕션 트랙에 `1.0.15 (22)` App Bundle을 대한민국 1개 국가로 전체 출시 설정
- Play Console 제출 활동 ID `13`으로 검토 제출 완료
- 자동 빠른 검사 완료 후 상태가 `검토 중`으로 전환됨
- Google 검토 및 실제 Play 스토어 노출 시점은 외부 심사 결과를 따른다

## 격리 규칙

이 런북의 작업 루트는 `just-one-round/`뿐이다. `Shook` 프로젝트는 절대 열거나
수정하지 않는다. 기존 사용자 변경을 보존하며 `git reset`, `git checkout`,
`git clean`을 실행하지 않는다.
