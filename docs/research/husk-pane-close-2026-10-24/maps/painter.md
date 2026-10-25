# Painter map — who writes a dead pane's screen/title, and why cc-pane-verdict and cc-husk-sweep disagree

Read-only investigation, 2026-10-24. Repo HEAD 7cdb9adae (worktree wt-cc-203953-20264). Every number is
labelled measured (with the command) or estimated (with the method). Pane 289 no longer exists at the
time of writing (`it2 session list --json | jq` lists 45 panes and none is 289), so cc-husk-sweep could
not be re-run against it live; its verdict is reconstructed from code and the custody store below.

## 1. Pane 289 timeline (measured)

Source: `jq 'select(.pane=="289")' ~/.claude/logs/pane-say.jsonl`, `grep 'pane=289' ~/.claude/logs/pane-close-retry.log`,
`grep 'targetPane":"289' ~/.claude/autonomy/custody/*.jsonl`.

| UTC | writer | what |
|---|---|---|
| 23:23:14Z | cc-pane-runner | fleet launch line `cd ~/Development/personal && … claude4 …` (detail row) |
| 23:23:41Z | custody | `open` pane 13 → 289, slug fire-evolve-short-C |
| 23:51:57Z | custody | `return` for the same marker: custody DISCHARGED |
| 23:53:36Z | **cc-pane-verdict via runner** | `DONE`, title `✓ done` (no sid), row 2 `⌘W closes it · last pane of a fullscreen window`. Runner detail: `claude4 exited 0 — guard: … refused (refused-fs) kitty window 289 … state=FS types=[4] onscreen=False` |
| 23:55:00Z | lead-crash-watchdog | rows `7555024a ended cleanly` + `uncommitted work in personal`; detail `reason: prompt_input_exit … dirty:138 · last close verdict: yes` |
| 23:55:00Z | **cc-pane-verdict via watchdog** | `CANTTELL`, `◆ check 7555024a` / `▶ cc-husk-sweep --pane 289` |
| 00:00:13Z | pane-close-retry | attempt 1: `REFUSED — /Users/chrisren/Development/personal holds 138 uncommitted change(s)` |
| 00:00:14Z | **cc-pane-verdict --recompute via reconciler** | `RESUME`, `⛔ resume 7555024a` / `✗ 7555024a stopped mid-task · 138 unsaved files` / `▶ cc-husk-sweep --resume --yes --pane 289` |
| 00:00Z–01:38Z | pane-close-retry | 21 attempts: 10 × gate-4 refusal, 11 × `rc=124 with no output` (no repaint on those, by design) |
| 01:45:55Z | pane-close-retry | `its tty was typed in since  — the operator owns it; row removed, never closed` (note: empty first_ts in the message) |

Three different states from three writers in 6.5 minutes, all through the "one writer". The last
one (RESUME) is false by the tool's own contract and by every fact on disk:

- the session's last assistant text said `Good to close: yes` (watchdog detail row above);
- custody was RETURNED at 23:51:57Z, before it exited (measured: `cc_pane_custody 289 1792884203` →
  `collected  fire-evolve-short-C  return  2026-10-24T23:51:57Z  13`);
- the 138 dirty paths are the shared checkout's (`git -C ~/Development/personal status --porcelain | wc -l` → 138,
  measured now), on branch `master` with no remote (`git remote -v` empty).

cc-husk-sweep's code on the same facts yields `COLLECTED` (cc-husk-sweep:562-563 overrides the RESUME that
verdict_of:517 derived from `dirty`), whose printed advice is "never resumed; close the pane"
(cc-husk-sweep:595) and whose resume loop skips it (cc-husk-sweep:608). So the painted ▶ command
`cc-husk-sweep --resume --yes --pane 289` would have done nothing — it violates the contract rule
"Every ▶ command is re-validated at paint time and must do what the row says"
(docs/research/husk-panes-2026-10-22/synthesis.md:268).

## 2. Every writer of a dead pane's screen or title

