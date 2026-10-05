#!/bin/sh
# Summarises Murmur's History for the Milestone 1 gate: dictations per outcome and per app, timing,
# and every dictation that did not paste. Reads ~/Library/Application Support/Murmur/murmur.sqlite.
# Pass a date (YYYY-MM-DD) to limit to that day; default is the last 24 hours.
DB="$HOME/Library/Application Support/Murmur/murmur.sqlite"
SINCE=${1:+"$1 00:00:00"}
exec python3 - "$DB" "$SINCE" <<'PY'
import json, math, sqlite3, sys
from datetime import datetime, timedelta, timezone
db, since = sys.argv[1], sys.argv[2]
if not since:
    since = (datetime.now(timezone.utc) - timedelta(hours=24)).strftime("%Y-%m-%d %H:%M:%S")
rows = sqlite3.connect(db).execute(
    "select startedAt, appName, appBundleId, status, durationMs, timings, rawText is not null, errorCode "
    "from dictation where startedAt >= ? order by startedAt", (since,)).fetchall()
def pct(v, q):
    v = sorted(v)
    return v[min(len(v), max(1, math.ceil(q / 100 * len(v)))) - 1] if v else None
print(f"Dictations since {since} UTC: {len(rows)}")
by_status = {}
for r in rows: by_status[r[3]] = by_status.get(r[3], 0) + 1
print("By outcome: " + ", ".join(f"{k} {v}" for k, v in sorted(by_status.items())))
apps = {}
for r in rows: apps[r[1] or r[2] or "?"] = apps.get(r[1] or r[2] or "?", 0) + 1
print(f"Apps ({len(apps)}): " + ", ".join(f"{k} {v}" for k, v in sorted(apps.items(), key=lambda x: -x[1])))
totals = [json.loads(r[5]).get("totalMs") for r in rows if r[3] == "inserted" and r[5]]
totals = [t for t in totals if t]
if totals:
    print(f"Release to paste: p50 {pct(totals,50):.0f} ms, p95 {pct(totals,95):.0f} ms, max {max(totals):.0f} ms")
lost = [r for r in rows if r[3] in ("recorded", "transcriptionFailed") and not r[6]]
kept = [r for r in rows if r[3] not in ("inserted", "cancelled") and r not in lost]
print(f"\nLost (spoke, but no text anywhere): {len(lost)}")
for r in lost: print(f"  {r[0]}  {r[1]}  {r[3]}  {r[7] or ''}  (audio is kept; Retry comes in Milestone 4)")
print(f"Not pasted but kept (text in History and on the clipboard): {len(kept)}")
for r in kept: print(f"  {r[0]}  {r[1]}  {r[3]}  {r[7] or ''}")
print("\nGate:", "PASS" if len(apps) >= 10 and not lost else "not yet", f"({len(apps)} apps, {len(lost)} lost)")
PY
