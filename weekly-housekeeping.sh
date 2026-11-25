#!/usr/bin/env bash
# Weekly housekeeping for the Hermes home: age-based compression and pruning of
# logs, scratch artifacts, state snapshots and curator backups.
#
# Runs as a --no-agent cron script: stdout is delivered verbatim, empty stdout is
# silent. Nothing here touches the memory store (MEMORY.md / USER.md) - that is a
# separate step in weekly-skill-consolidation.sh, because it needs a live agent
# turn to judge duplicates.
#
# Everything is age-based and conservative. Nothing is deleted that is younger
# than its threshold, and nothing here is irreversible except the explicit
# delete thresholds - the compress pass (gzip) keeps the content.
#
# Knobs (env, all optional):
#   SWEEP_DRY_RUN=1          print what would happen, change nothing
#   LOG_COMPRESS_DAYS=7      gzip plain log files older than this
#   LOG_DELETE_DAYS=30       delete log files (incl. .gz) older than this
#   TRANSCRIPT_DAYS=3        delete YouTube transcript dumps older than this
#   KEEP_SNAPSHOTS=2         keep the newest N state-snapshots/ dirs
#   KEEP_CURATOR_BACKUPS=3   keep the newest N skills/.curator_backups/ dirs
#   CHECKPOINT_DAYS=30       delete checkpoints/ files older than this
set -uo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
DRY=0
[[ "${SWEEP_DRY_RUN:-0}" == "1" ]] && DRY=1

LOG_COMPRESS_DAYS="${LOG_COMPRESS_DAYS:-7}"
LOG_DELETE_DAYS="${LOG_DELETE_DAYS:-30}"
TRANSCRIPT_DAYS="${TRANSCRIPT_DAYS:-3}"
KEEP_SNAPSHOTS="${KEEP_SNAPSHOTS:-2}"
KEEP_CURATOR_BACKUPS="${KEEP_CURATOR_BACKUPS:-3}"
CHECKPOINT_DAYS="${CHECKPOINT_DAYS:-30}"

verb() { [[ "$DRY" == "1" ]] && printf 'would %s' "$1" || printf '%s' "$1"; }

