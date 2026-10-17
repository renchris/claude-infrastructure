# Design: defense in depth for the 2026-10-16 teammate resurrection

Read-only design pass. Code cited from this worktree (HEAD f6b1fbff2). It builds on the five
investigator notes beside this file (A-E). "measured" names the command. "estimated" names the
method. "UNVERIFIED" means I could not check it.

## The invariant

**Only the owner of a session's lifetime may re-spawn it. Any other actuator must back off
when ownership signals it.** A teammate's owner is its lead. A mover owns only the close it
made, and that close is paid once its relaunch is proven. Every fix below enforces one face of
this rule at one seam.

## What actually broke (synthesis of A-E, with three new measurements)

1. The census read a member that was already current as "not current". The cause is a raw
   string compare at `scripts/limit-recover/lr-upgrade.sh:686`. Measured with
   `/bin/bash 3.2.57`: `[ "$E" = "$L" ]` gives *differ* and `[ "$E" -ef "$L" ]` gives *same*,
   where L = `~/.claude-293/node_modules/.bin/claude` and E = its resolved `claude.exe`.
2. The auto refill (`:3122`, `:3163`) queued the member on its own. Its lead was current.
   Measured with `ps -o args= -p 20540`, read-only: argv[0] is
   `~/.claude-293/node_modules/.bin/claude` with `--model claude-opus-5-5`. So no
   `lead-awaits-teammates` row asked for the member's move.
3. handoff-fire's watcher verified the relaunch and discharged the debt at 23:25:17. Inside
   the drive's proof window, the lead retired the new process. The approval came at
   23:25:40.800 and the pane closed with HUP at 23:25:45 (slot C). Step 6 (`:2683-2729`) then
   read "no process" as "relaunch failed". It ran `lru_relaunch_gated`, which was refused
   because the pane was absent, then `lru_settle_verdict`, then `cc-resume-debt settle`.
   - Estimated: the fire step ran from 18:25:15 (the handoff-fire.log mtime, slot C) to
     18:26:10 (events.jsonl). That is exactly 55 s, which equals `lru_proven`'s default budget:
     3 tries x 15 s hold (`LRU_PROVE_HOLD_S`) plus 2 x 5 s gap. This matches hrc=0 with three
     failed `lru_proven` tries.
   - UNVERIFIED: why the first try failed while pid 80169 was alive. Arithmetic alone cannot
     pin it. No fix below depends on it.
4. `_settle` treats `proven` as "no prior debt" (`bin/cc-resume-debt:681`, `_active` at
   `:126`). It reopened the debt, and `_relaunch` (`:464-517`) started the session in a new
   window with no team identity.
5. The launcher in that path, `bin/reso-resume-one`, lacks the no-echo guard that
   `lr-fire-resume.sh:1071-1076` / `:1649` / `:1045-1046` / `:1654` carry. That is where the
   composer junk came from (slot D).
6. Contributing: the TeammateIdle reaper was cancelled at 5 s. Its transcript lookup scans
   about 18k project dirs per root, 3-5 times per run (slot E). Public hook docs list
   `transcript_path` as a common input field for every event (measured: WebFetch of
   code.claude.com/docs/en/hooks).

Not changed: the vendor shutdown path. The approval and the lead-side pane close were correct
(slot C). Guards must key on facts this side can read (the member row, engagement, the
`teamName` key), never on the missing final assistant record.

## The fixes, ranked by how much of THIS incident each prevents on its own

