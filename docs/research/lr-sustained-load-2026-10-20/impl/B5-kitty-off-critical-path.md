# B5 — take kitty off the pre-commit critical path: implementation design

Date: 2026-10-20, about 17:00-18:10Z. Read-only design work. Code is cited at this worktree's `HEAD`
`28b25a119`. `main` is at `6fdf87eca`, and none of the seven commits between them touch a file named
here (`git diff --stat 28b25a119 6fdf87eca` lists only load-W0 operator files, two bats suites and a
plan doc). Labels: **[M]** measured (the command is named), **[E]** estimated (the method is named),
**[H]** hypothesis.

Nothing was typed, signalled, loaded or edited. The live reads were `ps`, `ioreg`, `lsappinfo`, one
`kitten @ ls` (full) and six `kitten @ ls --match`, all read-only RPCs, plus file reads under
`~/.claude/logs`, `~/.claude/cc-registry`, `~/.reso/limit-recover` and the Claude Code 2.1.293 binary.
The scripts are in `/tmp/b5-*.py|sh`.

---

## 0. Verdict

**BUILD a narrowed B5, in three parts. One sub-lever is dropped and one is gated on an operator OK.**

1. **Kernel pane identity.** Prove "pane P holds session S on tty T" from the registry row plus
   `ps` (pid, lstart, process env and ancestry), not from kitty's resolver. Fall back to today's kitty
   path on any doubt.
   - Measured on the live fleet: the kernel answer equals kitty's own window table in **30 of 30**
     live panes (§2, M4).
2. **The watcher's pane probe becomes advisory for a staged, signal-exiting move.** Its verdict is
   consumed after the stage, never before. The probe also asks kitty for one window
   (`ls --match id:N`) instead of listing all of them.
3. **Draft-safety guard K1 for an unanswered composer read.** A cached, affirmatively empty read of
   the same window and the same claude is enough when three things all hold since that read:
   - no keyboard or mouse input (kernel `HIDIdleTime`);
   - no keystroke of ours into the pane (the pane-keys ledger);
   - no screen-sharing session.
   K1 ships in **shadow**. Turning it on needs the operator's OK, backed by the shadow's paired data.

**Dropped: "tty write for the relaunch."**
- XNU refuses `TIOCSTI` to a caller for which the tty is not the controlling terminal
  (07 §6, F7: `bsd/kern/tty.c`).
- kitty's tty-borne remote control is disabled: `kitty.conf:136` sets
  `allow_remote_control socket-only`.
- The staged successor is already the kitty-free relaunch: 47 of 47 stages since 2026-10-18 were
  claimed [M7].

**Already done, not redone:**
- the SIGTERM exit (`hf_exit_signal`, `handoff-fire.sh:4061-4091`);
- the staged successor for resume and transplant recycles (`hf_succ_stage`, `:4787-4836`).

B5 only makes sure a kitty outage cannot stop a move from reaching them.

**Why only 60%.** Since wave 1 the rail runs at priority 31. There, kitty calls take 0.05-0.08 s
(`kitten`) and 0.4-1.25 s (`it2 session list`) (axis 07 F1). Gap 4 counted 0 kitty failures in 22
recycles fired from priority 31 at 30/core or more. So against **load**, B5 is now insurance. Its
remaining value is against **kitty-side outages**, which load does not cause and A1 cannot fix:
- the 10-01 screen lock with kitty at PRI 4, 9 of 9 calls failing (`recycle-unreachable-2026-10-01.md:11-13`);
- the stock 0.48.2 talk-thread death ("~10 h outage", `handoff-fire.sh:1502`, `:1504-1510`, `:1561`);
- the 2026-09-20 `i/o timeout` episode (`handoff-fire.sh:2841-2848`).

During such an outage every move today holds and retries every ≤300 s until kitty answers, for hours.
With B5 it proceeds, but only while K1 can prove there is no draft. In the screen-lock case K1 often
cannot (§5.5 residual R2), so B8 stays the fix for that class.

---

## 1. The open question: does Claude Code keep an unsent draft across SIGTERM?

**Answer: no, for an interactive pane session.** This rests on a binary scan [M] and the runtime
behaviour that follows from it [H, strong]. The design assumes the draft is **lost**: not merged, and
not restored by `--resume`.

Evidence, from the 2.1.293 binary (`~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe`,
`package.json` `"version": "2.1.293"`), read with `python3 -I /tmp/b5-binctx.py <bin> …`:

- **The only on-disk prompt-draft stores belong to background-job sessions.**
  - `restorePromptDraft` returns at once without `CLAUDE_JOB_DIR`:
    `async restorePromptDraft(){let e=a.CLAUDE_JOB_DIR;if(!e)return;let r=A(e,O),…}`, with
    `var O=".prompt-draft",x=262144` (binary offset 213157598).
  - The writer `G(e,r)` saves `e.getState().value` to `<job dir>/.prompt-draft`, inside the same
    `CLAUDE_JOB_DIR` / `CLAUDE_CODE_SESSION_KIND!=="bg"` module (offset 213161309).
  - The sibling `.prompt-stash` store logs `[bg] prompt stash too large to persist; kept in memory
    only` (offset 74690657).
- **An interactive pane has no `CLAUDE_JOB_DIR`.** `env | grep -c CLAUDE_JOB_DIR` ⇒ `0` in this session [M].
- **The shutdown's `last-prompt` record is the last *submitted* prompt**, with keys
  `lastPrompt, leafUuid, sessionId, type`. In 400 recent transcripts, 14,455 `lastPrompt` values
  matched a submitted user text in the same file. 2,384 did not, and every sampled miss was a
  submitted `!` bash-mode line or an `[Image #N]` chip, which are stored in another shape
  (`python3 -I /tmp/b5-lastprompt2.py`) [M]. So it is not a draft store [H, strong].
- **CC itself treats unsent input as lost across a process handoff.** It refuses to background a
  session with typed text: `"Backgrounding cancelled — you have unsent text in the input. Send it or
  clear it…"` and `"Cannot open agents — … would be lost"` (offsets 206131541, 214575520) [M].
- **SIGTERM runs `shutdown()` without that UI guard**, as the same path as `/exit`
  (`recycle-sigterm-proof-2026-10-11/REPORT.md:7-14`).

**Consequence for the design.** A signal exit cannot *merge* a draft into a message, which was the
typed `/exit`'s failure. It *destroys* the draft instead. So a draft must be proven absent, or carried
(`hf_rcy_carry`, `handoff-fire.sh:5297`), before the signal. That is what today's composer reads
do, and what K1 does when kitty cannot answer.

**Base rate of real drafts on limit-recover moves.** `grep -rh -o 'composer: [a-z-]+…'` over
`recon/actlogs`, `move/` and `results/` [M]:

| verdict | count |
|---|---|
| empty | 127 |
| unreadable | 9 |
| held | 3 |

Of the 3 held:
- 1 was our own `/exit` residue;
- 1 was unreadable;
- 1 was a real operator draft (`/limit-recover to account1 now if we have any remaining`, move
  `20261018T164953Z`). It was carried: `recycle-composer-carried` 2026-10-18T16:50:43Z.

So real drafts occur on about 0.7% of moves, and losing one is not hypothetical.

**Optional confirmation, not blocking (P0, operator ask 1).** A throwaway-tab run on 2.1.293, in the
harness shape of the W6 SIGTERM proof:
1. start `claude --session-id <u> "<reply OK>"` in a scratch kitty tab the build session creates;
2. once it is at rest, `kitten @ send-text --match id:<own tab> 'p0-nonce'` with no Enter;
3. `kill -TERM` the pinned pid;
4. run `claude --resume <u>` in the same tab, and read the box with `get-text`.

Expected result: the box is empty. If the draft does survive, K1 could be relaxed later; nothing in
this design depends on the result.

---

## 2. Measurements taken for this design

