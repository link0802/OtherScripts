#!/bin/bash
# Daily backup: 3 latest full backups with exclusion rules, rotating by day
# Also: OAuth guard with token refresh (oauth_guard.py)
# Keeps critical state: config.yaml, state.db, skills/, cron/, .env, auth.json, cache/citations/
# Excludes: hermes-agent/, tools/, node_modules/, cache/scratch/, backups/, checkpoints/, etc.

# OAuth Guard: check token before backup
if [ -f ~/.hermes/scripts/oauth_guard.py ]; then
    TOKEN_STATUS=$(python3 ~/.hermes/scripts/oauth_guard.py --silent 2>&1)
    if [ $? -ne 0 ]; then
        echo "TOKEN INVALID:" >&2
        python3 ~/.hermes/scripts/oauth_guard.py >&2
        exit 1
    fi
fi

set -euo pipefail
BACKUP_DIR="${BACKUP_DIR:-$HOME/Dropbox/hermesBack}"
KEEPS="${KEEPS:-3}"
DATE=$(date +%Y-%m-%d)
LABEL="hermes-${DATE}"

mkdir -p "$BACKUP_DIR"

# Build exclusion file for zip
EXCLUDE_FILE=$(mktemp)
cat > "$EXCLUDE_FILE" <<'ZIPEXCLUDE'
hermes-agent/
tools/
node_modules/
node/
installs/
backups/
checkpoints/
state-snapshots/
cache/scratch/
cache/terminal-output/
cache/spillover/
cache/cursors/
cache/images/
.cache/
.git/
__pycache__/
*.pyc
*.pyo
*.db-wal
*.db-shm
*.db-journal
gateway.pid
cron.pid
.gateway.lock
ZIPEXCLUDE

echo "Creating backup: $BACKUP_DIR/${LABEL}.tar.gz"

# Create tar.gz with exclusions, using tar instead of hermes backup CLI
# This gives us more control and smaller archives
cd "$HOME"

tar --create --gzip \
    --file="$BACKUP_DIR/${LABEL}.tar.gz" \
    --exclude-from="$EXCLUDE_FILE" \
    --transform 's,^hermes/,,' \
    .hermes/config.yaml \
    .hermes/.env \
    .hermes/auth.json \
    .hermes/state.db \
    .hermes/state.db-wal \
    .hermes/state.db-shm \
    .hermes/skills/ \
    .hermes/cron/ \
    .hermes/plugins/ \
    .hermes/protocol/ \
    .hermes/cache/citations/ \
    .hermes/cache/messages/ \
    .hermes/cache/media/ 2>/dev/null || true

rm -f "$EXCLUDE_FILE"

# Size check
SIZE=$(du -h "$BACKUP_DIR/${LABEL}.tar.gz" | cut -f1)
echo "Backup size: $SIZE"

# Rotate: keep only KEEPS newest per day
cd "$BACKUP_DIR"
ls -t hermes-*-*.tar.gz 2>/dev/null | tail -n +$((KEEPS + 1)) | while read old; do
    echo "Removing old backup: $old"
    rm -f "$old"
done

# Log to daily-backup.log
LOG_DIR="/home/link/.hermes/cron/output"
mkdir -p "$LOG_DIR"
echo "$(date '+%Y-%m-%d %H:%M:%S') ${LABEL} ${SIZE}" >> "$LOG_DIR/daily-backup.log"

echo "Done. Current backups:"
ls -lh "$BACKUP_DIR"/hermes-*-*.tar.gz 2>/dev/null || echo "No backups yet"

# Count total backups across days
TOTAL=$(ls -1 "$BACKUP_DIR"/hermes-*.tar.gz 2>/dev/null | wc -l)
echo "Total backups stored: $TOTAL"

# Telegram notification when backups >= 3
if [ "$TOTAL" -ge 3 ] && [ "${SEND_TELEGRAM:-0}" != "0" ]; then
    NEWEST=$(ls -t "$BACKUP_DIR"/hermes-*.tar.gz 2>/dev/null | head -1)
    if [ -n "$NEWEST" ] && [ -f ~/.hermes/telegram_bot_token ]; then
        BOT_TOKEN=$(cat ~/.hermes/telegram_bot_token)
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d chat_id="49272385" \
            -d text="📦 Backup: $TOTAL files, latest $(basename "$NEWEST")" \
            2>/dev/null || true
    fi
fi