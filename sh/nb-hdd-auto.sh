#!/bin/sh
# Runs when the HDD partition appears (udev rule 99-hdd-automount.rules).
# Mounts the HDD and brings Docker/Syncthing back if they were knocked out.
ok_mount() { ls /mnt/hdd/seafile >/dev/null 2>&1; }

state=$(systemctl is-system-running 2>/dev/null)
case "$state" in
    starting|stopping|maintenance) exit 0 ;;
esac

if ok_mount && systemctl is-active --quiet docker && systemctl is-active --quiet syncthing@link.service; then
    exit 0
fi

if ! ok_mount; then
    systemctl stop mnt-hdd.mount 2>/dev/null
    umount -l /mnt/hdd 2>/dev/null
    sleep 1
    systemctl start mnt-hdd.mount 2>/dev/null
    sleep 2
fi

if ! ok_mount; then
    echo "HDD detected but could not be mounted" | systemd-cat -t nb-hdd-auto
    exit 1
fi

systemctl restart docker 2>/dev/null
systemctl restart syncthing@link.service 2>/dev/null
echo "HDD auto-remounted; docker and syncthing restarted" | systemd-cat -t nb-hdd-auto
