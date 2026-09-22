<!-- arm A = claude-sonnet-5 @max · brief T2-recycle-goal · raw worker output, verbatim -->

# How `scripts/handoff-fire.sh --recycle` carries a predecessor's live `/goal` onto the successor

Repository snapshot: `/tmp/o55probe-repo-47c3317eb` (sha `47c3317eb`). All line numbers below were read directly at that sha; where a citation elsewhere in the repo names a different line, I read that location too and report what is actually there.

## 1. The read — decision function, oracle, and the store it reads

The inheritance **decision** is made by `inherit_recycle_goal()`, defined at `scripts/handoff-fire.sh:5840`:
```
5840:inherit_recycle_goal() { # $1=predecessor-sid → always 0
```
Its return contract is stated in its own header comment, `scripts/handoff-fire.sh:5836`: *"Mutates FIRE_GOAL; always 0 (inheritance must never fail a recycle)."* The function body (`:5840-5855`) confirms this — every branch (opt-out, no predecessor, terminal/absent goal, failed validation, success) ends in `return 0`; the only observable effect is whether the global `FIRE_GOAL` variable ends up populated.

It obtains the predecessor's condition by calling the **oracle** `goal_live_for_sid()`, `scripts/handoff-fire.sh:5845`:
```
5845:  _inh_cond="$(goal_live_for_sid "$1")" || return 0
```
`goal_live_for_sid()` is defined at `scripts/handoff-fire.sh:5809-5833`. What it reads:

- **Directory roots searched**: `CC_PROJECTS_DIRS`, iterated at `:5814` (`for pdir in $CC_PROJECTS_DIRS`). Its default is set once, at `scripts/handoff-fire.sh:416`:
  ```
  416:CC_PROJECTS_DIRS="${CC_PROJECTS_DIRS:-$HOME/.claude/projects $HOME/.claude-next/projects $HOME/.claude-secondary/projects $HOME/.claude-tertiary/projects $HOME/.claude-quaternary/projects}"
  ```
  i.e. five account-scoped project roots, space-separated.