| # | writer | call site | what it decides from | screen | title |
|---|---|---|---|---|---|
| W1 | **bin/cc-pane-verdict** (direct mode) | bin/cc-pane-verdict:96-122 render, :152-153 tty clear+2 rows, :160-164 `kitty @ set-window-title --temporary` else OSC-2 | the `--state` its caller passes | yes | yes |
| W1r | **bin/cc-pane-verdict --recompute** | bin/cc-pane-verdict:69-93 | ONE cc-pane-close output line + pane-exit record + `--reason` | yes | yes |
| W2 | bin/cc-pane-runner → W1 | `_verdict` bin/cc-pane-runner:179-192, called only at :333 (refused-fs) and :338 (unreadable) with `--state ${_PV_STATE:-DONE}`; `_PV_STATE=NOTHING` from `_no_command` :618 | guard rc + text only; sid only from cc-registry/<pane>.json if written since launch (:189-190) — SessionEnd deletes that row on a clean exit, hence `✓ done` with no sid on 3 of 4 runner paints (panes 165, 282, 289) | via W1 | via W1 |
| W2b | bin/cc-pane-runner direct `_say` lines (bypass W1) | :102 `_fallback` `⚠ <why> · pane is an ordinary shell`; :291 `pane kept, not closed · recycle check unavailable`; :315 `fullscreen guard missing`; :334/:339 fallback when W1 failed; :372 `✗ launch failed (exit N) · ▶ cc-husk-sweep --pane N` | — | yes (stderr = the pane) | no |
| W3 | hooks/lead-crash-watchdog.sh → W1 | `paint_pane_verdict` :2036-2123, builds state in `pane_verdict_text` :1920-2035, calls W1 at :2102-2114 with `--state $pvs --guard $pvg` | death class + cause, `pane_work_state` (git porcelain + `origin/main..HEAD`, :1664-1671), lr facts (:1951-1966), teammate facts, custody **only in the crash branch** (:2010-2025), and — only when the block promised a close — `cc-pane-close --dry-run` (:2060-2098, predicate :2174-2186) | via W1 | via W1 |
| W3b | watchdog fallback raw write (bypass W1) | :2115 `printf block; printf '\033]2;%s\007' title > /dev/$tty` when W1 is missing/failed or `CC_PANE_VERDICT_TOOL=off` | same facts, old wording (`⛔ NOT A CLEAN EXIT`, `✅ CLOSED CLEANLY`) | yes (appends, no clear) | OSC-2 |
| W4 | scripts/pane-close-retry.sh (the pane-close reconciler, launchd com.claude.pane-close-drainer, every tick) → W1r | `drain_husk` :261-328; closer call :303-304; recompute :324-326 `--recompute --reason <row.reason> --closer-out "$out"` | the closer's first refusal line | via W1r | via W1r |
| W5 | Claude Code itself | exit text `Resume this session with: claude --resume <sid>` | — | yes | its own titles |
| — | not painters | bin/cc-husk-sweep (lists/resumes, never paints), bin/cc-pane-close (logs + stdout to its caller), scripts/lead-reconciler.sh (roster drift alarm, no pane I/O), bin/cc-resume-layout.sh:813/1391 (temporary layout markers on live panes only) | | | |

Searches that bound this list (measured): `git grep -n 'cc-pane-verdict' -- ':!docs' ':!tests'` → callers
only in bin/cc-pane-runner, hooks/lead-crash-watchdog.sh, scripts/pane-close-retry.sh;
`git grep -n -E "033\]|x1b\]" -- bin scripts hooks lib` → the only OSC title writers are
bin/cc-pane-verdict:164 and hooks/lead-crash-watchdog.sh:2115.

The contract (synthesis.md:259 "Only bin/cc-pane-verdict writes a dead pane's tty or title") is not
met: W2b and W3b still write directly. More important than the count of writers: **W1 has two
inputs that compute the state differently** (W1 direct from the caller's model, W1r from the closer's
first refusal), and each caller has its own model, so "one writer" is one renderer over three state
models.

## 3. The state models side by side

### cc-pane-verdict (contract states: DONE / RESUME / OWNED / NOTHING / CANTTELL)

