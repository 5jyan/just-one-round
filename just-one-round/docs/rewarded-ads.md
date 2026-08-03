# 보상형 광고 운영 가이드

현재 구현은 AdMob 보상형 광고 한 종류만 사용한다. 사용자가 첫 판을 끝낸 뒤
직접 버튼을 누른 경우에만 전체 화면 광고를 열고, AdMob 서버 검증(SSV)이
성공해야 두 번째 판을 발급한다.

## 개발 상태

- 디버그 빌드에서 광고 ID를 지정하지 않으면 Google 공식 테스트 광고를 쓴다.
- 릴리스 빌드는 아래 실제 앱/광고 단위 ID를 플랫폼별로 자동 선택한다.
  - Android 앱: `ca-app-pub-8518567556283844~6404200741`
  - Android 보상형: `ca-app-pub-8518567556283844/1476407770`
  - iOS 앱: `ca-app-pub-8518567556283844~1939296419`
  - iOS 보상형: `ca-app-pub-8518567556283844/8947557896`
- 공식 테스트 광고 단위는 프로젝트의 SSV 주소를 설정할 수 없으므로 광고
  화면까지만 확인할 수 있다. 보상 발급까지 확인하려면 실제 광고 단위를 만들고
  해당 기기를 AdMob 테스트 기기로 등록해야 한다.
- 광고는 앱 전체 음소거와 `PG` 콘텐츠 등급 제한으로 요청한다.
- UMP 동의 정보 갱신과 필요한 동의 화면을 거친 뒤에만 광고를 요청한다.

## AdMob에서 준비할 값

1. Android/iOS 앱과 `보상형` 광고 단위는 등록되어 있다.
2. 보상은 `extra_play`, 수량은 `1`로 설정되어 있다.
3. 사용자 경험을 위해 필수 동영상만 허용하고 광고 모음과 양방향 광고는
   사용하지 않는다.
4. 운영 Android/iOS 광고 단위의 서버측 확인 URL은 운영 Edge Function으로
   설정한다.

   `https://yvowpyeoaexdrycgtyri.supabase.co/functions/v1/admob-reward-callback`

   로컬 Supabase를 Cloudflare Tunnel로 띄운 iPhone에서 테스트할 때는 앱이
   세션을 로컬 DB에 만들기 때문에, 테스트 직전에 해당 광고 단위의 URL을
   운영 Edge Function의 `/local` 경로로 잠시 바꾸고 로컬 전달 secret을
   설정해야 한다.

   `https://yvowpyeoaexdrycgtyri.supabase.co/functions/v1/admob-reward-callback/local`

   로컬 테스트가 끝나면 운영 URL로 되돌리고 전달 secret을 삭제한다. SSV URL은
   광고 단위별 설정이며 앱 코드나 Flutter 빌드 인자로 환경별 주소를 자동
   전환할 수 없다.

5. 실제 기기를 테스트 기기로 등록한 뒤에 테스트한다. 실제 광고를 개발 중에
   반복 클릭하면 안 된다.

## 빌드 설정

운영 ID는 코드에 연결되어 있으므로 일반 릴리스 빌드에는 별도 광고 인자가
필요 없다. 다른 AdMob 광고 단위를 임시로 시험할 때만 플랫폼별 값을 덮어쓴다.

```sh
flutter build apk \
  --dart-define=ADMOB_ANDROID_REWARDED_AD_UNIT_ID=ca-app-pub-.../... \
  --dart-define=ADS_ENABLED=true

flutter build ios \
  --dart-define=ADMOB_IOS_REWARDED_AD_UNIT_ID=ca-app-pub-.../... \
  --dart-define=ADS_ENABLED=true
```

`ADMOB_REWARDED_AD_UNIT_ID`는 두 플랫폼에 공통으로 적용하는 호환용
덮어쓰기 값이다. 플랫폼별 값이 있으면 플랫폼별 값이 우선한다.

Android 앱 ID도 필요할 때 Gradle 속성으로 덮어쓸 수 있다.

```sh
flutter build apk \
  -PADMOB_APP_ID=ca-app-pub-...~... \
  --dart-define=ADMOB_ANDROID_REWARDED_AD_UNIT_ID=ca-app-pub-.../...
```

iOS 운영 앱 ID는 `ios/Flutter/Release.xcconfig`에, 개발용 테스트 앱 ID는
`ios/Flutter/Debug.xcconfig`에 분리되어 있다.

