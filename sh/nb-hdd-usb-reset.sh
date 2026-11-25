#!/bin/sh
# Runs when the HDD partition disappears. If the disk is plugged back in but
# the USB port is stuck (kernel shows no device at all), reset the root hub so
# the bridge re-enumerates; the add-event rule then mounts it and restarts
# Docker/Syncthing.
UUID=b96304e4-7f14-4c1b-9f54-df0d29e0c1b8 # ! your drive UUID
present() { lsblk -n -o UUID 2>/dev/null | grep -q "$UUID"; }

state=$(systemctl is-system-running 2>/dev/null)
case "$state" in starting|stopping|maintenance) exit 0 ;; esac

sleep 5
present && exit 0

for hub in /sys/bus/usb/devices/usb1 /sys/bus/usb/devices/usb2; do
    [ -w "$hub/authorized" ] || continue
    echo 0 > "$hub/authorized" 2>/dev/null
    sleep 1
    echo 1 > "$hub/authorized" 2>/dev/null
    sleep 4
    if present; then
        echo "HDD back after resetting $hub" | systemd-cat -t nb-hdd-usb-reset
        exit 0
    fi
done
echo "HDD still missing after USB reset" | systemd-cat -t nb-hdd-usb-reset