| # | What | Reading | Command | |
|---|---|---|---|---|
| M1 | Cost of the kernel substitutes vs one kitty read, from priority 31, load1 243 (24/core) | `ioreg -c IOHIDSystem` 75-140 ms; `lsappinfo front` 37-65 ms; `ps -o … -p 1` 30-47 ms; `ps -axo pid,ppid` 73-75 ms; `kitten @ --to unix:/tmp/kitty-853 ls --match id:1` 54-73 ms (rc 1, "no matching windows") | `bash /tmp/b5-cost.sh` plus a loop over the real socket | M |
| M2 | A second kitty runs at PRI 4 | pid 41475, `/Users/chrisren/kitty-pr3/base/kitty/launcher/kitty --config=NONE …`, PRI 4; the production kitty 853 is at PRI 47 | `ps -o pid,ppid,pri,lstart,etime,command -p 853,41475` | M |
| M3 | `HIDIdleTime` is readable from the rail's own context | 25 reconciler actlogs carry a numeric `hid_idle_s`, 0 `unreadable`; precheck n=139: min 0, p50 513 s, max 35,745 s | `grep -rh -o 'hid_idle_s: …'` over the LR logs | M |
| M4 | **Kernel identity vs kitty's window table** | 30 live registry rows: env `KITTY_WINDOW_ID` = row key, env `KITTY_PID` = row `kitty_pid`, and the ancestor directly under kitty = kitty's own `windows[].pid`: **30/30 agree, 0 disagree**; row `lstart` = live `lstart` 30/30 | `python3 -I /tmp/b5-kid-validate.py` (one full `kitten @ ls`) | M |
| M5 | Registry hygiene | 54 rows: 14 with a dead pid, 10 with no pid (provisional), 30 live | shell loop over `~/.claude/cc-registry/*.json` | M |
| M6 | Zombies under kitty | **157** zombie children of kitty 853 (axis 07 saw 111) | `ps -axo stat=,ppid= \| awk '$2==853 && $1 ~ /Z/' \| wc -l` | M |
| M7 | Recycle outcomes since 2026-10-18 (start of `handoffs.jsonl`) | staged 47, claimed 47, revoked 0; `recycle-exit-signal` 9 (10-20); `recycle-held-unreachable` 2 (03:28Z and 04:23Z, both band 20, both the watcher's pane probe after the transplant) | `python3 -I /tmp/b5-handoffs.py 2026-10-01` and a per-day count | M |
| M8 | The process-env read already in use | `lr_pid_cfg` (`lr-lib.sh:1079-1094`) reads `ps -E -ww`, takes the LAST token and requires an env block; `cc_sid_for_pane` reads `ps eww` (`handoff-fire.sh:8998`) | source read | M |
| M9 | Suites touched by the probe transport | 21 suites set `CC_TERM=kitty`; 33 reference `pane_proof` or `__recycle` | `grep -l` over `tests/*.bats` | M |

---

## 3. The kitty reads left before the commit (remote limit-recover move), and their substitutes

The order a reconciler or move-lane move runs them. "Today" is what an unanswered read does now.

| # | Read (file:line) | Proves | Today, unanswered | B5 |
|---|---|---|---|---|
| P1 | precheck `hf_remote_pane_term` (`:13848`) | which terminal owns P; exports `CC_TERM_KITTY_TO` | `HELD:pane:resolver-unavailable` after ~3×13 s (`:2926-2936`) | kernel identity (§5.2). Skipped when it verifies |
| P2 | precheck `hf_recycle_kitty_probe` (`:13897`) | "later kitty steps will work" | up to 5 tries over a 120 s budget, then `HELD:unreachable` or `HELD:wedged` (`:1566-1597`, `:13898-13901`) | one try, advisory when identity verified (§5.3) |
| P3 | precheck `as_tty` (`:13903`), `kt_window_field pid` (`:13930`) | P's tty and window root | empty, so `REFUSED:pane:unknown` | `HF_KID_TTY`, `HF_KID_ROOT` |
| P4 | precheck focus (`:13959`) | the operator may be typing | `unknown`, read as not focused (`lr-lib.sh:1405-1407`) | unchanged: it already fails open |
| P5 | precheck composer (`:13972-13992`) | no draft | `HELD:composer-unreadable` | K1 (§5.5) |
| R1 | recycle prepass `hf_remote_pane_term` (`:16252`) | as P1 | exit 2, PARKED | kernel identity |
| R2 | `hf_remote_source_pin` → `as_tty_classified` (`:2980`) | the row pid's ancestry reaches P's tty | `RESOLVER-CANNOT-TELL`, exit 2 | `HF_KID_TTY` |
| R3 | recycle `hf_recycle_kitty_probe` (`:16342`) | as P2 | held | advisory (§5.3) |
| R4 | `recycle_fire` `as_tty_classified` (`:19568`) | tty | `recycle-held-unreachable` | `HF_KID_TTY` |
| R5 | `recycle_composer_block` (`:19656`, `:19670`) | no draft | 180 s of retries, then rc 2, refused | K1 on the first unanswered read |
| R6 | focus gate before the lock (`:19921-19936`) | focus | fails open | unchanged |
| R7 | watcher `pane_proof` (`:11616`, `:4422`) | the watcher can type the relaunch | the watcher exits, the foreground holds `recycle-held-unreachable` after the transplant (`:20009-20026`): **2 incident rollbacks, 310-410 s each** | `--only P` transport; advisory with the verdict deferred past the stage (§5.4) |
| R8 | freshness re-read (`:20037-20054`) | a draft typed during arming | rc 2, refused | K1 |
| R9 | last read: focus plus composer (`:3854-3864`) | as above, after the confirm | `HF_LR_REASON=unreachable` hold, then unconfirm | K1 |

Exit, relaunch and verification are already kitty-free when the move is staged and at rest:
`hf_exit_signal` (`:4061`), the pane's consumer's rename (`lib/pane-successor.sh:125-182`), and the
disk engagement oracle.

The watcher's post-commit kitty reads never block:
- `pane_enumerated` every 15 s (`:11948-11959`): only `absent` acts, `unknown` keeps waiting;
- the background-work dialog read (`:11975ff`): no dialog appears on a signal exit.

---

## 4. Design principles (all from the operator premise and the house rules)

1. **Strictly widening.** Every new path needs positive kernel proof. Any doubt ("cannot tell")
   falls back to today's kitty path, byte for byte. No new negative verdict exists; a B5 timeout
   means "fall back or retry".
2. **No new typing.** B5 adds no keystroke anywhere. The only irreversible act it can reach is the
   existing `hf_exit_signal`, under its existing three conditions.
3. **Draft polarity.** A box that cannot be read is never assumed empty. K1 is an affirmative
   cached-empty read plus kernel proof that nothing could have changed it.
4. **One kill switch per part, readable from a file**, because launchd jobs do not see an
   interactive shell's env. `~/.reso/limit-recover/kitty-offpath.mode` (`off|shadow|on`) is
   overridden by env `HF_KITTY_OFFPATH`. Missing file ⇒ code default.

---

## 5. The change

### 5.1 Mode resolution (new, `handoff-fire.sh`, beside `hf_lr_lib_load` at ~`:3632`)

```bash
# off ⇒ every B5 path is skipped (today, byte for byte). shadow ⇒ compute, log, act as today.
# on ⇒ act. Env wins over the file; the file lets an operator flip a launchd-run rail.
hf_kitty_offpath_mode() { # → off|shadow|on
  local m="${HF_KITTY_OFFPATH:-}"
  [ -n "$m" ] || m="$(head -c 16 "${LR_STATE_DIR:-$HOME/.reso/limit-recover}/kitty-offpath.mode" 2>/dev/null | tr -dc 'a-z')"
  case "$m" in off|shadow|on) printf '%s' "$m" ;; *) printf '%s' "${HF_KITTY_OFFPATH_DEFAULT:-on}" ;; esac
}
hf_draft_cache_mode() { # K1 alone: off|shadow|on, default shadow (§9)
  case "${HF_DRAFT_CACHE:-shadow}" in off|on) printf '%s' "$HF_DRAFT_CACHE" ;; *) printf shadow ;; esac
}
```

### 5.2 Kernel pane identity

**New, in `scripts/limit-recover/lr-lib.sh`, beside `lr_pid_cfg` (`:1079`).** One env reader, so the
two env readers cannot drift. `lr_pid_cfg` becomes a two-line caller of it.

```bash
lr_pid_env() { # $1=pid $2=VAR → the LAST "VAR=" token of its env block; rc 1 when no env block is readable
  local pid="${1:-}" var="${2:-}" out
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  if [ -n "${LR_MOVE_ENV_DIR:-}" ]; then out="$(cat "$LR_MOVE_ENV_DIR/$pid" 2>/dev/null)"   # existing fixture seam
  else out="$(ps -E -ww -o command= -p "$pid" 2>/dev/null)"; fi
  [ -n "$out" ] || return 1
  printf '%s\n' "$out" | tr ' ' '\n' | grep -qE '^(HOME|PATH)=' || return 1   # no env block ⇒ unknown
  printf '%s\n' "$out" | tr ' ' '\n' | sed -n "s/^$var=//p" | tail -1
}
```

**LAST token, on purpose.** Since wave 4 the owed prompt rides claude's argv (`a8ebaa7c0`). A prompt
that contains `KITTY_WINDOW_ID=7` sits before the env block, so the last match is the env's. The
cross-checks below catch a spoof anyway.

**New `hf_kernel_pane_identity` in `handoff-fire.sh`**, placed after `hf_remote_source_pin` (`:2995`)
so the definition-order guards hold. It runs at most once per process per pane.

```bash
# KERNEL PANE IDENTITY (B5). "Pane P holds S on tty T" from the registry row + the kernel, no kitty RPC:
#   (1) the row's claude pid is alive, not a zombie, and its lstart equals the row's (TZ=UTC, collapsed)
#   (2) its env (ps -E, LAST token) says KITTY_WINDOW_ID=P and KITTY_PID=K, and K equals the row's kitty_pid
#   (3) walking ppid from that pid reaches K; the process directly under K is the window ROOT R,
#       alive, not a zombie, with a controlling tty T (not ??)
#   (4) K is alive, not a zombie, and its comm's basename is kitty
#   (5) optional: HF_PANE_IDENTITY_FILE (the reconciler's census identity) agrees on every field it names
# rc 0 verified (exports CC_TERM=kitty and CC_TERM_KITTY_TO unless CC_TERM was set; sets HF_KID_*)
# rc 1 refuted (a field disagrees: a fact about the CACHED identity, not the pane ⇒ the caller falls back)
# rc 2 cannot tell (ps/env unreadable, no kitty ancestor, iTerm2 pane) ⇒ the caller falls back
hf_kernel_pane_identity() { # $1=pane $2=row pid $3=row lstart (may be empty) $4=row kitty_pid (may be empty)
  local pane="${1##*:}" pid="${2:-}" rls="${3:-}" rkp="${4:-}" wid kpid p pp n=0 root="" st tty kcomm ls
  HF_KID_OK=0 HF_KID_WHY=""
  [ "$(hf_kitty_offpath_mode)" != off ] || { HF_KID_WHY=off; return 2; }
  case "$pane" in ''|*[!0-9]*) HF_KID_WHY="pane id is not a kitty window id"; return 2 ;; esac
  case "$pid" in ''|*[!0-9]*) HF_KID_WHY="no row pid"; return 2 ;; esac
  st="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ')"
  case "$st" in '') HF_KID_WHY="row pid $pid gone"; return 2 ;; Z*) HF_KID_WHY="row pid $pid is a zombie"; return 1 ;; esac
  ls="$(_hf_lstart "$pid")"
  if [ -n "$rls" ] && [ "$(printf '%s' "$rls" | tr -s ' ')" != "$ls" ]; then HF_KID_WHY="row lstart ≠ live ($ls)"; return 1; fi
  wid="$(lr_pid_env "$pid" KITTY_WINDOW_ID)" || { HF_KID_WHY="env unreadable"; return 2; }
  kpid="$(lr_pid_env "$pid" KITTY_PID)" || { HF_KID_WHY="env unreadable"; return 2; }
  [ "$wid" = "$pane" ] || { HF_KID_WHY="env KITTY_WINDOW_ID=${wid:-none} ≠ pane $pane"; return 1; }
  case "$kpid" in ''|*[!0-9]*) HF_KID_WHY="no KITTY_PID in env"; return 2 ;; esac
  [ -z "$rkp" ] || [ "$rkp" = "$kpid" ] || { HF_KID_WHY="env KITTY_PID $kpid ≠ row kitty_pid $rkp"; return 1; }
  p="$pid"
  while [ "$n" -lt 40 ]; do
    pp="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
    case "$pp" in ''|*[!0-9]*|0|1) HF_KID_WHY="no kitty ancestor"; return 2 ;; esac
    [ "$pp" = "$kpid" ] && { root="$p"; break; }
    p="$pp"; n=$((n + 1))
  done
  [ -n "$root" ] || { HF_KID_WHY="ancestry walk exhausted"; return 2; }
  case "$(ps -o stat= -p "$root" 2>/dev/null | tr -d ' ')" in ''|Z*) HF_KID_WHY="window root $root gone or zombie"; return 1 ;; esac
  tty="$(ps -o tty= -p "$root" 2>/dev/null | tr -d ' ')"
  case "$tty" in ''|'??') HF_KID_WHY="window root $root has no tty"; return 2 ;; esac
  case "$(ps -o stat= -p "$kpid" 2>/dev/null | tr -d ' ')" in ''|Z*) HF_KID_WHY="kitty $kpid gone"; return 2 ;; esac
  kcomm="$(ps -o comm= -p "$kpid" 2>/dev/null)"; [ "${kcomm##*/}" = kitty ] || { HF_KID_WHY="pid $kpid is not kitty"; return 1; }
  HF_KID_PANE="$pane" HF_KID_PID="$pid" HF_KID_PID_LS="$ls" HF_KID_KPID="$kpid" HF_KID_KLS="$(_hf_lstart "$kpid")"
  HF_KID_ROOT="$root" HF_KID_ROOT_LS="$(_hf_lstart "$root")" HF_KID_TTY="/dev/${tty#/dev/}"
  HF_KID_SOCK="$(lr_pid_env "$pid" KITTY_LISTEN_ON 2>/dev/null)"; HF_KID_SOCK="${HF_KID_SOCK:-unix:/tmp/kitty-$kpid}"
  if ! hf_kid_file_agrees; then return 1; fi          # (5), reads HF_PANE_IDENTITY_FILE when set
  HF_KID_OK=1
  if [ -z "${CC_TERM:-}" ]; then export CC_TERM=kitty; CC_TERM_KITTY_TO="${CC_TERM_KITTY_TO:-$HF_KID_SOCK}"; export CC_TERM_KITTY_TO; fi
  return 0
}
```

Notes on the identity check:
- **The zombie exclusion is the skeptic's hole (a)** (axis 07 L2): kitty holds 157 zombies [M6], and
  `_hf_lstart` returns an lstart for a zombie.
- **A root that is not `login` is fine** (hole b): the identity is (pid, lstart), not the command name.
- **Each `ps` stays a plain call, as in the existing pins** (`:2988-2992`, `:4028-4037`). At priority
  31 each costs 30-75 ms at 24/core [M1]. A hung `ps` is the "SIGKILLed ps back after 1,226 s" class
  (REPORT §3.3). So the whole function runs inside one `hf_bounded_s 20 …` subshell wrapper at the
  call sites, and rc 124/137 ⇒ rc 2 (fall back).

**Call sites (diff sketch).**

- **Remote prepass, `:16251-16257`.** It runs today before the bind, so the bind moves up for the
  remote form only. The bind is file-only, so the order is free.
  ```bash
  if [ -n "$RCY_SOURCE_PANE" ]; then
    RCY_TERM_RC=0
    if [ -n "$RCY_SOURCE_SESSION" ] && hf_remote_source_bind "$RCY_SOURCE_PANE" "$RCY_SOURCE_SESSION" --recycle 2>/dev/null \
       && hf_kid_bounded "$RCY_SOURCE_PANE" "$HF_REMOTE_ROW_PID" "$(hf_row_field "$RCY_SOURCE_PANE" lstart)" "$(hf_row_field "$RCY_SOURCE_PANE" kitty_pid)"; then
      emit_recycle_event recycle-kid-resolved "" "$RCY_SOURCE_PANE" "kernel identity: kitty $HF_KID_KPID window $RCY_SOURCE_PANE root $HF_KID_ROOT on ${HF_KID_TTY#/dev/}; no terminal round-trip" || true
    else
      hf_remote_pane_term "$RCY_SOURCE_PANE" || RCY_TERM_RC=$?      # today's path, unchanged
    fi
    …existing rc handling…
  fi
  ```
  In **shadow** mode the kernel result is computed and logged as `recycle-kid-shadow`, with the
  kitty-resolved tty beside it once `hf_remote_pane_term` and the pin have run. Nothing is skipped.
  The bind at `:16294` still runs and prints its refusal text; the early call is silent and only
  feeds the identity.
- **`hf_remote_source_pin` `:2980`:**
  `if [ "${HF_KID_OK:-0}" = 1 ] && [ "$HF_KID_PANE" = "${pane##*:}" ] && [ "$(hf_kitty_offpath_mode)" = on ]; then ptty="$HF_KID_TTY"; else ptty="$(as_tty_classified "$pane")" || prc=$?; fi`.
  The pid → tty ancestry walk (`:2987-2992`) is unchanged and stays the pin.
- **`recycle_fire` `:19568`:** before `as_tty_classified`, for `RCY_REMOTE=1` with a verified,
  matching identity in mode `on`: `tty="$HF_KID_TTY"`.
- **Precheck.** After the bind (`:13659`): `hf_kid_bounded "$PRP_PANE" "$HF_REMOTE_ROW_PID" …`.
  - When it verifies in mode `on`: skip `hf_remote_pane_term` (`:13848`), set
    `PRP_TTY="$HF_KID_TTY"` instead of `as_tty` (`:13903`), and set `PRP_ROOT="$HF_KID_ROOT"` instead
    of `kt_window_field … pid` (`:13930`).
  - Print the new informational lines `pane_root_lstart: …` and `identity: kernel (…)`.

**Reconciler hint (optional field 5).** In `act.actuator_env` (`act.py:50-98`), when
`rec.identity.root_pid and rec.identity.root_lstart`, write `work/<sid>.identity.json` exactly as
`_command` already does for B (`__main__.py:1366-1368`, `T.to_dict(rec.identity)`). Set
`HF_PANE_IDENTITY_FILE` to it, and set `CC_TERM_KITTY_TO` from `"unix:/tmp/kitty-%d" % kitty_pid`
when `pane` is None. The latter is today's gap: a degraded kitty read passes no socket
(`__main__.py:1301-1309`). `hf_kid_file_agrees` compares
`window_id, kitty_pid, kitty_lstart, root_pid, root_lstart, tty`, each only when set.

### 5.3 The up-front kitty probe becomes advisory once identity is verified

At `:16342-16363` (recycle) and `:13897-13901` (precheck), when mode is `on` and `HF_KID_OK=1` for
this pane:
- `HF_KPROBE_TRIES=1`: one shot, not the 5-try, 120 s budget (`:1566-1597`);
- rc 1 or 2 ⇒ `emit_recycle_event recycle-kitty-probe-advisory …`, `HF_KITTY_RPC_DOUBT=1`, and
  continue;
- rc 2 (STUCK) still files its needs-human backlog item (`:16349-16350`). Only the hold goes.

When the identity did not verify, today's holds stand unchanged.

**Early stop, so a deaf kitty with no K1 proof still holds before the transplant.** In the precheck,
after an advisory probe failure, run K1 at once (§5.5). If K1 cannot prove the box empty, print
today's line and verdict (`HELD:unreachable`, `:13901`). The cost is today's (~16 s, one try), and it
avoids a transplant that would only roll back.

### 5.4 The watcher's pane probe: cheaper, advisory, and decided after the stage

**(a) Transport: one window, not 32.** In `bin/it2-kitty`'s `session list` verb, add
`--only <id>` ⇒ `kt ls --match id:<id>`. kitty's own rc 1 with "No matching windows" prints `[]`
with rc 0, a definite "enumerated, absent". The bound firing stays rc 124.

`pane_proof` (`:4422`) passes `--only "$pane"` **only** when `kitty_identity` is true and
`HF_PANE_PROOF_ONLY` is not `off`. The iTerm2 `it2` never sees the flag. The parse is unchanged:
- ids out of the JSON;
- an empty list with rc 0 ⇒ the existing `pane-UNREACHABLE` line;
- rc ≠ 0 ⇒ the existing `pane-NO-ANSWER` line.

Payload 650 KB → 49 KB, and 6-10× faster at priority 31 (axis 07 L5 CONFIRMED). `pane_enumerated`
(`:4483`) is unchanged: it needs other panes in the listing to say `absent`.

**(b) Advisory in the watcher (`:11616`).**

```bash
rcy_pp=0; pane_proof "$IT2" "$RSID" __recycle || rcy_pp=$?
if [ "$rcy_pp" != 0 ]; then
  if [ "$rcy_pp" = 2 ] && [ "${HF_PANE_PROOF_ADVISORY:-0}" = 1 ]; then
    echo "→ pane-probe ADVISORY: the terminal did not answer, and this recycle stages its successor and exits by signal — the foreground decides after the stage; nothing is typed by this watcher unless the stage is not claimed"
  else
    exit 1
  fi
fi
```

`HF_PANE_PROOF_ADVISORY=1` is exported by the foreground right before `detach` (`:19977`; `detach`
passes the env through) only when all of these hold:
- mode `on`, and `RCY_REMOTE=1`;
- `hf_succ_mode` ∈ {resume, transplant} (`:4778-4783`);
- `CC_PANE_SUCCESSOR` is not `off`, and `hf_succ_lib_load` succeeds;
- `HF_EXIT_ACTUATOR` is not `typed`.

**(c) The foreground defers the verdict instead of moving the stage.** Moving `hf_succ_stage` above
the probe, as the skeptic's L3 wording suggests, would widen the window in which a claude exiting on
its own launches the successor before the confirm re-copied the transcript. That is the subject-gone
race (`:4093-4104`), and the stage's documented place is "immediately before the irreversible tail"
(`:20127-20130`). So:

```bash
# :20009
RCY_PP=0; await_pane_proof "$log" || RCY_PP=$?
RCY_PP_DEFERRED=""
if { [ "$RCY_PP" = 3 ] || [ "$RCY_PP" = 2 ]; } && [ "${HF_PANE_PROOF_ADVISORY:-0}" = 1 ]; then
  RCY_PP_DEFERRED="$RCY_PP"; RCY_PP=0
  emit_recycle_event recycle-pane-probe-deferred "" "$SID" "pane probe rc $RCY_PP_DEFERRED (no answer / stalled); decided after the stage: the move proceeds only staged, pinned and signal-exiting" || true
fi
if [ "$RCY_PP" != 0 ]; then …unchanged holds… fi

# :20131
rcy_staged=0; hf_succ_stage "$tty" "$cmdfile" && rcy_staged=1
if [ -n "$RCY_PP_DEFERRED" ]; then
  rcy_why=""
  [ "$rcy_staged" = 1 ] || rcy_why="the successor could not be staged"
  [ "${HF_EXIT_ACTUATOR:-signal}" != typed ] || rcy_why="HF_EXIT_ACTUATOR=typed"
  [ -n "$rcy_why" ] || hf_exit_signal_pin "$tty" "${RCY_SOURCE_SESSION:-$rcy_old_sid}" || rcy_why="no single claude to signal ($HF_EXIT_SIG_WHY)"
  if [ -n "$rcy_why" ]; then
    hf_recycle_disarm                      # the watcher's EXIT trap revokes any stage (:11387)
    emit_recycle_event recycle-held-unreachable "" "$SID" "the watcher's pane probe got NO ANSWER and the relaunch could not avoid the terminal: $rcy_why" || true
    hf_recycle_owed_record "$SID" "the watcher's pane probe got no answer"
    echo "!! recycle ABORTED: the terminal did not answer the watcher's pane probe for $SID … /exit NOT typed, session stays alive. …" >&2   # :20019's text, verbatim
    exit 1
  fi
fi
```

This hold sits **before** `recycle_fire_commit`, so before the confirm: the same cost as today's
pane-probe hold.

In `recycle_fire_commit`, the `*)` arm of the exit-actuator `case` (`:19453`) gains one line, before
the typed `/exit`:
`[ -z "${RCY_PP_DEFERRED:-}" ] || hf_recycle_hold unreachable "pane probe unanswered and the signal exit declined ($HF_EXIT_SIG_WHY)" "the terminal did not answer and the exit would have to be typed"`.
This hold comes after the confirm, so it unconfirms; the text form is the one
`settle._RCY_HELD` (`settle.py:84-87`) and `classify._TERMINAL_TRANSIENT` (`classify.py:33-35`)
already read as TRANSIENT. It is reached only if the claude, the stage or the pin changed between the
stage point and the signal.

### 5.5 Draft-safety guard K1: a cached empty read plus kernel proof that nothing changed it

**The cache.** One file per window incarnation, written atomically (tmp + `mv`):
`${LR_STATE_DIR:-~/.reso/limit-recover}/composer-cache/<kitty_pid>.<window_id>.json`, dir mode 0700.

```json
{"v":1,"kitty_pid":853,"kitty_lstart":"Sun Oct 18 19:40:35 2026","window_id":41,"tty":"ttys051",
 "root_pid":61659,"root_lstart":"…","claude_pid":5276,"claude_lstart":"…",
 "state":"empty","read_started_at":1792512345.12,"read_ended_at":1792512345.31,"reader":"recon"}
```

- `state` ∈ {`empty`, `occupied`}. The text is **never stored**; it is an operator's.
- lstarts are whitespace-collapsed, TZ=UTC (registry rule, `hooks/session-register.sh:349`; repo
  lesson "an unpinned (pid,lstart) check convicts EVERY row on a DST flip").

**Writers.**
- **(W1) The reconciler.** `_read_composer` (`__main__.py:693-722`) gains `paths` (in scope at the call
  site `:324`). Around each `observe.composer_state(…)`:
  - stamp `t0 = time.time()` — wall clock at the read, **not** the pass `now`, which is B7's class;
    an early stamp is only more conservative, but it loses proofs;
  - after the read, when the result is `empty` or `draft`, write the file with `state` `empty` or
    `occupied`, `reader:"recon"`. The key comes from `PaneObs` (`kitty_pid, kitty_lstart, window_id,
    tty, root_pid, root_lstart`, `types.py:507-516`), and `claude_pid/lstart` from `s.pid/s.lstart`;
  - `unknown` writes nothing.
  This read already happens every pass for limited sessions in `DRAFT_READ_SUBSTATES`
  (`__main__.py:663-690`), so the cache is fresh at no new kitty cost.
- **(W2) handoff-fire.** `composer_content` (`:5037`) writes the file after a parse that succeeds
  (rc 0), `reader:"hf"`, when `HF_KID_OK=1` and `HF_KID_PANE` matches this pane. A write inside
  `$(…)` is a file write, so the subshell does not matter. Static or turn shapes (rc 1/3 with a screen
  read) write nothing.

**Invalidation: our own keystrokes.** The carry's put-back types an operator's text back into a box
with no HID event (`hf_rcy_carry`, cc-tui). Every send-text of ours must therefore be visible to K1:
- `bin/it2-kitty` already appends `{ts, pane, …}` to `~/.claude/logs/pane-keys.jsonl` for every
  send-text (`bin/it2-kitty:225-273`; 508 rows now);
- `scripts/lib/cc-tui.sh` `cc_tui_rpc` (`:108-117`) does not. Add the same row when `$1` is
  `send-text`. That covers lr-upgrade's Ctrl-C/Ctrl-Z/^U (`lr-upgrade.sh:1479,1753,1825,2356`) and the
  carry's put-back.

**The reader: `hf_draft_cache_proves_empty <pane>`** → rc 0 proven (sets `HF_DRAFT_PROOF`), rc 1 not
(sets `HF_DRAFT_NOPROOF_WHY`). Every clause must hold:

1. `HF_KID_OK=1` for this pane, so the identity is verified kernel-side in this process.
2. The cache file parses, and `kitty_pid, kitty_lstart, window_id, root_pid, root_lstart,
   claude_pid, claude_lstart` all equal the live `HF_KID_*` values. That makes it the same window
   **and the same claude**: a relaunched claude's box is a different box.
3. `state == "empty"`.
4. `read_started_at ≤ now` and `now − read_started_at ≤ HF_DRAFT_CACHE_MAX_AGE_S` (default 43200,
   which covers a night).
5. `HIDIdleTime` is read fresh (`lr_hid_idle_s`, `lr-lib.sh:1427-1432`, seam `LR_HID_IDLE_S`), is
   numeric, and `(now − hid) + HF_DRAFT_CACHE_RENDER_S ≤ read_started_at`, with a default render
   allowance of 30 s. The last keyboard or mouse event came at least 30 s **before** the read began,
   so its echo had time to render into the screen that was read.
6. No `pane-keys.jsonl` row for this pane has `ts ≥ read_started_at − HF_DRAFT_CACHE_RENDER_S`. The
   check is a bounded `tail -c 262144` plus `jq`.
7. No screen-sharing session: `pgrep -x screensharingd` finds nothing [M: absent now]. Remote
   keystrokes may not move `HIDIdleTime` [H].

**Where K1 is consulted** (mode `on`, or logged only in mode `shadow`): only when kitty did **not
answer** the read. A screen that answered but parsed as a dialog or turn shape keeps today's
verdict; the screen saying something is happening outranks the cache.
- `composer_content` writes `noanswer` into `$HF_COMPOSER_NOANSWER_FILE` when its `--ansi` read
  returned rc 124/137 or nothing. On a 124/137 it **skips the plain re-read**, which would only time
  out a second time (`:5046-5047`). Its rc stays 1, so `tests/handoff-composer-gate.bats` "unreadable
  pane (empty read) is UNKNOWN (rc 1)" keeps passing unchanged. This is the house side-file pattern
  of `HF_COMPOSER_SHAPE_FILE`.
- `recycle_composer_gate` (`:5239-5263`): on a non-zero read whose `noanswer` file is set, mode `on`
  and K1 proven ⇒ `return 0` at once. This covers R5, R8 and R9 and the focus gate's reader, all of
  which call it. Otherwise the loop runs as today.
- Precheck step 5 (`:13972-13992`): on `noanswer` and K1 proven ⇒ print
  `composer: empty (by cache: read <iso>, no keyboard or mouse input for <hid>s, no keys of ours since)`
  instead of `composer: unreadable`, and do not hold.
- **Shadow pairing.** Whenever a fresh read **succeeds** in the precheck or the recycle, K1 is first
  evaluated against the existing file, **before** W2 overwrites it, and one row is emitted:
  `recycle-composer-cache-shadow` with `fresh=<empty|occupied> k1=<proves|no:<why>> age=<s> hid=<s>`.
  The words avoid the bare token `draft`, because `settle._HOLD_SUB` maps `\bdraft\b` to HOLD-DRAFT
  (`settle.py:89-90`). These rows are K1's falsifier (§8, T12).

**What K1 cannot see. These are the residual risks, all [H]:**
- **R1. Human input that does not move `HIDIdleTime`.** Universal Control, some accessibility or
  automation tools, or a `kitten @ send-text` by a tool outside our two transports
  (`scripts/kitty-drag-w4.sh`, `scripts/cloud-websetup-drive.sh`, research-kit; none on the recovery
  path).
- **R2. A screen lock right after the operator's last input**, with kitty at PRI 4 from then on (the
  10-01 class). No read after the lock can succeed, so clause 5 fails for every pane whose last read
  predates the lock, and the move holds, as today. B8 (`NSAppSleepDisabled`) is the fix for that
  class. An auto-lock after idle does satisfy clause 5 when a read landed between the operator going
  idle and the lock [E].
