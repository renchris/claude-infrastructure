# P7-daemon-trigger — receipts

Unit: can a request written by the StopFailure hook wake the lr-reset-poller in seconds?
Date: 2026-09-19. All commands read-only.
Verdict: **PARTIAL** — the trigger is mechanically available and cheap, but the poller cannot
be trusted as the daemon half today, for a reason that is NOT the one briefed.

---

## R1 — The trigger is DOCUMENTED IN THE DAEMON AND IMPLEMENTED NOWHERE

`scripts/limit-recover/lr-reset-poller.sh:639-643`:

```
# ── 0. REQUESTS — a driver's hand-off to this daemon (LIMIT_RECOVER_100P) ───────
# `/limit-recover fleet` ... when a session's own tool is refused (the auto-mode
# classifier denies acting on a live pane from inside a session) it writes a request
# here and kickstarts this job. A LaunchAgent runs outside every session and every
# classifier, so this is the locus that cannot be refused.
```

The whole repo's only other mention of kickstart:

```
$ grep -rn "kickstart" claude-infrastructure/scripts/ claude-infrastructure/hooks/
scripts/limit-recover/lr-fleet.sh:464:      echo "  launchctl kickstart -k gui/$(id -u)/com.reso.lr-reset-poller"
scripts/limit-recover/lr-reset-poller.sh:642:# session) it writes a request here and kickstarts this job.
```

`lr-fleet.sh:462-465` in full:

```
if [ "$n" -gt 0 ]; then
  echo "lr-fleet: $n request(s) written. The poller drains them on its next tick (≤10 min); to run it now:"
  echo "  launchctl kickstart -k gui/$(id -u)/com.reso.lr-reset-poller"
```

=> The kickstart is **printed to a human**, never executed. The daemon's own comment asserts
an automation that does not exist. Worst-case wake today = the full StartInterval.

`hooks/stop-failure-marker.sh` (131 lines) contains **zero** of `kickstart|launchctl|requests`:

```
$ grep -n "kickstart\|launchctl\|requests" hooks/stop-failure-marker.sh   => (no output)
```

**`-k` is the WRONG flag and the shipped line would cause harm.** `man launchctl:97-102` —
`kickstart [-kp] service-target … -k  If the service is already running, kill the running
instance before restarting`. A tick mid-`lr-fleet --one` is exactly what the self-overlap lock
exists to protect (R5); `-k` kills it. The safe form is bare
`launchctl kickstart gui/$UID/com.reso.lr-reset-poller`.

## R2 — MEASURED COST OF THE MISSING TRIGGER: mean 323 s, max 609 s of blindness

StopFailure markers land ~1 s after the limit turn. Pairing marker ts against the poller's own
PARKED line, next3's 2026-09-19 cap wave:

```
$ jq -r '[.ts,(.session_id[0:8])]|@tsv' ~/.claude/autonomy/stop-failure/rate_limit__next3.jsonl | tail
$ grep "^2026-09-19" ~/.reso/limit-recover/poller.log | tail -25
```

| sid8 | StopFailure marker | poller PARKED | detection latency |
|---|---|---|---|
| 11569d45 | 19:53:44Z | 19:54:12Z | **28 s** |
| 65186f1f | 19:57:41Z | 20:04:28Z | **407 s** |
| 8843bcf3 | 19:58:53Z | 20:04:28Z | **335 s** |
| 4bc1159f | 20:00:44Z | 20:04:26Z | **222 s** |
| 26cd14be | 20:04:34Z | 20:14:43Z | **609 s** |
| 07e30aeb | 20:29:28Z | 20:35:06Z | **338 s** |

mean 323 s, max 609 s ≈ the full 600 s interval. The batch property the operator named is
confirmed on the same lines: ONE tick at 20:04:26-28 parked THREE next3 sessions in 2 s.

## R3 — THE PLIST: StartInterval only, no event trigger; job healthy

`~/Library/LaunchAgents/com.reso.lr-reset-poller.plist` — keys present:
`EnvironmentVariables{LR_POLLER_AUTOFIRE=1}`, `Label`, `ProgramArguments`, `RunAtLoad=true`,
`StandardErrorPath`, `StandardOutPath`, `StartInterval=600`.
**No WatchPaths, no QueueDirectories, no ThrottleInterval.**

