# Architecture

Last updated: 2026-07-16

## Overview

This repository contains a Flutter-based internal CRM app for mobile and desktop use. The app stores operational CRM data in Supabase, uses Supabase Auth for account sessions, and relies on Supabase Row Level Security plus the `auth-policy` Edge Function for privileged account and network-policy actions.

The main user workflows are:

- login, signup, approval, and login-policy checks
- customer DB management
- leads management
- wired members management
- inventory management
- dashboard summaries
- plan-change / add-service alerts
- rebate image and rate-card management
- admin operations, audit logs, recycle bin, and store/network management
- app update checks and installer/APK release distribution

## Technology Stack

### App

- Flutter / Dart
- Material UI
- `supabase_flutter` for Supabase Auth, PostgREST, Storage, and Edge Function calls
- `intl` for date and number formatting
- `fl_chart` for dashboard charting
- `shared_preferences` for local preferences and auth-session cleanup support
- `file_selector` and `excel` for export/import-style desktop workflows
- `network_info_plus` and `connectivity_plus` for login/network policy context
- `url_launcher`, `android_intent_plus`, `win32`, and `ffi` for platform-specific integrations

### Backend

- Supabase Postgres
- Supabase Auth
- Supabase Edge Function: `supabase/functions/auth-policy/index.ts`
- Supabase Storage for files such as rebate and notice images
- SQL migrations under `supabase/migrations`
- RLS policies and helper functions in migrations and legacy SQL setup files

### Build / Release

- Android release workflow: `.github/workflows/android-release.yml`
- Windows release workflow: `.github/workflows/windows-release.yml`
- iOS internal/unsigned sideload workflows exist, but official iOS distribution is not the normal release path
- Windows installer definitions:
  - `installer.iss`
  - `CRM_App_Setup.iss`
- Release artifacts are stored locally under `dist/` when downloaded from GitHub Actions

### Operations

- DB backup scripts:
  - `scripts/backup_supabase_db_to_gdrive.sh`
  - `scripts/restore_supabase_db_backup.sh`
  - `scripts/install_daily_db_backup_launchd.sh`
- Backup/restore notes: `docs/backup_restore.md`
- Handoff notes: `docs/handoff_2026-07-04.md`

## Folder Structure

```text
.
├── android/                         # Android Flutter host project
├── assets/fonts/                    # Bundled app fonts
├── docs/                            # Architecture, handoff, backup, feature prep docs
├── ios/                             # iOS Flutter host project
├── lib/
│   ├── constants/                   # Static app constants and templates
│   ├── pages/                       # Full app screens and feature pages
│   ├── services/                    # Supabase, export, update, platform, and domain services
│   ├── theme/                       # Theme definitions
│   ├── utils/                       # Shared formatting, filtering, store, phone, debounce helpers
│   ├── widgets/                     # Shared UI widgets and dialogs
│   └── main.dart                    # App bootstrap, update gate, auth gate
├── linux/                           # Linux Flutter host project
├── macos/                           # macOS Flutter host project
├── scripts/                         # Backup and restore scripts
├── supabase/
│   ├── functions/auth-policy/       # Edge Function for trusted auth/admin/network actions
│   └── migrations/                  # Versioned DB schema/policy/function migrations
├── test/                            # Flutter tests
├── web/                             # Web Flutter host project
├── windows/                         # Windows Flutter host project
├── .github/workflows/               # CI/release workflows
├── pubspec.yaml                     # Flutter dependencies and app version
├── installer.iss                    # Windows installer definition
└── CRM_App_Setup.iss                # Alternate Windows installer definition
```

Generated or local-only files commonly appear in the worktree and should not be committed unless explicitly requested:

- `.DS_Store`
- `.codex_backups/`
- `dist/`
- `ios/.DS_Store`
- `ios/ExportOptions.plist`

## Main App Flow

### Bootstrap

`lib/main.dart` is the entry point.

