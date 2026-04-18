# crm_app

## Runtime configuration

Supabase connection values are not stored in source code. Pass them at run or
build time with Dart defines:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=your-publishable-or-anon-key
```

Use the same defines for release builds. Never put service-role keys in this
app; server-only keys must stay in Supabase Edge Functions or other backend
infrastructure.
