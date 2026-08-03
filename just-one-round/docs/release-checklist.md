# 딱한판만 출시 체크리스트

마지막 갱신: 2026-08-04

## Shorebird OTA

- Shorebird 앱 ID: `3dd8845d-0de5-4362-b06a-ad463b923e54`
- 이번 App Store 제출 릴리스: `1.0.5+10` (Apple 로그인 후 업로드·심사 제출 대기)
- Flutter 버전: `3.44.8`
- 기존 스토어 기준 릴리스: Android `1.0.3+8`, iOS `1.0.2+8`
- iOS 출시 릴리스: `1.0.4+9` (2026-08-02 App Store 공개 확인)
- Android 내부 테스트 릴리스: `1.0.5+10` (2026-08-04 Google Play 게시 확인)
- Android 기준 AAB:
  `build/app/outputs/bundle/release/app-release.aab`
- iOS 기준 IPA:
  `build/ios/ipa/딱한판만-1.0.5+10.ipa`

스토어에 위 기준 릴리스를 먼저 배포한 뒤, Dart 코드만 바뀐 긴급 수정은
플랫폼별로 다음 명령을 실행한다.

```sh
upload_secret=$(security find-generic-password \
  -a upload \
  -s just-one-round-android-upload-key-20260731 \
  -w)
ANDROID_UPLOAD_STORE_PASSWORD="$upload_secret" \
  shorebird patch --platforms=android --release-version=1.0.4+9

shorebird patch \
  --platforms=ios \
  --release-version=1.0.4+9 \
  --export-options-plist=ios/ExportOptions-Shorebird-AppStore.plist
```

네이티브 코드, Flutter 엔진, 새 파일을 포함한 에셋 변경은 OTA 대상이
아니므로 버전과 빌드 번호를 올린 뒤 새 `shorebird release`와 스토어
업데이트를 만든다. 실제 게시 전에는 각 명령 끝에 `--dry-run`을 붙여
검증한다.

## 출시 차단 항목

- [x] 운영자명 `Saul Park` 확정
- [x] 공개 문의 이메일 `saulpark12@gmail.com` 반영
- [x] `legal-site`의 운영자명과 문의 정보 치환
- [x] 법적 문서 사이트를 `https://legal.shook.work`에 공개하고 앱의
  기본 법적 문서 URL로 지정
- [ ] Android 업로드 키 생성 후 `android/key.properties` 작성
- [ ] iOS·Android 앱 아이콘과 시작 화면을 실제 브랜드 이미지로 교체
- [x] Xcode에서 Apple Distribution 인증서와 App Store 프로비저닝 프로파일
  생성
- [x] 연결된 Supabase 프로젝트에 새 마이그레이션과
  `delete-account` Edge Function 배포
- [x] App Store Connect 개인정보 라벨을
  `docs/store-privacy-declarations.md`와 대조하여 게시
- [ ] Google Play Console 데이터 보안 설문 제출
- [ ] AdMob 운영 앱 ID·광고 단위·SSV 설정과 동의 메시지(UMP) 확인

## App Store Connect

- [x] 앱 레코드와 iOS 버전 `1.0.4` 생성
- [x] 한국어 설명, 홍보 문구, 키워드, 지원 URL, 저작권 입력
- [x] 심사 연락처, 심사 메모, 수동 출시 설정
- [x] 게임/캐주얼/액션 카테고리와 콘텐츠 권한 설정
- [x] 연령 등급 설문 완료(대한민국 전체, 글로벌 9+)
- [x] 개인정보 처리방침 URL과 개인정보 라벨 게시
- [x] 가격 무료, 공개 배포, 대한민국만 사용 가능하도록 설정
- [x] 검증하지 않은 Apple Silicon Mac 및 Apple Vision Pro 배포 제외
- [x] EU DSA 비거래자·EU 미배포로 신고
- [x] 대한민국 비즈니스 연락처 이메일 인증 및 규정 준수 활성화
  (`saulpark12@gmail.com`, 사업자등록번호 없음)
- [ ] 손쉬운 사용 지원 기능은 실제 기기 검증 후 필요한 경우 게시
- [x] iPhone 6.9형 소개 이미지 5장 업로드
  (6.5형에도 자동 적용, 1→2→3→4→5 순서 확인)
- [x] 첫 출시 대상을 iPhone 전용으로 변경
  (`TARGETED_DEVICE_FAMILY = 1`, iPad 스크린샷 불필요)
- [x] Apple Distribution 서명 빌드 `1.0.4 (9)` 업로드 및 선택
- [x] iOS `1.0.4 (9)` App Store 심사 제출
  (2026-08-01 23:37 KST, 제출 ID
  `e804d51a-f76a-460b-95e0-e902159174e6`)
- [x] iOS `1.0.4 (9)` 공개 후 운영 최소 지원 빌드를 `8`로 상향
  (iOS 빌드 7 이하 강제 업데이트, Android 빌드 8 유지)
