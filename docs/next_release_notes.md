# Release Notes

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
