---
status: in-progress
---

# CLOSE_RESUME_CUSTODY — a close is a debt until the resumed session is proven alive

Scope (frozen): (0) recover session d754cab6 in a new pane and establish the fate of the other four
sessions the 2026-09-28 23:10Z upgrade mover queued; (1) name the mover; (2) make every automated
close→resume path custody-tracked (a close is a DEBT until the resumed session is PROVEN alive);
(3) a failed or unverified resume is retried in a NEW pane with the SAME session id, and if that
fails it is filed as a `cc-backlog needs` row with the exact resume command plus a page — never a
log line only; (4) the mover refuses to /exit without a verified relaunch surface and re-checks it
between exit and relaunch; (5) bats cases per path for (a) new-pane retry with the same sid, (b)
second failure files a runnable row, (c) mover refuses without a verified surface; existing suites
stay green.

Operator ask (verbatim): "dedicated /handoff such that anytime we do a /limit-recover (or however
we executed) that it's not fire and forget such that if a close and resume fails on the resume, we
dont have hidden closed out sessions that we dont know are abandoned."

## Phase 0 — Agent Team orchestration

| Wave | Locus | Why |
|---|---|---|
| W0 recovery + recon | **L** (lead) | Customer session first; recovery is 3 commands. Recon ran as a 7-agent read-only workflow (`/tmp/crc-research/*.md`). |
| W1 implementation (4 disjoint file sets) | **T** (4 named teammates, own worktrees) | This lead IS already a dispatched session (fired by claude-infrastructure-918), so a further `/handoff` per wave would only add a hop. The four sets share one CLI contract (§2) and no file. |
| W2 integration, full suites, /ship, converge | **L** | Merge order + gate + land need the synthesis. |

Lead context budget: stop taking new work at ~60% fill; succession = `handoff-fire.sh --recycle`
with this doc as the brief (everything of value is here and in commits).

Teammates (W1), one worktree each, branched from this branch after the plan commit:

| Teammate | Files (sole owner) |
|---|---|
| `crc-core` | `bin/cc-resume-debt` (new), `tests/cc-resume-debt.bats` (new) |
| `crc-recycle` | `scripts/handoff-fire.sh` (recycle foreground + `__recycle` watcher only), `tests/handoff-recycle-custody.bats` (new) |
| `crc-mover` | `scripts/limit-recover/lr-upgrade.sh`, `tests/lr-upgrade-custody.bats` (new) |
| `crc-surface` | `scripts/boot-resume-launch.sh`, `scripts/limit-recover/lr-reset-poller.sh` (sweep call only), `hooks/operator-readout.sh` (stranded line), `tests/boot-resume-launch.bats` (state isolation fix + cases), `tests/operator-readout-stranded.bats` (new) |

## 1. Incident record (2026-09-28, UTC) — W0 findings

**The mover** is the launchd daemon `com.reso.lr-reset-poller` (`scripts/limit-recover/lr-reset-poller.sh`,
StartInterval 600). Every tick runs `lr-upgrade.sh --auto-enqueue` (lr-reset-poller.sh:963-970) and
detaches `lr-upgrade.sh --drain` (:939-957). Activation 47 invoked none of it: it only flipped the
launcher pin (`~/.zshrc _bin` → `.claude-284`), which `bin/cc-claude-bin` reads and `lru_census`
(lr-upgrade.sh:495-572) compares against, so every idle 2.1.280 row became `disp=upgrade`.
`cc-lr upgrade` was not in the chain (requests were `auto-upgrade-*.json`, `requested_by:"poller-auto"`).

