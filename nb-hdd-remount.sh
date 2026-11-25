#!/bin/sh
# Remount the HDD after it was physically reinserted, then restart dependents.
set -e
systemctl restart mnt-hdd.mount
sleep 2
systemctl restart docker
systemctl restart syncthing@link.service || true # link - username
echo "HDD remounted; docker and syncthing restarted."
