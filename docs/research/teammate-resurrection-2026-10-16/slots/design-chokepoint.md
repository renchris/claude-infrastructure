# Design: MINIMAL CHOKEPOINT (teammate resurrection, 2026-10-16)

Code cited from this worktree at HEAD f6b1fbff2. "measured" names the command; everything else is a
read of the cited lines. Nothing here was run against a live session.

## 1. The invariant

**No team-blind launcher ever resumes an Agent Teams member.** The predicate is the transcript the
launcher would load, through `lr-predicate.sh is-teammate-head`, which is the repo's one copy of that
test.

Why this works without any retirement evidence:

- **The launchers cannot carry team identity.** `bin/cc-resume-debt:509` calls the launcher with
  account, cwd and sid only. `scripts/boot-resume-launch.sh:203` builds `reso-resume-one acct cwd sid`.
  `bin/reso-resume-one` has no `--agent-*` flag. `lr-upgrade.sh:383-385` already records the
  consequence: a member resumed this way "comes back as a plain session, outside the team". So a
  resume through this path is never correct for a member, retired or not. Incident: pid 57630 has no
  `--agent-id` (slot A section 5).
- **No race.** The member's transcript head says "teammate" from its first records, before any
  retirement happens. It does not wait on the watchdog's 30 s poll (`claude-crashes.jsonl`), on the
  lead's config rewrite, or on a teardown marker that the vendor shutdown path never writes (slot B
  section 3).
- **It is existing house policy, enforced everywhere except here.** The reconciler has invariant 1
  (`lr_recon/census.py:184`, "lead-owned"). handoff-fire's recycle probe refuses
  `REFUSED:teammate` (`scripts/handoff-fire.sh:12872-12898`). cc-husk-sweep has its TEAMMATE verdict
  (`bin/cc-husk-sweep:48-49`). lr-reset-poller has `lrp_is_teammate`
  (`lr-reset-poller.sh:872-877`), and stop-failure-marker has `_sf_is_teammate` (`hooks/stop-failure-marker.sh:425-442`). The
  predicate's own docstring says "every recovery path has to ask this" (`lr-predicate.sh:36-39`). The
  new-window launcher is the one recovery path that never asks.

Measured on the incident files (`/bin/bash scripts/limit-recover/lr-predicate.sh is-teammate-head <tx>`):

- 5423f92a gives `{"teammate":true}` (bash 3.2.57, 0.47 s wall at load ~420).
- Its lead 6261c2ab gives `{"teammate":false}`, and its first 8 KB contain 0 `"agentName"` keys.
- The member's head carries `teamName` and `agentName` on `type=attachment` records (lines 5-9) and on a
  `type=user` record (line 10).

## 2. Where: the one door

All automated new-window resumes go through **`scripts/boot-resume-launch.sh`'s "ONE TYPER PER
SESSION" block (`:289-339`)**. That block already asks three ownership questions before a window
opens, and `--check-only` stops right after them (`:339`). Its callers:

- `cc-resume-debt _relaunch`: settle and sweep, which serve lr-upgrade, handoff-fire's watcher, and
  every mover's debt.
- `boot-resume.sh` launch path (`:1296`) and its batch `--check-only` (`:1137`).
- `lr_recon/act.py cmd_replace` (`:246`).
- An operator's `cc-do` of an escalation row (`cc-resume-debt:615`).

`grep` finds no other in-repo caller. The new check is ownership question 4. It returns its own
code, exit 7 ("never ours"), so that callers can tell it from exit 5 ("not ours now").

The engine `bin/reso-resume-one` repeats the same block (fence plus H(sid), `:636-678`, sourcing the
same `lr-lib.sh` at `:647`). It gets the same one-call question as a belt for direct callers
(`cc-resume-layout.sh` via `cc-restore`, and hand runs).

## 3. Changes

### 3.1 `scripts/limit-recover/lr-lib.sh`: one finder, no new predicate

The file is "the ONE home for the limit-recover predicates that more than one caller needs"
(`:2`). Add the function after `lr_holder_count` (`:625`):

