# Civic Intelligence — v1.0.0+1 Release Notes

## What shipped
- Rule-based civic-intelligence engine (honest, auditable): duplicate clustering (GPS proximity + category match + text Jaccard similarity, 0.60 threshold), severity scoring (category base weight + keyword signals + duplicate escalation), deterministic department routing.
- Authority dashboard (`/authority/`) and staff JSON API (`/api/authority/*`): lifecycle state machine (reported → verified → assigned → in_progress → resolved, with re-open paths), resolution evidence upload (BEFORE/AFTER heuristic image similarity via dHash + brightness), cluster view.
- Hardened Django backend: env-gated SECRET_KEY / DEBUG / ALLOWED_HOSTS / CORS, whitenoise for static files, PostgreSQL-ready configuration (`.env.production.example`, Procfile, runtime.txt), production-ready responsive settings (cookie security, CSRF_TRUSTED_ORIGINS).
- Honest branding across the mobile UI: "Civic analysis" (not "AI Analysis"), "Rule-based civic analysis — not a trained ML model." footnote, consistent user-facing language.
- Launcher icon (indigo rounded-square with location pin) + native splash screen.
- Mobile: profile shows "Sign in to see your email" instead of a placeholder address; map `userAgentPackageName` updated to the real package id.
- Release APK + AAB **now signed with a real release keystore**
  (`android/app/upload-keystore.jks`, backed up in `release/private/` — never
  commit or share). Release builds fall back to the debug key only if the
  signing properties are absent (local dev convenience).
- One-click deployment support: `render.yaml` blueprint + `backend/Dockerfile`
  (migrate + collectstatic + gunicorn on boot) and `GET /api/health/` health
  endpoint. `release\scripts\build-production.ps1` builds the final signed
  production APK/AAB against any HTTPS URL.

## What it doesn't do (honest scope)
- **No production backend deployment yet** — requires a hosting account and
  your own domain/credentials (single manual step; see PRODUCTION_DEPLOYMENT.md
  for the one-click Render path and the production build command).
  The `release/CivicIntelligence.apk` / `CivicIntelligence.aab` artifacts are
  produced by `build-production.ps1` once the HTTPS URL exists — the shipped
  `CivicIntelligence-local-demo.apk` is signed but points at a LAN demo backend.
- No real trained computer-vision model; duplicate/severity logic is deterministic rule-based.
- No non-staff authority mobile app; authority web dashboard is staff-only.

## How to try it
1. Start the Django backend (`backend/`) on your machine.
2. Install `CivicIntelligence-local-demo.apk` on an Android device connected to the same LAN.
3. Ensure the phone can reach `http://<your-machine-ip>:8000`.
4. Create staff user in the backend to access `/authority/` dashboard.

See `DEMO_GUIDE.md` for the full walkthrough.