| # | Fix | Alone prevents | Seam |
|---|---|---|---|
| 1a | Auto path moves a teammate only for its lead | the whole incident (no claim at 18:24:05). It also covers "a member awaiting shutdown is never disrupted" whatever its binary | A (policy) |
| 1b | Census compares binaries by file, not by string | the whole incident (the member reads `current`), plus all 12 no-op teammate recycles in upgrade-state (A, measured) | A (root cause) |
| 2 | lr-upgrade never relaunches a session whose relaunch was proven and then ended, or a member its lead retired, and never hands a teammate to the team-blind settle | the resurrection, the new window and the junk. It does not stop the needless recycle | B/C |
| 3 | cc-resume-debt never relaunches an Agent Teams member (abandon, with the reason) | the resurrection from **any** mover (settle and sweep) | B |
| 4 | cc-resume-debt settle honours a proof younger than GRACE_S | this resurrection, because debt #1 was proven 63 s earlier. lr-upgrade's verdict text would then be wrong ("relaunched in a NEW window") | B (amplifier) |
| 5 | TeammateIdle hook reads `transcript_path`; `find -print -quit`; reap-guard `--transcript` | probably the whole chain, since the pane would have closed around 18:19:42. Conditional: the hook must then finish within 5 s (UNVERIFIED) and the close must succeed (October: 18 confirmed of 56 reaps, slot E) | E |
| 6 | Port the no-echo guard to reso-resume-one, pinned by a marker span | only the composer junk | D |

1a and 1b tie on this incident. 1a ranks first because it is the one that enforces the stated
requirement (a member awaiting shutdown is not disrupted). 1b is the root cause of "there was
nothing to upgrade". Ship both.

---

## Fix 1b: binaries compared as files (`scripts/limit-recover/lr-upgrade.sh`)

New helper, placed beside `lru_flag` (~:229):

```bash
# ONE BINARY, TWO SPELLINGS (incident 2026-10-16). cc-claude-bin prints the launcher SYMLINK
# (.claude-293/node_modules/.bin/claude -> ../@anthropic-ai/claude-code/bin/claude.exe), and the
# vendor spawns every pane teammate with argv[0] = the RESOLVED claude.exe, so a string compare read
# every vendor-spawned member as not current: 12 no-op .claude-293 -> .claude-293 member recycles.
# The same file is the same binary; a path that does not exist keeps the plain string compare.
lru_same_bin() { [ "$1" = "$2" ] || [ "$1" -ef "$2" ]; }   # $1 $2=binary paths → 0 the same file
```

Apply it at three sites:

- `:686`: `elif lru_same_bin "$bin" "$target_bin" && [ "$model" = "$tgt" ]; then disp=current`
- `:448` (`lru_lead_block`): `if ! lru_same_bin "$b" "$4" || [ -z "$t" ] || [ "$m" != "$t" ]; then`
- `:1965` (`lru_resumed_on`): `lru_same_bin "${a%% *}" "$2" || continue`

## Fix 1a: a teammate is moved for its lead, never on its own (same file)

New helper, placed above `lru_refill` (:3109):

```bash
# A TEAMMATE IS MOVED FOR ITS LEAD, NEVER ON ITS OWN (incident 2026-10-16). An idle member is, as a
# rule, a FINISHED one waiting for its lead to end it: moving it buys nothing and races the lead's
# shutdown_request. So the automatic path queues an upgrade-teammate row only while the member's lead
# reads lead-awaits-teammates in the SAME census - the move is then a step of the lead's own.
# `cc-lr upgrade <pane>` (manual) still drives any member.
lru_auto_admits() { # $1=census rows $2=snapshot $3=disposition $4=pid → 0 the auto path may queue it
  local lead
  [ "$3" = upgrade-teammate ] || return 0
  lead="$(lru_flag "$(lru_snap_args "$2" "$4")" --parent-session-id "$LRU_RE_TEAMTOK")"
  [ -n "$lead" ] || return 1
  printf '%s\n' "$1" | LRU_S="$lead" awk -F'\t' '$2 == ENVIRON["LRU_S"] && $11 == "lead-awaits-teammates" { f = 1 } END { exit !f }'
}
```

Call sites:

- `lru_refill` `:3122`: add locals `snap pid`. Set `snap="$(lru_snapshot)"` once before the
  loop. Change the read to `read -r p s _ _ tgt _ _ _ _ pid d` (column 10 is the pid, `:722`).
  After the `case`, add `lru_auto_admits "$rows" "$snap" "$d" "$pid" || continue`.
- `lru_auto_enqueue` `:3163`: the same change, with `"$census"`.

## Fix 2: no relaunch after a proven-then-ended relaunch or a retirement, and never team-blind (same file)