1. `BootstrapApp` reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from `dart-define`.
2. `DesktopAuthSessionService` clears persisted desktop sessions where required.
3. `Supabase.initialize` configures the client.
4. `MyApp` starts with `UpdateGate`.
5. `UpdateGate` checks app update policy through the platform update service.
6. `AuthGate` routes to `LoginPage` or `AppLayout`.

### Authentication and Authorization

Key files:

- `lib/pages/login_page.dart`
- `lib/main.dart`
- `lib/services/login_policy_service.dart`
- `lib/services/desktop_auth_session_service.dart`
- `supabase/functions/auth-policy/index.ts`
- `supabase/migrations/20260704050000_create_profile_on_auth_signup.sql`

Flow:

1. Users sign up or sign in through Supabase Auth.
2. Signup metadata is copied into `public.profiles` by the `handle_new_user` DB trigger.
3. `LoginPage` verifies that a profile exists and is approved.
4. `LoginPolicyService` invokes the `auth-policy` Edge Function with the current access token and device/network context.
5. `auth-policy` loads the profile using a service role client and evaluates approval, role, store, and network rules.
6. `AuthGate` periodically re-checks login policy while the app is active.

Important rule: profile writes are locked down for normal clients. Trusted changes go through DB triggers or `auth-policy`.

### App Shell and Navigation

Key file:

- `lib/widgets/app_layout.dart`

`AppLayout` owns:

- sidebar/navigation
- selected store state
- current page selection
- global search handoff
- today plan-change alert popup
- store selector and add-store flow
- update/logout/exit actions

Role and store helpers are centralized in:

- `lib/utils/store_utils.dart`

## Major Modules

### Customer DB

Key files:

- `lib/pages/customer_page.dart`
- `lib/pages/customer_open_page.dart`
- `lib/services/customer_excel_export_service.dart`
- `lib/services/audit_log_service.dart`

Responsibilities:

- customer row listing, filtering, editing, soft deletion
- open/customer-limited view behavior
- Excel export
- Kakao/SMS/call action integration
- plan-change and add-service data fields
- export audit logging

### Leads

Key file:

- `lib/pages/leads_page.dart`

Responsibilities:

- leads listing, date/search filtering, create/update/delete
- role/store filtering
- phone formatting and contact actions
- audit logging and soft deletion

### Wired Members

Key file:

- `lib/pages/wired_members_page.dart`

Responsibilities:

- wired member listing and settlement calculations
- Excel export
- phone/contact actions
- rebate/margin/incentive calculation
- audit logging and soft deletion

### Inventory

Key file:

- `lib/pages/inventory_page.dart`

Responsibilities:

- device inventory list and search
- create/update/delete
- status and memo tracking
- store filtering

### Dashboard

Key file:

- `lib/pages/dashboard_page.dart`

Responsibilities:

- summary metrics from customers, leads, wired members, and inventory
- current/monthly sales and margin views
- detail dialogs for dashboard cards

### Admin and Audit

Key files:

- `lib/pages/admin_page.dart`
- `lib/pages/audit_log_page.dart`
- `lib/pages/recycle_bin_page.dart`
- `lib/pages/store_management_page.dart`
- `supabase/functions/auth-policy/index.ts`

Responsibilities:

- employee profile approval/update/delete/password changes
- notice creation and management
- audit log inspection
- recycle bin restore
- store and store-network management

Privileged admin mutations are routed through `auth-policy`, not direct client writes.

### Settings

Key file:

- `lib/pages/settings_page.dart`

Responsibilities:

- user profile display
- logout
- team/group view
- store network registration/request/approval cards where permitted

### Plan Change Alerts

Key files:

- `lib/services/plan_change_alert_service.dart`
- `lib/widgets/plan_change_alert_dialog.dart`

Responsibilities:

- compute due dates for carrier-specific plan-change/add-service rules
- persist due alert rows into `plan_change_tasks`
- track pending/done/skipped status and before/after change values
- expose task status and recent change history in Customer DB
- show once-per-day automatic alert
- allow manual reopening
- allow users to mark alert rows as completed
- privileged Excel export of alert rows

