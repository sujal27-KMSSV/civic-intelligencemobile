# Demo guide

A demo needs **no shared demo account and no credentials in the repository**.
Every account used by the demo / E2E is created at runtime.

## Running the whole stack locally

```powershell
# 1) Backend
cd backend
.\.venv\Scripts\python.exe manage.py migrate
.\.venv\Scripts\python.exe manage.py createsuperuser   # for the staff API
.\.venv\Scripts\python.exe manage.py runserver

# 2) App
cd ..
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

## Suggested demo script

1. **Citizen A** (register `demo-a@example.com` / strong temp password):
   create a "Pothole" camera report at Connaught Place.
2. **Citizen B** (register a second account): create a *same-category* report a
   few dozen metres away with a very similar description → the result screen
   shows "Similarity to existing reports: ~…%", and My Reports shows it was
   "Consolidated under Issue #id".
3. Open **Home** → the master card shows a priority chip (`PriorityChip`),
   "*Consolidates 2 reports*" and the part `priority_reasons` breakdown.
4. **Authority** (staff login on `authority-web/` or the JSON API): review the
   cluster, transition the status, and resolve with a "completed" photo to see
   the honest BEFORE/AFTER image-similarity measurement.
5. **Dark mode**: Profile → Appearance → Dark; verify the whole app follows.

## Importance of honesty in the pitch

Do not claim: photo-CV detection of infrastructure faults, a learned AI model,
global "accuracy 96%", PostGIS queries, or real-time push. Active language:
*"rule-based duplicate intelligence that consolidates reports of the same
issue, an explainable priority score, hotspot aggregation of real reports, and
image-similarity-based resolution verification under an authority decision."*

For the supporting evidence see [claim-sheet.md](claim-sheet.md).