# Feature Prep - 2026-07-09

Scope: prepare only. Do not build, deploy, release, or apply DB changes from this document.

## 1. Account Approval / Signup Health Dashboard

Goal: let admins see account states that currently require manual investigation.

### Current code

- Admin user list lives in `lib/pages/admin_page.dart`.
- Normal login blocks missing profiles, pending approval, and policy failures in `lib/pages/login_page.dart` and `lib/main.dart`.
- `auth.users -> public.profiles` creation is now captured in `supabase/migrations/20260704050000_create_profile_on_auth_signup.sql`.

### Minimal implementation

Add a compact status band above the existing admin user table:

- `승인 대기`: `profiles.approval_status = 'pending'`
- `승인 완료`: `profiles.approval_status = 'approved'`
- `거절/기타`: status not pending/approved
- `매장 미연결`: role is `사원` or `점장` and `store_id is null`
- `최근 로그인 차단 후보`: approved users with empty role/store fields

Do not query `auth.users` from the Flutter client. If auth/profile mismatch needs to be shown, add one Edge Function action later:

- `admin_account_health`
- service role reads `auth.users` and `profiles`
- returns counts only, no email body unless opening a detail view

### Files to touch later

- `lib/pages/admin_page.dart`
- `supabase/functions/auth-policy/index.ts` only if auth/profile mismatch counts are required

### Acceptance

- Admin can see counts without leaving employee management.
- Pending users remain approvable in the current table.
- No non-privileged role can see account health.

## 2. Audit Log Detail View

Goal: make existing audit logs useful for debugging real mistakes.

### Current code

- Base page exists: `lib/pages/audit_log_page.dart`.
- Audit table exists: `public.audit_logs`.
- CRM row triggers store `old` and `new` JSON in `detail`.
- Admin page already links to audit logs.

### Minimal implementation

Keep the existing list. Add a detail dialog when a row is clicked:

- top summary: action, table, target id, time
- actor id for now, actor name later if joined safely
- changed fields table:
  - field label
  - old value
  - new value
- for export actions, show row count/file/filter metadata

Add local helpers only:

- `_diffDetail(Map detail)`
- `_detailValue(dynamic value)`
- field label map extension in the existing `_detailKeyLabel`

Avoid a new audit service until the page grows more.

### Files to touch later

- `lib/pages/audit_log_page.dart`

### Acceptance

- Clicking an audit row opens a readable detail dialog.
- Update logs show only changed fields where possible.
- Insert/delete/export logs still render gracefully.

## 3. Data Quality Checks

Goal: find bad CRM data without blocking daily work.

### First checks

Start with read-only checks and warning cards:

- invalid phone format
  - customers, leads, wired_members
- missing required business fields
  - customer name/phone/store
  - lead subscriber/phone/store
  - wired subscriber/phone/store
  - inventory model/serial/store
- store mismatch
  - row store normalizes to empty
- duplicate phone candidates
  - same normalized phone across customers/leads/wired_members
- stale inventory
  - inventory status not changed for a long period later, only after timestamp rules are confirmed

### Minimal implementation

Create one admin-only page or panel:

- `lib/pages/data_quality_page.dart`
- fetch visible rows using existing Supabase tables
- compute checks client-side first
- show grouped issue cards:
  - severity
  - source table
  - title
  - reason
  - record id

Client-side is enough for the first version because this is an admin diagnostic screen. Move to RPC only if data volume becomes slow.

### Reuse

- `lib/utils/phone_utils.dart`
- `lib/utils/store_utils.dart`
- existing table fetch patterns in customer/leads/wired/inventory pages

### Files to touch later

- `lib/pages/data_quality_page.dart`
- `lib/widgets/app_layout.dart` or `lib/pages/admin_page.dart` for navigation
- optional: `lib/services/data_quality_service.dart` only if page code gets too large

### Acceptance

- Admin can see issue counts and rows.
- No data is modified from the first version.
- False positives are tolerable if labels are clear.

## Suggested Order

1. Audit log detail dialog: smallest, uses existing data.
2. Admin account health cards: low risk, high operational value.
3. Data quality page: largest surface, keep it read-only first.

## Non-goals For First Pass

- No automatic data repair.
- No DB writes from quality checks.
- No new notification system.
- No build/deploy until explicitly confirmed.