- From W3 (watchdog, direct): stranded → RESUME+stranded (:1955); moved-live → DONE (:1961);
  retired teammate → DONE, or CANTTELL if mid-task (:1974-1979); retired-by-desk → DONE (:1992);
  **RECYCLE/clean exit → DONE, but CANTTELL if work is dirty or unlanded (:1996-1997)**; crash with
  custody collected → DONE (:2014); **crash with no custody → RESUME regardless of `Good to close`
  (:2018)**; crash with custody open → OWNED (:2024); crash teammate → CANTTELL (:2032); a DONE whose
  closer dry-run refuses → DONE (fullscreen/unreadable/stuck) or CANTTELL for any other refusal
  (:2071-2088).
- From W2 (runner): DONE (guard refused) or NOTHING (no command). No session facts at all.
- From W1r (reconciler recompute), bin/cc-pane-verdict:80-91:
  - exit record `claude_started=false && rc!=0` → NOTHING (:80-81)
  - closer said WOULD CLOSE / CLOSED / ALREADY CLOSED / NOTHING TO CLOSE → DONE (:84)
  - `remote control is down` or `fullscreen guard` → DONE (:85)
  - **`uncommitted change` → RESUME, unsaved=N (:86-87)**
  - `STRANDED` → RESUME+stranded (:88)
  - `nothing says session` → RESUME if `--reason crash`, else CANTTELL (:89)
  - anything else (identity, live job, window mismatch, no transcript) → CANTTELL (:90)
  - never produces OWNED, never reads custody, transcript, teamName, lineage or transplant.

### cc-husk-sweep (RESUME / DONE / UNKNOWN / TEAMMATE / COLLECTED / DUPLICATE / RECYCLED / MOVED / TRANSPLANTED)

Precedence, lowest to highest (bin/cc-husk-sweep:556-578): `verdict_of(close, work)` :516-519
(dirty/unlanded → RESUME; close=no → RESUME; close=yes & clean → DONE; else UNKNOWN) → COLLECTED if
custody discharged since transcript start (:562-563) → TRANSPLANTED (:564) → RECYCLED/MOVED lineage
(:567-568) → TEAMMATE (:569) → DUPLICATE for a sid two husks claim, unless already a never-class
(:575-578). UNKNOWN is resumed by `--resume` (:44, :609); COLLECTED/TEAMMATE/DUPLICATE/RECYCLED/MOVED/
TRANSPLANTED never are (:608).

## 4. Every input fact where they disagree

