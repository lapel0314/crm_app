# Release Notes

## v1.2.2 (준비 중) — 디자인 개편

- 디자인 토큰 도입 (`lib/theme/app_theme.dart`). 틸 시안 검토 후 핑크 유지로 확정. 통신사 배지 색(LG핑크/SK파랑/KT빨강)은 테마와 무관한 고정 토큰으로 분리.
- 대시보드 최상단 "오늘 할 일" 히어로 — 요금제/부가 미처리·사전예약 대기 건수, 클릭 시 바로 이동.
- 토스트 통일: 성공(진회색)/오류(빨강) 구분 + 아이콘, 전 화면 39곳.
- 목록 빈 상태를 아이콘+제목+안내문 구조로 개선 (주요 7개 화면).
- 데스크톱 하단 얇은 푸터(현재 매장/앱 버전), 상단바 보조 버튼 시각 무게 축소, 다이얼로그 규격 테마 통일.
- 로그인 히어로·사이드바 브랜드 로고 확대.
- 롤백 앵커: v1.2.1 (cb0a604) — 디자인 전체 되돌리기는 해당 태그로.

## v1.2.1

- 목록 페이지네이션에 처음/끝 페이지 이동(<< >>) 버튼 추가 (고객DB/가망고객/유선회원, 공용 위젯으로 통합).
- 고객정리: 확인 완료한 이슈를 "무시" 처리해 저장 (재계산돼도 다시 안 뜸). "무시됨 보기"에서 해제 가능. 검사값이 수정되면 자동 재검출, 중복 유형은 새 중복 발생 시 재표시.
- 사전예약 관리 페이지 신설 — 가망고객 페이지에서 진입. 고객명/번호/통신사/공시·선약/예약기종·색상/예약번호/받으실 날짜/신분증스캔/진행상태(대기·완료·취소) 관리.
- 회원가입 매장명이 자유입력에서 활성 매장 드롭다운으로 전환 (오타 유령매장 방지). 매장 이름 목록만 로그인 전에도 조회 가능하도록 서버 함수 추가.
- 좁은 창에서 상단 통합검색 입력칸이 버튼으로만 축소되던 것을 인라인 입력칸 유지로 개선.
- 로그인 화면에서 이메일/비밀번호 입력 후 엔터로 바로 로그인.
- 신규 DB 마이그레이션 3건: `data_quality_dismissals`, `pre_reservations`, `list_active_store_names()`.

## v1.2.0

- 모바일(Android) 통합검색/리베이트 진입점 복구 (v1.1.5 상단바 개편 때 사라졌던 회귀).
- PC 상단 통합검색 검색칸이 아이콘만 보일 정도로 작아지던 레이아웃 수정.
- 유선회원 문자/카카오 버튼을 고객DB와 동일한 디자인(카카오 로고)으로 통일.
- 승인현황 뒤로가기 등 화면 전환 시 프리징 해소 (페이지 인스턴스 캐시) + 승인현황 모바일 레이아웃.
- 감사로그 로딩/스크롤 최적화 (최근 500건, 가상화, 검색 디바운스).
- 모델명 관리 버튼 잘림 및 검색 프리징 수정.
- 목록/엑셀에서 서버 1000행 제한으로 최신 고객이 누락될 수 있던 문제 대비 (전량 로드).
- 모바일 로그인 유지: 종료 버튼이 로그아웃까지 하던 것 수정, 일시적 네트워크 오류로 강제 로그아웃되던 것 수정 (+재시도 화면).
- Android 업데이트 시작 시 구버전 프로세스 자동 종료, 중복 태스크 유발 설정 제거.
- 문자/카톡 발송 문구의 매장명 하드코딩(이대역점) 제거 — 현재 매장명 자동 반영.
- 상세 내역: `docs/release_notes_batch_2026-08-02.md`

## Next Patch Todo