1. `lru_hf_evidence` (`:2153`): initialise `HFE_ENGAGED=0` on line `:2154`, then add
   `grep -q '^→ recycle VERIFIED' "$1" 2>/dev/null && HFE_ENGAGED=1`. That line is written only by
   `recycle_await_verdict` on engagement (`scripts/handoff-fire.sh:18946`).
2. Two new helpers, placed above `lru_relaunch_gated` (~:2221):

```bash
lru_resume_running() { # $1=sid → 0 when a claude carrying --resume <sid> runs now (the snapshot's own test)
  printf '%s\n' "$(lru_snapshot)" | LRU_PAT="--resume $1" awk "$LRU_PROC_LINE"' && $8 ~ /(^|\/)claude(\.exe)?$/ && index($0, ENVIRON["LRU_PAT"]) { f = 1 } END { exit !f }'
}
# NEVER RE-SPAWN WHAT ITS OWNER ENDED (incident 2026-10-16). web-next16 was relaunched in place
# (handoff-fire VERIFIED, its debt discharged), its lead's shutdown_request then reached the NEW
# process and the lead closed the pane - all inside this drive's proof window - and the drive read
# "no process now" as "the relaunch failed": cc-resume-debt resurrected the retired member in a NEW
# window, outside its team. Asked only when no --resume <sid> claude runs: (1) a relaunch the watcher
# PROVED has been paid for, so an end after it is not this mover's close; (2) a member whose lead
# retired it (no member row) or is retiring it (unread shutdown_request) belongs to its lead.
lru_relaunch_moot() { # $1=sid → reason on stdout; rc 0 = relaunch nothing, by any path
  local sid="$1" why="" targs cfg
  if [ "$(lru_st_get "$sid" .role)" = teammate ]; then
    targs="$(lru_st_get "$sid" .team_args)"; cfg="$(lru_st_get "$sid" .cfg)"
    case "$(lru_teammate_block "$targs" "$cfg")" in
      teammate-no-team) why="teammate $(lru_flag "$targs" --agent-id "$LRU_RE_TEAMTOK") was retired by its lead (no member row in its team file)" ;;
      teammate-shutdown-pending) why="teammate $(lru_flag "$targs" --agent-id "$LRU_RE_TEAMTOK") has an unread shutdown_request from its lead" ;;
    esac
  fi
  lru_hf_evidence "$(lru_st_get "$sid" .run)/handoff-fire.log"
  [ "$HFE_ENGAGED" = 1 ] && why="the relaunch engaged (handoff-fire VERIFIED) and has since ended${why:+ - $why}"
  [ -n "$why" ] || return 1
  lru_resume_running "$sid" && return 1
  printf '%s' "$why"
}
```

3. `lru_relaunch_gated` `:2239`: make the moot check the first arm of the existing WHY chain.
   Every later block is guarded by `[ -z "$LRU_RELAUNCH_WHY" ]`, so the team-hold restore at the
   tail still runs:
   `if LRU_RELAUNCH_WHY="$(lru_relaunch_moot "$sid")"; then :`
   `elif [ "$n" -gt "$LRU_RELAUNCH_MAX" ]; then ...` (the rest is unchanged).
4. `lru_settle_verdict` `:2012`. This one choke point serves all five callers (`:2718`, `:2726`,
   `:2368`, `:2376`, `:2378`). Add these lines before `lru_settle`:

