# Android 수동 APK 배포 가이드

이 앱은 Google Play 배포를 사용하지 않습니다. Android 배포는 Supabase Storage에 APK를 올리고, `app_updates` 테이블의 최소 허용 버전으로 강제 업데이트를 제어하는 방식입니다.

## 1. 로컬 준비

Android Studio 또는 Android SDK가 필요합니다. Flutter가 SDK를 찾는지 먼저 확인합니다.

```powershell
flutter doctor -v
```

Supabase 값은 앱에 하드코딩하지 않고 빌드할 때 전달합니다.

```powershell
flutter build apk --release `
  --dart-define=SUPABASE_URL=https://ysafjyubntkeorriywmu.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_LLt7Nx5xNWoROgTKD82YkA_eKtp-HLy
```

생성 파일:

```text
build\app\outputs\flutter-apk\app-release.apk
```

## 2. 업데이트 테이블

Supabase SQL Editor에서 `supabase_app_updates.sql`을 먼저 실행합니다. 기존 Windows 업데이트 컬럼은 유지하면서 Android용 컬럼을 추가합니다.

Android APK 예시:

```sql
update public.app_updates
set is_active = false
where platform = 'android' and is_active = true;

insert into public.app_updates (
  platform,
  version,
  installer_url,
  latest_version,
  min_required_version,
  apk_url,
  update_message
)
values (
  'android',
  '1.0.4',
  'https://ysafjyubntkeorriywmu.supabase.co/storage/v1/object/public/installers/pinkphone-crm-1.0.4.apk',
  '1.0.4',
  '1.0.4',
  'https://ysafjyubntkeorriywmu.supabase.co/storage/v1/object/public/installers/pinkphone-crm-1.0.4.apk',
  '새 Android 앱을 설치한 뒤 다시 실행해주세요.'
);
```

`min_required_version`보다 설치된 앱 버전이 낮으면 앱 시작 화면에서 업데이트 안내만 표시되고 본 화면에 진입할 수 없습니다.

## 3. APK 업로드 절차

1. `pubspec.yaml` 버전을 올립니다.
2. `lib/services/update_service_base.dart`의 `appVersion`도 같은 버전으로 맞춥니다.
3. `flutter build apk --release ...`를 실행합니다.
4. 생성된 APK를 Supabase Storage public bucket에 업로드합니다.
5. `app_updates`의 기존 `android` 활성 row를 비활성화합니다.
6. 새 APK URL로 `android` row를 추가합니다.
7. 구버전 기기에서 앱을 실행해 업데이트 화면이 뜨는지 확인합니다.

## 4. 업데이트 UX

앱 실행 시 `UpdateGate`가 Supabase `app_updates`를 조회합니다.

- `platform = 'android'`
- `is_active = true`
- `current_version < min_required_version`이면 차단
- 업데이트 버튼은 `apk_url`을 외부 브라우저로 엽니다.
- 사용자는 APK를 내려받아 직접 설치한 뒤 앱을 다시 실행합니다.

Android 8 이상에서는 사용자가 브라우저 또는 파일 앱의 "알 수 없는 앱 설치" 권한을 허용해야 할 수 있습니다. 앱 내부 설치 권한을 강제로 요구하지 않고, 브라우저 다운로드 방식으로 안정성을 우선했습니다.

## 5. 연락 기능

고객DB, 가망고객, 유선회원에서 전화/문자/카카오톡 버튼을 제공합니다.

- 전화: 기본 전화 앱 열기
- 문자: 기본 SMS 앱 열기
- 카카오톡: Android 공유 Intent로 카카오톡 열기
- 번호가 비어 있으면 안내 메시지 표시
- 고객DB, 가망고객, 유선회원은 여러 명 선택 후 문자/카카오톡 버튼을 사용할 수 있습니다.

카카오톡은 공식 Kakao SDK 로그인/친구 API가 아니라 Android 공유 Intent 방식입니다. 별도 Kakao 네이티브 앱 키 설정은 필요하지 않습니다. 카카오톡이 설치되어 있지 않으면 설치 화면으로 유도합니다.

## 6. 남은 테스트 항목

- 실제 Android 기기에서 로그인
- 고객DB/가망고객/유선회원 전화 앱 열기
- 여러 명 선택 후 SMS 앱 수신자 입력 확인
- 여러 명 선택 후 카카오톡 공유 화면 확인
- `min_required_version`을 현재보다 높게 올려 강제 차단 확인
- 새 APK 설치 후 재실행 시 정상 진입 확인

