# Civic Intelligence — API Configuration

## Mobile base URL
`lib/core/constants/api_constants.dart` reads the base URL from a
`String.fromEnvironment` value. Default (no define): `http://10.0.2.2:8000`
(Android emulator). For a physical device use the machine's LAN IP:

```
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.1.8:8000
```

## Environment variables (backend)
| Variable | Default | Notes |
|---|---|---|
| `SECRET_KEY` | dev fallback | required in production (boot fails without it when DEBUG=False) |
| `DEBUG` | 1 | set 0 in production |
| `ALLOWED_HOSTS` | `*` | comma-separated; must be explicit in production |
| `CORS_ALLOW_ALL_ORIGINS` | equals DEBUG | prefer explicit list in production |
| `CORS_ALLOWED_ORIGINS` | empty | comma-separated HTTPS origins |
| `CSRF_TRUSTED_ORIGINS` | empty | comma-separated dashboard origins |
| `SECURE_SSL_REDIRECT` | 0 | set 1 behind a TLS proxy |
| `DB_ENGINE` | sqlite | `postgresql` switches to Postgres using `DB_*` vars |
| `DB_NAME/DB_USER/DB_PASSWORD/DB_HOST/DB_PORT` | dev | Postgres settings |

## Public endpoints
| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/api/auth/register/` | – | returns user + token |
| POST | `/api/auth/login/` | – | returns user + token |
| GET | `/api/issues/` | – | public list, newest first |
| POST | `/api/issues/` | token | multipart; runs civic analysis |
| GET | `/api/issues/{id}/` | – | public detail |
| PATCH | `/api/issues/{id}/` | token | reporter may edit own `description`/`address` only |
| GET | `/api/my-reports/` | token | own reports |

## Authority endpoints (staff only, token or session)
| Method | Path | Notes |
|---|---|---|
| GET | `/api/authority/issues/` | filters: `status`, `severity`, `department`, `include_resolved=1` |
| GET | `/api/authority/issues/{id}/` | full analysis + duplicate cluster |
| POST | `/api/authority/issues/{id}/transition/` | `{"new_status": "verified"}`; lifecycle validated |
| POST | `/api/authority/issues/{id}/resolve/` | multipart `image` + `notes`; sets resolved + similarity |
| GET | `/api/authority/stats/` | aggregate counters |

## Web dashboard (staff only)
- `/authority/` — queue + Leaflet map + stats
- `/authority/issues/{id}/` — detail with transitions and resolution upload
- Login is through Django admin (`/admin/login/`), same account store as mobile.

## Worker commands (Windows dev)
```powershell
.\.venv\Scripts\python.exe manage.py migrate
.\.venv\Scripts\python.exe manage.py test
.\.venv\Scripts\python.exe manage.py runserver 0.0.0.0:8000
```