- **R3. A box changed by a terminal reply leaking into input.** A late answer to a terminal query, for
  example. It is never a human draft, so losing it costs nothing.

### 5.6 "SIGTERM where safe": what changes and what does not

- **Unchanged conditions** (`hf_exit_signal`, `:3997-4007`): at rest, proven by the last read; our
  successor staged; exactly one pinned claude whose lstart is re-read before the signal. Kill switch
  `HF_EXIT_ACTUATOR=typed`.
- **New: a move whose pane probe went unanswered may only exit by signal** (§5.4c). So "kitty is
  deaf" can never reach the typed `/exit` (`:19463-19483`) nor its read-back.
- **The self form is unchanged.** An in-turn self-recycle is mid-turn by construction, so a signal
  would kill its own turn. The deferred self-recycle already reaches the signal (`:20080-20109`).
  Moving a session from its own death hook is G2's item. G2 should reuse `hf_kernel_pane_identity`
  for its `HF_SELF_CLAUDE_PID/LSTART/TTY` hints (gap-2 §7 Stage 1, step 6).
- **The typed fallback is unchanged.** A stage nobody claims within `CC_RECYCLE_CLAIM_GRACE_S` (20 s)
  at a bare shell is revoked and the relaunch is typed (`:12474-12490`), with a 600 s deadline
  (`:12589`). Under a deaf kitty that ends `recycle-dead` with a recovery packet and an open resume
  debt. The session is transplanted and resumable, and no data is lost. Measured frequency of an
  unclaimed stage: 0 of 47 [M7].