```bash
# ── TEAM MEMBER: never resumed by a team-blind launcher (2026-10-16) ──────────────────────────────
# An Agent Teams member is its LEAD's to end and to re-spawn; a resume that cannot carry its
# --agent-id/--team-name identity brings it back outside its team (lr-upgrade.sh:383-385), which is
# what cc-resume-debt -> boot-resume-launch -> reso-resume-one did to 5423f92a 40 s after its lead
# retired it. The TEST is lr-predicate's is-teammate-head (lr_predicate.py:411, the one copy); this
# only finds the transcript the launcher would load and keeps "could not ask" apart from "no".
# rc 0 member (deciding transcript on stdout) · 1 not a member, or no transcript · 2 UNDECIDED
# (a copy unreadable, or it carries the key and the predicate could not run).
lr_team_member() { # $1=sid [$2=cfg: the store the resume loads; empty = every store] [$3=cwd]
  local sid="${1:-}" cfg="${2:-}" cwd="${3:-}" stores c f hd out list rc=1
  [ -n "$sid" ] || return 1
  if [ -n "$cfg" ]; then stores="$cfg"; else stores="$(lr_config_dirs)"; fi
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    # The exact project dir CC derives from the cwd (hooks/lib/peer-owned.sh:958 spelling) first;
    # the store-wide glob only when it is absent (measured 0.9 s per store at load ~420).
    list=""
    [ -n "$cwd" ] && f="$c/projects/$(printf '%s' "$cwd" | LC_ALL=C sed 's/[^a-zA-Z0-9]/-/g')/$sid.jsonl" \
      && [ -f "$f" ] && list="$f"
    if [ -z "$list" ]; then
      for f in "$c"/projects/*/"$sid".jsonl; do [ -f "$f" ] && list="$list$f"$'\n'; done
    fi
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      [ -r "$f" ] || { rc=2; continue; }
      hd="$(head -c "${LR_HEAD_BYTES:-8192}" "$f" 2>/dev/null)"   # no pipe: pipefail cannot misread it
      case "$hd" in *'"agentName"'*) ;; *) continue ;; esac     # no key, no member: no python fork
      out="$(/bin/bash "$LR_LIB_DIR/lr-predicate.sh" is-teammate-head "$f" 2>/dev/null)" || out=""
      case "$out" in
        *'"teammate":true'*) printf '%s' "$f"; return 0 ;;
        *'"teammate":false'*) ;;
        *) rc=2 ;;
      esac
    done <<EOF2
$list
EOF2
  done <<EOF
$stores
EOF
  return "$rc"
}
```

Notes on the design:

- The key pre-filter is not a second predicate. It can only answer "no". The parsed predicate is the
  only thing that answers "yes". The same pre-filter is the first line of `is_teammate_head`
  (`lr_predicate.py:447`).
- The code is safe for bash 3.2: no `mapfile`, no namerefs, and no `case`+`continue` inside `$( )`.

### 3.2 `scripts/boot-resume-launch.sh`: ownership question 4

- Move `brl_cfg_for` (`:412-419`, a pure function) above the ownership block, unchanged.
- After the H(sid) `case` (`:328-332`) and **before** `[ "$CHECKONLY" = 1 ] && exit 0` (`:339`), add:

```bash
#   4. NOT A TEAMMATE (2026-10-16). A member is its lead's to end and to re-spawn, and this launcher
#      carries no team identity, so a resume here is an orphan by construction (5423f92a came back
#      in a NEW window as pid 57630, no --agent-id, 40 s after its lead retired it). Exit 7 = never
#      ours (5 = not ours now), so cc-resume-debt abandons rather than escalates. Undecided is held
#      like an unknown H(sid). Kill switch CC_RESUME_TEAMMATE_GUARD=off.
if [ "${CC_RESUME_TEAMMATE_GUARD:-on}" != off ]; then
  if command -v lr_team_member >/dev/null 2>&1; then
    _brl_tm="$(lr_team_member "$sid" "$(brl_cfg_for "$acct")" "$cwd")"; _brl_tmrc=$?
    case "$_brl_tmrc" in
      0) echo "boot-resume-launch: teammate: $sid is an Agent Teams member ($_brl_tm) - its lead owns it and this launcher cannot carry its team identity, not launching" >&2; exit 7 ;;
      2) echo "boot-resume-launch: teammate test for $sid undecided (transcript unreadable or lr-predicate unavailable) - treated as held, not launching" >&2; exit 5 ;;
    esac
  else
    echo "boot-resume-launch: lr_team_member unavailable (lr-lib.sh predates it) - teammate guard OFF for $sid" >&2
  fi
fi
```