```bash
  local why
  if why="$(lru_relaunch_moot "$1")"; then
    lru_rd abandon --sid "$1" --why "lr-upgrade: $why" || true
    lru_result "$1" "$2" skipped "not live: $why; nothing relaunched" "" "$6" "$7"; return 3
  fi
  # A TEAMMATE NEVER GOES TEAM-BLIND: cc-resume-debt relaunches with account, cwd and sid only, so
  # a member comes back as a plain session outside its team (pid 57630). Its lead re-spawns it.
  if [ "$(lru_st_get "$1" .role)" = teammate ] && ! lru_resume_running "$1"; then
    lru_rd abandon --sid "$1" --why "lr-upgrade: a teammate is never relaunched team-blind" || true
    lru_result "$1" "$2" failed "stranded teammate ($3): NOT handed to cc-resume-debt, whose NEW-window relaunch carries no team identity - its lead owns it (re-spawn it from the lead, or run $(lru_st_get "$1" .run)/launch.sh)" "$5" "$6" "$7"; return 1
  fi
```

   The header comment changes to: `rc 0 upgraded · 1 failed · 3 nothing relaunched on purpose`.
   The reason prefix "not live:" maps to the `notlive` class (`:2090`), so the record goes
   terminal `not-live` and lands in drain news. The verdict vocabulary does not change.
   `lru_rd abandon` is the house idiom (`:1701`, `:1711`, `:1736`). On an already-proven debt
   it is a no-op (`bin/cc-resume-debt:341-345`).

## Fix 3: cc-resume-debt never relaunches a team member (`bin/cc-resume-debt`)

New helper, placed beside `_transcript` (:212):

```bash
# AN AGENT-TEAMS MEMBER IS NEVER RELAUNCHED FROM HERE (incident 2026-10-16). This retry carries
# account, cwd and sid only, so a member comes back as a plain session OUTSIDE its team that no lead
# will message or end (5423f92a, pid 57630). bin/cc-husk-sweep is_teammate's rule: a member's records
# carry a "teamName" KEY, a lead's none; a "teamName" quoted in message text is JSON-escaped.
_team_member() { # <sid> → its team on stdout; rc 0 when its transcript is an Agent Teams member's
  local t; t="$(_transcript "$1")" || return 1
  LC_ALL=C grep -m1 -o '"teamName":"[^"]*"' "$t" 2>/dev/null | sed 's/^"teamName":"//; s/"$//' | grep .
}
```

In `_relaunch` (`:464`), add `team` to the locals. Right after `mkdir -p "$LOGS"`, before the
fence is loaded, add:

```bash
  if team="$(_team_member "$1")"; then
    _abandon "$1" "Agent Teams member of $team: a NEW-window relaunch carries no team identity and would re-spawn it outside its team - its lead owns it"
    return 1
  fi
```

Measured with `grep -c` on the incident pair: the member transcript has `"teamName":"` on 134 of
202 lines, and the lead 6261c2ab has it on 0 of 869. The abandoned state makes `_settle` return
4, and `_sweep` skips it from then on.

## Fix 4: a paid debt is not "no debt" (`bin/cc-resume-debt` `_settle`, `:676`)

Add this before the `:681` block:

```bash
  # A PAID DEBT IS NOT "NO DEBT" (incident 2026-10-16): the watcher discharged 5423f92a's debt at
  # 23:25:17, lr-upgrade settled it 63 s later, and the reopened debt relaunched a retired member
  # 3 s after (now=1 skips GRACE). A proof younger than GRACE_S is this close being paid.
  if [ -f "$(_meta "$1")" ] && [ "$(_get "$1" state)" = proven ]; then
    pe="$(jq -r '[.events[]? | select(.state == "proven") | .epoch] | last // empty' "$(_meta "$1")" 2>/dev/null)"
    case "$pe" in ''|*[!0-9]*) ;; *)
      if [ $(( $(_now) - pe )) -lt "$GRACE_S" ]; then
        _note "debt for $1 was proven $(( $(_now) - pe ))s ago - the close is paid, nothing to settle"; return 0
      fi ;;
    esac
  fi
```

Add `pe` to `_settle`'s locals.

## Fix 5: the TeammateIdle hook stops scanning 18k dirs (`hooks/teammate-auto-shutdown.sh`, `scripts/reap-guard.sh`)

- Hook `:791`, after `SESSION_ID`: `TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)`
- Hook `_find_transcript` (`:584`): first line
  `if [[ -n "${TRANSCRIPT_PATH:-}" && "${TRANSCRIPT_PATH##*/}" == "$sid.jsonl" && -f "$TRANSCRIPT_PATH" ]]; then printf '%s' "$TRANSCRIPT_PATH"; return 0; fi`.
  The find becomes `find "$r" -maxdepth 2 -name "$sid.jsonl" -print -quit` (drop `| head -1`).
  The three callers (`:677`, `:1077`, `:1431`) get the fix with no other edit.
