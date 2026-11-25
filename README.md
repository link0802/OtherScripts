# OtherScripts
Simple, small, but useful scripts. 

## editOllama.sh 

Edit local ollama models (parameters or properties) and/or rename them 

## youtube-remove-video-from-WatchLater.js

Simple js script to remove video from youtube WL. Open https://www.youtube.com/playlist?list=WL, open devTools (f12), in console - allow paste - > paste script. 
var i = 0; // start from
var videoCount = 500; // total number of videos

## opencode-free.py

**opencode-free** : run OpenCode with automatic failover across free cloud models.

Every model in the default ladder is on a $0 tier. When one hits its quota
(429 / rate limit / transport error), the next one takes over, so a long task
does not die on the first exhausted provider.

Usage:
    opencode-free "Fix the login bug and add tests"
    opencode-free -f config.yaml "Review this file for security issues"
    opencode-free --thinking "Explain how auth works"
    opencode-free --list            # show the ladder
    opencode-free --model opencode/big-pickle "..."   # force a specific model

Any flags you do not recognise are passed straight through to `opencode run`.

## charge_notif.sh

**charge_notif.sh** : notify user about AC connect/disconnect on laptop using sound and telegram message (token from hermes .env)

## Hermes AI housekeeping scripts

**daily-backup.sh** : daily backup to Dropbox in zip archive, keep only recent 3. 

**hindsight-backup.sh** : backup of long-term memory - hindsight.

**memory-health-check.sh** : check memory status/size every day.

**weekly-housekeeping.sh + weekly-skill-consolidation.sh** : Weekly skill, memory and etc cleanup,review and consolidation.


## External USB-HDD operations

###### Remount USB external HDD to server after sudden disconnect

**nb-hdd-auto.sh** : Runs when the HDD partition appears (udev rule 99-hdd-automount.rules). Mounts the HDD and brings Docker/Syncthing back if they were knocked out.
**nb-hdd-remount.sh** : Remount (using _systemctl_) the HDD after it was physically reinserted, then restart dependents.
**nb-hdd-watch.sh** : HDD watchdog: keeps /mnt/hdd mounted and Docker/Syncthing running. Runs every 2 minutes from nb-hdd-watch.timer.
**nb-hdd-usb-reset.sh** : Runs when the HDD partition disappears. If the disk is plugged back in but the USB port is stuck (kernel shows no device at all), reset the root hub so the bridge re-enumerates; the add-event rule then mounts it and restarts Docker/Syncthing.

###### Backup

**nb-backup.sh** : Daily restic backup: OS drive (tag "system") + data disk (tag "data"). Repository lives on the HDD at /mnt/hdd/backups/restic-repo, capped at ~90 GiB.