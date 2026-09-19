# D1-zero-touch — critique, lens: safety-blast-radius

Critic: adversarial, read-only. Repo root `R=/Users/chrisren/Development/claude-infrastructure`; every
`file:line` below is relative to it and was read this session, or is `<command> => <output>`. Research
units cited as `Uxx §n`. Design cited as `D1 §n` / `D1 Cn` / `D1 :line`.

## 0. Verdict

The design's mechanics are mostly the right ones and it is a large safety improvement over today (a
husk becomes a row; the load term stops refusing; the retype goes away). But **five of the seven safety
questions in the brief come back YES or "not as claimed"**, and one of them is a capacity-gate bypass
that outlives the recovery by the whole life of the recovered session. Every refutation below is
fixable in a few lines; none of them is a reason to abandon the shape.

| brief question | answer | refutation |
|---|---|---|
| ever `/exit` a pane it cannot relaunch? | **YES** — under a held operator draft the admission token is stale by the design's own arithmetic; and any pane the operator mis-reads is `/exit`ed with no check that it is limited | R4, R7, R6 |
| two writers on one uuid? | **no concurrent writers** (the transplant lock arbitrates — kept) — but a re-drive can serially `/exit` a live, already-recovered session, and the converse holds too: a session can never be recovered a second time | R8, R3 |
| bypass the capacity gate in a way that can thrash the box? | **YES** — `export CC_ADMIT_NET_ZERO=1` in the launcher makes every Agent-tool spawn from every recovered session count +0 against the active ceiling, forever | R1 (fatal), R2 |
| type into a pane the operator is using? | composer gate holds (kept) — but the re-drive, the quiet-pty inject and the 3 s `shell-stable` verdict each put keystrokes where they must not go | R8, R10, R6 |
| touch teammates the lead owns? | no direct touch (kept); the lead is severed from `teams/`, which the transplant does not carry | R16 (minor) |
| land/deploy a recovered session's work? | **NO** — kept | — |
| respect the shared-checkout rule? | **YES** — nothing in the chain writes a tracked file; the design's own converge uses the exact carve-out | — |
| every override explicit and reversible? | mostly; NET_ZERO is hardcoded with no env override, the hook's `kickstart` default was flipped ON below the operator's conviction threshold and can only be reversed by an operator settings edit | R1, R11 |

---

## 1. Refutations

### R1 · FATAL · `export CC_ADMIT_NET_ZERO=1` leaks into the recovered session for its whole life — every Agent-tool spawn from it is admitted at +0

**Claim refuted:** D1 §11 "The budget is not widened; the token cannot admit what the gate did not admit
≤ 180 s earlier." and D1 C6 "Why this is not a bypass … the operation it admits is net-zero."

**Why:** the launcher is a bash file whose `export` lines are inherited by everything it starts. D1 C7
(`:316-320`) adds `export CC_ADMIT_NET_ZERO=1` (unconditional — not `${…:-1}`) beside the two exports
the launcher already has. `lr-fire-resume.sh:463` then spawns the TUI as
`spawn -noecho env -u CLAUDE_CODE_CHILD_SESSION DISABLE_AUTOUPDATER=1 CLAUDE_CONFIG_DIR=$cfg $bin …` —
`env` unsets exactly one variable and passes every other one through, so `CC_ADMIT_NET_ZERO=1` reaches
the `claude` process and every hook it runs. `hooks/agent-teams-enforce.sh:229-230` gates every
teammate/subagent spawn with `CC_ADMIT_LOAD_TERM=off CC_ADMIT_SID=… cc_capacity_admit agent-tool …` —
it prefixes two variables and inherits the rest, so `NET_ZERO=1` governs its active term. D1 C6's change
is inside `cc_capacity_admit` (`:298-300`, "the active term's `+1` at `:832` becomes `+0`") and is
caller-agnostic. Net: **a recovered lead that fans out six teammates is admitted at +0 six times.** The
`reserve-active` arm (`capacity-admit.sh:834-840`, `act + 1 > act_limit`) still charges +1 but only
when presence is `present` — i.e. the widening is unbounded exactly when the operator is away, which is
the autonomous case this design is for. `hooks/agent-teams-enforce.sh:232` calls the active ceiling
"the ceiling the whole design point rests on".

