# Release Notes

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
