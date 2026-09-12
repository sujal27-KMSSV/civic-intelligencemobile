# Civic Intelligence — Django REST Backend

Backend for the Civic Intelligence Flutter app (Android). Implements the exact
contract in `../API_CONTRACT.md`. DRF Token auth, SQLite by default, Postgres
ready.

## Stack

- Python 3.12+ (tested on 3.14)
- Django + Django REST Framework
- django-cors-headers, Pillow (image uploads), python-dotenv
- SQLite out of the box; PostgreSQL via env vars

## Windows PowerShell setup

```powershell
# 1. Create & activate a virtual environment
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1

# 2. Install requirements
pip install -r requirements.txt

# 3. Configure environment (optional; defaults are dev-friendly)
Copy-Item .env.example .env   # then edit values (SECRET_KEY, DB_*, ...)

# 4. Run migrations
python manage.py makemigrations
python manage.py migrate

# 5. Create a Django admin superuser
python manage.py createsuperuser

# 6. Start Django (LAN-visible — required for a physical phone)
python manage.py runserver 0.0.0.0:8000
```

## Test the API

Admin UI: `http://127.0.0.1:8000/admin/`

```powershell
# register
$body = '{"first_name":"Jane","last_name":"Doe","email":"citizen@example.com","phone":"+911234567890","password":"secret123"}'
Invoke-RestMethod -Uri "http://127.0.0.1:8000/api/auth/register/" -Method Post -ContentType "application/json" -Body $body

# login
$login = '{"email":"citizen@example.com","password":"secret123"}'
Invoke-RestMethod -Uri "http://127.0.0.1:8000/api/auth/login/" -Method Post -ContentType "application/json" -Body $login

# full test suite
python manage.py check
python manage.py test
```

## Endpoints

| Method | Path                | Auth  | Purpose                        |
|--------|---------------------|-------|--------------------------------|
| POST   | `/api/auth/register/` | open | create account → `{token, user}` |
| POST   | `/api/auth/login/`    | open | login → `{token, user}`          |
| GET    | `/api/issues/`        | open | public feed (array, newest first)|
| POST   | `/api/issues/`        | token | submit issue (multipart: image, latitude, longitude, description?) |
| GET    | `/api/issues/{id}/`   | open | issue detail                    |
| PATCH  | `/api/issues/{id}/`   | owner/staff | update status/fields |
| GET    | `/api/my-reports/`    | token | current user's reports (array)  |

Issues list/detail are public (the app preloads the feed on the splash screen).
Creating an issue requires authentication. `my-reports` returns only the
authenticated user's issues. AI-derived fields (`category`, `confidence`,
`severity`, `duplicate`, `duplicate_count`, `department`) are stored honestly
with defaults — no analysis is claimed before an AI service runs.

## PostgreSQL (optional)

Uncomment `# psycopg[binary]>=3.2` in `requirements.txt`, then:

```powershell
pip install -r requirements.txt
# set in .env:
# DB_ENGINE=postgresql
# DB_NAME=civic_intelligence
# DB_USER=civic
# DB_PASSWORD=...
# DB_HOST=127.0.0.1
# DB_PORT=5432
python manage.py migrate
```

## Connecting the Flutter app

The app's base URL is a compile-time define with a dev-only default
`http://10.0.2.2:8000` (the Android emulator's alias for the host machine).

**Emulator** (Django on the same PC as the emulator):

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

**Physical phone** (phone and PC on the same Wi-Fi; find your PC's LAN IP with
`ipconfig`; the backend is already listening on `0.0.0.0`):

```powershell
flutter run --dart-define=API_BASE_URL=http://YOUR-PC-LAN-IP:8000
# release APK:
flutter build apk --release --dart-define=API_BASE_URL=http://YOUR-PC-LAN-IP:8000
```

Replace `YOUR-PC-LAN-IP` with the machine's actual LAN IP (e.g.
`192.168.1.8`) — do not use `localhost`/`10.0.2.2` from a physical phone.
If the phone still cannot connect, allow inbound TCP 8000 in Windows Firewall
for private networks.

## End-to-end success check

1. Register → login (app reaches Home, stays logged in).
2. Submit an issue with photo + GPS + description → result screen.
3. Issue appears in My Reports (newest first) and on the map/feed.