### Rate Cards and Rebates

Key files:

- `lib/services/rate_card_service.dart`
- `lib/widgets/rate_card_rules_panel.dart`
- `lib/pages/rebate_page.dart`
- `lib/services/rebate_image_service.dart`

Responsibilities:

- rebate/rate-card CRUD and Google Sheet CSV linkage
- rebate image upload/view/delete
- role-gated management UI

### Platform and Update Services

Key files:

- `lib/services/update_service_base.dart`
- `lib/services/update_service.dart`
- `lib/services/update_service_io.dart`
- `lib/services/update_service_stub.dart`
- `lib/services/desktop_auth_session_service.dart`

Responsibilities:

- app update lookup and installer launch
- SHA-256 installer verification
- desktop session cleanup and sign-out behavior

## Data Flow

### Normal Read Flow

```text
Flutter page
  -> Supabase client PostgREST query
  -> RLS policies in Supabase Postgres
  -> rows returned to page
  -> client-side formatting/filtering where needed
```

Most normal read paths use direct Supabase table queries and rely on RLS plus store/role helper functions.

### Normal Write Flow

```text
Flutter page
  -> Supabase table insert/update
  -> RLS policy validates role/store access
  -> DB triggers generate audit logs where configured
```

Customer, leads, wired members, inventory, and several content records use this pattern.

### Plan Change Task Flow

```text
PlanChangeAlertService computes due alert entries
  -> missing rows are inserted into public.plan_change_tasks
  -> alert dialog and Customer DB read task status through RLS
  -> user marks an alert as completed or edits customer plan/add-service fields
  -> task status, before/after values, actor, timestamp, and log row are saved
```

The task table is separate from `customers` so operational customer data and follow-up processing history remain independent.

### Trusted Admin / Policy Flow

```text
Flutter service/page
  -> Supabase Edge Function invoke: auth-policy
  -> Edge Function validates current access token
  -> Edge Function loads profile with service role
  -> Edge Function performs privileged DB/Auth action
  -> result returned to Flutter
```

This flow is used for:

- login policy checks
- store network registration/request/approval
- admin profile approval/update/delete
- admin password updates
- export audit recording
- notice deletion

### Signup Flow

```text
LoginPage.signup
  -> supabase.auth.signUp(metadata)
  -> Supabase Auth creates auth.users row
  -> DB trigger public.handle_new_user inserts public.profiles row
  -> user must complete email verification
  -> admin approves profile
  -> LoginPage.login allows approved profile
  -> LoginPolicyService checks runtime policy
```

### Update Release Flow

```text
GitHub push/tag
  -> Android / Windows GitHub Actions build artifacts
  -> GitHub Release assets
  -> public.app_updates active rows updated with URLs and SHA-256
  -> app UpdateGate detects update
  -> platform update service downloads/verifies/launches installer or APK
```

## Database and Security Notes

- RLS is expected to be enabled for sensitive CRM tables.
- `profiles` writes should remain restricted to trusted paths.
- `auth-policy` uses service role access and must enforce authorization before returning privileged data.
- `audit_logs` are privileged-select only.
- `plan_change_tasks` and `plan_change_task_logs` store 요금제/부가서비스 follow-up status and before/after change history.
- Soft-deleted records remain recoverable through recycle-bin flows.
- `normalized_store` is generated in `profiles`; application code must not update it directly.

## Documentation Maintenance Rule

When an important structural change is made, update this file in the same change set. Important structural changes include:

- new top-level folder or major module
- new page that changes navigation or primary workflows
- new service that owns a business flow
- new Supabase Edge Function action
- new DB table, trigger, RLS policy family, or migration that changes data ownership/access
- release/update pipeline changes
- authentication, authorization, or network-policy changes

If the change is purely visual, copy-only, or a local bug fix without architectural impact, this document does not need an update.