- **How a transcript is located inside them**: for each `pdir`, `find "$pdir" -name "$sid.jsonl" -type f` (`:5829`), inside a `while IFS= read -r hit` loop (`:5816`) — a nested lookup, not a flat `$pdir/$sid.jsonl` guess, because (per the sibling function `transcript_for_sid`'s comment, `:4666-4668`) "Claude Code stores transcripts one level deeper, under a per-project slug."
- **Record type/shape treated as the answer**: a transcript line whose top-level JSON has `"type":"attachment"`, whose `.attachment.type` is `"goal_status"`. The jq filter is at `:5818-5819`:
  ```
  5818:      rec="$(grep -a 'goal_status' "$hit" 2>/dev/null | jq -rc --slurp '
  5819:        [ .[] | select(.type=="attachment") | .attachment | select(.type=="goal_status") ] | last // empty' 2>/dev/null)" || continue
  ```
  The record carries boolean `sentinel`/`met`/`failed` and a string `condition` field (consumed at `:5823-5824`).
- **Which record wins when there are several**: the *temporally last* `goal_status` attachment in a given file wins — `| last // empty` at `:5819`. Across multiple candidate files (nested-project duplicates of the same sid, or successive `pdir`s), the comment at `:5821-5822` states the rule explicitly: *"LAST record wins in both directions: a terminal goal (met/failed/cleared) inherits nothing, and this transcript IS the answer — stop searching other dirs either way."* Mechanically this is `return 1` immediately on a terminal record (`:5827`) or `return 0` immediately on a live one (`:5825-5826`) — the **first** `hit` file that contains *any* `goal_status` record decides the outcome and the search stops; only a hit with **no** `goal_status` records at all (`[ -n "$rec" ] || continue`, `:5820`) causes the search to keep going.

**How the predecessor's identity is obtained**: `rcy_old_sid="$(cc_sid_for_pane "$SID")"`, `scripts/handoff-fire.sh:12524` — called on the *current* (about-to-be-recycled) pane, before anything is typed into it. `cc_sid_for_pane()` is defined at `scripts/handoff-fire.sh:4955`; its tail (read at `:4988-4997`) matches a live process to the pane by its `ITERM_SESSION_ID` env var (`:4989-4992`) and then extracts that process's own `"sessionId"` field out of its transcript file (`:4994`) — i.e. it reads the predecessor's identity off its *own live process*, not off a stored pointer.

## 2. Which library is, and is not, involved

`hooks/lib/goal-state.sh` ships `goal_live_condition()` (`hooks/lib/goal-state.sh:60-73`), which is the general-purpose "is this transcript's goal live?" predicate used elsewhere in the tree. **The recycle path does not call it.** `scripts/handoff-fire.sh` defines its own, separate function, `goal_live_for_sid()` (`:5809-5833`), and says so explicitly in the comment immediately above it, `scripts/handoff-fire.sh:5801-5808`:
```
5801:# GOAL INHERITANCE oracle (2026-08-10). Reads the PREDECESSOR session's transcript and prints its
5802:# LIVE goal condition — the last goal_status ATTACHMENT with met==false and not failed. Twin of
5803:# hooks/lib/goal-state.sh::goal_live_condition (the SSOT for the record dictionary); duplicated
5804:# here deliberately: this file resolves the transcript BY SID across CC_PROJECTS_DIRS with the same
5805:# nested-project `find` goal_armed_for_pane uses, and adding a cross-tree source seam to the fire
5806:# path is a worse trade than 15 mirrored lines. grep narrows first (a bare jq over a multi-MB
```
So this is a **deliberate, named duplication**, not an oversight — the stated reason is that `goal_live_condition` takes an already-resolved transcript *path* (`hooks/lib/goal-state.sh:60`: `goal_live_condition() { # $1 = transcript path`) whereas the recycle path needs to resolve a transcript from a bare *sid* across `CC_PROJECTS_DIRS`, the same resolution `goal_armed_for_pane` (same file, `:5774`) already needs, so the author kept it local rather than adding a cross-file dependency to the fire path.

**Interface difference**: `goal_live_condition($1=path)` vs. `goal_live_for_sid($1=sid)` — confirmed by their respective signature comments (`hooks/lib/goal-state.sh:60` vs. `scripts/handoff-fire.sh:5809`).

**Implementation difference — hardening present in one, absent in the other**: `goal-state.sh` wraps its grep in a dedicated helper, `_goal_grep()` (`hooks/lib/goal-state.sh:52-58`), specifically to separate three grep outcomes (match / no-match rc-1 / real-error rc≥2) rather than let a pipefail'd caller conflate "no goal_status lines at all" with "unreadable file." The header explains the bug this exists to prevent, `hooks/lib/goal-state.sh:34-42`: *"Both readers below were written as `grep … | jq …` and both consumers run `set -o pipefail`… `goal-inert-watch.sh` logged `goal-unreadable` 375× for a transcript it had read perfectly."* `goal_live_for_sid()` does **not** use `_goal_grep` — it calls a bare pipe directly, `scripts/handoff-fire.sh:5818`: `` grep -a 'goal_status' "$hit" 2>/dev/null | jq -rc --slurp '...' ``.

What that absence does or does not change: reasoning from the code actually read (I did not check whether `handoff-fire.sh` itself runs under `set -o pipefail`, so this is derived from the two lines directly involved, not observed at runtime) — on a truly-empty grep match, `jq --slurp` still receives valid (empty) input and exits 0, producing no output; `rec` then reaches `[ -n "$rec" ] || continue` at `:5820` regardless of whether the preceding `|| continue` at `:5819` fired first. Both paths land on the same `continue`. So for the common case this brief is about — a predecessor that never armed a goal — the missing hardening does **not** change the outcome, because the caller's own `[ -n "$rec" ]` check is a second line of defense the `goal_live_condition` call sites don't uniformly have. Both functions do share one hardening: filtering on `.type=="attachment"` to exclude the assistant's own prose mentioning goals — `hooks/lib/goal-state.sh:25` ("a bare `grep goal_status` matches the assistant's own PROSE about goals — 6 hits where the truth was 1") and `scripts/handoff-fire.sh:5807-5808` ("`type==\"attachment\"` then drops the assistant's own PROSE about goals (measured: 6 grep hits where the truth was 1)") — identical measurement, independently re-stated.

## 3. Precedence vs. an explicit `--goal`

Mechanically, "explicit wins" is `inherit_recycle_goal()`'s very first guard, `scripts/handoff-fire.sh:5842`:
```
5842:  [ -z "${FIRE_GOAL:-}" ] || return 0
```
If `FIRE_GOAL` is already non-empty when this function runs, it returns immediately and does nothing further — it never even calls the oracle.

Besides the `--goal` CLI flag (`scripts/handoff-fire.sh:8950`: `` --goal) FIRE_GOAL="${2:?--goal needs a condition}"; shift 2 ;; ``), the **environment variable `FIRE_GOAL` itself** trips the identical guard, because that is how the variable is seeded at script start, `scripts/handoff-fire.sh:508`:
```
508:FIRE_GOAL="${FIRE_GOAL:-}"                       # --goal: MESSAGE 2, armed AFTER engagement (arm_goal)
```
This is a plain `:-` default-substitution: if the process's environment already carries a `FIRE_GOAL` variable, that value survives untouched. The file documents this as intentional at `scripts/handoff-fire.sh:34`: `` #                       above; DoD at <path>'. Env equivalent: FIRE_GOAL. `` — i.e. running `FIRE_GOAL='<condition>' scripts/handoff-fire.sh --recycle …` trips the same "explicit wins" branch as `--goal '<condition>'` ever passing through the flag parser at all.