```
$ launchctl print gui/501/com.reso.lr-reset-poller
  state = not running ; runs = 414 ; last exit code = 0 ; run interval = 600 seconds
  minimum runtime = 10 ; default environment = { PATH => /usr/bin:/bin:/usr/sbin:/sbin }
```

Job is loaded and healthy. The unattended PATH resolves both tools a trigger would need:

```
$ env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin bash -c 'command -v launchctl' => /bin/launchctl
$ env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin bash -c 'command -v jq'        => /usr/bin/jq
```

## R4 — WHICH launchd PRIMITIVE. Apple discourages WatchPaths BY NAME.

`man launchd.plist:330-342`:

```
WatchPaths <array of strings>
  This optional key causes the job to be started if any one of the listed paths are modified.
  IMPORTANT: Use of this key is highly discouraged, as filesystem event monitoring is highly
  race-prone, and it is entirely possible for modifications to be missed. When modifications
  are caught, there is no guarantee that the file will be in a consistent state when the job
  is launched.

QueueDirectories <array of strings>
  This optional key keeps the job alive as long as the directory or directories specified
  are not empty.
```

`man launchd.plist:316-319` — `ThrottleInterval`: "by default, jobs will not be spawned more
than once every 10 seconds", overridable.

Consequence: **QueueDirectories beats WatchPaths for this job.** A missed WatchPaths event is a
lost recovery with no retry; QueueDirectories is self-healing by construction — it re-fires
until the directory drains, and the poller already drains it (`rm -f "$_rq"`,
lr-reset-poller.sh:658). The queue directory already exists and is already the request
contract: `lr-reset-poller.sh:152  REQUESTS="$STATE/requests"; mkdir -p "$REQUESTS"` →
`~/.reso/limit-recover/requests/` (empty now; `results/` holds 5 executed requests, latest
2026-09-14 10:39, so the drain path is proven end-to-end).

There IS in-fleet WatchPaths precedent, in the sentinel-file shape (not directory):

```
$ grep -l WatchPaths ~/Library/LaunchAgents/*.plist
  com.claude.browse-mirror.plist ; gl.reso.worktree-gc.plist
gl.reso.worktree-gc.plist: WatchPaths = [ /Users/chrisren/.reso/worktree-gc.wake ]
  beside StartCalendarInterval, RunAtLoad=false
```

## R5 — THE LOCK UNDER A 5-SESSION BURST: correct, but INVISIBLE

`lr-reset-poller.sh:169-192` — SKIP, never queue; holder identity is pid+lstart:

```
LOCKD="${LR_POLLER_LOCK_DIR:-$STATE/poller.lock}"
if ! mkdir "$LOCKD" 2>/dev/null; then
  ... if live holder: exit 0        # a genuine live tick holds it — skip this one
  rm -rf "$LOCKD" ...               # stale (dead or pid recycled) — steal it
  mkdir "$LOCKD" 2>/dev/null || exit 0
fi
```

Behaviour under a burst of N wakes (kickstart or QueueDirectories): the first wake takes the
lock, the other N-1 `exit 0`. That is CORRECT for safety — the comment at :172-176 records the
2026-07-26 incident (four concurrent `--resume` on one sid, ~1.9 GB, four processes appending
to one transcript) — and it is why a burst trigger needs no de-duplication of its own.

**But the skip emits NO log line** — no `log()` before `exit 0`, and the poller only logs on
events, never per tick. So "ran and found nothing", "skipped on the lock" and "never fired" are
indistinguishable on disk. Corroborating gap in today's log: ticks at 20:04:26 / 20:14:43 /
**20:35:06** — a 20 m 23 s gap where a ~10 m tick is missing, and nothing on disk attributes
it. With QueueDirectories this matters more, not less: a queue that cannot drain because every
wake loses the lock would spin at the ThrottleInterval floor with zero log output.

Tick duration, for sizing the contention window: the 19:43 recovery tick ran 19:43:04
(CONSOLIDATED) → 19:43:47 (last RESUMED) = **43 s** for 5 candidates / 2 resumes / 3
transplants — well inside 600 s. So burst contention is tens of seconds, not minutes.

## R6 — THE LIVE account-map DEFECT: the brief's reading is WRONG, and the real one is worse

