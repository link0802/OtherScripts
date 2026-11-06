#!/usr/bin/env python3
"""
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
"""

import argparse
import os
import re
import subprocess
import sys
import time

OPENCODE = os.path.expanduser("~/.opencode/bin/opencode")

# Free models, best first. All verified working on 2026-10-22.
LADDER = [
    ("google/gemini-3.5-flash",  "Gemini 3.5 Flash  - 1500 req/day, 1M ctx, no card"),
    ("opencode/nemotron-3-ultra-free", "Nemotron 3 Ultra  - Zen free, ~200-660 req/day"),
    ("opencode/deepseek-v4.1-flash-free", "DeepSeek V4.1 Flash  - Zen free"),
    ("opencode/glm-5.3-flash-free", "GLM 5.3 Flash  - Zen free"),
    ("opencode/mimo-v2.6-flash-free", "MiMo V2.6 Flash  - Zen free"),
    ("opencode/big-pickle", "Big Pickle  - Zen free"),
    ("opencode/beam-free", "Beam Free  - Zen free"),
    ("kilo/nvidia/nemotron-3-ultra-550b-a55b:free", "Nemotron 3 Ultra 550B  - Kilo free"),
    ("openrouter/nvidia/nemotron-3-ultra-550b-a55b:free", "Nemotron 3 Ultra 550B  - OpenRouter free"),
]

# Markers that mean "this model is done for today, try the next one".
FATAL = [
    "429", "rate limit", "rate-limit", "too many requests", "quota",
    "out of", "exceeded", "limit 8000", "tokens per minute",
    "no longer available", "not available", "FreeTierError",
    "socket connection was closed", "transport", "context length",
    "maximum context", "insufficient", "balance", "Streaming response failed", "[504]","Upstream idle timeout exceeded",
]


def looks_like_failure(output: str) -> bool:
    low = output.lower()
    return any(m.lower() in low for m in FATAL)


def run_model(model: str, prompt_args: list[str]) -> int:
    cmd = [OPENCODE, "run", "--standalone", prompt_args[0], "--model", model] + prompt_args[1:]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    sys.stdout.write(proc.stdout)
    if proc.stderr.strip():
        sys.stderr.write(proc.stderr)
    return proc.returncode, proc.stdout + proc.stderr


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True, description="OpenCode with free-model failover")
    ap.add_argument("prompt", nargs="?", help="prompt for opencode run")
    ap.add_argument("-f", "--file", action="append", default=[], help="attach file")
    ap.add_argument("--model", help="force a single model, skip failover")
    ap.add_argument("--list", action="store_true", help="list the model ladder")
    ap.add_argument("extra", nargs="*", help="extra args passed to opencode run")
    args, passthrough = ap.parse_known_args()

    if args.list:
        print("Free-model ladder (tried in this order):\n")
        for i, (m, desc) in enumerate(LADDER, 1):
            print(f"  {i}. {m:<55} {desc}")
        print("\n--model <id> to force one. Any unknown flag is passed to opencode run.")
        return 0

    if not args.prompt:
        ap.print_help()
        return 2

    prompt_args = [args.prompt]
    for f in args.file:
        prompt_args += ["-f", f]
    prompt_args += list(args.extra) + list(passthrough)

    models = [args.model] if args.model else [m for m, _ in LADDER]

    # OPENCODE_FREE_LADDER="a/b,c/d" overrides the ladder (comma-separated).
    override = os.environ.get("OPENCODE_FREE_LADDER")
    if override:
        models = [m.strip() for m in override.split(",") if m.strip()]

    for attempt, model in enumerate(models, 1):
        if len(models) > 1:
            print(f"\n[opencode-free] trying {attempt}/{len(models)}: {model}", flush=True)
        rc, output = run_model(model, prompt_args)
        if rc == 0 and not looks_like_failure(output):
            print(f"\n[opencode-free] done with {model}", flush=True)
            return 0
        if model != models[-1]:
            print(f"[opencode-free] {model} failed, falling over in 3s...", flush=True)
            time.sleep(3)

    print("\n[opencode-free] all free models failed. Check quotas or add a paid key.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
