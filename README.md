# 핑크폰 CRM

Flutter 기반 CRM Windows 앱입니다. Supabase를 백엔드로 사용하며, 고객 관리,
재고/가망고객 관리, 공지, 리베이트 이미지 조회 기능을 포함합니다.

## 현재 리베이트 운영 방식

리베이트 자동입력/PDF 파싱 기능은 사용하지 않습니다. 현재 버전에서는 관리자만
통신사와 날짜를 선택해 리베이트 이미지를 업로드하고, 사용자는 앱에서 해당
이미지를 조회하는 방식으로 운영합니다.

- 유지: 리베이트 이미지 업로드, 수정, 삭제, 조회
- 제거: 단가 등록 버튼
- 제거: PDF/이미지 자동 파싱 및 자동 단가 입력
- 유지: 기존 Supabase 테이블과 SQL 파일

## 실행 설정

Supabase 접속 정보는 소스 코드에 저장하지 않습니다. 실행 또는 빌드할 때
`dart-define`으로 전달합니다.

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=your-publishable-or-anon-key
```

릴리즈 빌드도 같은 값을 사용해야 합니다. `service_role` 키는 절대 앱에 넣지
마세요. 서버 전용 키는 Supabase Edge Functions 또는 별도 백엔드에서만 사용해야
합니다.

## Windows 설치파일 빌드

Windows 설치파일은 Flutter release 빌드와 Inno Setup 컴파일을 함께 실행해야
합니다. 아래 스크립트를 사용하면 Supabase 설정이 포함된 앱 실행파일을 만든 뒤
설치파일까지 생성합니다.

```powershell
$env:SUPABASE_URL = "https://your-project.supabase.co"
$env:SUPABASE_ANON_KEY = "your-publishable-or-anon-key"
$env:INSTALLER_PASSWORD = "123456"

.\build_windows_installer.ps1
```

PowerShell 실행 정책 때문에 막히면 아래처럼 실행합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build_windows_installer.ps1 `
  -SupabaseUrl "https://your-project.supabase.co" `
  -SupabaseAnonKey "your-publishable-or-anon-key" `
  -InstallerPassword "123456"
```

설치파일은 `output` 폴더에 생성됩니다.

## 업데이트 배포

새 버전을 배포할 때는 다음 값을 함께 올립니다.

1. `pubspec.yaml`의 앱 버전
2. `lib/services/update_service.dart`의 `appVersion`
3. `installer.iss`와 `CRM_App_Setup.iss`의 `MyAppVersion`
4. 새 Windows 설치파일
5. Supabase `app_updates` 테이블의 `version`, `installer_url`

Supabase Storage에는 기존 파일을 덮어쓰기보다 새 버전 파일명으로 업로드하는 것을
권장합니다. 캐시 때문에 이전 설치파일이 내려가는 일을 줄일 수 있습니다.