광고를 긴급 중단하려면 빌드 시 `--dart-define=ADS_ENABLED=false`를 사용한다.
운영 중 즉시 끄는 원격 스위치는 아직 포함하지 않았다.

## Supabase 배포 설정

### 환경별 SSV 콜백

보상형 광고의 SSV 콜백은 보상 세션을 만든 Supabase 프로젝트와 같은 환경을
가리켜야 한다.

| 앱/서버 환경 | 앱의 `SUPABASE_URL` | AdMob SSV 콜백 |
| --- | --- | --- |
| 운영 | `https://yvowpyeoaexdrycgtyri.supabase.co` | `https://yvowpyeoaexdrycgtyri.supabase.co/functions/v1/admob-reward-callback` |
| 로컬 iPhone 테스트 | `https://jor-api.shook.work` | `https://yvowpyeoaexdrycgtyri.supabase.co/functions/v1/admob-reward-callback/local` |

AdMob 콘솔이 Cloudflare Tunnel 주소를 직접 확인하지 못할 수 있으므로, 로컬
iPhone 테스트에서는 운영 Edge Function의 `/local` 경로를 사용한다. 이 경로는
임시 `ADMOB_LOCAL_CALLBACK_URL`로 서명된 콜백을 로컬 함수에 전달한다. 테스트
전에는 다음 secret을 추가하고, 완료 후에는 반드시 콜백 URL을 운영 주소로
복구하고 secret을 삭제한다.

```sh
supabase secrets set \
  ADMOB_LOCAL_CALLBACK_URL=https://jor-api.shook.work/functions/v1/admob-reward-callback
# 테스트 종료 후
supabase secrets unset ADMOB_LOCAL_CALLBACK_URL
```

운영 프로젝트:

- 이름: `just-one-round`
- 리전: 서울 (`ap-northeast-2`)
- 프로젝트 ref: `yvowpyeoaexdrycgtyri`
- URL: `https://yvowpyeoaexdrycgtyri.supabase.co`

콜백에서 허용할 AdMob 광고 단위를 쉼표로 구분해 저장한다. Google 콜백의
`ad_unit` 값이 숫자 부분만 오는 경우와 전체 광고 단위 ID가 오는 경우를 모두
처리한다.

```sh
supabase secrets set \
  ADMOB_REWARDED_AD_UNIT_IDS=ca-app-pub-8518567556283844/1476407770,ca-app-pub-8518567556283844/8947557896
supabase db push
supabase config push
supabase functions deploy admob-reward-callback --no-verify-jwt --use-api
```

AdMob의 URL 확인 도구는 synthetic callback을 사용하므로 URL 확인 중에만
`ADMOB_ALLOW_URL_VERIFICATION=true`를 사용한다. Android와 iOS 확인 또는 로컬
테스트가 끝나면 운영 프로젝트에는 `false`로 복구한다.

SSV 콜백은 Google 공개키의 ECDSA 서명을 확인하고, 다음 조건을 모두 만족할
때만 보상 세션을 `verified`로 바꾼다.

- 앱이 미리 만든 세션 ID와 사용자 ID가 콜백 값과 일치
- 허용 목록에 있는 광고 단위
- 중복되지 않은 AdMob transaction ID
- 당일에 만들었고 만료되지 않은 세션

## 광고 품질 운영 권장값

- AdMob의 민감한 카테고리와 앱 분위기에 맞지 않는 일반 카테고리를 차단한다.
- 광고 심사 센터를 주기적으로 확인하고 조잡하거나 오해를 유도하는 소재를
  차단한다.
- 시작 단계에서는 미디에이션, 광고 포드, 보상형 전면 광고를 켜지 않는다.
- 버튼 문구와 보상은 항상 명확하게 유지하고, 광고를 보지 않아도 기본 한 판은
  온전히 즐길 수 있게 둔다.

## 나중에 다른 광고사로 교체하기

화면과 게임 로직은 `RewardedAdService` 인터페이스만 사용한다. AppLovin 같은
다른 SDK를 붙일 때는 새 서비스 구현과 서버 콜백 검증 함수를 추가하고
`main.dart`의 provider 주입만 바꾸면 된다. 다만 네이티브 광고 SDK와
Android/iOS 설정은 새 광고사에 맞게 다시 빌드해야 한다.
