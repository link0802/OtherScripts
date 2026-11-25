#!/bin/bash
# Daily restic backup: OS drive (tag "system") + data disk (tag "data").
# Repository lives on the HDD at /mnt/hdd/backups/restic-repo, capped at ~90 GiB.
set -uo pipefail

REPO=/mnt/hdd/backups/restic-repo
PWFILE=/mnt/hdd/backups/restic-password.txt
LOG=/var/log/nb-backup.log
LIMIT=$((90 * 1024 * 1024 * 1024))

export RESTIC_REPOSITORY="$REPO"
export RESTIC_PASSWORD_FILE="$PWFILE"

exec >>"$LOG" 2>&1
echo "===== $(date -Is) backup run"

# The disk may still be reappearing after a yank; wait up to a minute.
for _ in $(seq 1 12); do
    if ls /mnt/hdd/seafile >/dev/null 2>&1; then break; fi
    sleep 5
done
if ! ls /mnt/hdd/seafile >/dev/null 2>&1; then
    echo "HDD not readable, skipping this run"
    exit 1
fi

# OS drive: everything except regenerable / transient trees.
restic backup / --tag system --one-file-system \
    --exclude /mnt --exclude /media --exclude /proc --exclude /sys --exclude /dev \
    --exclude /run --exclude /tmp --exclude /var/tmp --exclude /snap --exclude /lost+found \
    --exclude /var/lib/snapd --exclude /var/cache/apt --exclude /var/log/journal || true

# Data disk: everything except the repository itself and the nested container
# overlay mounts (their real storage is on the OS drive).
restic backup /mnt/hdd --tag data --one-file-system \
    --exclude /mnt/hdd/backups \
    --exclude /mnt/hdd/docker/rootfs || true

restic forget --group-by tags --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

# Hard size guard: drop the oldest snapshots until under the cap.
size=$(du -sb "$REPO" | cut -f1)
while [ "$size" -gt "$LIMIT" ]; do
    oldest=$(restic snapshots --json | jq -r "sort_by(.time) | .[0].short_id // empty")
    if [ -z "$oldest" ]; then break; fi
    echo "repo $size bytes > $LIMIT, forgetting $oldest"
    restic forget "$oldest" --prune
    size=$(du -sb "$REPO" | cut -f1)
done

echo "repo size: $(du -sh "$REPO" | cut -f1)"
restic stats --mode restore-size 2>/dev/null | tail -3 || true
echo "===== done $(date -Is)"
