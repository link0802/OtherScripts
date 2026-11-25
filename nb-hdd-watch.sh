#!/bin/bash
# HDD watchdog: keeps /mnt/hdd mounted and Docker/Syncthing running.
# Runs every 2 minutes from nb-hdd-watch.timer.
UUID=b96304e4-7f14-4c1b-9f54-df0d29e0c1b8
STAMP=/run/nb-hdd-reset.stamp

state=$(systemctl is-system-running 2>/dev/null)
case "$state" in starting|stopping|maintenance) exit 0 ;; esac

readable() { ls /mnt/hdd/seafile >/dev/null 2>&1; }

if readable && systemctl is-active --quiet docker && systemctl is-active --quiet syncthing@link.service; then
    exit 0
fi

# Device is present but the filesystem is not usable -> remount + restart.
if lsblk -n -o UUID 2>/dev/null | grep -q "$UUID"; then
    /usr/local/bin/nb-hdd-auto >/dev/null 2>&1
    exit 0
fi

# Device is not on the USB bus at all -> one hub reset at most every 10 min.
now=$(date +%s)
last=0
[ -f "$STAMP" ] && last=$(cat "$STAMP" 2>/dev/null || echo 0)
if [ $((now - last)) -ge 600 ]; then
    echo "$now" > "$STAMP"
    for hub in /sys/bus/usb/devices/usb1 /sys/bus/usb/devices/usb2; do
        [ -w "$hub/authorized" ] || continue
        echo 0 > "$hub/authorized" 2>/dev/null
        sleep 1
        echo 1 > "$hub/authorized" 2>/dev/null
        sleep 4
    done
fi
exit 0