- Header: add `· 7 never ours to launch: an Agent Teams member (its lead owns it)` to the Exit list
  (`:23-29`). Add "4. not a teammate" to the `--check-only` description (`:16-17`) and to the block
  comment (`:290-296`).
- The fence trap (`:320`) releases the launch lock on exit 7, as it already does on exit 5.

### 3.3 `bin/cc-resume-debt _relaunch`: map exit 7 to abandon

Add this right after `lr_recon_act_done` (`:512`) and before the attempts `_set` (`:514`):

```bash
  # rc 7: the launcher's "never ours" - an Agent Teams member (boot-resume-launch ownership question
  # 4). Not a failed attempt: escalating would file a backlog row telling the operator to resume a
  # member its lead owns. Abandoned, with the reason; settle then returns 4, the sweep skips it.
  if [ "$rc" = 7 ]; then
    _note "$1 is an Agent Teams member - its lead owns it; debt abandoned, never relaunched"
    _abandon "$1" "not relaunched: an Agent Teams member - its lead owns it, and a new-window resume cannot carry its team identity (launcher exit 7; $LOGS/$1.log)"
    return 1
  fi
```

- `_abandon` (`:341-349`) already closes custody and sets `abandoned`. `_settle` (`:695`) already maps
  `abandoned` to rc 4, and `_sweep` (`:717`) already skips inactive debts. No new state is needed.
- In the header STATE MACHINE (`:29-36`), add the line `open, launcher exit 7 → abandoned`.

### 3.4 `bin/reso-resume-one`: the engine belt

Inside the fence block, after the holders `case` (`:669-676`), add:

```bash
    if [ "${CC_RESUME_TEAMMATE_GUARD:-on}" != off ] && command -v lr_team_member >/dev/null 2>&1; then
      _rro_tm="$(lr_team_member "$sid" "$cfg" "$wt")"
      case $? in
        0) printf '%s\n' "reso-resume-one: NOT LAUNCHING $sid — an Agent Teams member ($_rro_tm): its lead owns it, and this engine cannot carry its team identity" >&2
           rr_refused_exit 7 ;;
        2) printf '%s\n' "reso-resume-one: teammate test for $sid undecided — launching (fail-open, as the holder check here; boot-resume-launch holds it)" >&2 ;;
      esac
    fi
```

The fail-open on rc 2 matches this file's own rule for unknown holders (`:672`).

### 3.5 Adapters

- **`scripts/boot-resume.sh`**: change `5)` to `5|7)` at `:1140` (check-only) and `:1301` (launch). Extend
  the held message at `:1456` and the counter comment at `:1041` with "or an Agent Teams member its
  lead owns".
- **`scripts/limit-recover/lr-upgrade.sh` `lru_settle` (`:1993-2004`)**: add the arm
  `4) LRU_SETTLE_WHY="not live: not relaunched ($3); cc-resume-debt abandoned the debt - its reason is in $LRU_RD_LOG (launcher exit 7 = an Agent Teams member its lead owns)" ;;`
- **`lru_settle_verdict` (`:2012-2020`)**: add the arm
  `4) LRU_NEXT_CLASS=notlive; lru_result "$1" "$2" skipped "$LRU_SETTLE_WHY" "" "$6" "$7"; return 3 ;;`
  It reuses the existing `notlive` class and the `not-live` terminal (`:2090`, `:2110`). The result is
  never `stranded`, which never expires (`:2140`). Today rc 4 falls into the `*)` arm: `failed` plus
  `stranded`.

### 3.6 Disruption: the census `current` test (`lr-upgrade.sh`)

This is the one door every upgrade drive passes, auto or manual: drive step 1 re-runs the census
(`:2549-2571`). Add:

