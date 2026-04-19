param(
  [string]$SupabaseUrl = $env:SUPABASE_URL,
  [string]$SupabaseAnonKey = $env:SUPABASE_ANON_KEY,
  [string]$InstallerPassword = $env:INSTALLER_PASSWORD,
  [string]$InnoSetupCompiler = "C:\Users\User\AppData\Local\Programs\Inno Setup 6\ISCC.exe"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
  throw "SUPABASE_URL is required. Pass -SupabaseUrl or set the SUPABASE_URL environment variable."
}

if ([string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
  throw "SUPABASE_ANON_KEY is required. Pass -SupabaseAnonKey or set the SUPABASE_ANON_KEY environment variable."
}

if ([string]::IsNullOrWhiteSpace($InstallerPassword)) {
  $InstallerPassword = "123456"
}

if (!(Test-Path -LiteralPath $InnoSetupCompiler)) {
  throw "Inno Setup compiler was not found: $InnoSetupCompiler"
}

flutter build windows --release `
  --dart-define=SUPABASE_URL=$SupabaseUrl `
  --dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey `
  --dart-define=INSTALLER_PASSWORD=$InstallerPassword

& $InnoSetupCompiler installer.iss
