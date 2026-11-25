#!/usr/bin/env bash
# charge_notif.sh -- on charger disconnect (AC 1 -> 0), play a short sound,
# show a desktop alert and send a Telegram message. On connect (AC 0 -> 1),
# send a Telegram message.
#
# How the volume is handled:
#   The system master is raised to 80% and unmuted ONLY for the duration of
#   this notification, then it is restored to exactly the value it had
#   before. No permanent change is made and no other sound is affected.
#   The default PCM (SAY_DEV="") is used, so the master volume setting is the one
#   that applies. (If you instead wanted to bypass the mixer entirely, set
#   SAY_DEV="-D hw:0,0" -- but then volume becomes fixed to the hardware, not 80%.)

set -u

AC_DIR="/sys/class/power_supply"
WAV="/tmp/charge_notif.wav"
SAY_DEV=""                       # empty -> default PCM (goes through the master mixer)
COOLDOWN=5                       # seconds to wait so we do not repeat on a flapping state
DRY="${DRY:-0}"                  # 1 = print but do not play
AC_FILE=""

# --- find the AC online file -------------------------------------------------
for d in "$AC_DIR"/*; do
  case "$(basename "$d")" in
    AC*) AC_FILE="${d}/online"; break ;;
  esac
done
[ -n "$AC_FILE" ] || { echo "charge_notif: no AC power device found" >&2; exit 1; }

# --- generate a short beep notification (mono, 44.1 kHz, 16-bit) --------------
gen_wav() {
  python3 - "$WAV" <<'PY'
import sys, wave, math, struct
out = sys.argv[1]
rate = 44100
with wave.open(out, 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
    data = bytearray()
    for i in range(int(rate * 0.22)):
        if i < rate * 0.15:
            t = 0.5 * math.sin(2 * math.pi * 880 * i / rate)
        elif i < rate * 0.18:
            t = 0.0
        elif i < rate * 0.35:
            t = 0.55 * math.sin(2 * math.pi * 880 * (i - rate * 0.18) / rate)
        else:
            t = 0.0
        data += struct.pack('<h', int(16000 * 0.6 * max(-1.0, min(1.0, t))))
    w.writeframes(bytes(data))
PY
}

# --- current master state ----------------------------------------------------
# print the numeric master volume, e.g. "80%"
amix_get()  { amixer sget Master 2>/dev/null | grep -oE '[0-9]+%' | head -n1; }
# 0 if unmuted, 1 if muted
amix_mute() { amixer sget Master 2>/dev/null | grep -q '\[off\]' && echo 1 || echo 0; }

# temporarily raise Master to 80% and unmute (only for the notification)
set_80() { amixer sset "Master" "80%" unmute >/dev/null 2>&1; }

# play the sound. the caller is responsible for restoring the previous master
# state. v and m hold the values captured before the raise.
play_notif() {
  local v m
  [ "$DRY" = "1" ] && { echo "[dry] playing"; return 0; }
  v=$(amix_get); m=$(amix_mute)
  set_80
  aplay -q "$SAY_DEV" "$WAV" 2>/dev/null
  sleep "$COOLDOWN"
  local rc=$?
  if [ "$m" = "0" ]; then amixer sset Master "$v" unmute; else amixer sset Master "$v" mute; fi
  return $rc
}

# send the message to Telegram. the bearer token is read from ~/.hermes/.env and
# never logged. delivered to this chat (chat_id 49272385).
telegram_msg() {
  local tok="$1"
  [ -f /home/link/.hermes/.env ] || return 0
  tok=$(grep -oE 'TELEGRAM_BOT_TOKEN=[^ ]+' /home/link/.hermes/.env | cut -d= -f2)
  [ -n "$tok" ] || return 0
  curl -s -X POST "https://api.telegram.org/bot${tok}/sendMessage" \
    -d "chat_id=49272385" -d "text=${1}" >/dev/null 2>&1
  return 0
}

# all notifications for one disconnect: sound, desktop alert, Telegram message.
send_notify() {
  local ts
  ts=$(date '+%d.%m %H:%M')
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u normal "Charge disconnected" "Laptop charger has been unplugged at ${ts}." 2>/dev/null
  fi
  telegram_msg "Charge disconnected at ${ts}."
}

# Telegram notification for plugging the charger in; no sound is played.
send_connect_notify() {
  local ts
  ts=$(date '+%d.%m %H:%M')
  telegram_msg "Charge connected at ${ts}."
}

# Handle only state transitions; kept separate so the event can be tested safely.
handle_transition() {
  local prev="$1" st="$2"
  if [ "$prev" = "1" ] && [ "$st" = "0" ]; then
    echo "charge_notif: charger disconnected - playing notification"
    play_notif "$SAY_DEV"
    send_notify
    echo "charge_notif: done, master restored"
    sleep "$COOLDOWN"
  elif [ "$prev" = "0" ] && [ "$st" = "1" ]; then
    echo "charge_notif: charger connected - sending Telegram message"
    send_connect_notify
    sleep "$COOLDOWN"
  fi
}

main() {
  if [ ! -f "$WAV" ]; then
    gen_wav || { echo "charge_notif: could not create wav" >&2; exit 1; }
  fi
  command -v aplay >/dev/null 2>&1 || { echo "charge_notif: aplay missing" >&2; exit 1; }

  local st prev=1
  prev=$(cat "$AC_FILE" 2>/dev/null | tr -d '[:space:]')

  echo "charge_notif: watching $AC_FILE (prev=$prev)"
  while :; do
    sleep 0.25
    st=$(cat "$AC_FILE" 2>/dev/null | tr -d '[:space:]')
    handle_transition "$prev" "$st"
    prev=$st
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