```bash
# A binary's identity is its FILE, not its spelling (2026-10-16): the vendor starts a pane teammate on
# the lead's RESOLVED binary (.../bin/claude.exe; q2-teammate-relaunch.md:73) while cc-claude-bin names
# the launcher symlink (.../node_modules/.bin/claude). As strings, every vendor-spawned member read
# upgrade-teammate on the binary it already ran (12 of 12 recorded drives were .claude-293 → .claude-293).
# `-ef` = same device+inode, symlinks followed, no fork, bash 3.2; a missing path falls back to the string.
lru_same_bin() { [ "$1" = "$2" ] || [ "$1" -ef "$2" ]; }
```

Call sites:

- `:686`: `elif lru_same_bin "$bin" "$target_bin" && [ "$model" = "$tgt" ]; then disp=current`
- `:448`: `if ! lru_same_bin "$b" "$4" || [ -z "$t" ] || [ "$m" != "$t" ]; then`
- `:1965`: `lru_same_bin "${a%% *}" "$2" || continue`

Measured with `/bin/bash /tmp/ef-test.sh`:

- `[ .claude-293/node_modules/.bin/claude -ef .claude-293/.../bin/claude.exe ]` is true, while the
  string compare differs.
- A different version's `claude.exe` (.claude-219) reads different.
- `-ef` against a nonexistent path is false.

### 3.7 Optional belt: the identity-carrying in-pane relaunch

`lru_relaunch_gated` (`:2228`) types the member's own launcher, with its identity, through
`--relaunch-at-shell`. If a retired member's pane survived at a shell (the lead's close refused, for
example by the fullscreen guard), that path would re-spawn the member with its team identity into a
team that no longer lists it. Add this after the attempts and identity checks (`~:2240`):

```bash
  if [ -z "$LRU_RELAUNCH_WHY" ] && [ "$role" = teammate ]; then
    v="$(lru_teammate_block "$targs" "$cfg")"     # the census's own gate, re-asked at type time
    [ -n "$v" ] && LRU_RELAUNCH_WHY="not live: teammate retired by its lead ($v) - nothing typed"
  fi
```

The caller then settles, and the chokepoint refuses and abandons. The result is one decision point
and no new return code.

## 4. The incident under this design

| t (CDT) | Today | With this design |
|---|---|---|
| 18:24:05 | the census reads `upgrade-teammate` (string compare) | the census reads `current` (3.6). **Never claimed: no /exit, no relaunch, no race** |
| 18:26:20 | if driven anyway: settle opens debt #2, then `_relaunch`, then the launcher | the launcher's Q4 sees `{"teammate":true}` and exits 7. `_abandon`, settle rc 4 |
| 18:26:23 | NEW kitty OS window, pid 57630 (orphan) | no window |
| 18:26:52 | `upgraded`, "relaunched in a NEW window" | `skipped` "not live: …", terminal `not-live` |

## 5. Tests

All tests are hermetic: stubs, `PATH=<stubs>:/usr/bin:/bin`, run with `/bin/bash`.

1. **NEW `tests/teammate-resurrection-replay.bats`**: the real chain (real `bin/cc-resume-debt`, real
   `scripts/boot-resume-launch.sh`, real `lr-lib.sh` and `lr-predicate.sh`; kitty and resume-one are
   stubs).
   - "REPLAY 2026-10-16 5423f92a: lr-upgrade's settle on a retired teammate whose recycle debt was
     PROVEN opens no window — the debt is abandoned (settle rc 4), no backlog row, no mail".
   - Fixture: meta for debt #1 `state:"proven"`, events "opened by handoff-fire" then "recycle engaged
     in pane 217".
   - Fixture transcript at `$HOME/.claude-secondary/projects/<slug(WT)>/5423f92a-…jsonl`, in the
     measured shape: 4 header records, then `attachment` records with
     `"teamName":"session-3cbb68e5","agentName":"web-next16"`, a `user`
     `<teammate-message teammate_id="team-lead">{"type":"shutdown_request","requestId":"shutdown-1792193137331@web-next16",…}`,
     then `deferred_tools_record`, and no assistant record.
   - Stubs: resolve gives `account=next2`, `config_dir=$HOME/.claude-secondary`; find gives DEAD.
   - Assert: status 4; kitty argv file absent; `.state=="abandoned"` with the last note matching
     "Agent Teams member"; `events[0].note` is "opened by settle (no prior debt)", which pins today's
     re-open as known; no backlog or notify log; no pending-launch marker; the debt log holds
     `boot-resume-launch: teammate:`.
   - "REPLAY control: the same chain with the member records stripped from the head relaunches the
     same sid in a NEW window (the gate refused, not the fixture)."