- Hook `:1205`: add `${TRANSCRIPT_PATH:+--transcript "$TRANSCRIPT_PATH"}` to `reap-guard decide`.
- reap-guard `cmd_decide` (`:150`): add a `--transcript) tx_hint="${2:?}"; shift 2 ;;` flag.
  After `local tj="" grace_skipped=0` (`:173`), add
  `[ -n "$tx_hint" ] && [ "${tx_hint##*/}" = "$sid.jsonl" ] && [ -f "$tx_hint" ] && tj="$tx_hint"`.
  `:182` becomes `[ -n "$tj" ] || tj="$(rg_find_transcript ...)"`. In `rg_find_transcript`
  (`:119`), use `-print -quit`.
- Measured: `find /tmp -maxdepth 0 -print -quit` works on this macOS find.

Follow-ups, not in this diff: `$SECONDS` budget checkpoints with a `pcq_add` retry (E fix 2).
The 5 s timeout lives in `~/.claude/settings.json:590-598` and is the operator's to change.

## Fix 6: no echo before interact in reso-resume-one (`bin/reso-resume-one`, `scripts/limit-recover/lr-fire-resume.sh`)

- `lr-fire-resume.sh`: wrap `:1071-1076` (`set lr_tty_orig ""` ... `}`) in
  `  # >>> lr-tty-quiet` / `  # <<< lr-tty-quiet`. Leave the code as it is.
- `reso-resume-one`: insert the same marked span, byte-identical, right before `spawn` at
  `:830`. Add a one-line Tcl comment above it with **no apostrophes** (`:810`). Right before
  `set lr_keep [lr_drain_user]` (`:963`), insert
  `if {$lr_tty_orig ne ""} { catch {exec /bin/stty $lr_tty_orig <@ stdin 2>/dev/null} }`.
- Bash side: before `expect -c` (`:798`) add `rr_tty_saved=""; [ -t 0 ] && rr_tty_saved="$(stty -g 2>/dev/null)"`.
  Right after `rr_rc=$?` (`:975`) add `[ -z "$rr_tty_saved" ] || stty "$rr_tty_saved" 2>/dev/null || true`.

## Tests (bats, hermetic, lr-upgrade cases run under /bin/bash)

tests/lr-upgrade.bats (team block, after T11):
- `T12 [RED] a vendor-spawned member on the target (argv[0] = the claude.exe the launcher symlink resolves to) reads CURRENT, and its lead reads UPGRADE-LEAD, not LEAD-AWAITS-TEAMMATES`.
  The fixture is a real symlink tree under `$BATS_TEST_TMPDIR`, with the cc-claude-bin stub
  echoing the symlink. RED: revert `lru_same_bin`.
- `T13 [RED] INCIDENT 2026-10-16 replay: an idle member relaunched in place (handoff-fire VERIFIED) whose lead then retires it is never relaunched - no --relaunch-at-shell, no cc-resume-debt settle; verdict skipped "not live: ... retired by its lead"; terminal not-live`.
  Shape: `team_file`; lead on the target; the member is a real `sleep` pid; a recording
  cc-resume-debt stub with prove rc 1 and settle rc 0. The hf stub prints `OPEN_LINE` and
  `→ recycle VERIFIED: ...`, kills the member pid, rewrites the team file `nomember`, and exits
  0. Assert that rd.log has no `settle` and hf.log has no `--relaunch-at-shell`. RED: drop the
  moot check.

tests/lr-upgrade-settle.bats:
- `S14 [RED] crash-settle: a record whose handoff-fire log says VERIFIED and whose session has since ended is settled not-live - nothing typed, no settle` (plain role).
- `S14b [RED] a member refused at its shell (not engaged, member row present) is never handed to cc-resume-debt settle; its debt is abandoned; terminal stranded naming its lead`.
- `S15 [RED] --auto-enqueue and refill never queue a member on its own; they queue it while its lead's row reads lead-awaits-teammates` (control in the same case).
- Controls that must stay green unchanged: S2, S3a, S3b, S9c (a plain session that never
  engaged still settles).

