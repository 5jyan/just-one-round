# 딱한판만 (Just One Round)

하루에 한 판, 게임별 2~5분 제한 시간 안에 미니게임을 플레이하고 그날의 순위를 확인하는 모바일 게임 앱.

## 핵심 약속

- 매일 다른 미니게임을 제공한다.
- 기본 플레이 기회는 하루 한 판이다.
- 보상형 광고를 보면 한 판을 추가로 플레이할 수 있다.
- 플레이 직후 전체 및 조건별 순위를 보여준다.
- 짧게 플레이하지만 매일 다시 방문할 이유를 만든다.

## 초기 기술 방향

- 클라이언트: Flutter + Flame
- 서버: Supabase (PostgreSQL, Auth, Edge Functions)
- 개발 환경: 로컬 Supabase
- 대상: iOS / Android
- 초기 시장: 한국
- 영문명: Just One Round
- 내부 프로젝트명: `just-one-round`

## 문서

- [제품 정의](docs/product.md)
- [MVP 범위](docs/mvp.md)
- [기술 구조](docs/architecture.md)
- [도트 UI/UX 방향](docs/design-system.md)
- [개발 및 기기 검증](docs/development.md)
- [출시 체크리스트와 Shorebird OTA 규칙](docs/release-checklist.md)
- [미결정 사항](docs/open-questions.md)

## 다음 목표

첫 번째 미니게임 하나를 선택해 다음 흐름을 실제 기기에서 끝까지 실행한다.

`앱 실행 → 익명 사용자 생성 → 오늘의 게임 → 한 판 플레이 → 점수 제출 → 오늘의 순위 → 광고 대체 버튼 → 추가 한 판`
