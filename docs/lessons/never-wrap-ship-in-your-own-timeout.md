# Never wrap /ship in your own timeout

_Relocated VERBATIM from `.claude/rules/agent-operating-lessons.md` (always-loaded tier) — the rules file now carries the hook and links here. Nothing was shortened._

[Never wrap /ship in your own timeout](.) — 2026-09-08: a land wrapped in `timeout 900 bash scripts/ship-land.sh` was KILLED at 936s with **every gate clean** — `verdict=killed signal=SIGTERM … a TIMEOUT is in our OWN ancestry`. ship-land already bounds itself (wall-clock ratchets, bounded in-lock fetch/push, gate rounds) and under land-lock contention its legitimate runtime exceeds any bound you would guess. An outer timeout cannot distinguish "contended but progressing" from "wedged", so it can only ever convict a healthy land — and the work stays stranded on the branch. Run it unbounded and read ITS verdict.