- Velopack 전환 PoC 준비.
  - 로컬 Mac에 .NET SDK와 Velopack CLI `vpk 1.2.0` 설치 완료.
  - `~/.zprofile`에 `DOTNET_ROOT=/usr/local/opt/dotnet/libexec`와 `~/.dotnet/tools` PATH 설정을 추가했습니다.
  - 다음 패치에서 Windows 우선 PoC를 진행하되, 앱 소스 통합/빌드/배포는 별도 승인 후 진행합니다.
  - 검토 항목: 기존 Inno 설치본에서 Velopack 설치본으로 전환, 앱 아이콘/바로가기, 업데이트 feed, private download, macOS 확장 가능성.

## v1.1.9

- 회원가입 권한 보안 보강.
  - 회원가입 화면 직급 선택에서 `대표`, `개발자`를 제거했습니다.
  - Supabase signup trigger/Edge Function에서도 자가가입 metadata로 `대표`, `개발자` role이 확정되지 않도록 막았습니다 (UI 우회 방지).
  - 관리자 API·네트워크 등록/승인/비활성화 같은 privileged action에 `approval_status` 확인을 추가했습니다.
  - RLS 권한 판정 함수(`current_profile_has_role`)가 검증 안 된 원문 텍스트로 폴백하던 문제를 같이 고쳤습니다.
- 배포 링크 비공개 전환 (인프라 준비).
  - 비공개 Storage 버킷 `app-installers` + `app_updates.storage_path`를 추가했습니다. 이번 릴리스는 기존 공개 GitHub Release 방식으로 배포하고, 새 비공개 배포 방식은 다음 패치부터 순차 전환합니다.
- 고객DB/유선회원에 생년월일 필드를 추가했습니다.
  - 등록/수정/상세 화면과 엑셀 내보내기에 반영했습니다. 선택 입력이며, 기존 고객 데이터는 비어 있습니다.
  - 유선회원 엑셀 내보내기에서 마진 강조색이 다른 열에 적용되던 기존 버그를 같이 고쳤습니다.

## v1.1.5

- 오늘 요금제/부가서비스 알림 팝업 프리징 완화.
  - 알림 행을 한 번에 전부 그리지 않고 보이는 행 중심으로 지연 렌더링합니다.
- 대시보드 모델명 집계 보정.
  - 등록된 고객DB 원본 모델명은 유지하고, 대시보드 통계 집계 시에만 `A175`, `SM-A175`, `아이폰17`, `iphone17` 같은 유사 표기를 같은 모델로 묶습니다.
- 고객정리 사용성 보강.
  - 점검 항목에서 해당 고객자료로 바로 이동할 수 있는 버튼을 추가했습니다.
- 승인현황 화면 이동 보정.
  - 승인현황 화면에서 이전 화면으로 돌아갈 수 있도록 상단 뒤로가기를 추가했습니다.
- 상단 통합검색 시인성 개선.
  - 상단 검색 영역이 더 잘 보이도록 강조했습니다.

## v1.1.4

- Android/Windows update re-check while app is already running.
  - `UpdateGate` now checks for updates on app resume after a 10 minute cooldown.
- Audit log Korean readability patch.
  - Audit actions such as `insert_customers` and `update_customers` are shown as business-friendly Korean labels.
  - Audit list summaries now show customer/staff/business fields instead of raw `old/new` JSON.
  - Developer raw JSON remains available only inside the detail dialog when needed.
- Sidebar simplification.
  - `승인현황` moved into `직원관리` as a header button.
  - Standalone sidebar `감사로그` removed because `직원관리` already links to it.
  - `데이터점검` renamed to `고객정리` for more natural shop-floor wording.
- Deleted-record restore page cleanup.
  - Sidebar `휴지통` becomes `삭제자료`, and `휴지통/복구` becomes a more business-friendly deleted-record restore screen.
  - Added search, table-type filters, delete-period filters, delete actor display, restore confirmation, and post-restore navigation.
  - Bulk restore and permanent delete are intentionally excluded.
