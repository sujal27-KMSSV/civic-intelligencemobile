# Civic Intelligence — Quality Gates (v1.0.0+1)

| Layer | Gate | Result |
|---|---|---|
| Flutter static analysis | `flutter analyze` | 0 issues |
| Flutter unit tests | `flutter test` | **118/118 passed** |
| Django backend tests | `manage.py test` | **37/37 passed** (29 issues + 8 authority) |
| On-device integration | 2026-09-12 | PASSED: register → logout → login → report (POST 201) → my-reports (200) → details (200) |
| Release APK install + cold launch | 2026-09-12 | No crash; server log confirmed real release-app traffic (auth + media upload) |
| Release APK | Local build (API_BASE_URL=http://192.168.1.8:8000) | 52.7 MB `CivicIntelligence-local-demo.apk` |
| Release AAB | `flutter build appbundle` | 51.5 MB `CivicIntelligence-app-release.aab` |
| Security | Auth token guard on all writes; staff-only authority endpoints; env-gated SECRET_KEY / DEBUG / ALLOWED_HOSTS in production | Pass |
| Honest labeling | No claim of a trained ML model in any user-facing string or doc | Verified by grep |

### Scope note
The on-device APK uses a LAN demo URL and is debug-signed. The AAB is production-configurable but unsigned for store upload. Actual store submission requires a signing key and a live HTTPS backend URL — both manual steps documented in the release notes.