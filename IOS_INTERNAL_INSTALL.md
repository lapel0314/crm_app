# iOS 사내 링크 설치

이 방식은 App Store/TestFlight를 쓰지 않고 사내에서 링크로 설치하기 위한 `Ad Hoc` 배포 방식입니다.

## 제한

- Apple Developer Program 유료 계정이 필요합니다.
- 설치할 아이폰 UDID가 Apple Developer 계정의 Devices에 등록되어 있어야 합니다.
- Ad Hoc 프로비저닝 프로파일에 포함된 기기만 설치할 수 있습니다.
- UDID 등록 없이 모든 직원이 설치하려면 Apple Developer Enterprise Program이 필요합니다.

## GitHub Secrets

GitHub 저장소 `Settings` -> `Secrets and variables` -> `Actions`에 아래 값을 추가합니다.

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `IOS_CERTIFICATE_BASE64`
- `IOS_CERTIFICATE_PASSWORD`
- `IOS_PROVISION_PROFILE_BASE64`
- `IOS_KEYCHAIN_PASSWORD`

인증서와 프로파일은 Mac에서 아래처럼 base64로 변환해 넣습니다.

```bash
base64 -i certificate.p12 | tr -d '\n' | pbcopy
base64 -i profile.mobileprovision | tr -d '\n' | pbcopy
```

`IOS_CERTIFICATE_BASE64`에는 `certificate.p12` 값을, `IOS_PROVISION_PROFILE_BASE64`에는 `profile.mobileprovision` 값을 넣습니다.

## 빌드

1. GitHub Actions에서 `iOS Internal Release Build` 실행
2. `export_method`는 사내 링크 설치용으로 `ad-hoc` 선택
3. `publish_release`는 `true` 선택
4. 완료되면 GitHub Release에 아래 파일들이 업로드됩니다.

- `pinkphone-crm-<version>.ipa`
- `pinkphone-crm-<version>-manifest.plist`
- `pinkphone-crm-<version>-install.html`
- `pinkphone-crm-<version>-install-link.txt`

## 설치 링크

`install-link.txt` 안의 `itms-services://...` 링크를 사내에 공유합니다. 아이폰에서는 Safari로 링크를 열어야 설치가 시작됩니다.

GitHub Release asset 링크에서 설치가 시작되지 않으면, `ipa`와 `manifest.plist`를 Supabase Storage 같은 public HTTPS 저장소에 올리고 manifest 안의 IPA URL을 그 주소로 바꿔서 사용합니다.