| # | input fact | cc-husk-sweep | cc-pane-verdict | code |
|---|---|---|---|---|
| D1 | **custody DISCHARGED (return/abandon) + dirty cwd** (pane 289) | COLLECTED — never resume, close the pane | W3 RECYCLE branch ignores custody → CANTTELL; W1r reads only the closer's gate-4 refusal → **RESUME** | sweep :562-563, :595, :608; watchdog :1995-2004 (no custody read; custody read only at :2010); verdict :86-87; closer gate 3 accepts custody :498 but gate 4 still runs :508-512 (no `skipwork`) |
| D2 | **`Good to close: yes` + dirty cwd** | RESUME (work outranks the word) | W3: CANTTELL; W1r: RESUME. And cc-pane-close itself passed gate 3 on this fact (`why=…Good to close: yes` :497) before refusing at gate 4 — a gate-4 refusal *implies* the session meant to end, yet W1r renders it as "stopped mid-task" | sweep :517; watchdog :1997; verdict :86-87; closer :497, :511 |
| D3 | **`Good to close: yes`, clean tree, then killed** (SIGTERM after finishing) | DONE | W3 crash branch: RESUME (`⛔ KILLED`) — the crash branch never reads `close` | sweep :518; watchdog :2005-2030 (close only goes into `detail` :2012) |
| D4 | `Good to close: no` or no close at all, clean tree | RESUME (no) / UNKNOWN (none) — both resumed by `--resume` | W3 RECYCLE: DONE → closer dry-run refuses "nothing says" → CANTTELL (:2085); W1r: CANTTELL, or RESUME iff the husk row's `reason` is `crash` (:89) | sweep :518, :609; watchdog :2060-2088; verdict :89 |
| D5 | **unlanded commits** (ahead of origin/main), clean tree | RESUME | W3 RECYCLE: CANTTELL (:1997); cc-pane-close checks porcelain only (:510-511) so W1r gets WOULD CLOSE/CLOSED → DONE and the pane closes | sweep :513-517; watchdog :1669-1670; closer :508-512; verdict :84 |
| D6 | trunk is not `origin/main` (e.g. ~/Development/personal: branch master, no remote) | `rev-list origin/main..HEAD` errors → reads `clean` (fail-open) | same in watchdog `pane_work_state` | sweep :513-514; watchdog :1669-1670 |
| D7 | custody OPEN | verdict unchanged (open "changes nothing", :54) | W3 crash: OWNED (:2024); W3 RECYCLE: not read; W1r: never OWNED (reconciler instead holds the row and does not repaint, pane-close-retry:294-296) | sweep :54, :563; watchdog :2023-2025; verdict :83-91 |
| D8 | teammate (`teamName` in transcript) | TEAMMATE (top precedence, never resumed) | W3 crash: CANTTELL (:2032), retired: DONE; closer gate 3 passes for a teammate but gate 4 still runs → dirty member worktree → W1r **RESUME with `▶ cc-husk-sweep --resume`**, which the sweep refuses | sweep :569, :608; closer :496, :508-512; verdict :86-87 |
| D9 | recycled / moved (handoffs `recycle-engaged`, pane-successor claim, later registration elsewhere) | RECYCLED→ / MOVED→ (never resumed) | W3: only lr facts (transplant tombstones) via `pane_lr_facts` (:1950-1966); a handoff recycle into another pane is RECYCLE class → DONE/CANTTELL by work; closer `moved_live` (:309, :500-501) skips gate 4 → DONE; no-live-copy → STRANDED → W1r RESUME+`cc-lr recover` | sweep :279-356, :567-568; watchdog :1950-1966; closer :500-505; verdict :88 |
| D10 | transplanted (lr tombstone names another store) | TRANSPLANTED→acct (never resumed) | W3 stranded → RESUME (`cc-lr recover`) / moved-live → DONE; W1r: STRANDED → RESUME | sweep :564, :608; watchdog :1955, :1961; verdict :88 |
| D11 | two husks resolve to one sid | DUPLICATE | no such state; each pane is painted on its own | sweep :575-578 |
| D12 | identity unresolvable by the watchdog registration (registry or scrollback names a sid) | resolves via registry/scrollback (:370-408) and gives a real verdict | closer gate 1 refuses ("no session registration…", :429) → W1r CANTTELL | sweep :358-411; closer :429; verdict :90 |
| D13 | which cwd | the transcript's last recorded `cwd` | W3: `LEAD_CWD` = the SessionStart hook's `$PWD`; closer: transcript cwd | sweep :556-558; watchdog :1610, :2309 (LEAD_CWD, default $PWD); closer :495 |
| D14 | dirty count is the whole shared checkout, not this session's paths | same (`git status --porcelain | wc -l`) | same in watchdog and closer | sweep :511; watchdog :1667; closer :510 — all three agree on the wrong number; they differ only in what they do with it |
| D15 | which fact wins in the closer's single answer | sweep reads every fact | W1r sees only the FIRST failing gate: gate 4 (dirty) masks gate 5 (fullscreen guard). Pane 289's runner had already been told refused-fs at 23:53:36Z; the reconciler never got that far | closer gate order :489-520; verdict :73-91 |
| D16 | husk row `reason` (drives :89) | n/a | `pcq_add` merges by kind+pane, so the LAST producer's reason wins: pane 289's runner row `reason=guard-fullscreen` (cc-pane-runner:332) was overwritten by the watchdog's `reason=ended` (watchdog :2141-2143) — estimated from the 23:53:36Z → 23:55:00Z order and pcq_add's merge (scripts/lib/pane-close-queue.sh:55-66) | |

The root shape: **cc-pane-verdict --recompute maps a closer REFUSAL to a session STATE.** The closer
answers "may I close this window now?"; its gates mix session facts (gate 3: did it mean to end),
safety facts (gate 4: is any work in the cwd at risk) and actuation facts (gate 5: guard). A gate-4
refusal says "the cwd is dirty" — it does not say "the session stopped mid-task", and it implies the
opposite, because gate 3 must already have passed. The contract's own RESUME definition is "the
session died mid-task, its work is at risk, and nobody else owns it" (synthesis.md:287) and its DONE
is "work saved or landed, custody returned, or Good to close: yes" (synthesis.md:278); pane 289 met
DONE twice over.