### 5.7 Optional refinement: a per-process deaf latch (separable, about 25 LOC)

After a kitty read in this process returns rc 124/137, set `HF_KITTY_DEAF_UNTIL=$((now+60))`; it is
not exported. Until then, `composer_content` skips the RPC, marks `noanswer`, and goes straight to K1.
Focus reads are already fail-open, so they skip too.

When kitty is fully deaf, this cuts the per-move bound waiting from about 2 min to about 45 s [E: 13 s
per bounded call × the calls of §3]. It never changes a verdict: K1 or today's hold still decides.

---

## 6. Data and format changes

| What | Where | Readers |
|---|---|---|
| `composer-cache/<kitty_pid>.<window_id>.json` v1 (§5.5) | `$LR_STATE_DIR/composer-cache/` | `hf_draft_cache_proves_empty` only |
| `kitty-offpath.mode` (`off\|shadow\|on`) | `$LR_STATE_DIR/` | `hf_kitty_offpath_mode` |
| `work/<sid>.identity.json` for A/R moves (same shape as B's) | `recon/work/` | `hf_kid_file_agrees` |
| New `handoffs.jsonl` classes: `recycle-kid-resolved`, `recycle-kid-shadow`, `recycle-kitty-probe-advisory`, `recycle-pane-probe-deferred`, `recycle-composer-cache` (proceeded on K1), `recycle-composer-cache-shadow` | `~/.claude/logs/handoffs.jsonl` | B6 / the operator; no parser keys on them |
| `pane-keys.jsonl` rows from `cc_tui_rpc send-text` (same schema, `verb:"cc-tui"`) | `~/.claude/logs/pane-keys.jsonl` | K1 clause 6, provenance |
| New precheck lines: `identity: kernel (…)`, `pane_root_lstart: …`, `composer: empty (by cache: …)` | lr-handoff's relayed precheck | the first token `empty` keeps every `composer: [a-z-]+` reader correct |
| `it2 session list --json --only <id>` | `bin/it2-kitty` | `pane_proof` |
| Env: `HF_KITTY_OFFPATH`, `HF_DRAFT_CACHE`, `HF_DRAFT_CACHE_RENDER_S` (30), `HF_DRAFT_CACHE_MAX_AGE_S` (43200), `HF_PANE_PROOF_ADVISORY` (derived), `HF_PANE_PROOF_ONLY` (on), `HF_PANE_IDENTITY_FILE`, `HF_COMPOSER_NOANSWER_FILE` | — | — |

No existing field, row class, verdict string or rc changes meaning.

---

## 7. Failure modes under permanent 15-40/core load

| # | Failure | Handling | Net effect |
|---|---|---|---|
| F1 | A `ps`, `ioreg` or `lsappinfo` call is slow at priority 31 (residual 1.1-7×, REPORT §3.1) | each sits inside a `hf_bounded_s` wrapper; 124/137 ⇒ rc 2 "cannot tell" ⇒ today's kitty path | never a verdict; at worst today's behaviour |
| F2 | The registry row is stale (dead pid; 14 of 54 rows today [M5]) | the bind refuses already (`:2970-2972`); the identity sees rc 2 | unchanged |
| F3 | A zombie claude or window root | rc 1 or 2 ⇒ fall back | the skeptic's hole (a) closed |
| F4 | kitty restarted: window ids reused, old pids dead | the row pid is dead or `KITTY_PID` differs ⇒ refuted ⇒ fall back | as strong as today's pin |
| F5 | The window outlives its root (`close_on_child_death no`, `kitty.conf:1038`) | claude re-parents to launchd, so the ancestry walk finds no kitty ⇒ rc 2 | fall back |
| F6 | The env spoofed by argv text | LAST-token rule, plus `KITTY_PID` = row `kitty_pid`, ancestry reaching that kitty, and the optional census identity | cross-checks catch it |
| F7 | The pane probe gets no answer, and the stage fails or the pin fails | held before the confirm (§5.4c) | today's cost, no more |
| F8 | The pane probe gets no answer and the signal declines after the confirm (state changed) | `hf_recycle_hold unreachable` unconfirms; TRANSIENT, retried ≤300 s | rare; same class as today's post-confirm holds |
| F9 | SIGTERM ignored | existing `exit-signal-ignored` hold (`:19450-19452`); no KILL | unchanged |
| F10 | Stage unclaimed while kitty is deaf | typed fallback fails after 600 s ⇒ `recycle-dead`, packet, debt; session resumable | measured 0/47; data-safe |
| F11 | K1 has no proof (no cache, mismatch, input since, ledger row, screen-sharing, age) | today's composer-unreadable hold; TRANSIENT ≤300 s (wave 2) | never proceeds on an unknown box |
| F12 | `HIDIdleTime` unreadable | clause 5 fails ⇒ no proof | fail closed |
| F13 | A torn or concurrent cache write | tmp + `mv`, last writer wins; a parse failure ⇒ no proof | fail closed |
| F14 | A deaf kitty makes each bounded call cost about 13 s | about 2 min of bounds per move (about 45 s with §5.7), against hours of holding today | bounded |
| F15 | The watcher keeps running after an advisory no-answer while the foreground holds | the hold writes `exit-aborted` and disarms (`:3803-3808`); the EXIT trap revokes the stage (`:11387`) | existing machinery |
| F16 | The successor's turn stalls because kitty's **main** thread is starved (PRI 4) and the pty output buffer fills (`vt_parser_has_space_for_input`, axis 07 §2) | not addressed: B5 removes kitty RC, not kitty-as-terminal; the disk oracle reports never-engaged | residual [H]; B8 |
| F17 | Records born while the reconciler's own `kitten @ ls` is degraded have no pane (`census.py:376-395`), and settle needs `h.pane` | out of scope; the moved session works, the record closes when kitty answers [H] | follow-up B5-R (§11) |
| F18 | iTerm2 panes | no `KITTY_*` env ⇒ rc 2 ⇒ today's path | unchanged |

---

## 8. Test plan

Every RED case below fails on `28b25a119` and passes after the change. Each power claim names the
mutant that must turn it red, per the rule "Green in both arms"
(`.claude/rules/agent-operating-lessons-situational.md:62`).

Seams, so no suite reads the live box:
- `LR_MOVE_ENV_DIR` (process env fixtures, already exists);
- a `ps` fixture through a new `HF_KID_PS_BIN` (a stub script answering `-o stat=|ppid=|tty=|comm=|lstart= -p N` from a TSV);
- `LR_HID_IDLE_S`;
- `CC_PANE_KEYS_LOG`;
- `HF_SCREENSHARING_PGREP`;
- `LR_STATE_DIR`.

These satisfy `scripts/test-hermeticity-lint.sh`.

| ID | Suite (new unless noted) | Cases | RED-before control / mutant |
|---|---|---|---|
| T1 | `tests/handoff-kernel-identity.bats` | verified (exports `CC_TERM=kitty`, `CC_TERM_KITTY_TO` from env `KITTY_LISTEN_ON`; keeps a preset `CC_TERM`); zombie claude ⇒ 1; zombie root ⇒ 1; row lstart ≠ live ⇒ 1; env window id ≠ pane ⇒ 1; argv carrying `KITTY_WINDOW_ID=99` before an env with `=41` ⇒ verified as 41; no env block ⇒ 2; ancestry to launchd ⇒ 2; kitty comm not kitty ⇒ 1; census file disagreeing on `root_lstart` ⇒ 1; mode `off` ⇒ 2 | the function does not exist on base (RED by absence). Mutants that must turn a case red: drop the `Z*` test (zombie cases), use `head -1` for the env (argv-spoof case), drop the census compare |
| T2 | `tests/handoff-recycle-kitty-offpath.bats` | remote prepass with a kitty stub that sleeps past the bound, plus a valid kernel fixture ⇒ passes the prepass with `recycle-kid-resolved`, and the kitty stub's call log shows **0** resolver/pin calls | base: exits 2 with `REMOTE-PANE-RESOLVER-…` (RED). Control: `HF_KITTY_OFFPATH=off` ⇒ base behaviour, byte-identical stderr |
| T3 | extend `tests/handoff-fire-pane-proof.bats` (21 cases) | with `CC_TERM=kitty` the shim receives `session list --json --only 41`; `[]` rc 0 ⇒ `pane-UNREACHABLE`; rc 124 ⇒ `pane-NO-ANSWER`; with `CC_TERM=iterm2` no `--only` reaches the shim | base sends no `--only` (RED). Mutant: send `--only` unconditionally ⇒ the iTerm2 case fails |
| T4 | `tests/it2-kitty-only.bats` | `--only` maps to `ls --match id:N`; kitty's "No matching windows" rc 1 ⇒ `[]` rc 0; a timeout keeps rc 124 | absent on base |
| T5 | extend `tests/handoff-recycle-successor-claim.bats` (10) | watcher with `HF_PANE_PROOF_ADVISORY=1` and a probe answering no-answer keeps running; with UNREACHABLE it exits 1; without the env it exits 1 | base exits on no-answer (RED) |
| T6 | `tests/handoff-recycle-deferred-probe.bats` (drives `recycle_fire_armed`'s tail over stubs, as `handoff-recycle-hold-after-watcher-commit.bats` does) | (a) no-answer + staged + pinned ⇒ reaches `hf_exit_signal` and emits `recycle-exit-signal`; (b) no-answer + stage refused ⇒ `recycle-held-unreachable` and **no `lr-transplant --phase confirm` call** recorded; (c) no-answer + pin fails ⇒ same as b; (d) no-answer, staged, then `hf_exit_signal` rc 1 ⇒ `held: unreachable` with an unconfirm call; (e) `HF_PANE_PROOF_ADVISORY` unset ⇒ today's hold | (a) is RED on base. Mutant: drop the post-stage check ⇒ (b) and (c) go red |
| T7 | `tests/handoff-draft-cache.bats` | `hf_draft_cache_proves_empty`: proves (cache empty, same incarnation, HID idle covers the read, no ledger row, no screen-sharing); each clause violated singly ⇒ no proof (identity field, claude lstart, `state=occupied`, input 10 s after the read, ledger row 5 s after, screen-sharing up, age > max, HID unreadable, torn JSON); render allowance: input 20 s before the read ⇒ no proof | RED by absence. One mutant per clause (deleting it) must turn exactly its case red |
| T8 | extend `tests/handoff-composer-gate.bats` (61) | the existing "unreadable pane (empty read) is UNKNOWN (rc 1)" stays green; new: a 124 on the ansi read ⇒ `noanswer` side-file written, **no second read** (stub call count 1); `recycle_composer_gate` in mode `on` with K1 proving ⇒ rc 0 at once (elapsed < interval); mode `shadow` ⇒ rc 2 after the wait and one shadow row; a dialog shape (rc 3) ⇒ K1 never consulted | the new cases are RED on base; the existing pin is the equivalence guard |
| T9 | precheck case in `tests/lr-handoff-precheck-*.bats` | deaf kitty stub plus K1 proving ⇒ `verdict: OK`, with `composer: empty (by cache…)` and `identity: kernel`; K1 not proving ⇒ `HELD:unreachable` after **one** probe (stub count 1, not 5) | base: `HELD:unreachable` after 5 tries (RED for the proving case) |
| T10 | `lr_recon/tests/test_composer_cache.py` | `_read_composer` writes the file with `read_started_at` from an injected wall clock that **advances inside the pass** (B7's helper), not `now`; `unknown` writes nothing; the key fields come from `PaneObs` | RED by absence. Mutant: stamp with `now` ⇒ the advancing-clock case fails |
| T11 | `tests/cc-tui-pane-keys.bats` | `cc_tui_rpc send-text --match id:7 -- x` appends one row with `pane:"7"`; `get-text` appends none | RED on base |
| T12 | shadow falsifier (live, read-only analytics, run by the agent before asking to flip K1) | `jq -r 'select(.class=="recycle-composer-cache-shadow")\|.detail' ~/.claude/logs/handoffs.jsonl` | **criterion:** ≥50 rows with `k1=proves` and 0 with `fresh=occupied k1=proves`. One disagreement keeps K1 off and is a finding |
| T13 | load proof, under B1's harness when it exists | fault matrix "kitty RC delayed 2-15 s" plus "kitty RC dead", staged moves, n = 9 | red arm (base): every move `HELD:unreachable`/PARKED; cure arm (mode on, caches fresh, `LR_HID_IDLE_S` large): all ENGAGED, 0 typed `/exit` |

**Gate hygiene before `/ship`** (rule at `agent-operating-lessons-situational.md:260`):
- bare `shellcheck` on every changed `.sh` and `.bats`;
- `scripts/test-afunix-path-lint.sh`, `scripts/test-hermeticity-lint.sh`, `bats-assert-liveness-fix.py`;
- run the suites serially, and count `ok` + `not ok` against the `1..N` plan line;
- run the touched suites under `/bin/bash` 3.2: the watcher and the precheck run under launchd's
  interpreter (rule "Deployment interpreter ≠ yours").

---

## 9. Rollout, kill switch, operator steps

1. **Land with code defaults `HF_KITTY_OFFPATH_DEFAULT=shadow` and `HF_DRAFT_CACHE=shadow`.** Every
   B5 computation runs and logs (`recycle-kid-shadow` with the kitty-resolved tty beside it, and K1
   shadow pairs). Behaviour is today's. The bash halves go live at converge. The reconciler's cache
   writer (W1) loads at the daemon's **next natural restart**: do not restart it mid-cohort to deploy
   this (A6).
2. **Identity shadow criterion: ≥30 `recycle-kid-shadow` rows, 0 tty disagreements** (M4 already
   reads 30/30 offline). Then land a one-line default change to `on` for parts 5.2-5.4 (identity,
   advisory probe, `--only`). K1 stays shadow.
3. **K1 shadow criterion (T12) met ⇒ ask the operator** (operator ask 2). With their OK, land
   `HF_DRAFT_CACHE` default `on`.

**Kill switches**, each restoring today's behaviour for its part:

| Scope | Command |
|---|---|
| Everything (no restart needed; read at every call) | `printf off > ~/.reso/limit-recover/kitty-offpath.mode` |
| K1 only | `HF_DRAFT_CACHE=off` |
| The `--only` probe | `HF_PANE_PROOF_ONLY=off` |
| Already existing | `HF_EXIT_ACTUATOR=typed`, `CC_PANE_SUCCESSOR=off`, `CC_RECYCLE_KITTY_PRECHECK=0` |

**Operator steps.** None are required to land and run parts 1-2. Asked:
1. Optional: authorize the P0 draft-survival proof (§1). The build session would create and close
   its own scratch kitty tab and `send-text` without Enter into that tab only. The W6 SIGTERM proof
   is the precedent for scratch tabs; that proof typed nothing.
2. Required before K1 goes live: rule that an unanswered composer may be passed on K1's proof. This
   is the narrower form of gap-2 §8's open ruling "whether an unreadable composer may proceed under
   the HID-idle rule", with the T12 numbers attached.

---

## 10. Size

[E], sized function by function from the sketches above:

| Area | Lines |
|---|---|
| `handoff-fire.sh`: identity, file compare, bounded wrapper | ~110 |
| `handoff-fire.sh`: call sites | ~35 |
| `handoff-fire.sh`: probe advisory | ~20 |
| `handoff-fire.sh`: pane-probe advisory and deferred verdict | ~45 |
| `handoff-fire.sh`: cache put/get and K1 | ~110 |
| `handoff-fire.sh`: `composer_content` and gate hooks | ~25 |
| `handoff-fire.sh`: mode | ~15 |
| `lr-lib.sh` | ~15 |
| `bin/it2-kitty` | ~20 |
| `cc-tui.sh` | ~15 |
| `lr_recon` (`__main__.py`, `act.py`, `store.py`) | ~50 |
| **Code subtotal** | **~460** |
| Tests | ~520 |
| **Total** | **~980** |

The optional latch (§5.7) adds about 25.

---

## 11. Dependencies and relations

- **A1 (landed, 07ce89a99).** A prerequisite in practice: B5's value is computed against a rail at
  priority 31.
- **B1-load-harness (soft).** T13's end-to-end proof under a kitty-RC fault needs it. B5's unit suites
  do not.
- **A6-restart-safety (soft).** The reconciler half loads at a restart; do not force one mid-cohort.
- **B7-now-audit (soft).** W1 must stamp wall clock; T10 uses B7's advancing-clock helper if it
  lands first, else its own.
- **B8-kitty-hygiene (complementary, not a dependency).** B8 cuts the frequency of kitty outages; B5
  limits their cost. Only B8 fixes F16 and residual R2.
- **G2-self-recovery depends on B5:** it reuses `hf_kernel_pane_identity` and the advisory reads.
- **D2-warning-band-shedding benefits:** "the kitty precheck is the next gate" (REPORT D2 risk).
- **B3-deadline-override.** Its hard predicate "an unsent draft" becomes evaluable during a kitty
  outage through K1.
- **C2-socket-prompt.** Independent: the owed prompt already rides argv (wave 4).
- **Follow-up B5-R (not in this LOC).** Let `lr_recon/observe.py` bind `(kitty_pid, window_id)` per
  claude from `ps -E` when its own `kitten @ ls` is degraded, so records born during a kitty outage
  get a pane (F17).

---

## 12. Conviction

**60%** that this design, as specified, takes kitty off the pre-commit path without new draft loss,
and is worth its size:
- **Parts 5.2-5.4 alone: 80%.** They are strictly widening, the 30/30 identity agreement is
  measured, and they are mostly test churn.
- **K1: 50%.** Its soundness rests on R1, which is [H]; the shadow pairing is designed to settle it.

What would move the number:
- the T12 disagreement count;
- the first kitty RC outage at a cap wall after landing: the number of moves that proceed vs hold;
- whether B8 lands, which would shrink the class B5 insures against.

---

## Review — efficacy-under-permanent-load

Adversarial review, 2026-10-20 ~18:40Z, read-only, at this worktree's `HEAD` `28b25a119`. The question: does B5
bound recovery time at 15-40/core with every lane at PRI 31, and does any new wait, bound or gate assume that
load falls? Labels: [M] measured (command named), [E] estimated (method named), [H] hypothesis.

**Verdict: NEEDS-CHANGES. Adjusted conviction 40%** (design: 60%). The safety polarity holds: every new path
falls back or holds TRANSIENT, and no new bound is keyed on load. But the design does not bound recovery time
in the outage class it targets. One part regresses today's ride-through of short kitty stalls. One mechanism
cannot be implemented as written, and the rollout default contradicts §9.

### What I verified and found sound

- **Citations.** I read every cited site the design leans on. All match at `28b25a119`: `:16252`, `:2980`,
  `:19568`, `:13848`, `:13897`, `:13903`, `:13930`, `:13959`, `:13972`, `:19977`, `:20009`, `:20131`,
  `:11616`, `:4422`, `:4061-4091`, `:19453`, `:11387`, `:12589`.
- **No new wait on load.** Every new bound fires on the wall clock and maps to "fall back" or a TRANSIENT hold.
  `classify._TERMINAL_TRANSIENT` (`classify.py:33-35`) and `settle._RCY_HELD` (`settle.py:84-87`) already
  carry `unreachable` and `composer-unreadable`. G1 and G2 hold.
- **The signal path needs K1 under a deaf kitty, and K1 is enough for it.** `hf_exit_signal` requires
  `RCY_REST_PROVEN=1` (`:4065`). Only `hf_recycle_last_read` sets it (`:3946`), after `recycle_composer_gate`
  (`:3859`), and `:20109` sets it on the deferred-self path. So K1 at R9 is the gate, as the design says.
- **Pid keys line up for W1 and the identity.** The live registry pid equals Claude Code's own session-row
  pid for 25 of 25 sessions [M: python read of `~/.claude/cc-registry/*.json` against
  `~/.claude*/sessions/*.json`, filtered to live pids]. So W1's `claude_pid` (the lead holder,
  `observe.py:624`) will match `HF_KID_PID` (the row pid, `:2734`).
- **Live readings.** 157 zombies under kitty 853, at load1 218 [M: `ps -axo stat=,ppid=`, `uptime`].
- **Recycle outcomes.** Since 2026-10-18 there were 48 stages, 48 claimed and 0 revoked. There were 2
  `recycle-held-unreachable` in total and 0 since the 07:23Z PRI-31 reload [M: python count over
  `~/.claude/logs/handoffs.jsonl`]. Against load, at PRI 31, B5 is insurance, as §0 says.
- **`--only` is the most load-relevant part.** It cuts the watcher probe from 0.44-0.68 s to 0.047-0.084 s at
  PRI 31 (axis 07 L5). It is strictly widening, and "No matching windows" is distinct from rc 124 (07 L5).

### Findings

**R-1. Regression: the precheck's single probe gives up today's ride-through for the reconciler and the move
lane.**
- Today the reconciler's actuator sets `LR_INPLACE_AWAIT=0` (`act.py:65`). That gives `max=5` tries over a
  120 s budget (`handoff-fire.sh:1568`, `:1566-1597`). The schedule exists for 10-60 s accept stalls: 43e6eb4b
  held on one probe, and the same kitty answered 48 s later (`:1557-1565`).
- §5.3 sets `HF_KPROBE_TRIES=1` whenever the identity verifies. Its early stop then prints
  `HELD:unreachable` whenever K1 cannot prove. That is every case while K1 is in shadow (rollout step 2), and
  every case after any keyboard input.
- So a stall that today rides through in ≤145 s becomes a hold plus a TRANSIENT backoff of up to 300 s.
- "The cost is today's (~16 s, one try)" is the cost for an in-tool-call caller, not for a detached one.
  T9 ("after ONE probe (base: 5 tries)") pins the regression in place.

**R-2. "One `hf_bounded_s 20 …` subshell wrapper" cannot run as written.**
- `hf_bounded_s` execs `"$HF_TIMEOUT_BIN" -k 3 "$_s" "$@"` (`:1145-1150`). `timeout(1)` cannot exec a bash
  function.
- A forked, bounded subshell cannot hand `HF_KID_*` back to the parent, nor export `CC_TERM` to it.
- `hf_kid_bounded` is called in §5.2 but never defined.
- The sketch also forks about 14 `ps`: `ps -E` three times, one `ppid` per ancestry level, and per-field
  `stat`, `tty`, `comm` and `lstart`. That is costly under the measured fork storm of 280-1,410 execs/s with
  40-53% system time (REPORT §3.3).

**R-3. The rollout default contradicts §9, and two kill switches are env-only.**
- §5.1 falls back to `${HF_KITTY_OFFPATH_DEFAULT:-on}`, and nothing sets that variable for the launchd rail.
  So B5 would land **live**, skipping the identity shadow criterion of §9 step 2.
- `HF_DRAFT_CACHE` and `HF_PANE_PROOF_ONLY` are env-only, against principle 4: "launchd jobs do not see an
  interactive shell's env". Turning K1 off on the reconciler would need a plist edit and a restart, which A6
  says not to force mid-cohort.
- Nothing ties K1's mode to `kitty-offpath.mode`.

**R-4. Coverage hole: K1 has no cache for the sessions a cap wall during an outage produces.**
- W1 hooks `_read_composer`. That reads only dead (limited) sessions (`__main__.py:676-690`, `:704`), or idle
  fan-out, which is off by default (`:710`). It reads only when the reconciler's own `kitten @ ls` bound the
  pane (`:706`).
- W2 writes only for panes handoff-fire is already moving.
- So in a kitty-RC outage:
  - a session that hits its cap **during** the outage never gets a cache line, because no read can succeed;
  - its record is born with no pane (F17). In this incident 3 of 9 records were born pane-less and rebound
    at 02:40:42Z [M: `grep '"ev":"rebind"' recon/events.jsonl`].
- K1 therefore helps only sessions that were limited and read **before** the outage. "Every move today
  holds … With B5 it proceeds" does not hold for the overnight cap-wall case.

**R-5. The target outage class is load-driven, and proceeding through it may hand off to a starved
terminal.**
- §0 calls the screen-lock class one "which load does not cause". The evidence says otherwise. On 10-01 the
  same PRI-4 kitty answered at load 51 in 0.10-0.12 s and failed 9 of 9 calls at load 120-133
  (`recycle-unreachable-2026-10-01.md:11`).
- Under the premise (load1 150-400), a PRI-4 kitty is deaf for the whole lock (07 L6: "an overnight screen
  lock is a recurring scenario").
- Axis 07 traces the 10-01 talk-thread death to the same deaf main thread (`07-kitty-control-plane.md:93-95`).
- That main thread also runs the VT parse, and the I/O thread stops reading a pty whose buffer is full
  (`:84-89`).
- So a K1 proof from a pre-lock cache would SIGTERM a session into a successor whose output kitty does not
  drain.
- Whether Claude Code 2.1.293 then stalls is [H]. The binary is a Bun build: `strings` on `claude.exe` names
  `bun-darwin-aarch64`. Node documents TTY writes as *synchronous on POSIX*
  (https://nodejs.org/api/process.html#a-note-on-process-io); Bun's behaviour is unverified.
- Either way, F16 is not a side residual. It sits on the main path of the class B5 most often meets.

**R-6. T12 cannot falsify K1 at a useful rate.**
- A keyboard-typed draft always moves `HIDIdleTime`, so K1 already refuses it. A disagreement needs a
  non-HID writer (R1), whose rate is unknown and plausibly well under the 0.7% draft base rate.
- 0 disagreements in 50 bounds that rate only below ~6% per proved move [E: rule of three, 3/50].
- Most pairs would be near-tautological. Every successful read at P5, R5, R6, R8 and R9 rewrites the cache
  (W2), so the next pair judges a cache that is seconds old. K1 exists for an hours-old pre-outage cache.
- The rows carry no load or kitty-band field, so they cannot show the 30 s render allowance holds at
  30-40/core.

**R-7. New calls on the critical path have no bound.**
- K1 calls `lr_hid_idle_s`, which runs `/usr/sbin/ioreg -c IOHIDSystem` with no bound
  (`lr-lib.sh:1427-1432`). It also calls `pgrep`.
- lr-handoff runs the whole precheck with no outer bound (`lr-handoff.sh:1471`). F1's "each sits inside a
  `hf_bounded_s` wrapper" is not true of these calls.
- A kernel stall ("a SIGKILLed `ps` came back after 1,226 s", REPORT §3.3) would hang the move here with no
  timeout.

**R-8. K1 is used first instead of last.**
- At R5, K1 answers the first unanswered read. That gives up the gate's existing 180 s / 15 s retry
  (`:19670-19673`, `:5239-5263`), which rides a 10-60 s stall with a **real** read.
- A cached proof should not replace a real read that will probably arrive within a minute.

**R-9. The plain re-read skip has no mode gate.**
- §5.5 drops `composer_content`'s second read on 124/137 with no mode gate.
- With mode `off`, that changes today's precheck: a slow but live kitty loses one 10 s chance. That breaks
  principle 1's "byte for byte".

**R-10. The typed fallback under a deaf kitty is a certain failure.**
- After an advisory no-answer, a stage left unclaimed for 20 s at a bare shell is revoked and the relaunch
  is typed (`:12475`, `:12481-12484`). With kitty deaf, typing cannot work, so the revoke turns a slow claim
  into a certain `recycle-dead` at 600 s (`:12589`).
- The risk is low: 0 revoked in 48 [M]. But `rcy_cgrace` is a fixed 20 s for a shell start under 40/core,
  while its sibling `rcy_cmax` is load-scaled (`:12476`).

**R-11. Build blocker: the `LR_MOVE_ENV_DIR` seam already has a different file format.**
- The existing fixtures hold the bare `CLAUDE_CONFIG_DIR` value, not an env block (`lr-lib.sh:1082-1084`;
  `tests/lr-move-plan.bats:335`; `tests/lr-reset-poller-parked-helpers.bash:57`). About 20 suites set the
  variable [M: `grep -rln LR_MOVE_ENV_DIR tests`].
- If `lr_pid_cfg` becomes a caller of `lr_pid_env`, those fixtures have no `HOME=`/`PATH=` line. They would
  return rc 1, and the suites would go red.

### Required changes

1. **Keep the probe schedule (R-1).** Keep today's probe schedule (5 tries / 120 s for `LR_INPLACE_AWAIT=0`)
   unless K1 proves. Only a K1 proof may cut it short. Rewrite T9 to assert 5 stub calls in the K1-not-proving
   case.
2. **Define `hf_kid_bounded` (R-2).** Either:
   - bound each `ps` (`hf_bounded_s 5 /bin/ps …`, 124/137 ⇒ rc 2); or
   - run a `__kid` verb under `hf_bounded_s 20` that prints validated `KEY=VALUE` lines for the parent to
     import.

   Cut the reads to at most 3 forks:
   - one `ps -E -ww -o command= -p <pid>`, read once for all three variables;
   - one `ps -axo pid=,ppid=,stat=,tty=,comm=`, walked in awk;
   - one `TZ=UTC LC_ALL=C ps -o pid=,lstart= -p <pid>,<root>,<kpid>`.

   T1 gains a stub `ps` that sleeps past the bound and must yield rc 2.
3. **Fix the rollout default and the switches (R-3).**
   - Code default `shadow` in `hf_kitty_offpath_mode`.
   - File-backed modes for K1 (`draft-cache.mode`) and for `--only`.
   - K1's effective mode is the lower of its own mode and `kitty-offpath.mode`.
4. **Close the coverage hole or state it (R-4).** Either:
   - (a) broaden W1 to every pane holding a claude. Re-read a pane only when `HIDIdleTime` shows input since
     its last cached read: zero reads while the operator is away, and one sweep of `kitten @ get-text` reads
     at 0.047-0.084 s each while they are active (07 L5) [E]. Bring B5-R (`ps -E` pane binding in
     `observe.py`) into scope, so that records born during an outage have a pane; or
   - (b) drop the "proceeds during an outage" value claim, and state that K1 covers only sessions limited
     and read before the outage began.
5. **Gate on kitty's band (R-5).**
   - Before any B5 proceed past an unanswered kitty (K1 at R5/R8/R9, or the deferred probe), read kitty's
     main-thread band from the kernel: `ps -M -p $HF_KID_KPID`, at least 3 samples, main thread.
   - If it is in the background band (≤4), hold as today with a distinct reason ("kitty background-banded:
     its main thread would not drain the successor's output; B8"), as a TRANSIENT retry.
   - Correct §0: the screen-lock class is load × band, permanent under the premise. Rank B5 behind B8.
6. **Rebuild the falsifier (R-6).**
   - Count one pair per (pane, move), only for a cache aged ≥300 s or written by `recon`.
   - Size n to the rate the operator accepts: ≥300 such pairs to bound the rate below 1% [E: rule of three].
   - Add an adversarial arm to the P0 scratch-tab run: text injected by a path outside both ledgers, and a
     queued message restored into the box; K1 must refuse both.
   - Every row records load1/ncpu, kitty's main-thread pri and the read's duration. Require ≥30 of the rows at
     ≥30/core before asking to turn K1 on.
7. **Bound the new calls (R-7).** Bound `ioreg` and `pgrep` inside K1 (10 s; 124/137 ⇒ `unreadable` ⇒ no
   proof). Correct F1.
8. **Make K1 the last resort (R-8).** Consult K1 only after a second unanswered read 30-60 s after the first,
   or when the remaining wait would end in a hold, whichever comes first. R8 and R9 get one bounded retry
   before K1. The added cost is ≤60 s per move in a full outage, still bounded.
9. **Gate the re-read skip (R-9).** Apply it only in mode `on` with `HF_KID_OK=1`, or under the §5.7 latch.
   Add a mode-`off` byte-equality case to T8.
10. **Hold the revoke in advisory mode (R-10).** Revoke and type only after a bounded kitty probe answers;
    otherwise keep waiting for the claim up to the load-scaled `rcy_cmax`.
11. **Use a new seam (R-11).** Use a new `LR_PID_ENV_DIR` seam for env-block fixtures, and leave
    `lr_pid_cfg`'s fixture branch byte-identical.

### Net under the premise

- **Healthy kitty at PRI 46-54, rail at 31.** B5 is roughly neutral. `--only` adds margin. The kernel
  identity costs about the same as the kitty resolver it replaces [E: M1's per-`ps` cost × fork count].
- **Kitty at PRI 4 while the screen is locked.** B5 either cannot prove (no cache, or input since the cache),
  or, without change 5, proceeds into a successor that kitty starves.
- **RC dead with a healthy main thread and an operator away since the last cache read.** This is the one
  class where B5 delivers bounded recovery. Changes 4 and 8 decide how often that class occurs.

With these changes, the design is NEEDS-CHANGES rather than UNSOUND: nothing in it can lose a draft or pass a
timeout off as a verdict. As specified, it does not yet bound recovery time in its own target class.

---

## Review — correctness-and-safety

Adversarial review, 2026-10-20 ~18:50Z, read-only, at this worktree's `HEAD` `28b25a119`. The question: can B5
strand a move, double-move, lose a draft, split-brain, break an invariant or break an existing test? Labels:
[M] measured (command named), [E] estimated (method named), [H] hypothesis. The repo rules were read first
(`.claude/rules/*.md`). The ones that bear on this design are "Remote pane identity is the target's", "Nth
fallback source un-seals old fixtures", "Deployment interpreter ≠ yours" and "Probe writes into a live session".

**Verdict: NEEDS-CHANGES. Adjusted conviction 45%** (design: 60%).
- The design's shape is sound. The kernel identity walks the **target** pid's ancestry, as the rule requires.
  Every path falls back on doubt. The deferred probe is gated on stage, pin and signal. K1 ships in shadow.
- As written, though, it has **draft-loss paths**: S1, S8, S9, S10, S11. It has **strand windows**: S5, S6. It
  has two **implementability/shadow defects**: S2, S3. It **breaks about 21 existing suites**: S4.
- I disagree with the efficacy review's closing line ("nothing in it can lose a draft"). S1 and S10 are
  concrete paths to a SIGTERM over an unread draft.
- Every defect has a local fix, and none needs B5 to be abandoned.

### Verified and holding

- **Citations.** The cited sites match at `28b25a119` [M: `sed -n`/`grep -n`]: `:16251-16257`, `:2980`,
  `:2987-2992`, `:13848`, `:13897-13903`, `:13930`, `:19568`, `:19977`, `:20009`, `:20131`, `:11616`,
  `:11387`, `:19453`, `:4061-4091`, `:4787-4836`, `:12474-12490`, `:12589`, `lr-lib.sh:1079-1094`,
  `act.py:50-98`, `__main__.py:693-722`, `:1366-1368`, `kitty.conf:136`, `kitty.conf:1038`.
- **The two 10-20 holds were NO-ANSWER (await rc 3), not stalls (rc 2).** Both watcher logs read
  `listing rc=124 in 13s` and `rc=124 in 12s` [M: `grep pane-probe` over
  `$TMPDIR/handoff-recycle-41-1792466679-4Peazr.log` and `…-30-1792470113-9ABLep.log`].
- **Live counts.** Stages staged and claimed: 48 and 48 [M: `grep -o '"class":"recycle-successor-[a-z-]*"'
  handoffs.jsonl | uniq -c`]. Zombies under kitty 853: 157 [M: `ps -axo stat=,ppid= | awk …`]. Only
  `/tmp/kitty-853` is a socket; kitty 41475 has none [M: `ls -la /tmp/kitty-*`].
- **No SIGTERM without the post-confirm proofs.** `RCY_REST_PROVEN=1` is set only at the end of
  `hf_recycle_last_read` (`:3946`), after the focus, composer, limit, at-rest, subagent, team and bg-work reads
  (`:3854-3945`). So the deferred path cannot skip them.
- **A stage revoked before the signal is caught.** `hf_exit_signal` re-checks `hf_succ_ours_staged` right
  before the signal (`:4066`), and the watcher's EXIT trap revokes its own stage (`:4951-4955`).
- **The env reaches the watcher.** `detach` is a `Popen` with no `env=` (`:2149-2156`), so
  `HF_PANE_PROOF_ADVISORY` is inherited.
- **The focus gate's composer reader is `recycle_composer_gate`** (`_hf_focus_composer`, `:3640-3642`), as
  §5.5 says. That fact is what makes S9 below real.
- **Double-move.** The pane lock, the move claim (`hf_recycle_claim_foreign`), the tombstone and the
  confirm/unconfirm custody are untouched. The identity changes no actor. I found no double-move path.
- **TZ and locale pinning is load-bearing.** A live `ps -o lstart` renders `Sun 18 Oct 19:40:35 2026` in the
  ambient locale, against `Sun Oct 18 …` under `LC_ALL=C` [M: `ps -o pid,pri,lstart,comm -p 853,41475`].
  The `HF_KID_PS_BIN` stub must pin it too.

### Findings

**S1 (draft loss, wrong pane). The identity trusts an inherited `CC_TERM_KITTY_TO`.**
- Sketch line: `CC_TERM_KITTY_TO="${CC_TERM_KITTY_TO:-$HF_KID_SOCK}"`. The resolver it replaces tries an
  operator-named socket first "but it is still VERIFIED below, never trusted" (`:2856-2858`).
- Where a preset comes from:
  - `act.actuator_env` sets it from the census socket (`act.py:85-86`);
  - §5.2 adds a new source: `"unix:/tmp/kitty-%d" % kitty_pid` for a record whose pane is None. That is the
    degraded-census case, where `kitty_pid` can be stale.
- Window ids restart at 1 in every kitty, and two kitty processes run on the box now (853, 41475). A preset
  naming the wrong live kitty has three effects:
  - (a) `composer_content` reads **another pane's** box and may return `empty`;
  - (b) W2 writes that read into `composer-cache/<HF_KID_KPID>.<P>.json`. This poisons the cache under the
    **right** incarnation key, and later K1 proofs inherit it;
  - (c) the advisory watcher, which no longer proved the pane, types its fallback relaunch through that socket.
- Today's pane proof has the same exposure only if the wrong kitty happens to list the same id. B5 knows the
  right kitty pid and still does not use it.

**S2 (cannot be implemented as written). A bounded identity cannot set the parent's state.**
- `hf_bounded_s` execs an external `timeout` binary (`:1145-1151`). A bash function cannot run under it, and a
  subshell drops `HF_KID_*` and the exports.
- Concur with efficacy R-2. On the safety side:
  - run unbounded in the parent, it adds about 14 `ps` forks with no bound to the critical path;
  - wrapped naïvely, B5 is silently inert.

**S3 (shadow acts as on). Shadow mode is not a shadow.**
- The sketch exports `CC_TERM`/`CC_TERM_KITTY_TO` on any verification while mode ≠ off (§5.2 sketch, the
  `if [ -z "${CC_TERM:-}" ]` line). It has no mode test.
- The prepass call site skips `hf_remote_pane_term` whenever the identity verifies:
  `if bind && hf_kid_bounded …; then …resolved… else hf_remote_pane_term`. That test is not mode-gated either.
- So in `shadow` the resolver is skipped at R1 exactly as in `on`, which contradicts "Nothing is skipped".
- Together with §5.1's `${HF_KITTY_OFFPATH_DEFAULT:-on}` (efficacy R-3), B5 would land acting.

**S4 (breaks existing suites). `lr_pid_env` reads the existing seam in the wrong format.**
- `LR_MOVE_ENV_DIR/<pid>` holds a **bare config dir**:
  - `lr-lib.sh:1082-1084` returns the file content as the answer;
  - fixtures write `printf '%s' "$HOME/.claude-tertiary" > "$LR_MOVE_ENV_DIR/$$"`
    (`tests/lr-move-plan.bats:335`; `tests/lr-lib.bats:857`).
- 21 suites reference the seam [M: `grep -rln LR_MOVE_ENV_DIR tests/ | wc -l` ⇒ 21].
- Making `lr_pid_cfg` a caller of `lr_pid_env` has two outcomes:
  - the `HOME=`/`PATH=` check fails, so every fixture reads rc 1;
  - if that check is dropped, the result is the `${out:-$HOME/.claude}` default. That is the "source husk read
    as a successor" failure `lr-lib.sh:1086-1087` exists to stop.
- Concur with efficacy R-11.

**S5 (strand, split-brain risk). The new post-confirm hold in the `*)` arm skips the debt and is mis-ordered.**
- The hold runs after `_hf_resume_debt open` (`:19422-19431`) and after the `exit-committed` marker
  (`:19437-19440`).
- Both existing post-debt holds abandon the debt first: `:19450` (exit-signal-ignored) and `:19465`
  (exit-readback). The design's line does not.
- Ordering: "before the typed /exit" can land ahead of the subject-gone yield at `:19456`. Placed there, a
  claude that already exited, whose watcher owns the relaunch, gets disarmed and unconfirmed. That is the
  pane-7 strand class (`:4093-4104`).
- An open debt over a source the hold has just unconfirmed is a resume owed on a live session. Whether the
  debt settler's holder check refuses it is [H].

**S6 (strand window). Deferring rc 2 has no evidence behind it and opens a race.**
- rc 2 means the watcher's probe has **not finished**. The advisory watcher still exits 1 on a late
  `pane-UNREACHABLE`, for example a `--only` reply of `[]` (§5.4b).
- Its EXIT trap then revokes the stage. If that lands after the SIGTERM, the result is: transplanted,
  confirmed, claude gone, stage revoked, watcher dead, debt open. That is a strand.
- The design also defers on **any** non-zero listing. A stale shim rejecting `--only` (usage rc) or a python
  crash (the `list` pipeline maps every failure to exit 1: `bin/it2-kitty:95`, `:1384-1399`) is a **broken
  transport**. Catching that before the kill is exactly `pane_proof`'s purpose (`:2171-2177`: 4 of 4
  post-kill relaunch failures). Advisory mode would read it as "kitty deaf".

**S7 (regression).** The precheck's single probe gives up today's 5-try / 120 s schedule while K1 is shadow.
Concur with efficacy R-1. It is listed here because it moves holds before the transplant, against the premise.

**S8 (draft loss). The definition of "kitty did not answer" is too wide.**
- §5.5 writes `noanswer` on rc 124/137 **"or nothing"**. An empty read is often an answer:
  - a blank screen;
  - kitty's `No matching windows` for a mis-addressed socket (S1);
  - an iTerm2-routed read of a numeric id when `CC_TERM=iterm2` is preset. The identity does not override a
    preset `CC_TERM`, yet it still sets `HF_KID_OK=1`.
- The identity also ignores the resolver's own kill switch `CC_REMOTE_PANE_TERM=off` (`:2829`).
- Today's `|| true` (`:5045-5046`) drops the rc that would separate the two cases.

**S9 (draft loss; against an operator ruling). K1 is reachable inside the focus gate.**
- `lr_focus_gate` passes a **focused** pane only after two EMPTY composer reads 10 s apart (`lr-lib.sh:1409-1418`;
  operator decision 7, D7.2c).
- Through `_hf_focus_composer`, two K1 answers from **one** cached read would satisfy it.
- "Focused" is the screen saying the operator is present. The design's own rule says that outranks the cache.

**S10 (draft loss). The keystroke ledger cannot see our own late or in-flight sends, and can drop rows.**
- (a) kitty executes timed-out requests late: "Measured: kitty executed a timed-out request ~9 min late, and 3
  of 4 rc-124 pastes in a scratch window were on screen" (`handoff-fire.sh:1118-1119`).
  - Take a `send-text` row with rc 124 whose `ts` is before `read_started_at − 30`. It can land in the box
    after the cached read, with no HID event and no new row.
  - In the outage class B5 targets, the senders include the carry's put-back, `lr-upgrade`'s keys and wakes.
- (b) Rows are appended after `kt` returns (`bin/it2-kitty:269-272`), so a send in flight while K1 evaluates
  is invisible. [H] The window is one send's duration.
- (c) `tail -c 262144 | jq` has three gaps:
  - the window's first line is partial;
  - one torn line stops `jq`, and `fromjson?` would skip it silently, losing a row;
  - nothing proves the window reaches back to `read_started_at`. Rotation or growth hides older rows. Today the
    file is 513 rows / 132 KB over about 41 h [M: `wc -lc`, first and last `ts`]. Adding `cc_tui_rpc` rows
    grows it.

**S11 (draft loss). W1's parser is weaker than the gate it stands in for.**
- `observe.composer_from_screen` drops any row matching `^\s*Try "[^"]*("|\.\.\.)\s*$` as the placeholder
  **even when it is not faint** (`observe.py:325`, `:421-422`). So an operator draft such as
  `Try "rebasing onto main"` reads `empty`.
- Today that read only steers bucketing, and the actuator re-reads with `composer_content` before /exit. K1
  makes the W1 read the last word.
- `tests/composer-parser-parity.bats` covers dialogs, menus and plain boxes only [M: its `@test` list]. It does
  not cover this rule, labeled borders, tall boxes or indented boxes.

**S12 [H] (draft loss in the target class). The 30 s render allowance assumes a responsive kitty main thread.**
- Keystrokes and remote-control commands both run on kitty's main thread.
- In the PRI-4 / App Nap class, the measured backlog reached minutes (S10a). A keystroke 30 s or more before
  the read could still be unapplied when the read is served.
- A read that kitty served promptly is evidence that its main thread was not backlogged. The cache already
  records `read_ended_at`.

**S13 [H] (draft loss). Clause 2 compares against identity values cached at process start.**
- Claude Code's own box changes are invisible to HID and to the ledger: for example a prompt restored after an
  interrupted or failed turn, or a queued-message pop.
- A transcript-mtime clause would catch every such change that writes a record.

**S14 (kill-switch invariant).**
- `HF_DRAFT_CACHE` and `HF_PANE_PROOF_ONLY` are env-only. That is against principle 4, and efficacy R-3 makes
  the same point.
- In addition, "env wins over the file" lets an `on` in any env defeat the documented "Everything" switch
  (`printf off > kitty-offpath.mode`). An env `on` can come from a plist, an actuator env, or a caller.
- `--only` ignores `kitty-offpath.mode` altogether.
- A kill switch must be monotone: `off` from any source wins.

**S15 (falsifier).** Concur with efficacy R-6, and two additions:
- **Pairs are correlated.** A 180 s gate polls every 15 s (`:5242-5262`) and yields up to 12 pairs from one
  box.
- **The criterion is stated over the wrong population.** It counts proves. The power lives in `fresh=occupied`
  reads: drafts are about 0.7% of moves (§1), so 50 proves contain about 0.35 expected drafts [E: 50 × 0.007].

**S16 (hermeticity and the test plan).**
- **(a) Un-sealing.** The mode file under `${LR_STATE_DIR:-$HOME/.reso/limit-recover}` and the real process
  table are new sources that un-seal old fixtures. Handoff-fire suites use **numeric** panes (41, 7, 30) and
  live pids (`$$`, `sleep` children). A bats run inside kitty window 41 verifies a fixture row `{41, $$}`. Then
  `CC_TERM_KITTY_TO` becomes the **real** socket, and later reads or sends can reach the runner's own pane.
  That is the "Probe writes into a live session" class. `tests/lr-lib.bats:832-835` uses unforgeable pane ids
  for exactly this reason.
- **(b) New event and line texts must avoid every pattern in `classify._CLASSES`** (`classify.py:44-80`):
  `\bdraft\b`, `\bcomposer\b.{0,20}\bunreadable\b`, `\bmenu\b`, `\biterm`, `headless`, and the rest.
  `settle._HOLD_SUB` alone is not enough. For example, `k1=no:composer unreadable` would classify HOLD if it
  reached an actuator's output.
- **(c) Test-plan facts.**
  - T9 names `tests/lr-handoff-precheck-*.bats`, which do not exist. The precheck suites are
    `tests/handoff-probe-preconditions.bats` and `tests/handoff-recycle-kitty-precheck.bats`.
  - `handoff-composer-gate.bats` has 60 `@test`, not 61 [M: `grep -c '^@test'`].
  - T4's "a timeout stays rc 124" is false inside `bin/it2-kitty`: pipefail plus python turn any `kt ls`
    failure into exit 1 (`:95`, `:1384-1399`). The 124 comes from `pane_proof`'s outer `hf_bounded`.

**S17 (minor).**
- `HF_PANE_PROOF_ADVISORY` must be exported as `0` when the conditions fail, and `export -n`'d in the watcher
  (precedent `:11395`). Otherwise a nested re-fire inherits `1`.
- `hf_kid_file_agrees` must normalise the tty: PaneObs carries `ttys051` (`observe.py:181`), the identity
  carries `/dev/ttys051`.
- The identity should require the socket to exist (`-S`).
- With `HF_KID_TTY`, the pin's walk (`:2987-2992`) re-checks the identity's own walk. So the window id rests on
  the env token alone, and §5.2's "the cross-checks catch a spoof anyway" holds for `KITTY_PID` but not for the
  window id. Parse only the env block, by stripping the `ps -o command=` argv prefix from the `ps -E` output.
- `cc_sid_for_pane` (`:8998`) uses `grep -m1`, the FIRST token. It is not precedent for the LAST-token rule.
- `composer-cache/` needs garbage collection.
- Define `hf_kitty_offpath_mode` above its first user, so the definition-order guards hold.

### Tried and could not break

- **SIGTERM without at-rest.** Impossible (`:3946`).
- **Typed /exit after an unanswered probe.** Blocked by the `*)` hold, once S5 is fixed.
- **Stage revoked between the stage and the signal.** Caught at `:4066`.
- **iTerm2 UUID panes.** Identity rc 2.
- **The window outliving its root.** The ancestry walk fails, so rc 2.
- **kitty restart with window ids reused.** The row pid is dead, or `KITTY_PID` differs, so the identity falls
  back.
- **The 157 zombies.** Handled by the `Z*` checks.
- **Mixed-version converge.** The old foreground never sets `HF_PANE_PROOF_ADVISORY`, so a new watcher keeps
  today's behaviour.

### Required changes

1. **(S1) Bind the socket to the verified kitty.** When the identity verifies:
   - set `CC_TERM_KITTY_TO` to `HF_KID_KPID`'s socket. A preset whose `kitty-<pid>` differs is overridden, or
     the identity returns rc 2;
   - export `CC_TERM_KITTY_PID=$HF_KID_KPID`, so `bin/it2-kitty`'s `prove_target` (`:590-600`) refuses a
     socket of another kitty;
   - W2 writes the cache only when the read's socket pid equals `HF_KID_KPID`.

   Drop the `actuator_env` `/tmp/kitty-<pid>` fallback, or limit it to A/R with a socket that exists and whose
   pid matches.
2. **(S2) Run the identity as a re-exec.** Use a `__kid` verb under `hf_bounded_s`. It prints strictly
   validated `KEY=value` lines; the parent assigns and exports them. Bound `ioreg` and `pgrep` the same way
   (124/137 ⇒ no proof).
3. **(S3) Make shadow side-effect-free.** Add no export, and skip the resolver only in mode `on`. Set the code
   default to `shadow`. Add a T2 shadow control that asserts the resolver ran and stderr equals base.
4. **(S4) Use a new seam.** Give `lr_pid_env` its own seam (e.g. `LR_PID_ENV_DIR`, env-shaped files). Leave
   `lr_pid_cfg` and its fixtures byte-identical. Route every identity `ps` call, `_hf_lstart` included, through
   `HF_KID_PS_BIN`.
5. **(S5) Fix the `*)` arm.** Place the deferred-probe hold **after** the `hf_recycle_subject_gone` yield, and
   precede it with `_hf_resume_debt abandon --sid "$rcy_debt_sid" --why …`. Add T6(f) for the abandon and for
   the ordering.
6. **(S6) Narrow the deferral.** Defer only `RCY_PP=3`, and only when the watcher's listing rc was 124 or 137
   (log it in the NO-ANSWER line, and key the advisory on it). rc 2 and every other rc keep today's hold.
7. **(S7) Keep today's probe schedule.** Keep the 5 tries / 120 s unless K1 is `on` and proves, as in efficacy
   change 1.
8. **(S8) Narrow "no answer".** `noanswer` holds exactly when the bounded read's rc is 124 or 137. The identity
   returns rc 2 when `CC_TERM` is preset to anything other than `kitty`, or when `CC_REMOTE_PANE_TERM=off`.
9. **(S9) Keep K1 out of the focus gate.** Never consult K1 when the focus state is `yes`. Pass a no-cache flag
   from `_hf_focus_composer` into `recycle_composer_gate`.
10. **(S10) Close the ledger gaps.**
    - Any row for this pane with rc ≠ 0 and `ts ≥ read_started_at − HF_DRAFT_CACHE_LATE_SEND_S` (default
      ≥900) blocks K1.
    - Drop the window's first line.
    - Any unparseable line means no proof.
    - The oldest parsed `ts` must predate the largest lookback, or read the whole file.
    - Write a `pending` row before each send (it2-kitty `kt`, `cc_tui_rpc`).
11. **(S11) Bring W1 to parity.** W1 writes `empty` only when the placeholder rule did not fire on non-faint
    text. Add parity cases between `composer_from_screen` and `composer_content` to
    `tests/composer-parser-parity.bats` (non-faint `Try "…"`, labeled border, tall box, indented box) before
    K1 consumes `reader:"recon"` rows.
12. **(S12, S13) Add three K1 clauses.**
    - `read_ended_at − read_started_at ≤ 2 s`.
    - The session transcript's mtime ≤ `read_started_at`.
    - The live lstart of `HF_KID_PID` is re-read at K1 time and still equals `HF_KID_PID_LS`.
13. **(S14) Make the kill switches monotone and file-backed.**
    - File-backed modes for K1 and for `--only`.
    - `off` from any source wins over `on` from any other.
    - `--only` is off whenever `kitty-offpath.mode` is off.
14. **(S15) Fix the falsifier.**
    - Deduplicate pairs per (pane, claude lstart, cache `read_started_at`).
    - State the criterion over occupied reads: at least 30 distinct `fresh=occupied` pairs with 0
      `k1=proves`, plus at least 50 distinct proves aged 300 s or more.
    - Emit pairs from W1's per-pass reads, evaluated against the prior file before it is overwritten.
15. **(S16) Test hygiene.**
    - Suites that do not opt in pin `HF_KITTY_OFFPATH=off`, or the identity refuses to run under a test marker
      unless `HF_KID_PS_BIN` is set.
    - Lint every new event and line text against `classify._CLASSES`.
    - Correct T4 and T9, and the suite counts.
    - At the `on` default flip, run every suite that reaches `hf_remote_pane_term`, `pane_proof` or `__recycle`
      under `/bin/bash` 3.2.
16. **(S17) Apply the minor items above.**
