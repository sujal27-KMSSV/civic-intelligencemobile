# Civic Intelligence — Local Demo Guide

## Prerequisites
- Python 3.14+ (the `backend/.venv` is provided and pre-migrated).
- A physical Android device (or emulator) on the same network as the backend.

## Start the backend

```powershell
cd backend
.\.venv\Scripts\activate
python manage.py migrate --run-syncdb   # already applied, safe no-op
python manage.py createsuperuser        # create staff account for the authority dashboard
python manage.py runserver 0.0.0.0:8000
```

## Allow firewall traffic

A Windows firewall rule named `CivicDjango8000` (TCP 8000, all profiles) should
already exist. If the phone cannot reach the server, verify with:

```powershell
netsh advfirewall firewall show rule name=CivicDjango8000
```

If missing, create it (requires UAC):

```powershell
New-NetFirewallRule -DisplayName "CivicDjango8000" `
    -Direction Inbound -Action Allow -Protocol TCP `
    -LocalPort 8000 -Profile Any -Enabled True
```

## Install the APK

The release APK in `release/CivicIntelligence-local-demo.apk` is built against
`http://192.168.1.8:8000`. If your machine has a different LAN IP, rebuild the
APK with your actual IP:

```powershell
cd ..   # project root
flutter build apk --release --dart-define=API_BASE_URL=http://<YOUR_LAN_IP>:8000
```

Then install:

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

## Access the authority dashboard

Open a browser on the same machine running the backend and visit:
`http://localhost:8000/authority/`

Log in with the superuser you created. Staff-only actions: verify, assign,
start work, resolve with evidence photo.

## Check live server logs

Logs are written to `backend/server.err.log` (shown in the terminal when using
`runserver`). You will see real traffic from the release APK in real time:
registration, photo upload, my-reports fetches, etc.