## 4. The opt-out

Exact name: `CC_RECYCLE_GOAL_INHERIT`. Exact comparison, `scripts/handoff-fire.sh:5843`:
```
5843:  [ "${CC_RECYCLE_GOAL_INHERIT:-1}" != 0 ] || return 0
```
Default: unset or empty ⇒ `${VAR:-1}` substitutes the literal string `1`, so inheritance is **on by default**. The comparison is a POSIX string inequality against the literal `0`. Consequence: **only** the exact string `CC_RECYCLE_GOAL_INHERIT=0` disables inheritance. Any other value — `false`, `no`, `off`, `2`, or an explicitly-set empty string (which `:-` treats as unset and substitutes back to `"1"`) — leaves the comparison `!= 0` true, so inheritance stays **on**. This matches the header's own summary at `scripts/handoff-fire.sh:5837`: `` # inherited condition re-runs the SAME pre-arm validation as a passed one … CC_RECYCLE_GOAL_INHERIT=0 opts out ``.

## 5. Terminal or absent predecessor goals

Inside `goal_live_for_sid()` (`scripts/handoff-fire.sh:5809-5833`), the decision on a found record is at `:5823-5827`:
```
5823:      if [ "$(printf '%s' "$rec" | jq -r '(.met // false) or (.failed // false)' 2>/dev/null)" = "false" ]; then
5824:        printf '%s' "$rec" | jq -r '.condition // ""'
5825:        return 0
5826:      fi
5827:      return 1
```
- **Met or failed (terminal)**: `.met or .failed` is true, so the `if` is false, falling through to `return 1` (`:5827`) — the function fails **immediately**, and per the comment at `:5821-5822` ("stop searching other dirs either way") the search **stops**; it does not check other project roots for a possibly-different transcript of the same sid.
- **Never armed (absent)**: no `goal_status` record exists in the matched file at all, so `rec` is empty; `[ -n "$rec" ] || continue` at `:5820` fires and the search **keeps looking** — next `hit`, then next `pdir` — until either a real record is found somewhere or all five roots (`:416`) are exhausted, at which point the function falls out of the `for` loop to its final statement, `return 1` (`:5832`).

Either way `inherit_recycle_goal()` sees a non-zero return from the oracle and takes its own no-op branch, `scripts/handoff-fire.sh:5845-5846`:
```
5845:  _inh_cond="$(goal_live_for_sid "$1")" || return 0
5846:  [ -n "$_inh_cond" ] || return 0
```

## 6. Validation of an inherited condition

The validator is `check_goal_arm()`, `scripts/handoff-fire.sh:5734-5767`. It is invoked with **no arguments** at `scripts/handoff-fire.sh:5848` (`if check_goal_arm; then`), immediately after `inherit_recycle_goal` has already written `FIRE_GOAL="$_inh_cond"` at `:5847` — so what it "reads" is the same global `FIRE_GOAL` the CLI `--goal` path populates, via `scripts/handoff-fire.sh:5735`: `local cond="${FIRE_GOAL:-}"`. Its own header states the reuse is deliberate, `:5732-5733`: *"Pre-fire validation of a --goal condition. Runs beside the payload gates, BEFORE any side effect, so a malformed goal costs a refusal rather than a half-fired pane."* (I confirmed one call site directly, at `:5848`; the comment implies a second, general call site alongside "the payload gates" for the plain `--goal` flag, which I did not independently locate.)