tests/cc-resume-debt.bats (beside `:281`):
- `settle on a debt proven 63 s ago opens nothing and relaunches nothing (the incident's paid debt)`.
- `settle on a debt proven longer ago than GRACE_S reopens and relaunches (control)`.
- `an Agent Teams member's debt is abandoned, never relaunched - settle returns 4, sweep skips it`.
- `control: a lead transcript, or one that quotes "teamName" inside message text, still relaunches`.

tests/teammate-auto-shutdown.bats:
- `transcript_path from the payload: the tool-in-flight gate reads it and no transcript find runs`.
  The transcript sits outside `CC_CLASSIFY_PROJECT_ROOTS`, and a PATH-stub `find` records any
  `-name <sid>.jsonl` call. `mkinput` gains an optional 5th field.
- `a transcript_path naming another session is ignored (falls back to the roots)`.

tests/reap-guard.bats:
- `decide --transcript <path> resolves R-d from it without scanning the roots`.

tests/lr-fire-resume-reply-drain.bats:
- `the lr-tty-quiet block is identical in both launchers, precedes spawn, and is undone immediately before the drain`.

tests/reso-resume-one.bats:
- `RED-PROOF no echo before interact: the pane tty stops echoing while claude boots`.
  This ports `tests/lr-fire-resume-submit.bats:637` through `CC_RR_NO_INTERACT` and the stub
  claude, sampling `stty -a` on the pty slave 1 s in.

## Risks

- Fix 1a changes fleet behaviour. A non-current lead with long-lived members still upgrades them
  (they are its prerequisite). A current lead's stale members are now never auto-moved, so they
  converge only when retired or driven by hand. That is the intended trade.
- Fix 2 writes `not-live`, not `upgraded`, for a relaunch that was verified by process but never
  registry-proven before it ended. That is honest under the 2026-09-28 rule ("a process is not
  proof"), but it differs from the operator's mental model of "it did upgrade".
- Fix 3 abandons rather than escalates. A teammate stranded by some mover other than lr-upgrade
  then leaves only a custody abandon with a reason, and no backlog row. A backlog row's
  `boot-resume-launch` command would be team-blind and wrong, so this is deliberate.
- Fix 3's `_transcript` globs `<cfg>/projects/*/<sid>.jsonl` across about 18k dirs on every
  relaunch attempt. That cost already exists for recovery proofs, but under load it is a few
  seconds (estimated from slot E's find timings).
- Fix 4 can skip a settle for a session that crashed within GRACE_S after a proof. Crash recovery
  belongs to the watchdog path, not to the mover's paid debt.
- Fix 5 deploys `--transcript` across two files. A mid-land skew (new hook, old reap-guard) makes
  reap-guard `die` on an unknown flag, and the hook then defers. That fails closed.
- Fix 6: an apostrophe in the inserted Tcl comment breaks the single-quoted expect program
  (`:810`). Run `/bin/bash -n` and the bats `--count` plan line check.
- Not covered here, same class: `scripts/boot-resume.sh` (reboot) and operator cc-do rows run
  `boot-resume-launch.sh` with no team gate. Follow-up: lift `_team_member` into
  `lib/team-member.sh` and make it ownership question 4 there (exit 5).

## UNVERIFIED

- argv[0] of the old pid 15617. It is inferred from q2-teammate-relaunch.md:73. No live teammate
  existed to sample: measured `ps -axww -o pid=,args=` found no `--agent-id` process.
  `lru_same_bin` is correct for either spelling.
- Why the first `lru_proven` try failed while 80169 was alive. No fix depends on it.
- Whether the hook finishes within 5 s once the scans are gone (git status, jq,
  `cc-sessions --json` remain).
- When exactly the lead removed the member row. Fix 2 does not depend on it, because
  `HFE_ENGAGED` alone makes the relaunch moot.
