#!/bin/bash
# Hindsight memory backup for the Hermes daily backup.
#
# Runs `hindsight-admin backup` (a restorable .zip of the whole Hindsight DB)
# against the embedded pg0 instance. The embedded daemon stops itself after an
# idle timeout, so this starts it if needed and stops it again afterwards.
#
# Safe to call from daily-backup.sh; failures are logged, never fatal.
set -uo pipefail

PROFILE="${HINDSIGHT_PROFILE:-hermes}"
OUT_DIR="${HOME}/.hermes/backups/hindsight"
KEEP="${HINDSIGHT_BACKUP_KEEP:-7}"
DATE="$(date +%Y-%m-%d)"
OUT="${OUT_DIR}/hindsight-${DATE}.zip"

log() { echo "hindsight-backup: $*"; }

# --- locate the binaries -----------------------------------------------------
HA="${HOME}/.local/bin/hindsight-admin"
[ -x "$HA" ] || HA="$(command -v hindsight-admin 2>/dev/null || true)"

# hindsight-embed lives in the active Hermes environment (its path changes when
# Hermes rebuilds the environment), so resolve it from facts.json.
HB=""
FACTS="$(ls -d "${HOME}"/.hermes/installs/*/facts.json 2>/dev/null | head -1)"
if [ -n "$FACTS" ]; then
  VENV="$(python3 - "$FACTS" <<'PY' 2>/dev/null
import json, sys
try:
    print(json.load(open(sys.argv[1]))["packages"]["venv"]["environment"])
except Exception:
    pass
PY
)"
  [ -n "$VENV" ] && [ -x "$VENV/bin/hindsight-embed" ] && HB="$VENV/bin/hindsight-embed"
fi
if [ -z "$HB" ]; then
  HB="$(find "${HOME}/.hermes/installs" -type f -name hindsight-embed 2>/dev/null | head -1)"
fi

if [ -z "$HA" ] || [ -z "$HB" ]; then
  log "hindsight-admin or hindsight-embed not found - skipping"
  exit 0
fi

INST="${HOME}/.pg0/instances/hindsight-embed-${PROFILE}/instance.json"
if [ ! -f "$INST" ]; then
  log "no pg0 instance at ${INST} - skipping"
  exit 0
fi

DB_URL="$(python3 - "$INST" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print("postgresql://%s:%s@127.0.0.1:%s/%s" % (d["username"], d["password"], d["port"], d["database"]))
except Exception:
    pass
PY
)"
if [ -z "$DB_URL" ]; then
  log "could not read the pg0 instance credentials - skipping"
  exit 0
fi

mkdir -p "$OUT_DIR"

# --- make sure the embedded database is up -----------------------------------
WAS_RUNNING=0
if "$HB" -p "$PROFILE" daemon status 2>/dev/null | grep -qi "running"; then
  WAS_RUNNING=1
else
  log "starting the embedded daemon (first run can take a minute)..."
  "$HB" -p "$PROFILE" daemon start >/dev/null 2>&1 || true
fi

# --- back up -----------------------------------------------------------------
if HINDSIGHT_API_DATABASE_URL="$DB_URL" "$HA" backup "$OUT" >/dev/null 2>&1; then
  log "wrote ${OUT}"
else
  log "hindsight-admin backup failed - skipping"
fi

# --- leave the daemon as we found it -----------------------------------------
if [ "$WAS_RUNNING" = "0" ]; then
  "$HB" -p "$PROFILE" daemon stop >/dev/null 2>&1 || true
fi

# --- prune -------------------------------------------------------------------
ls -t "${OUT_DIR}"/hindsight-*.zip 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
  rm -f "$old"
done