It rejects three shapes, each with a stated mechanical reason:
1. **A newline in the condition** (`:5745-5749`) — rejected because the arming paste (`/goal $cond`) is atomic but its terminating Enter/CR is not selective: *"the rest would be stranded in the composer as an unsent fragment."*
2. **A condition starting with `/`** (`:5754-5757`) — rejected because it would be pasted as `/goal /whatever…`, so CC would parse a **second** slash command instead of arming a goal.
3. **Length over `GOAL_MAX_CHARS` (default 4000, `:5735`)** (`:5759-5765`) — rejected because *"the harness HARD-CAPS a goal condition at ${limit} and replies '…' WITHOUT setting anything (measured 2026-08-08)."*

On any of these, `check_goal_arm` itself calls `emit_fire_refusal` with a distinct code (`payload-goal-arm-multiline` `:5748`, `payload-goal-arm-slash` `:5756`, `payload-goal-arm-cap` `:5763`) before returning 1. `emit_fire_refusal()` is defined at `scripts/handoff-fire.sh:758-760` and delegates to `emit_fire_event refused …` (`:759`) — so **a durable record of the refusal is written**, via the general fire-event log, but it is written generically as "a `--goal` condition failed pre-arm validation" — nothing in `check_goal_arm` or `emit_fire_refusal`'s arguments distinguishes an inherited condition's failure from an explicitly-typed `--goal`'s failure.

What happens to the condition and the recycle when `check_goal_arm` refuses: back in `inherit_recycle_goal`'s `else` branch, `scripts/handoff-fire.sh:5850-5853`:
```
5850:  else
5851:    echo "⚠ predecessor holds a LIVE goal but its condition fails pre-arm validation — NOT inherited; re-arm it yourself with /goal in the relaunched session" >&2
5852:    FIRE_GOAL=""
5853:  fi
```
`FIRE_GOAL` is reset to empty — inheritance is silently dropped — and the function still returns 0 (`:5854`), so **the recycle itself is never blocked** by a failed inheritance. The refusal is announced only via this `echo … >&2` (`:5851`) — readable by whoever is attached to the pane's stderr at the moment `--recycle` runs (this executes synchronously in the predecessor's own process, before `/exit` is typed). Unlike `check_goal_arm`'s own refusal paths, this specific outer message is **not** passed to any `emit_*` function — there is no separate durable record of "an inherited goal was dropped for validation reasons" as distinct from "a `--goal` condition was dropped for validation reasons"; only the latter, generic record exists (via `check_goal_arm`'s own `emit_fire_refusal` calls).

## 7. Where in the recycle flow the call sits, and the transport path

**The single call site**: `scripts/handoff-fire.sh:12540`, inside an if/else, `:12535-12541`:
```
12535:  if [ -n "$RESUME_LAUNCHER" ]; then
12536:    # A same-uuid --resume carries an UNMET goal with it (recycle-100p §2.3, measured on 2.1.220);
12537:    # inheriting it here would arm the same condition twice in one session.
12538:    FIRE_GOAL=""
12539:  else
12540:    inherit_recycle_goal "$rcy_old_sid"
12541:  fi
```
**The branch that deliberately skips inheritance, and why**: when `$RESUME_LAUNCHER` is set (a same-uuid `--resume`, not an ordinary new-sid recycle), `FIRE_GOAL` is forced empty instead (`:12538`) — the comment (`:12536-12537`) gives the reason directly: a `--resume` carries its own unmet goal forward already, so re-arming via inheritance here would arm the *same* condition **twice** in one session.

**Immediately before** the call site: `rcy_old_sid="$(cc_sid_for_pane "$SID")"` (`:12524`) resolves the predecessor identity, followed by the explanatory comment block `:12525-12534` (goal is session-scoped and dies with `/exit`; default precedence rules restated). **Immediately after**: the if/else closes at `:12541`, then `RCY_T0="$(date -u +%FT%T)"` (`:12542`, a resume-mode engagement baseline) and `pin_term_verdict_for_watcher` (`:12543`) — all still in the predecessor's own process, still before `/exit` is typed (the file's own ordering rule is stated at `:12508`: *"ORDER IS LOAD-BEARING: watcher FIRST (heartbeat-verified), /exit LAST"*).

