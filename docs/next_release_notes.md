# Release Notes

## Next Patch Todo

- 공개 배포 링크 비공개 전환. (코드/마이그레이션 작성 완료, 실제 파일 이전·마이그레이션 적용·과거 릴리스 비공개 전환은 별도 승인 후)
  - 비공개 Storage 버킷 `app-installers` + `app_updates.storage_path` 추가 (`supabase/migrations/20260801020000_private_app_installers_storage.sql`).
  - 앱은 `storage_path`가 있으면 로그인 세션으로 signed URL을 발급받아 다운로드하고, 세션이 없으면 강제 업데이트 화면에서 먼저 로그인하도록 변경했습니다 (`lib/main.dart`의 `UpdateGate`, `lib/services/update_service_io.dart`).
  - 과거 활성 릴리스의 `installer_url`/`apk_url`은 하위 호환으로 계속 동작합니다.
  - 과거 설치파일을 Private GitHub Release로 옮기는 것은 수동 작업으로 남겨둡니다.
  - 조사 중 발견한 관련 버그도 같이 고쳤습니다: `current_profile_has_role()`가 `role_code`가 비어 있으면 검증 안 된 `role` 원문 텍스트로 폴백하던 문제 (`supabase/migrations/20260801010000_fix_role_fallback_authorization.sql`) — 리베이트 이미지, 네트워크 관리 등 이 함수를 쓰는 모든 RLS에 영향.
  - `docs/architecture.md` 갱신 완료.
- 회원가입 권한 보안 보강. (코드 변경 완료, 검증/마이그레이션 적용/Edge Function 배포 대기)
  - 회원가입 화면 직급 선택에서 `대표`, `개발자`를 제거합니다.
  - 이미 대표/개발자 계정이 있으므로 신규 대표/개발자 계정은 기존 관리자 화면에서만 부여합니다.
  - UI 우회 방지를 위해 Supabase signup trigger/Edge Function에서도 자가가입 metadata로 `대표`, `개발자` role이 확정되지 않도록 막습니다.
  - 관리자 API/네트워크 등록·승인·비활성화 같은 privileged action은 `approval_status` 확인을 함께 적용합니다. (매장 네트워크 셀프 부트스트랩 `bootstrap_signup_network`는 실제 권한을 부여하지 않는 가입 직후 흐름이라 승인 전에도 유지)
- Velopack 전환 PoC 준비.
  - 로컬 Mac에 .NET SDK와 Velopack CLI `vpk 1.2.0` 설치 완료.
  - `~/.zprofile`에 `DOTNET_ROOT=/usr/local/opt/dotnet/libexec`와 `~/.dotnet/tools` PATH 설정을 추가했습니다.
  - 다음 패치에서 Windows 우선 PoC를 진행하되, 앱 소스 통합/빌드/배포는 별도 승인 후 진행합니다.
  - 검토 항목: 기존 Inno 설치본에서 Velopack 설치본으로 전환, 앱 아이콘/바로가기, 업데이트 feed, private download, macOS 확장 가능성.

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
