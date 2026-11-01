# 딱한판만 (Just One Round)

매일 바뀌는 짧은 미니게임을 플레이하고 그날의 실제 사용자 순위를 확인하는 모바일 게임 앱. 게임마다 생존·클리어 시간·정해진 라운드 등 종료 조건이 다르다.

## 핵심 약속

- 매일 다른 미니게임을 제공한다.
- 기본 플레이 기회는 하루 한 판이다.
- 기본 도전 후 보상형 광고로 도전 한 판을 추가하고, 이후에는 보유 도전권으로 추가 도전할 수 있다.
- 플레이 직후 내 순위·주변 순위를 확인하고 전체 일일 랭킹을 열 수 있다.
- 짧게 플레이하지만 매일 다시 방문할 이유를 만든다.

## 기술 구성

- 클라이언트: Flutter + Flame
- 서버: Supabase (PostgreSQL, Auth, Edge Functions)
- 개발 환경: 로컬 Supabase
- 대상: iOS / Android
- 초기 시장: 한국
- 영문명: Just One Round
- 내부 프로젝트명: `just-one-round`

## 문서

- [게임 목록과 구현 계약](docs/games.md)
- [제품 정의](docs/product.md)
- [MVP 범위](docs/mvp.md)
- [기술 구조](docs/architecture.md)
- [도트 UI/UX 방향](docs/design-system.md)
- [개발 및 기기 검증](docs/development.md)
- [Android 서명 및 배포 런북](docs/android-release.md)
- [푸시 알림 일반 가이드](docs/PUSH_NOTIFICATIONS_GUIDE.md)
- [프로젝트별 푸시 알림 설정](docs/PUSH_NOTIFICATIONS_SETUP.md)
- [출시 체크리스트와 Shorebird OTA 규칙](docs/release-checklist.md)
- [미결정 사항](docs/open-questions.md)

## 검증할 기본 흐름

게임별 변경을 배포하기 전에 아래 흐름을 실제 기기에서 확인한다. 게임별 세부 규칙과 검증 근거는 [게임 문서 색인](docs/games.md)을 따른다.

`앱 실행 → 익명 사용자 생성 → 무료 연습권 1장 → 오늘의 도전 → 점수 제출 → 오늘의 순위 → 선택형 광고 → 연습권 2장`
