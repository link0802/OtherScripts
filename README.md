# OtherScripts
Simple, small, but useful scripts. 


## youtube-remove-video-from-WatchLater.js

Simple js script to remove video from youtube WL. Open https://www.youtube.com/playlist?list=WL, open devTools (f12), in console - allow paste - > paste script. 
var i = 0; // start from
var videoCount = 500; // total number of videos

## opencode-free.py

opencode-free - run OpenCode with automatic failover across free cloud models.

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

## editOllama.sh

edit all local ollama models,create temp modelfile, edit context (or any other parameter/name) using bash. 

## hermesDailyBackup.sh 

Daily backup local Hermes agent data to dropbox folder. Keep only fresh 3 backups. Notify user using telegram token.