**The transport path** — how the resolved value actually reaches the successor:
1. `inherit_recycle_goal` (or the resume-skip branch) leaves the final value sitting in the **predecessor process's** `FIRE_GOAL` variable.
2. Before `/exit` is typed, the predecessor spawns a session-detached watcher via `detach(...)`, `scripts/handoff-fire.sh:12628`, which re-execs this same script with a `__recycle` dispatch and a positional argument list that includes `"$FIRE_GOAL"` alongside `"$rcy_old_sid"`, `"$RECYCLE_MARKER"`, etc. `detach()` (not `nohup`) is used specifically so this watcher survives the predecessor's own `/exit` (comment at `:12511-12515`).
3. Inside that re-exec'd watcher, the value is read back positionally: `scripts/handoff-fire.sh:7158`:
   ```
   7158:  FIRE_GOAL="${8:-}"                               # --goal condition to re-arm as MESSAGE 2
   ```
4. The watcher types the relaunch line into the successor pane, then polls for **process alive** and, distinctly, for **engagement** (a real assistant turn, via `recycle_engaged`/`resume_engaged`, `:7358-7359`) — arming is gated on the latter, not the former.
5. Only once engagement is confirmed, `scripts/handoff-fire.sh:7365`:
   ```
   7365:        arm_goal "$IT2" "$RSID" "$FIRE_GOAL"
   ```
   `arm_goal()` (`scripts/handoff-fire.sh:5864-5918`) pastes `/goal $cond` into the successor's pane as a second message ("MESSAGE 2"), then polls the **successor's own transcript** for a matching `goal_status` attachment via `goal_armed_for_pane()` (`:5774-5799`, called in `arm_goal`'s loop at `:5906`) before declaring `verdict=set` (`:5907`).

So "at what moment in the successor's life it is armed": strictly **after** engagement is positively confirmed from the successor's own transcript — never at boot, never merely on process-alive — matching both `inherit_recycle_goal`'s own success message, `scripts/handoff-fire.sh:5849` (*"re-arming on the successor after engagement"*), and the watcher's comment at `:7361-7364` explaining why re-arming is necessary at all: a recycle mints a brand-new session id, and a `/goal` Stop hook is session-scoped, so without this the successor would silently start with no goal.

## Citation audit

Every line-number citation to `inherit_recycle_goal` (or the machinery immediately around it) that I found anywhere in this repo is stale relative to the code's current position (`inherit_recycle_goal` def `:5840`, oracle def `:5809`, call site `:12540`). None resolves exactly; one is close.

| Citing location | Cited line(s) | What is actually there | Verdict |
|---|---|---|---|
| `CLAUDE.global.md:223` | `scripts/handoff-fire.sh:4676-4684` | `transcript_for_sid()`, an unrelated stamp-recovery helper (read at `:4679-4694`) | Does not resolve |
| `hooks/goal-inert-watch.sh:36` | `scripts/handoff-fire.sh:4671-4688` | Same `transcript_for_sid()` region | Does not resolve |
| `scripts/handoff-fire.sh:4824` (the file's **own** internal summary comment) | `:5089, called at :11070` | `:5089` is mid-comment in an unrelated subagent-liveness (`stop_reason`) discussion (read at `:5080-5093`); `:11070` is inside worktree-pool `claim` logic (read at `:11060-11077`) | Does not resolve — self-citation, still wrong |
| `docs/research/backlog-pipeline-recon-2026-08-12/recon-wave.md:35` | `scripts/handoff-fire.sh:3778-3800` | Header/body of the unrelated `pane_cc_state()` cc-vs-shell discriminator (read at `:3773-3803`) | Does not resolve |
| `docs/plans/NONLIMIT_RESUME_LADDER.md:753` | `:4994-5009` | Tail of `cc_sid_for_pane()` running into the unrelated `live_teammates_of()` header (read at `:4988-5011`) | Does not resolve (adjacent supporting code, not the cited function) |
| `docs/research/voluntary-inplace-switch-2026-09-22/A03-precheck-healthy-source.md:96,348`; `A05-recycle-engagement.md:106` | `handoff-fire.sh:5805` (for `inherit_recycle_goal`) | Mid-comment inside `goal_live_for_sid`'s header block (read at `:5804-5805`) — 35 lines before the actual `inherit_recycle_goal` def at `:5840` | Closest found, but still not the function itself |
| Same two docs | "called `:11070`" / `:12406-12412` | The `as_tty_classified` pane→tty error-handling branch (read at `:12406-12412`), 128 lines before the real call at `:12540` | Does not resolve |

The one citation style that **does** survive drift is pattern-based, not line-based: `tests/handoff-goal-arm.bats:45` extracts the function by name — `` sed -n '/^inherit_recycle_goal() {/,/^}/p' "$HF" `` — which is immune to exactly the churn that stranded every numeric citation above.