## 5. pane-say.jsonl, 14 days: RESUME painted where the sweep would say DONE/COLLECTED

Window: the log starts 2026-10-19T12:46:49Z (measured: `head -1 pane-say.jsonl | jq .ts`), and
cc-pane-verdict's first paint is 2026-10-23T04:02:33Z (measured), so pane-say covers 5.5 of the 14 days
for cc-pane-verdict. The remaining days are covered from lead-crash-watchdog.log.

**cc-pane-verdict paints, all time (measured: `jq -r 'select(.tool=="cc-pane-verdict")|.state' pane-say.jsonl | sort | uniq -c`):**
45 paints = 16 NOTHING, 16 DONE, 12 CANTTELL, **1 RESUME**. Zero unparseable lines (`jq -R 'fromjson? // "BAD"' | grep -c BAD` → 0).

By caller (measured by /tmp/painter-probe/callers.py: a cc-pane-runner or lead-crash-watchdog record on
the same pane within ±3 s names the caller, else it is the reconciler's recompute):

| caller | DONE | CANTTELL | NOTHING | RESUME |
|---|---|---|---|---|
| reconciler (W1r) | 8 | 11 | 16 | **1 (pane 289)** |
| watchdog (W3) | 4 | 1 (pane 289) | 0 | 0 |
| runner (W2) | 4 | 0 | 0 | 0 |

**Result: 1 of 1 cc-pane-verdict RESUME paints (100%) was a pane the sweep's logic calls COLLECTED** —
pane 289. There is no other RESUME paint to sample. The sample is one, so the rate is not a rate; what
it shows is that the only time W1r produced RESUME, it was wrong, and the mapping (:86-87) fires on
every dirty shared checkout, which is the common case for a fired peer in ~/Development/personal.

**Pre-cc-pane-verdict RESUME-equivalent paints (watchdog crash branch, "⛔ KILLED"/"<sid8> killed"),
2026-10-10..24** (measured: `awk 'substr($0,2,10)>="2026-10-10"' lead-crash-watchdog.log | grep 'pane verdict PAINTED' | grep -E 'killed \(|KILLED here'`):
12 paints. Their sweep-relevant facts (measured by /tmp/painter-probe/eval.py over transcripts,
custody store and watchdog registrations; custody state is as of NOW, not paint time):

| sid8 | pane | painted | last close | teammate | custody now | sweep logic (estimated) |
|---|---|---|---|---|---|---|
| 5b813b72 | 200 | 10-10 13:08 | no | yes | collected | TEAMMATE |
| 6cad6b17 | 313 | 10-11 22:00 | **yes** | no | - | DONE if clean, then MOVED→329 after 22:33 |
| b1f3a41e | 460 | 10-21 10:25 | **yes** | no | collected | DONE/COLLECTED |
| 4da72f17 | 27 | 10-21 10:25 | no | no | - | RESUME (agree) |
| 97dc902f | 464 | 10-21 10:26 | - | no | collected | UNKNOWN/COLLECTED |
| 443f8f8e | 462 | 10-21 10:26 | **yes** | no | collected | DONE/COLLECTED |
| c9bdd035 | 369 | 10-21 10:26 | **yes** | no | collected | DONE/COLLECTED |
| 7a4dd6b5 | 465 | 10-21 10:26 | - | no | collected | UNKNOWN/COLLECTED |
| 204106ae | 461 | 10-21 10:26 | - | no | collected | UNKNOWN/COLLECTED |
| 95d2333c | 453 | 10-21 10:26 | no | no | collected | RESUME/COLLECTED |
| 942942fc | 463 | 10-21 10:26 | - | no | collected | UNKNOWN/COLLECTED |
| 570d3917 | 85 | 10-22 04:19 | **yes** | no | collected | DONE/COLLECTED |

- 5 of 12 (measured, column "last close") had written `Good to close: yes` before they were killed; the
  crash branch (watchdog :2005-2030) painted RESUME/OWNED for all five because it never reads `close`
  (fact D3). Whether the sweep would have said DONE depends on the work state at that moment, which
  cannot be reconstructed (estimated, not measured).
- 1 of 12 was a teammate (sweep: TEAMMATE). That paint predates the current teammate→CANTTELL rule.
- 10 of 12 now read COLLECTED, but custody is read as of today; the 2026-10-21 mass-SIGTERM nine were
  resumed by `cc-husk-sweep --resume` at 17:03-17:04Z that day (measured: ~/.claude/logs/husk-sweep.jsonl,
  8 rows, verdict `resumed`), so at that time the sweep did NOT read them as COLLECTED — custody was
  presumably still open (estimated). Not a disagreement at paint time; it shows custody is a
  time-varying fact that only the sweep re-reads live and only W3's crash branch reads at all.
- The watchdog log headline cannot tell a RESUME paint from an OWNED one (both start "killed (…)"),
  so "RESUME" here is an upper bound.

**A second recompute defect in the same log (historical, fixed):** pane 165 flipped DONE ↔ CANTTELL six
times on 2026-10-23 (measured: `jq 'select(.tool=="cc-pane-verdict" and .pane=="165")'`). Each CANTTELL
(13:30:40Z, 15:16:20Z, 19:04:54Z, 20:37:01Z …) follows a closer `rc=124` with empty output
(`grep 'rc=124:  — row kept' pane-close-retry.log` → 7 lines, last 2026-10-23T20:36:49Z): an empty answer
was recomputed as CANTTELL. Fixed by the empty-output guard (pane-close-retry:308-313, verdict :70;
commit 4cb749ceb); pane 289's 11 timeouts logged `rc=124 with no output` and did not repaint.

## 6. Other observations relevant to the incident

- **A held row is a frozen paint.** When pane-close-retry removes the row (operator typed, pane-close-retry:278-280),
  nothing repaints again; pane 289 kept its false RESUME paint after 01:45:55Z. The contract's KEPT ON
  PURPOSE says "no paint", but the last paint stays on screen.
- **The runner's DONE has no sid** because `_verdict` (cc-pane-runner:189-190) reads the registry row
  that SessionEnd removes on a clean exit; the watchdog passes `--sid` but runs ~85 s later.
- **The runner's fullscreen fact is lost to the reconciler**: runner :332 writes `reason=guard-fullscreen`,
  the watchdog then writes `reason=ended`; the closer stops at gate 4 before its own guard (D15, D16).
- The watchdog called the closer's dry-run only for a block containing "closing in"/"safe to close"
  (:2060); a RECYCLE with dirty work never promises a close (:2000-2001), so on pane 289 the
  predicate was not run and the watchdog painted CANTTELL without knowing the closer's answer.

## 7. Fix levers (for the synthesis; not implemented)

1. **cc-pane-verdict --recompute must not map gate-4 to RESUME.** A refusal at gate 4 means gate 3
   passed (session meant to end / custody ruled done / teammate / self-close stamp); render DONE with a
   "work in the shared checkout, not this session's" qualifier, or a distinct state with a ⌘W action —
   never "stopped mid-task" and never a `--resume` the sweep will refuse. Better: have cc-pane-close
   emit a machine line of every gate's verdict (`gate3=yes:close gate4=dirty:138 gate5=refused-fs`) and
   recompute from that, not from the first REFUSED text.
2. **One state function, two consumers.** Put the session-state derivation (close word, custody live,
   teammate, lineage, transplant, work) in one sourced lib that cc-husk-sweep, the watchdog's
   pane_verdict_text and cc-pane-verdict --recompute all call; the closer's answer only picks row 2
   (the actuation class). Today custody is read by the sweep (live), the watchdog crash branch (once),
   and the closer gate 3, and never by the recompute.
3. **Gate 4 should test this session's paths, not the cwd** (or skip when gate 3 passed via custody
   return / Good to close: yes on a shared checkout). All three tools count the whole checkout (D14).
4. **The crash branch should read `Good to close: yes`** (D3) and the RECYCLE branch should read
   custody (D1).
5. **Close the remaining direct writers** (W2b, W3b) or route them through cc-pane-verdict, and make a
   row removal (operator took over) clear or neutralise the last paint instead of leaving it.
6. **Unlanded check keyed on origin/main is fail-open** on repos with another trunk or no remote (D6);
   and the closer does not check unlanded at all (D5).
