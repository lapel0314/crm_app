# AGENTS.md

## Project Context

Before making non-trivial changes in this repository, read `docs/architecture.md`.

That document is the source of truth for:

- technology stack
- folder structure
- major module responsibilities
- authentication and data-flow boundaries
- release/update flow
- architecture maintenance rules

## Working Rules

- Do not change source code when the user asks for analysis or documentation only.
- Do not build, deploy, release, or apply production changes unless the user explicitly confirms that step.
- Keep generated/local files out of commits unless the user explicitly asks for them.
- Treat `.DS_Store`, `.codex_backups/`, `dist/`, `ios/.DS_Store`, and `ios/ExportOptions.plist` as local/generated artifacts by default.

## Architecture Update Rule

When an important structural change is made, update `docs/architecture.md` in the same change set.

Important structural changes include:

- adding or removing a major page, service, or module
- changing app navigation or core data flow
- changing Supabase Auth, RLS, Edge Function, or DB trigger behavior
- adding a new DB table or migration that changes data ownership/access
- changing build, release, app update, or deployment flow

Small visual tweaks, copy changes, and isolated bug fixes do not require an architecture update unless they change one of the boundaries above.