# 0 if some running process holds the file open (never touch a live log).
# lsof is a single fast C pass; the /proc scan is the portable fallback and is
# built once per run, not once per file.
OPEN_FDS_CACHE=""
ensure_open_cache() {
  [[ -n "$OPEN_FDS_CACHE" ]] && return 0
  OPEN_FDS_CACHE=$(mktemp "${TMPDIR:-/tmp}/hermes-openfds.XXXXXX")
  for fd in /proc/[0-9]*/fd/*; do readlink "$fd" 2>/dev/null; done | sort -u > "$OPEN_FDS_CACHE"
}
is_open() {  # path
  local target
  [[ -e "$1" ]] || return 1
  if command -v lsof >/dev/null 2>&1; then
    [[ -n "$(lsof -t -- "$1" 2>/dev/null)" ]]
    return
  fi
  target=$(readlink -f -- "$1" 2>/dev/null) || return 1
  [[ -n "$target" ]] || return 1
  ensure_open_cache
  grep -Fxq -- "$target" "$OPEN_FDS_CACHE"
}
trap '[[ -n "${OPEN_FDS_CACHE:-}" ]] && rm -f -- "$OPEN_FDS_CACHE"' EXIT

# --- helpers -----------------------------------------------------------------

# gzip plain files in a dir older than N days (keeps content, frees space)
gzip_files() {  # dir days label
  local dir="$1" days="$2" label="$3" list f n=0
  [[ -d "$dir" ]] || return 0
  list=$(find "$dir" -maxdepth 1 -type f ! -name '*.gz' ! -name '.*' ! -name '*.lock' -mtime +"$days" 2>/dev/null)
  [[ -n "$list" ]] || return 0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    is_open "$f" && continue
    if [[ "$DRY" == "1" ]]; then n=$((n + 1)); else gzip -9 -n -- "$f" 2>/dev/null && n=$((n + 1)); fi
  done <<< "$list"
  printf '  %-30s %s %s file(s) older than %sd\n' "$label" "$(verb gzip)" "$n" "$days"
}

# delete files in a dir older than N days
prune_files() {  # dir days label
  local dir="$1" days="$2" label="$3" list f n=0
  [[ -d "$dir" ]] || return 0
  list=$(find "$dir" -maxdepth 1 -type f ! -name '.*' ! -name '*.lock' -mtime +"$days" 2>/dev/null)
  [[ -n "$list" ]] || return 0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    is_open "$f" && continue
    if [[ "$DRY" == "1" ]]; then n=$((n + 1)); else rm -f -- "$f" && n=$((n + 1)); fi
  done <<< "$list"
  printf '  %-30s %s %s file(s) older than %sd\n' "$label" "$(verb remove)" "$n" "$days"
}

# delete subdirectories of a dir older than N days (e.g. curator report dirs)
prune_dirs() {  # dir days label
  local dir="$1" days="$2" label="$3" list d n=0
  [[ -d "$dir" ]] || return 0
  list=$(find "$dir" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -mtime +"$days" 2>/dev/null)
  [[ -n "$list" ]] || return 0
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    if [[ "$DRY" == "1" ]]; then n=$((n + 1)); else rm -rf -- "$d" && n=$((n + 1)); fi
  done <<< "$list"
  printf '  %-30s %s %s dir(s) older than %sd\n' "$label" "$(verb remove)" "$n" "$days"
}

# keep only the newest N subdirectories of a dir
keep_newest_dirs() {  # dir n label
  local dir="$1" keep="$2" label="$3" total victims v n=0
  [[ -d "$dir" ]] || return 0
  total=$(find "$dir" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | wc -l)
  [[ "$total" -gt "$keep" ]] || return 0
  victims=$(find "$dir" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn | tail -n +"$((keep + 1))" | cut -d' ' -f2-)
  while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    if [[ "$DRY" == "1" ]]; then n=$((n + 1)); else rm -rf -- "$v" && n=$((n + 1)); fi
  done <<< "$victims"
  printf '  %-30s %s %s/%s dir(s), kept newest %s\n' \
    "$label" "$(verb remove)" "$n" "$total" "$keep"
}

# --- report ------------------------------------------------------------------

echo "=== weekly housekeeping - $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
[[ "$DRY" == "1" ]] && echo "mode: dry-run (no changes)"
echo

BEFORE=$(du -sh "$HERMES_HOME" 2>/dev/null | cut -f1)

echo "--- logs: compress then delete ---"
for d in logs logs/session_sweep logs/process-results logs/update_receipts; do
  gzip_files "$HERMES_HOME/$d" "$LOG_COMPRESS_DAYS" "$d"
done
for d in logs/session_sweep logs/process-results logs/update_receipts; do
  prune_files "$HERMES_HOME/$d" "$LOG_DELETE_DAYS" "$d"
done
prune_dirs "$HERMES_HOME/logs/curator" "$LOG_DELETE_DAYS" "logs/curator"

echo "--- scratch artifacts ---"
prune_files "$HERMES_HOME/cache/scratch/transcripts" "$TRANSCRIPT_DAYS" "scratch/transcripts"

echo "--- snapshots and backups ---"
keep_newest_dirs "$HERMES_HOME/state-snapshots" "$KEEP_SNAPSHOTS" "state-snapshots"
keep_newest_dirs "$HERMES_HOME/skills/.curator_backups" "$KEEP_CURATOR_BACKUPS" "curator_backups"

echo "--- checkpoints ---"
prune_files "$HERMES_HOME/checkpoints" "$CHECKPOINT_DAYS" "checkpoints"

AFTER=$(du -sh "$HERMES_HOME" 2>/dev/null | cut -f1)

echo
echo "home size: $BEFORE -> $AFTER"