The briefed symptom is real but is **two transient events, not a standing break**, and the line
number is not 21 alone. Collapsing the whole 234-line err log:

```
$ sed 's/[0-9]\+/N/g' ~/.reso/limit-recover/poller.launchd.err | uniq -c
  20 lr-reset-poller.sh: line 150: cc_acct_name_for_dir_basename: command not found
   1 ../../lib/account-map.generated.sh: line 17: syntax error: unexpected end of file
   4 lr-reset-poller.sh: line 162: cc_acct_name_for_dir_basename: command not found
 204 lr-reset-poller.sh: line 139: _LRP_SELF: unbound variable
   1 ../../lib/account-map.generated.sh: line 21: syntax error: unexpected end of file
   4 lr-reset-poller.sh: line 296: cc_acct_name_for_dir_basename: command not found
```

The signature is exact and twice-repeated: **1 syntax error → exactly 4 `command not found`.**
Four = the four config dirs of the §1 detect loop (`lr-reset-poller.sh:664`:
`for cfg in ~/.claude-next ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary`). So
each event is **one tick that detected nothing at all**, silently. The err file's last write is
2026-09-15 19:48, so neither event is live right now.

The file is FINE at this moment, and it is not hand-maintained:

```
$ ls -la ~/.claude/lib/account-map.generated.sh
  -> /Users/chrisren/Development/claude-infrastructure/lib/account-map.generated.sh
     (repo copy: mtime Sep 19 15:04, 2354 bytes)
$ git status --porcelain lib/account-map.generated.sh  => (clean)
$ git diff HEAD -- lib/account-map.generated.sh        => (empty)
$ bash -n ~/.claude/lib/account-map.generated.sh       => PARSES OK
```

Line 21 of the current file is `    next2|claude2) CC_ACCT_DIR="$HOME/.claude-secondary" ;;` —
valid. Last content change was 2026-08-11 (`088875158 fix(fire): pin the account with an env
prefix…`); today's 15:04 mtime is a **regeneration that produced byte-identical content**.

**Root cause — a non-atomic generator writing the live file in place.**
`scripts/gen-account-map.sh:117-118`:

```
} > "$OUT"
chmod +x "$OUT"
```

A truncating `>` redirect straight onto the destination, with no temp-file + `mv`. `$OUT` is
the very inode every consumer sources (the `~/.claude/lib/` path is a symlink to it). Any
consumer sourcing it inside the write window reads a truncated file — which is exactly "syntax
error: unexpected end of file" at a *different* line each time (17, then 21), as the two events
show. Regeneration is not rare: it ran again today.

**Second fault — the poller's fallback chain is not a fallback.** `lr-reset-poller.sh:293-296`:

```
for _CC_AM in "${CC_ACCOUNT_MAP:-}" "$(dirname "$0")/../../lib/account-map.generated.sh" \
              "$HOME/.claude/lib/account-map.generated.sh"; do
  [ -n "$_CC_AM" ] && [ -f "$_CC_AM" ] && { source "$_CC_AM"; break; }
done
acct_of_cfg() { cc_acct_name_for_dir_basename "${1##*/}"; }
```

Three defects in four lines: (a) `$0` is `~/.claude/scripts/limit-recover/lr-reset-poller.sh`,
so candidates 2 and 3 resolve to the **same inode** — there is no redundancy; (b) the `break`
does not depend on `source`'s exit status, so a FAILED source still ends the loop; (c) there is
no post-source assertion (`declare -F cc_acct_name_for_dir_basename`).

**What the poller does wrong while broken.** `set -uo pipefail` (`:40`) — no `-e`, so the
failure is swallowed. The only consumer is `lr-reset-poller.sh:665`:

```
acct=$(acct_of_cfg "$cfg"); [[ -n "$acct" ]] || continue
```

at the head of `# ── 1. DETECT + LEDGER parked sessions`. With the map unsourced, `acct` is
empty for all four dirs, `continue` fires four times, and the **entire detection pass is skipped
with no log line and exit code 0**. The §0 request arm (`:646`) is unaffected — it never calls
`acct_of_cfg` — so a broken tick still drains queued requests while detecting nothing new.
Extent: 2 events in the err log's whole life, plus 5 earlier ticks in the line-150 era (20/4),
i.e. rare but wholly silent.