The existing two exports (`lr-handoff.sh:590-591`) are meant to persist; the author copied the pattern
for a per-OPERATION flag. This is `docs/lessons/a-fixture-s-hermeticity-ends-where-its-subject-spawns-a-third-tool.md`
in the other direction: the environment outlives the process it was scoped to.

**Fix (one line each):** never `export` it — `lr-fire-resume.sh` applies it call-scoped
(`CC_ADMIT_NET_ZERO=1 cc_capacity_admit lr-fire-resume …`, as U05 P5(i) wrote it); and the spawn line
gains `env -u CC_ADMIT_NET_ZERO -u CC_ADMIT_TOKEN -u LR_STATE_FILE -u LR_RUN_DIR …` as belt. Same
treatment for `CC_ADMIT_LOAD_TERM=off` (harmless for the Agent tool, which sets it itself, but
`bin/reso-resume-one` / `bin/cc-resume-layout.sh` run from that session would inherit it).

**Evidence:** D1 :316-320, :298-300, :640-643 · `scripts/limit-recover/lr-fire-resume.sh:461-465` ·
`hooks/agent-teams-enforce.sh:227-231` · `scripts/lib/capacity-admit.sh:834-840` ·
`scripts/limit-recover/lr-handoff.sh:586-593` (today's heredoc, no `CC_ADMIT_*`).

### R2 · MAJOR · C1's `kind:"limited"` beat and C6's NET_ZERO compose to a −1 undercount; up to `LR_REQ_CONCURRENCY` uncounted mid-turn sessions at once

**Claim refuted:** D1 C6 / U05 §4.2 "the `+1` is the replacement, and the session it replaces is still in
`act`" — the premise NET_ZERO rests on.

**Why:** `cc_sp_active` selects `.kind == "prompt"` beats (`scripts/lib/spawn-presence.sh:319-321`);
`hooks/session-beat.sh:59` takes `kind="${1:-prompt}"` with no vocabulary check and the beat file is
overwritten in place (U05 §4.1). D1 C1 (`:154-157`) writes `kind:"limited"` at the limit — so by the time
S1 probes, the limited session is **already out of `act`**. NET_ZERO then declines to charge the
replacement. At token redemption nothing is evaluated; at the fresh-eval fallback NET_ZERO applies again
and the old pid is dead. In all three paths the recovery adds one mid-turn session that no term counts,
until its first `UserPromptSubmit` beat lands (~10-20 s). With three workers (D1 C3) that is a transient
ceiling of 8 + 3. Bounded, but D1 §11's "not widened" is false, and this is
`~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/remedial-classes-may-not-compose.md`
exactly: two individually-correct cures over one count. Keep the `limited` beat (it is the correct fact);
drop NET_ZERO, or apply it only when the beat is still `prompt`.

**Evidence:** D1 :154-157, :298-300, :739-741 · `scripts/lib/spawn-presence.sh:314-321` ·
`hooks/session-beat.sh:59` · U05 §4.1-4.2.

### R3 · MAJOR · a session that re-limits on its target can never be recovered again; D1 §10 says "the lane recurses"

**Claim refuted:** D1 §10 row "re-limited on the target … the target's OWN StopFailure writes a NEW
request, from=next3 … the lane recurses".

**Why (two independent blocks):** (a) D1 C1 `:146-147` "second guard: skip if `$STATE/locks/$SID.lock`
… exists". The lock is written by `lr-transplant.sh:66-68` and **removed by nothing** —
`grep -rn 'locks/' scripts/limit-recover/*.sh hooks/handed-off-session-guard.sh => 5 hits, all reads or
writes, zero `rm``; U06 §3 verified all five of today's locks still on disk after the recoveries. So the
guard skips the second request with `log_idl passed` — silent, no page. (b) Even without the guard,
`lr-transplant.sh:62-65` `REFUSED — lock exists` unless `--force`, which no automated path passes. The
only fallback is the reset poller's same-account wait behind `lr-reset-poller.sh:896` — the 2 h 41 m
wait this whole design exists to remove — and `lr_transplanted_to` (lock `to` == this cfg) will not even
retire it. This contradicts LR-i (`scripts/limit-reset-safety-gate.sh:66`: "A session resumed once MUST
re-park on its NEXT limit event") applied to the transplant lane.

**Fix:** key the lock on `(sid, death_uuid)` or make the successful engagement (state `RECOVERED`)
rewrite the lock's `from` to the target so a later transplant from the target is a fresh move; the
tombstone stays where it is. At minimum the C1 guard must be `HANDOFF.json beside THIS transcript`
only (that half already discriminates source from target), never the global lock.

**Evidence:** D1 :146-147, :616 · `scripts/limit-recover/lr-transplant.sh:59-68` ·
`scripts/limit-recover/lr-reset-poller.sh:896-905` · `scripts/limit-reset-safety-gate.sh:66`.

### R4 · MAJOR · the admission token's 180 s TTL omits the composer gate: under a held operator draft the token is stale by construction and the pane is `/exit`ed on a decision the launcher will not honour

**Claim refuted:** D1 §11 "Never `/exit` a pane the relaunch cannot be admitted into — … the probe's
admit is carried as a one-shot token the launcher redeems"; D1 §7 "admission token TTL 180 s —
shell-wait 120 + 60 margin".

**Why:** D1 §3 mints the token in S1 (probe) and redeems it inside `lr-fire-resume` after S3. Between
them, in D1's own §7 table: transplant ≤ 5 s, composer gate **180 s** (`:11634`, U04 §1 F2), arm ≤ 5 s,
pane-proof ≤ 18 s (U04 §1 F6), `/exit` ×3 + settle ~10 s, `/exit`→shell **120 s**, boot. Worst case
≈ 340 s > 180 s. The margin sentence in §7 simply forgot the 180 s row four lines above it — the
`docs/lessons/inner-bound-outer-bound-starves-the-tail.md` shape the design itself cites. The case
where it binds is precisely the one where the operator is at the pane (a draft held them off), so the
pane is `/exit`ed, the launcher evaluates fresh with headroom/segments/active ON, and a genuine refusal
is a recorded husk (D1 §10 "launcher refused (gate)") — recorded and re-driven, but the promise was
"never".

**Fix:** mint the token in handoff-fire immediately before F9 (after the composer gate clears and the
freshness re-read passes), using the same `cc_capacity_probe` it already sources for `capacity_gate()`
(`handoff-fire.sh:5888`); 180 s is then 120 + 60 as written. U04 §5 E(i) asked for exactly this
placement.

**Evidence:** D1 :82-101 (stage order), :516-539 (§7 rows), :633-637 · `scripts/handoff-fire.sh:11634`
· U04 §1 F2, F6, W2.

### R5 · MAJOR · `relaunch.rc` is a stale marker on every re-drive — the second attempt fails in ≤ 0.5 s on the first attempt's verdict, and three re-drives are burned in seconds

**Claim refuted:** D1 R8 "every recorded [husk] re-driven automatically"; D1 §10 "launcher refused
(gate) … `mode:relaunch` request → WatchPaths → re-drive in seconds; token re-minted".

**Why:** D1 C7 writes `printf '%s\n' "$rc" > "$BUNDLE/relaunch.rc"` on launcher failure. D1 C9's poll
reads `[ -s "$LR_RUN_DIR/relaunch.rc" ] && { rcy_verdict="launcher-exited:…"; break; }` where
`LR_RUN_DIR=$BUNDLE` (C7 `:320`). A `mode:relaunch` re-drive uses the same bundle and the same launcher
(D1 C5 "launcher only"), so the file from attempt 1 is present before attempt 2's launcher has run: the
watcher declares `launcher-exited:9` at its first tick, writes `FAILED:relaunch`, files another
`mode:relaunch` request; repeat. `fire_fail_note` reaches `LR_FIRE_FAIL_MAX=3`
(`lr-reset-poller.sh:243`) inside a minute and latches the sid for `LR_FIRE_LATCH_HOURS=6` (`:244`).
`docs/lessons/a-stale-pid-does-not-decay-into-harmlessness-it-decays-into-a-gu.md`.

**Fix:** `rm -f "$LR_RUN_DIR/relaunch.rc"` immediately before `it2_type_verified` types the relaunch
(and record the typed-at epoch; accept the rc file only if its mtime ≥ that).

**Evidence:** D1 :322-330, :385-394, :611 · `scripts/limit-recover/lr-reset-poller.sh:238-248, :257-279`.

### R6 · MAJOR · the `shell-stable` verdict at a 3 s floor is a false FAILED during the gate itself, and its re-drive types a second launcher line into a live composer

**Claim refuted:** D1 C9 "The `≥ 3 s` floor before trusting `at_shell` and the two-sample rule are
required … the launcher's own bash prologue IS bash for ~2 s (U04 §5 C)".

**Why:** U04 §5 C says **≥ 9 s**, not 3, and gives the reason. `pane_cc_state`
(`scripts/handoff-fire.sh:3566-3575`) answers `shell` whenever the foreground group is nothing but
`zsh|bash|sh|…`; leg (a) answers `cc` only once a claude pid is in the closure. D1 C7 replaces the
launcher's `exec` with a plain call, so during the gate the foreground group is `bash(launcher) →
bash(lr-fire-resume)` — all shells — and reads `shell` between the gate's own `jq`/`ps` children. That
gate includes `cc_sp_active`, measured **7.2 s cold** over 3,767 beat files (U05 §4.3). Two `shell`
samples 0.5 s apart inside a 7 s window is the common case on a loaded box. The verdict `shell-stable`
→ `FAILED:relaunch` → `mode:relaunch` request → the poller types `bash <launcher>` again into a pane
whose first launcher is now at `expect`/`claude` — the "second launcher line into the composer it was
just given" that `scripts/handoff-fire.sh:6805-6809` names as the reason the retype gate is `at_shell`
and not `! cc_alive`. Second defect in the same loop: the 20 s timeout with **no** discriminator falls
through to the `no claude process` branch — a timeout is not a verdict
(`docs/lessons/a-gate-refusal-is-not-a-gate-result.md` class), and 20 s is a bound sized in the
foreground for a boot the design labels "~4 s, inference" (`bound-must-fit-the-band-not-the-bench`).

**Fix:** keep U04's 9 s floor and require an affirmative discriminator — `relaunch.rc` (fixed per R5),
`cc_alive`, or an IDL `lr-fire-resume` row after the typed-at ts (U04 §5 D) — for any FAILED; on the
timeout write INDETERMINATE and keep polling to a longer bound (120 s), never a re-drive.

**Evidence:** D1 :385-399, :530 · U04 §5 C ("The ≥9 s floor and the 2-consecutive-sample rule are
required") · `scripts/handoff-fire.sh:3532-3576, :6805-6809` · U05 §4.3 (`jq -rs … cold: real 7.24s`).

### R7 · MAJOR · the daemon transplants and `/exit`s ANY session it is pointed at — nothing on the drive path checks that the session is limited, and C5 removes the one implicit check that exists today

**Claim refuted:** D1 §10 (no row for "request names a non-limited session"); D1 C12 "never guess: an
ambiguous identification that picks one is how a wrong pane gets recycled" — the refusal covers the
tuple resolver only; a pane id is "exact, single hit, done" (D1 C10) and a **mis-read** pane id is exact.

**Why:** today `lr-fleet.sh --one` runs the census and, on a miss, explicitly proceeds anyway:
`lr-fleet.sh:427-434` "not limit-blocked per the census — the caller may still know better …; fall back
to the registry for the pane and the store for the cfg" → `lf_one` → transplant → recycle. D1 C5 makes
that registry path FIRST ("`--one SID` must not census"). `lr-transplant.sh` reads nothing about the
transcript's tail; `lr-ingest-verify` clause A (kind ∈ session/weekly/monthly_spend) runs **inside the
launcher, after the transplant** (D1 C7). So `lr-fleet --request 124` where the screenshot said `⌗122`
in a 30-column pane (U07 §2b: 9 of 16 panes truncate; U07 §0: two panes render byte-identical lines)
transplants and `/exit`s a healthy, mid-work session, then resumes it on another account with a prompt
that begins `lr-ingest-verify FAILED: clause A`. Nothing is lost, but the brief's first question is
answered YES for a session that was never limited. `mode:drill` (D1 §13) has the same shape with no
ownership check — a drill request against a production sid is an unrequested transplant.

**Fix:** at CLAIM (D1 C3), before anything, `lr_last_api_error "$TP"` must return `kind=limit` with the
request's `death_uuid` — the same envelope gate C1 applies at write time (`lr-lib.sh:129-159`) — else
`FAILED:claim:not-limited` and a page; `mode:drill` requires a throwaway marker in the session's cwd or
an explicit `--i-mean-it`.

**Evidence:** D1 :256-258, :278-283, :462-465, :687-689 · `scripts/limit-recover/lr-fleet.sh:418-440` ·
`scripts/limit-recover/lr-transplant.sh:50-103` (no tail read) · U07 §0, §2b.

### R8 · MAJOR · a `mode:relaunch` re-drive through handoff-fire's recycle form `/exit`s a live, already-recovered session — after the operator does exactly what the failure page told them to

**Claim refuted:** D1 §11 "Never two writers on one uuid"; D1 C5 `mode:relaunch` "(tombstone exists,
pane at a shell — launcher only)" — the parenthetical is a precondition the design never checks.

**Why:** the only relaunch primitive the design names is handoff-fire's remote recycle. Its F1 dispatch
(`scripts/handoff-fire.sh:11604-11619`) types on `shell`, refuses on `unknown`, and on `cc` **falls
through to the composer gate and `/exit`**. Its admission checks are `hf_remote_source_bind`
(`:1969-2016`: the registry row for the pane names the sid — never which account) and
`hf_transplant_evidence` (`:2044+`: a `<sid>.HANDOFF.json` exists under the roots — true forever after
any transplant). After a `FAILED:relaunch` page whose text is `bash …/lr-launch-<sid8>-*.sh to run it
by hand` (D1 §9), the operator runs it; `session-register` rewrites the row with the same sid, the new
pid, `account: <target>`; the TUI is `cc`. The queued re-drive (WatchPaths, seconds) binds, passes
evidence, gates on an empty composer, and types `/exit` into the operator's live recovered session,
killing its in-flight turn — then relaunches the same uuid. Serial, not split-brain, but it is the
design typing into a pane the operator is using. The same path fires from the reaper's STALE re-drive
and from the poller's changed retirement arm (D1 C3 "otherwise write `requests/<sid>.json` with
`mode:"relaunch"`").

**Fix:** before any re-drive, `lr_registry_live_rows "$sid"` under the target cfg with a live pid ⇒
append `RECOVERED` and stop (the design already has this predicate in C3 for retirement — apply it as
the pre-drive guard); and `mode:relaunch` must refuse a `cc` pane outright rather than fall through.

**Evidence:** D1 :172-173, :225-229, :230-237, :581-583 · `scripts/handoff-fire.sh:11604-11619,
:1969-2016, :2044-2075`.

### R9 · MAJOR · clause D (`session-continue.sh clear` in the launcher) clears a SIBLING session's sentinel and spends its mechanical budget, and does not even reach the recovered session's own

**Claim refuted:** D1 C7 / U12 §6.1 clause D "the side effect ingest step 1 performs, moved to the
shell" (run in the launcher, before `lr-fire-resume`).

**Why:** the sentinel path is `hash(CLAUDE_CONFIG_DIR|cwd)` (`hooks/lib/continue-sentinel.sh:11, :25`).
`clear` does `rm -f "$f" "${f}.count" "${f}.sid" "${f}.cwd"` for `$PWD` with **no sid comparison**
(`hooks/session-continue.sh:157-165`) and then writes `${f}.mech` — spending the mechanical
ship-floor budget for that cwd — with `SC_SID` = `?` because `CLAUDE_CODE_SESSION_ID` is unset in a
launcher (`:172-173`). In the launcher, `CLAUDE_CONFIG_DIR` is whatever the pane's shell carries (the
source account's, or unset ⇒ `~/.claude`), so the hash it clears is the SOURCE-account hash for a cwd
that up to four sibling sessions share (U14 §3.2: `('claude-tertiary','claude-infrastructure')=4`;
U07 §2a: 6 of 16 live panes in the shared checkout) — while the recovered session, running under the
TARGET cfg, reads a different hash and keeps whatever stale sentinel it had. Wrong target, cross-session
side effect on a store that blocks other sessions' Stops.

**Fix:** run `clear` as the recovered session's own first Bash call (it then has the right
`CLAUDE_CONFIG_DIR` and sid), or in the launcher as `CLAUDE_CONFIG_DIR="$TCFG"
CLAUDE_CODE_SESSION_ID="$SID" session-continue.sh clear` and add a `.sid == $SID` gate to `clear`.

**Evidence:** D1 :335-341, U12 §6.1 D · `hooks/lib/continue-sentinel.sh:7-25` ·
`hooks/session-continue.sh:156-201` · U14 §3.2.

### R10 · MAJOR · the quiet-pty fallback sends a blind CR into whatever is on screen — on the one path (a CC version bump) where what is on screen is most likely a menu

**Claim refuted:** D1 C8 "the quiet-pty fallback — … an 8 s settle arm that injects anyway …
(version-proof; a status-line phrase is not)".

**Why:** the arm fires when `LR_RE_READY` never matched within the settle window — exactly the state a
wording change leaves the resume-return menu, the trust dialog or the upsell in, since their arms are
also phrase-keyed. It then sends `\025` (no effect on a menu) + text + `\r`; a CR on a selector takes
its highlighted default (U03 (c): "A CR onto an open permission dialog accepts its default"), and on the
resume menu that can be "from summary" — the lossy continuation `LR_ASIS` exists to avoid
(`lr-fire-resume.sh:338-350`, `:386`). `answer_menu` (`:501-503`) parks rather than guesses for the
same reason; the fallback reverses that doctrine. The launcher carries the source's `--permission-mode`
verbatim (`lr-handoff.sh:581`), so a `default`-mode session is exposed to a permission dialog as well.

**Fix:** the quiet arm may inject only after an affirmative screen read shows no `❯` selector and an
empty composer box (`composer_content` exists, `handoff-fire.sh:2392`); otherwise `FAILED:ready` and
the loud line the design already specifies.

**Evidence:** D1 :358-362, :533 · `scripts/limit-recover/lr-fire-resume.sh:338-350, :386, :501-503,
:549-561` · `scripts/limit-recover/lr-handoff.sh:581` · U03 §2 (a), (c).

### R11 · MINOR · `CC_SF_REQUEST_KICK` default flipped ON at a self-stated 88 %, against the unit that designed it, in a hook that runs in every session

**Why:** U10 §2e recommended `CC_SF_REQUEST_KICK=${CC_SF_REQUEST_KICK:-0}` "until the operator rules";
D1 C1 `:158-164` ships `:-1` and states "my conviction 88 %". The operator's own F2 rule is >90 % to
implement. `launchctl kickstart` is neither `load` nor an autofire flip
(`scripts/limit-reset-safety-gate.sh:34-38`: "the agent NEVER loads launchd or flips autofire itself"),
and `hooks/validate-bash.sh` carries no `launchctl` rule (`grep -n -i launchctl hooks/validate-bash.sh
=> nothing`), so it is defensible in remit; `man launchctl` confirms only `-k` kills. But the enable is
agent-side and the disable requires the env var in every session's hook environment — a settings.json
(c10) edit — so the override is explicit but not symmetric. WatchPaths (C2) supersedes it in days; ship
`:-0` until then.

**Evidence:** D1 :158-164 · U10 §2e item 2 · `scripts/limit-reset-safety-gate.sh:34-38` ·
`man launchctl => "kickstart [-kp] … -k If the service is already running, kill the running instance"`.

### R12 · MINOR · the per-caller refusal counter is left shared; on the fresh-eval fallback one sid's refusals release another's `budget-expired` ADMIT

**Why:** `_cc_admit_state_file` keys on caller only (`scripts/lib/capacity-admit.sh:509-514`); U05 P3
asked to key it per recovery and D1 C6 does not. With three concurrent workers whose tokens expired
(R4), sid A's two headroom refusals plus sid B's one release sid C at `budget-expired` — the shared-counter
accident that produced today's single "success" (U05 §3.4), now on the fallback path. Bounded: with the
load term off, fresh refusals are rare (0 of 127 headroom refusals ever, U05 §7.4).

### R13 · MINOR · "`FAILED:submit` exit 12, TUI left alive" is structurally unreachable

**Why:** `lr-fire-resume` runs `expect -c` (not `exec`) and the program ends in `interact`
(`lr-fire-resume.sh:432, :584`, U03 §2); an `exit 12` before `interact` closes the pty and kills the
TUI, and after `interact` it runs hours later. The state line can be written from inside expect via
`exec`; the exit code cannot carry the verdict while the TUI lives. D1 §10 and C9's `submit-failed`
grep must key on the state line / log, never on rc 12.

### R14 · MINOR · "the 3rd failure pages needs-human" is a 6 h snooze, not a park; HELD has no bound in §7

**Why:** `fire_latched` expires the latch after `LR_FIRE_LATCH_HOURS=6` and clears the counter
(`lr-reset-poller.sh:244, :271-279`), so a permanently dead pane is re-driven 3× every 6 h forever. And
`HELD:draft` is listed as a non-terminal hold (D1 §3) with no stage bound in §7; only the 15-min
whole-request bound reaches it.

### R15 · MINOR · the irreversible step precedes the composer gate

**Why:** D1 §3 keeps today's order — transplant (lock + tombstone + rename) before the composer gate.
An operator drafting in the pane finds it tombstoned mid-draft (`handed-off-session-guard.sh:65-66`
then refuses their submit). U02 §2a explains why the tombstone must precede the `/exit` (it is the
driver's authorization); nothing prevents a non-authoritative composer pre-check before the transplant,
which makes the HELD case fully reversible at zero cost.

### R16 · MINOR · a recovered lead is severed from `teams/`; the fastpath's only protection is lr-audit's RUNNING verdict

**Why:** `~/.claude-quaternary/teams` is a real per-account directory (`ls -d => …/teams`; `tasks` is the
symlink, `teams` is not). `lr-transplant.sh:72-83` copies the transcript, the session dir and
`tasks/<list>/` — not `teams/`. The lead resumes on the target with no `teams/<t>/config.json` while its
teammates sit `teammate-skip`'d on the dead account (D1 §10). D1 §10 says "lead's ingest re-audits
(exists)" but C7's fastpath skips the ingest unless clause A sees a `RUNNING` member; `lr-audit.py:156-162`
keys RUNNING on the member's own pid, so a limit-blocked (pid-alive) teammate does trip it today. Not a
regression the design introduces, but the design's teammate row understates what is lost.

---

## 2. What survives (keep in the synthesis)

- **StopFailure as the detector and the request lane as the transport** — D1 §2 first two bullets; the
  hook fires sub-second with the envelope (U10 §1c), the LaunchAgent is outside every classifier
  (`lr-reset-poller.sh:639-643`), the consumer ignores unknown keys (`:648-660`).
- **Envelope-not-text gating + per-death-uuid latch** — `$ERR` ∈ rate_limit, `lr_last_api_error`'s
  `isApiErrorMessage` gate, O_EXCL latch keyed on the death record (D1 C1). The LR-o false-positive
  class stays closed.
- **Teammate skip via `agent_assignee_argv` ∧ `agentName`** — no direct touch of a lead-owned session.
- **Claim-by-rename and the transplant lock as THE two-writer arbiter** — `lr-transplant.sh:62-68`
  refuses a second owner; verified. (R3 is about the lock never releasing, not about it arbitrating.)
- **Tombstone + `handed-off-session-guard.sh` + `lr-resume-tombstone-guard.bats` unchanged** — D1 §14.
- **Affirmative-only typing (`unknown ≠ shell`), the composer gate with `HELD:draft`, echo-verified
  `it2_type_verified`, no `send-key`, no `cc-pane send`, no `session run` for messages** — D1 §2, C12.
- **Load term OFF for the recovery callers** — matches `hooks/agent-teams-enforce.sh:229` and
  `handoff-fire.sh:6075`; a term switch, never a ceiling change (U05 P1).
- **The admission token's shape** — one-shot, TTL, uid-checked, sid-named, probe-inert (U05 P2 / T1) —
  once minted after the composer gate (R4).
- **No retype** — the retype re-ran the identical command against a counter advanced by one (U02 §2d).
- **The `no claude process` branch gains a row + alarm + re-drive request** — U04 §3's three lines.
- **Transcript-based `submitted` (nonce in a `type:"user"` record) then `engaged` after that record** —
  closes U11 §0(B) and U03 (a)/(b).
- **Retirement keyed on `RECOVERED` or a live registry row under the target, never on lock+file** —
  U02 §2c's highest-leverage finding; apply the same predicate as the pre-drive guard (R8).
- **Recovery never lands or deploys** — iron rule 7 (`commands/limit-recover.md:89, :454`); nothing in
  the chain writes a tracked file (bundle, state, launcher, locks all under `~/.reso` / `~/.claude`);
  `lr-ingest-verify` clause C is read-only `git branch --show-current`. The design's §15 converge
  spells the exact carve-out `.claude/settings.json:53-54` grants.
- **`cc-find` refusing on ambiguity and printing both rows** — the correct polarity (U07 §6c); extend the
  same refusal to a pane id that resolves to a non-limited session (R7).
- **`--recovery` ranker floors with `CC_ROUTE_RECOVERY=off` byte-identical** — U13 §4.
- **Fired peers recovered in place** — preserves pane, worktree, custody; report to the originator.
- **No `settings.json` edit; WatchPaths as an operator c10 step with `launchd-parity-lint.sh`
  asserting live == SSOT** — `scripts/launchd-parity-lint.sh` exists; the plist today has
  `StartInterval 600` only (`com.reso.lr-reset-poller.plist:37`).
- **Kill switches that exist and are honoured** — `CC_SF_REQUEST`, `CC_ROUTE_RECOVERY`,
  `CC_ADMIT_GATE`, `CC_RECYCLE_COMPOSER_GATE` (`handoff-fire.sh:11632`), `LRH_LIVE_PARSER_CHECK`.
- **State file as an append-only, ≤ 1 KB-per-line ledger** — under the stdio buffer, O_APPEND atomic.

## 3. The three lines that would close the fatal and the worst majors

1. `lr-fire-resume.sh:324`: `CC_ADMIT_NET_ZERO=1 cc_capacity_admit lr-fire-resume …` (call-scoped) and
   `env -u CC_ADMIT_NET_ZERO -u CC_ADMIT_TOKEN -u LR_STATE_FILE -u LR_RUN_DIR` on the spawn line;
   delete the `export CC_ADMIT_NET_ZERO=1` from the launcher heredoc. (R1)
2. Mint the token in handoff-fire after the composer gate, `rm -f relaunch.rc` before typing, and
   refuse any FAILED verdict without an affirmative discriminator. (R4, R5, R6)
3. At CLAIM: re-verify `lr_last_api_error` = limit on the source transcript, and if
   `lr_registry_live_rows` under the target is live ⇒ `RECOVERED`, never touch the pane. (R7, R8)