- [ ] Apple Distribution 서명 빌드 `1.0.5 (10)` 업로드 및 선택
- [ ] iOS `1.0.5 (10)` App Store 심사 제출

## Google Play

- [x] 내부 테스트 트랙에 `1.0.5 (10)` 게시
  (2026-08-04, 출시명 `1.0.5 (10) - 광고 보상 즉시 시작`)

## 앱과 서버에 반영된 항목

- [x] 앱 설정에서 약관·개인정보처리방침·운영정책 접근
- [x] 앱 안에서 익명 계정과 연결 데이터 삭제
- [x] 닉네임 자동 필터, 신고, 사용자 차단
- [x] PIN 검증 없이 일반 사용자가 테스트 계정으로 승격할 수 있던 RPC 제거
- [x] 설정의 버전 7회 터치와 서버 PIN 검증을 통과한 계정만 테스트 모드 활성화
- [x] iOS 릴리즈 설정에서 개발용 로컬 네트워크 권한 제거
- [x] Android 릴리즈에서 디버그 키 사용 제거
- [x] 서버 최소 지원 빌드와 앱 강제 업데이트 화면 연결
- [x] 실제 iOS App Store 상품 URL
  `https://apps.apple.com/app/id6794861323`을 강제 업데이트 설정에 입력

## 출시 직전 검증

- [x] `flutter test` (2026-08-03, 292개 통과)
- [x] `flutter build appbundle --release --build-name 1.0.5 --build-number 10`
  (실제 업로드 키로 서명 및 `jarsigner -verify` 확인)
- [x] iOS Release Xcode Archive 및 앱 설정 검증
- [x] iOS `1.0.5 (10)` Release 앱 생성, Apple Distribution 서명 및 IPA 검증
- [x] Android `1.0.5 (10)` 내부 테스트 게시 상태 확인
- [x] Shorebird iOS Release Archive·IPA 생성 및 App Store Connect 업로드
  (`1.0.4+9`, Shorebird release `744017`)
- [ ] 신규 설치 → 게임 → 광고 보상 → 점수 제출 확인
- [ ] 닉네임 신고·차단 후 닉네임만 숨고 순위·비교 기록 수가 유지되는지 확인
- [ ] 오전 6시 10분 이후 전날 NPC 포함 최종 결과가 한 번만 표시되는지 확인
- [ ] 계정 삭제 후 Supabase Auth와 연결 데이터 삭제 확인
- [ ] Kakao Login/OIDC와 Supabase manual linking 설정 확인
- [ ] Android/iOS Native app key, package/bundle ID, custom scheme 설정 확인
- [ ] 전날 플레이를 완료한 카카오 미연결 계정의 다음 날 기본 플레이가 프로필 연결 화면에서 차단되는지 확인
- [ ] 카카오 미연결 계정도 광고 검증을 거쳐 두 번째 시도를 받을 수 있는지 확인
- [ ] 개인정보 선택 메뉴가 필요한 지역에서 Google UMP 화면 확인
- [ ] 공개 법적 문서 URL이 앱과 스토어 등록정보에서 모두 열리는지 확인
- [ ] 신고 큐 운영 담당자와 확인 주기 지정

## 새 게임 출시 순서

새 게임을 포함한 앱 빌드가 스토어에 공개되기 전에는 해당 게임을 오늘의
게임 로테이션에 넣지 않는다.

1. 새 게임 행의 `minimum_app_build`를 해당 게임이 처음 포함된 앱 빌드
   번호로 설정한다.
2. iOS·Android 업데이트가 스토어에서 실제로 설치 가능한지 확인한다.
3. `app_runtime_config`의 스토어 URL을 실제 상품 페이지로 확인한다.
4. `minimum_supported_build`를 새 빌드 번호로 올린다.
5. 새 게임을 `is_active = true`로 전환한다.

```sql
update public.games
set minimum_app_build = 2, is_active = true
where id = 'new_game_id';

update public.app_runtime_config
set minimum_supported_build = 2
where id;
```

`minimum_supported_build`를 먼저 올리면 스토어 업데이트가 아직 보이지 않는
사용자가 플레이할 수 없으므로 반드시 스토어 공개 확인 뒤 실행한다.

## 권장 검토

변호사 또는 개인정보 전문가 검토는 출시의 기술적 필수 조건은 아니다.
다만 아래에 해당하면 공개 전 검토를 권장한다.

- 아동을 주 이용자로 설계하거나 아동의 개인정보를 추가로 처리하는 경우
- 유료 결제·구독·현금성 보상을 추가하는 경우
- 위치·연락처·사진·건강정보 같은 민감도가 높은 정보를 추가하는 경우
- 해외 이용자를 적극 대상으로 하거나 맞춤형 광고 범위를 넓히는 경우
- 사업자 구조나 위탁·국외 처리 관계가 문안과 일치하는지 판단하기 어려운 경우