The 204× `_LRP_SELF: unbound variable` is a separate, already-FIXED bug — the current script
carries its own post-mortem at `:136-141`.

---

## THE DESIGN — trigger in two parts, cheapest first

**Part A (agent-side, no operator step, live immediately).** The hook is a symlink
(`~/.claude/hooks/stop-failure-marker.sh -> repo`, verified `ls -la`), so a repo edit is live
with no deploy-live converge. Append one arm after the marker write:

```bash
# wake the reset poller now instead of waiting up to StartInterval (600 s)
/bin/launchctl kickstart "gui/$(id -u)/com.reso.lr-reset-poller" >/dev/null 2>&1 || true
```

Bare `kickstart`, never `-k` (R1). `/bin/launchctl` absolute, never a bare name — the hook's
unattended PATH is `/usr/bin:/bin:/usr/sbin:/sbin` (R3) and a bare-name miss under `|| true` is
a silent no-op. No permission rule is needed: hooks execute outside the classifier, whereas an
agent-side `launchctl kickstart` would prompt (`~/.claude/settings.json:283` allowlists only
`launchctl load` for a different job) — the hook is the right locus precisely because it is not
subject to that. Expected latency: bounded by `ThrottleInterval` (default 10 s), against
today's measured mean 323 s / max 609 s.

UNMEASURABLE here: `kickstart`'s exact exit behaviour against an already-running instance of
this job — running it was out of scope for this unit. `|| true` makes the arm safe either way.

**Part B (operator-owned, c10 — it edits a plist).** QueueDirectories on the queue that already
exists, as the self-healing backstop for kickstarts that are missed:

```bash
plutil -insert QueueDirectories -json '["/Users/chrisren/.reso/limit-recover/requests"]' \
  ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist
plutil -insert ThrottleInterval -integer 5 \
  ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist
launchctl bootout  "gui/$(id -u)/com.reso.lr-reset-poller"
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist
launchctl print "gui/$(id -u)/com.reso.lr-reset-poller" | grep -E 'state|runs|interval'
```

Keep `StartInterval 600` — it is the floor that survives a missed event. Do **not** use
WatchPaths (R4: Apple discourages it by name; a missed event is a lost recovery with no retry).

**Part C — three preconditions Part B needs, or it converts a rare silent miss into a spin.**

1. The lock's `exit 0` (`:180`) must `log "TICK-SKIP <holder pid>"` first, so a non-draining
   queue is legible.
2. A once-per-tick heartbeat line, so "ran and found nothing" is distinguishable from "never
   ran" — the 20 m 23 s gap in R5 is currently unattributable.
3. R6's two fixes: `gen-account-map.sh` writes `$OUT.tmp` then `mv` (atomic rename), and
   `lr-reset-poller.sh:293-296` becomes
   `source "$_CC_AM" && declare -F cc_acct_name_for_dir_basename >/dev/null && break`, with a
   hard `log` + `exit 1` when no candidate yields the function.

Without (3), a QueueDirectories wake landing during a regeneration detects nothing, logs
nothing, exits 0, drains nothing — and re-fires forever.

**Recovery-chain dependency, noted not designed (out of scope for this wave):** Part A shortens
DETECTION only. The poller's §2 fire pass still runs through the capacity gate, and
`cc_sp_active` (scripts/lib/spawn-presence.sh:298) counts a limit-dead pane as mid-turn because
Stop never fires on a limit turn — so a faster trigger delivers candidates to a gate that
over-counts today. Triggering sooner without that fix means parking sooner, not recovering
sooner.

## TRUST VERDICT — can the poller be the daemon half today?

**Not as-is, and the gap is in OBSERVABILITY, not mechanism.**

For: loaded, 414 runs, last exit 0; the request queue exists and has drained 5 real requests;
the overlap lock is correct under burst and was written from a real incident; the batch property
holds (3 sessions, one tick, 2 s).

Against: the only trigger is a human reading an `echo`; a broken tick detects nothing and says
nothing; a skipped tick says nothing; the account map it depends on is rewritten non-atomically
in place by a generator that ran again today.

A daemon that can silently detect nothing is worse than one that is merely late, because the
operator's ask is explicitly that a claimed recovery which produced nothing must be NAMED.
Ship Part A now (agent-side, reversible, one line); ship Part C before Part B.