2. `tests/lr-lib.bats`:
   - "lr_team_member: the 5423f92a head shape (teamName+agentName on attachment records) is a member,
     found by the exact cwd slug without the store glob"
   - "lr_team_member: a lead head (agent-name header, no member records) and a plain head are not
     members; no transcript is rc 1"
   - "lr_team_member: a head without the agentName key never runs the predicate (LR_PREDICATE_PY
     fixture module records each import)"
   - "lr_team_member: key present and the predicate unrunnable (LR_PREDICATE_PY absent) is UNDECIDED
     rc 2, never 'not a member'"
3. `tests/lr-recon-fence-callsites.bats` (where the launcher's ownership questions are pinned, `:280-330`):
   - "boot-resume-launch: an Agent Teams member's transcript refuses with exit 7 — no window, launch
     lock released"
   - "boot-resume-launch --check-only exits 7 for a member (boot-resume's batch path inherits it)"
   - "boot-resume-launch: an undecided teammate test is held, exit 5"
   - "boot-resume-launch: CC_RESUME_TEAMMATE_GUARD=off launches a member as before"
4. `tests/cc-resume-debt.bats`:
   - "relaunch rc 7 (an Agent Teams member) abandons the debt: settle rc 4, no backlog row, no mail,
     custody closed". It sits beside "relaunch rc≠0 escalates" (`:134`), which is its control.
   - "sweep: an rc-7 debt is abandoned once and never relaunched again"
5. `tests/reso-resume-one.bats`: "TEAMMATE: a direct invocation on a member transcript exits 7 and
   spawns nothing". It sits beside the FENCE cases (`:871-900`).
6. `tests/boot-resume.bats`: "--check-only rc 7 is counted held, never failed, and the session is not
   launched".
7. `tests/lr-upgrade-settle.bats`:
   - "S3d REFUSED at the shell, cc-resume-debt settle rc 4: skipped 'not live:', terminal not-live,
     never stranded, no 'NEW window' claim". It mirrors S3a/S3b (`:216-250`).
   - (with 3.7) "S3e a teammate whose member row is gone is never typed into at its shell".
8. `tests/lr-upgrade.bats`:
   - "T12 [RED] a vendor-spawned teammate on <target>/@anthropic-ai/claude-code/bin/claude.exe reads
     CURRENT; its lead reads UPGRADE-LEAD, not LEAD-AWAITS-TEAMMATES". The fixture is a real temp tree
     with `.bin/claude -> ../@anthropic-ai/claude-code/bin/claude.exe`, because `-ef` needs real
     files; the `/opt/cc` paths at `:46-51` and `:658` do not exist.
   - "T12 control: a teammate on another version's claude.exe still reads UPGRADE-TEAMMATE".

## 6. Not covered, stated

- **Teammates on an OLD binary are still auto-recycled while idle.** Slot A's F2 is not adopted. The
  outcome of the shutdown race is now bounded (not-live, no orphan).
- **`cc-resume-debt _settle` still re-opens a `proven` debt as "no prior debt"** (`:681`, slot B F2). For
  non-teammates, a stale settle can still resume a session that was closed after it was proven.
- **lr-upgrade still holds `fire` open through `lru_proven`.** An engaged-then-retired member reads
  "not live", not "upgraded, then retired" (slot B F1, slot C fix 4).
- **Slots D (composer junk, reso-resume-one echo) and E (TeammateIdle 5 s timeout) are separate seams.**
- **The live orphan pid 57630 is untouched.** Its transcript head means it will never be auto-resumed
  again.