- 23:10:29 `poller.log:5654` — `UPGRADE-AUTO queued: 405(d754cab6) 838(ddd154a9) 842(46bc0436) 845(e0487c53) 849(8ea01453)`; drain pid 17181.
- 23:12:11 `lru_drive` → `handoff-fire.sh --recycle --same-account --await` (lr-upgrade.sh:1188-1190) typed `/exit` (hf:13455); claude 22651 exit 0 at 23:12:24.
- ≤23:12:43 kitty window 405 was destroyed (closer unknown); its tty ttys005 was reused by a NEW window 928 (operator's session bb4c628b).
- The watcher's `at_shell` is tty-only (`pane_cc_state`, hf:4042) so it "CONFIRMED a shell" on a reused tty; nothing re-enumerated the pane before the writes (hf:7602-7605); both writes failed → `recycle-dead` row (hf:7610) + `hf_alarm` record whose push timed out (`refused-rc124`; desk role points at dead pane 672).
- lr-upgrade then retyped blind into `-s 405` ×4 (`|| true`, lr-upgrade.sh:1212), and its proof `lru_resumed_on` (lr-upgrade.sh:1092-1102 → `lr_resume_procs`, lr-lib.sh:482) accepted ANY `--resume d754cab6` process on the box — the operator's out-of-pane rescue (`/tmp/bottle-session-recover.sh`, 23:21:19, pid 34997, died by HUP 23:25:04) — and wrote `verdict:"upgraded"`. Its mail went to the literal address `poller-auto` (exit 3, swallowed).
- The same class had already stranded pane 906 / 6b075742 at 13:28Z that day, also unsurfaced.

**Fates (verified 23:30Z):** 405/d754cab6 STRANDED → recovered by this session at 23:38:52Z via
`boot-resume-launch.sh next2 <wt-pool-2> d754cab6…` (capacity gate admitted on budget expiry), now
LIVE in pane 932 on 2.1.284 (`cc-find d754cab6` → `932 … LIVE`); inbox notice left. 838, 842, 845,
849 are alive on 2.1.280, never moved: the operator parked their requests in
`~/.reso/limit-recover/upgrade-queue.parked-20260928/` and touched `upgrade-auto.off`. Re-arming
that queue is the operator's call and should wait for this work to land.

## 2. Design

### D1 — one debt ledger, the custody engine, a sibling store
`bin/cc-custody` is reused unchanged against `CC_CUSTODY_DIR=~/.claude/autonomy/resume-debt`.
**Why a sibling store, not the dispatch store:** every consumer of the dispatch store (wrap-ledger
`CUSTODY_OPEN`, completion-assert, the session-continue wake floor, operator-readout) scopes rows by
cwd and treats an unattributable row as the reader's own debt. A daemon-owned resume debt keyed on the
subject's worktree would turn the NEXT innocent session in that worktree 🔧 and contradict its done-claim
— the alarm-polarity defect backlogs a9ede190ee3b/9581119669f9 already removed once. Rich per-debt
state lives in a sidecar `meta/<sid>.json` beside the custody rows.

### D2 — the contract: `bin/cc-resume-debt`
```
cc-resume-debt open   --sid S --cfg CFG --cwd C [--pane P] [--account A] [--by WHO] [--why TEXT]
                      → prints marker `resume:<sid>:<epoch>`; idempotent per sid (an open debt is reused)
cc-resume-debt prove  --sid S [--hold N]        → rc 0 iff S is LIVE now AND still LIVE N s later
cc-resume-debt discharge --sid S --why TEXT     → return the open debt (rc 0 even if none)
cc-resume-debt abandon   --sid S --why TEXT     → abandon (the close never happened)
cc-resume-debt step   --sid S                   → advance ONE state transition, never blocks >hold
cc-resume-debt settle --sid S [--wait N]        → loop step until terminal (proven | escalated)
cc-resume-debt sweep                            → one step for every open debt (poller backstop)
cc-resume-debt surface --pane P                 → rc 0 iff pane P is enumerated by the terminal now
cc-resume-debt list [--open] [--escalated] [--json]
```
**Proof** = `cc-find <sid>` prints a row whose liveness column is `LIVE` (registry pid + lstart
match — a nested or out-of-pane process is refused registration, so it cannot satisfy this), read
twice `CC_RESUME_DEBT_HOLD_S` (15) apart. Point-in-time argv matches are NOT proof (the incident).

**State machine** (in `meta/<sid>.json.state`): `open` → (proof) `proven` [discharge] ·
`open` + age ≥ `GRACE_S` (240) → `retrying`: relaunch in a NEW window with the SAME sid via
`CC_RESUME_DEBT_RELAUNCH` (default `bash ~/.claude/scripts/boot-resume-launch.sh <acct> <cwd> <sid>`),
attempt recorded · `retrying` + proof → `proven` · `retrying` + `WAIT_S` (180) elapsed or relaunch
rc≠0 → `escalated`: ONE `cc-backlog needs` row (project `claude-infrastructure`, session vars
unset, title carries the full sid + mover + run stamp, `--run` = the same relaunch command, which
starts with `bash`, needs no stdin and spawns its own window) and one page (`cc-notify --page`,
bounded, verdict recorded). `escalated` stays OPEN: a later proof discharges it and closes the
backlog row (`cc-backlog done <id> --evidence …`). Callers that already know the in-place relaunch
failed call `settle` directly, which skips the grace.

### D3 — surface verification (the mover and the recycle watcher)
- **Before /exit** (lr-upgrade `lru_drive`): refuse with verdict `skipped` + reason
  `relaunch-surface-unverified` unless `cc-resume-debt surface --pane P` passes.
- **Between exit and relaunch** (handoff-fire `__recycle`): run `pane_enumerated` immediately before
  the relaunch writes and again after a write failure; `absent` ⇒ `recycle-dead` with detail
  "pane vanished between exit and relaunch" (distinct from a read-back failure).
- **Retype loop** (lr-upgrade): surface check before every retype; absent ⇒ stop retyping.
- Proof replaces `lru_resumed_on`'s pane-agnostic argv match for the `upgraded` verdict.

### D4 — wiring per path
| Path | Opens debt | Discharges | On failure |
|---|---|---|---|
| handoff-fire `--recycle` (all callers: lr-upgrade, lr-handoff `--in-place`, lr-fleet, self-recycle) | foreground, just before `/exit` (hf:13455) for the source sid; abandon if `/exit` never sent | `recycle-engaged` (either oracle) | every `recycle-dead` arm → `cc-resume-debt settle --sid` (new window, same sid; then backlog+page) |
| lr-upgrade `lru_drive` / `lru_switch_bg_drive` | bg-drive opens its own (it exits via `claude stop` + ^C) | proof | bare shell / surface gone / unproven ⇒ `settle` |
| boot-resume-launch (boot-resume, /resume-sessions, settle's own relaunch) | after a successful launch, unless `CC_RESUME_DEBT_SETTLING=1` | proof via sweep | sweep escalates |
| lr-reset-poller tick | — | — | `cc-resume-debt sweep` every tick (backstop if a watcher died) |
| operator-readout | — | — | itemised `⚠ N stranded session(s)` line with each `▶ cc-do <id>` |

Not a close→resume path (checked, no change): lr-handoff REPLACE-in-place (verifies the successor
before self-close), lr-transplant, lr-fire-resume / reso-resume-one (engines, called inside a debt).

## 3. Open items / known issues
- Who destroyed kitty window 405 within ~19 s of a clean `/exit` is unknown (kitty is set to keep a
  window on program exit). The design no longer depends on the answer.
- `tests/boot-resume-launch.bats` ran the REAL capacity gate against live state (no
  `CC_ADMIT_STATE_DIR`/`CC_ADMIT_IDL`), spending the production refusal budget; fixed in W1 (`crc-surface`).
- Trunk red outside this diff: `tests/skill-listing-budget.bats` cases 1+5 (skills/launch-film, f91e3681d).
