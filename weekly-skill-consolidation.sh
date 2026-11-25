#!/usr/bin/env bash
# Weekly skill-library consolidation - the cheap alternative to replaying every
# session through a live agent.
#
# Runs as a --no-agent cron script: stdout is delivered verbatim, empty stdout is
# silent. The heavy option (one full agent turn per session) is deliberately NOT
# here - see the session-refine-sweep skill for that, run it on demand.
set -uo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
SWEEP="$HERMES_HOME/skills/software-development/session-refine-sweep/scripts/session_sweep.py"
LOG_DIR="$HERMES_HOME/logs/session_sweep"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"
OUT="$LOG_DIR/consolidation-$STAMP.log"

echo "=== weekly skill consolidation - $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo

# 1. Prune-only is the built-in default; --consolidate opts into the LLM merge
#    pass that folds overlapping skills into an umbrella. SWEEP_DRY_RUN=1 makes
#    this a preview that changes nothing.
if [[ "${SWEEP_DRY_RUN:-0}" == "1" ]]; then
    echo "mode: dry-run (no changes)"
    if hermes curator run --consolidate --dry-run >"$OUT" 2>&1; then
        echo "curator: ok"
    else
        echo "curator: FAILED (exit $?)"
    fi
else
    if hermes curator run --consolidate >"$OUT" 2>&1; then
        echo "curator: ok"
    else
        echo "curator: FAILED (exit $?)"
    fi
fi
echo "--- curator output (tail) ---"
tail -n 40 "$OUT" 2>/dev/null
echo

# 2. Consolidation folds away skills it judges to be the same topic. Anything it
#    merges is recoverable, so name it here instead of letting it vanish silently.
#    `hermes curator pin <name>` stops a later run from merging that skill again.
ARCHIVED="$(sed -n 's/^[[:space:]]*[•*-][[:space:]]*\([A-Za-z0-9._-]\{1,\}\)[[:space:]]*→.*/\1/p' "$OUT" 2>/dev/null | sort -u)"
if [[ -n "$ARCHIVED" ]]; then
    echo "--- merged into a sibling (recover with one command each) ---"
    for s in $ARCHIVED; do
        printf '  %-28s hermes curator restore %s\n' "$s" "$s"
    done
    echo
fi

# 3. Backlog report: what a full session sweep would still cost. Reported, not paid.
if [[ -f "$SWEEP" ]]; then
    echo "--- session sweep backlog (not run - informational) ---"
    for mode in unprocessed new; do
        printf '  %-14s ' "$mode:"
        python3 "$SWEEP" --mode "$mode" --list 2>&1 | head -1
    done
    echo "  full sweep:     python3 $SWEEP --mode unprocessed --min-messages 20"
    echo
fi

# 4. Memory consolidation - the weekly dedupe/compaction pass over MEMORY.md and
#    USER.md. Hermes has no automatic compaction for memory: entries only grow
#    until they hit the character budget, and then `add` starts being rejected.
#    This is one agent turn per week and is the pass that prevents that.
#    Set SWEEP_MEMORY=0 to skip it.
if [[ -f "$SWEEP" && "${SWEEP_MEMORY:-1}" == "1" ]]; then
    echo "--- memory consolidation (MEMORY.md + USER.md) ---"
    # Another agent writing the same file is how an entry vanishes: this pass
    # reads MEMORY.md, a batch agent rewrites it, this pass writes back a
    # version that never saw the new entry. Skip rather than race. One-shot
    # batch loops (`hermes chat -q "$(cat batch_prompt_*.txt)"`) are the usual
    # offender; SWEEP_MEMORY_FORCE=1 overrides.
    BUSY="$(pgrep -f 'hermes[ ]chat' 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "${BUSY:-0}" != "0" && "${SWEEP_MEMORY_FORCE:-0}" != "1" ]]; then
        echo "  skipped: $BUSY 'hermes chat' process(es) running - memory is being written elsewhere"
        echo "  (re-run later, or set SWEEP_MEMORY_FORCE=1 to override)"
    else
        python3 "$SWEEP" --scope memory --list
        if [[ "${SWEEP_MEMORY_DRY_RUN:-0}" == "1" ]]; then
            echo "  (dry-run: not applying changes)"
        else
            # Snapshot the store before the pass: this is the only moment an unattended
            # agent turn rewrites MEMORY.md/USER.md, so it is the only moment a copy is
            # worth having on hand for a quick restore. See the session-refine-sweep skill,
            # recovery section, for the other sources (state.db snapshots, Dropbox backup).
            SNAP="$HERMES_HOME/cache/memory-snapshots/$(date -u +%Y%m%d-%H%M%S)"
            mkdir -p "$SNAP"
            for f in MEMORY.md USER.md; do
                [[ -f "$HERMES_HOME/memories/$f" ]] && cp -p "$HERMES_HOME/memories/$f" "$SNAP/$f"
            done
            [[ -n "$(ls -A "$SNAP" 2>/dev/null)" ]] && echo "  snapshot before pass: $SNAP"

            COUNT='import os;d=os.environ["HERMES_HOME"]+"/memories";print(sum(len(open(os.path.join(d,f),encoding="utf-8-sig").read()) for f in ("MEMORY.md","USER.md") if os.path.exists(os.path.join(d,f))))'
            BEFORE="$(python3 -c "$COUNT" 2>/dev/null || echo 0)"
            python3 "$SWEEP" --scope memory --timeout-per-session 600 2>&1 | tail -n 40
            AFTER="$(python3 -c "$COUNT" 2>/dev/null || echo 0)"
            echo "  store chars before/after: $BEFORE -> $AFTER"
            if [[ "$BEFORE" -gt 0 && "$AFTER" -lt "$((BEFORE * 80 / 100))" ]]; then
                echo "  WARNING: the pass shrank the store by more than 20% - it over-reached."
                echo "  Recover from the snapshot above if entries were lost."
            fi

            # Keep only the 8 most recent snapshots.
            ls -1dt "$HERMES_HOME"/cache/memory-snapshots/*/ 2>/dev/null | tail -n +9 | xargs -r rm -rf
        fi
    fi
    echo
fi

# 5. Housekeeping - age-based compress/prune of logs, scratch artifacts, state
#    snapshots and curator backups. Safe by default, nothing here needs an agent.
#    Set SWEEP_HOUSEKEEPING=0 to skip, SWEEP_DRY_RUN=1 for a preview.
HK="$HERMES_HOME/scripts/weekly-housekeeping.sh"
if [[ -f "$HK" && "${SWEEP_HOUSEKEEPING:-1}" == "1" ]]; then
    echo "--- housekeeping ---"
    SWEEP_DRY_RUN="${SWEEP_DRY_RUN:-0}" bash "$HK"
    echo
fi
