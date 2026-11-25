#!/usr/bin/env bash
# Daily memory-store health check. No agent, no LLM cost - one python startup.
# Silent when healthy (cron delivers empty stdout as nothing). Prints an alert only when:
#   - MEMORY.md / USER.md is over budget, or past 85% of it (memory add() starts failing)
#   - an entry is blocked by the strict content filter, so it is silently dropped from
#     the system prompt and blocks every batch write
#   - the store shrank suspiciously since yesterday - the signature of a concurrent
#     writer (another chat, a batch loop) overwriting it and losing entries
# Recovery for a lost entry: the daily Dropbox backup, the built system-prompt
# snapshots in state.db, and the pre-pass snapshots in cache/memory-snapshots/.
set -uo pipefail
export HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
python3 - <<'PY'
import json
import os
import sys
import time
from pathlib import Path

home = Path(os.environ.get("HERMES_HOME") or (Path.home() / ".hermes"))
mem_dir = home / "memories"
state = home / "cache" / "memory-health.json"

LIMITS = {"MEMORY.md": 8000, "USER.md": 5000}
WARN = {"MEMORY.md": 6800, "USER.md": 4250}  # 85% of the budget
DELIM = "\u00a7"

# Same strict-scope rule the memory tool applies when it writes.
scanner = None
for cand in sorted(Path.home().glob(".hermes/installs/*/environments/*/workspace/tools/threat_patterns.py")):
    sys.path.insert(0, str(cand.parent.parent))
    try:
        from tools import threat_patterns as scanner  # noqa: WPS433 (path built at runtime)
        break
    except Exception:
        continue


def stats(path):
    if not path.exists():
        return None
    raw = path.read_text(encoding="utf-8-sig")
    entries = [e.strip() for e in raw.split(DELIM) if e.strip()]
    return {"chars": len(raw), "entries": len(entries), "raw": raw}


alerts = []
now = {}
for name, limit in LIMITS.items():
    s = stats(mem_dir / name)
    if s is None:
        alerts.append(f"{name}: MISSING at {mem_dir}")
        continue
    now[name] = {"chars": s["chars"], "entries": s["entries"]}
    if s["chars"] > limit:
        alerts.append(f"{name}: OVER BUDGET {s['chars']:,}/{limit:,} chars - memory add() is rejected until it is consolidated")
    elif s["chars"] > WARN[name]:
        alerts.append(f"{name}: {s['chars']:,}/{limit:,} chars ({int(s['chars'] / limit * 100)}%) - consolidate soon (weekly job ba1a83228c11 does it)")
    if scanner is not None:
        for entry in [e.strip() for e in s["raw"].split(DELIM) if e.strip()]:
            hits = scanner.scan_for_threats(entry, "strict")
            if hits:
                alerts.append(f"{name}: BLOCKED entry ({','.join(hits)}) - dropped from the system prompt: {entry[:80]}")

prev = {}
if state.exists():
    try:
        prev = json.loads(state.read_text(encoding="utf-8")).get("stats", {})
    except Exception:
        prev = {}
for name, cur in now.items():
    old = prev.get(name)
    if not old:
        continue
    shrank = cur["chars"] < old["chars"] * 0.75 or cur["entries"] < old["entries"] - 2
    was_healthy = old["chars"] < WARN.get(name, 0)
    if shrank and was_healthy:
        alerts.append(
            f"{name}: SHRANK since yesterday ({old['chars']:,} -> {cur['chars']:,} chars, "
            f"{old['entries']} -> {cur['entries']} entries) while it was healthy - a concurrent "
            f"writer likely overwrote it. Recover: daily Dropbox backup, system-prompt snapshots "
            f"in state.db, pre-pass copies in cache/memory-snapshots/."
        )

if alerts:
    print(f"MEMORY STORE ALERT ({time.strftime('%Y-%m-%d %H:%M')})")
    for a in alerts:
        print(" - " + a)
    print("Check: python3 ~/.hermes/skills/software-development/session-refine-sweep/scripts/check_memory_store.py")

state.parent.mkdir(parents=True, exist_ok=True)
state.write_text(json.dumps({"date": time.strftime("%Y-%m-%d"), "stats": now}, ensure_ascii=False), encoding="utf-8")
PY
