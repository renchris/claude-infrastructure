# Critique: D3 schema-first, through the constraints-feasibility lens

Design reviewed: `docs/research/lead-keeps-working-2026-10-24/designs/D3-schema-first.md`, cited below as `D3 §n` or `D3:line`.
Worktree `lead-idle-fix` at `b6b53ea89`. Code anchors are `path:line` in this worktree.
Read-only review: the only write is this file. Numbers are labelled **measured** (with the command) or **estimated** (with the method).

Verdict: **sound-with-fixes**. Score **5.5/10** on this lens.

- **Hard constraints that hold.** D3 edits no settings file and registers no new hook. It touches only already-registered Stop hooks, a CLI and the launchd supervisor, which picks up changes through its sha self-restart. The rule-text budget is truly net-neutral.
- **Three gate weakenings.** D3 claims each is safe, but each weakens an existing gate:
  - a done-claim spare in completion-assert;
  - a sanctioned path that re-files legacy hard class-C packets as class B;
  - drift of the shared DoD scope that can switch off the backlog drain floor (CLOSE_FLOOR).
- **One dead safety bound**: the supervisor's per-sweep cap.
- **One goal unmet**: goal (d) records a grant that the harness will refuse to honour without a settings edit.
- **Size**: about 35 files. That is well past the 6-file threshold, so it needs teammates.

---

## 1. Hard constraints

| Constraint | Finding | Evidence |
|---|---|---|
| No settings edit | **Holds.** D3 explicitly leaves the `codex exec` allow rule to the operator | D3 §7.2 (D3:762-764), §13.7 (D3:1074-1075) |
| No new hook registration | **Holds.** Changed: session-continue, completion-assert, operator-readout, anti-deference-nudge, dispatch-assert (all registered on Stop). dod-persist is called as a script from session-continue (`bash "$dp" intake`, D3:550), not registered anew. lead-supervisor is a launchd daemon with no plist edit (D3:708-709) | registered timeouts read-only: `jq '.hooks.Stop[]?.hooks[]?' ~/.claude/settings.json` shows session-continue, completion-assert, boundary-handoff and operator-readout, each `timeout: 10` (measured) |
| Never weaken an existing gate | **Violated three ways** (defects 1-3) | §2 below |
| Infinite-loop bound on every hook change | Mostly holds (latch, total cap, kill switch, assignee, teardown, context-high). The per-sweep supervisor cap is dead (defect 4), and the drive latch is weaker than stated (defect 7) | §2 |
| Stop is right for a genuine money, self-modification or permission gate | Holds for **new** packets with a hard `--category`. For **legacy** hard packets it does not hold (defect 2) | D3:153-154, D3:180 |

## 2. Defects

### D-1 (major): a done-claim over an open part-gating decision is no longer convicted when the dirt is not the session's

- **The new ledger arm keys on any dirt.** It reads `elif [ "$BLOCKED" -gt 0 ] && { [ "$DIRTY" -eq 1 ] || [ "$UNGATED" -gt 0 ]; }` → 🔧 (D3:378). `DIRTY` is any dirt in the tree, not the session's own.
- **completion-assert's "BLOCKED ON YOU" term keys on the rung.** It runs only `if [ "$RUNG" = "⛔" ]` (`hooks/completion-assert.sh:1218`). The 🔧 demotion skips it.
- **The dirt term that would replace it is exonerated six ways:**
  - `dirty-assignee-shared-cwd`
  - `dirty-not-mine`
  - `dirty-predates-session`
  - `dirty-outside-session-exec`
  - `dirty-unreachable-per-path`
  - `dirty-live-peer-edited`

  (`hooks/completion-assert.sh:1027-1043`).
- **No generic rung check catches it.** D6's rung check is gated to `RUNG ∈ {✅,👤}` (`hooks/completion-assert.sh:1535`). FILED_MINE and CUSTODY are not computed off the ✅-eligible path (`scripts/wrap-ledger.sh:2622-2648`).
- **Net effect.** Take a part-gating class-C packet, a sibling's dirty file, `REMAINDER=0` and `LOOP_OPEN=0`, and a close that says "✅ Good to close: yes":
  - today it is convicted "BLOCKED ON YOU" (`hooks/completion-assert.sh:1238`);
  - under D3 it abstains `ledger-clean` (`:1654`).

  R:106 even tells the model "A 🔧 you did not cause is not yours … close on your own state". This brings back the 2026-08-07 defect the ⛔ term was written for (`hooks/completion-assert.sh:1184-1186`).
- **Fix** (one line each):
  - completion-assert: convict on `BLOCKED>0` (via `lfield`) as well as on `RUNG=⛔`, and keep the honest-no spare;
  - **or** in the ledger arm, replace `DIRTY` with own dirt (a DIRTY_MINE-style term) or drop it, so foreign dirt keeps today's ⛔.

### D-2 (major; it breaches the "never weaken" constraint): `--supersedes` and the challenge reach legacy hard class-C packets

- **Legacy packets are eligible by design.**
  - `--supersedes` validation accepts category `""` (legacy) or `pick` (D3:180).
  - `ghard` is false for every legacy packet without a `.producer` (D3:153-154).
  - D3 states this as a feature: the 48 open legacy class-C packets across 23 sessions are "eligible for `--supersedes` by its own filer" (D3:290).
- **The challenge text actively steers them to class B.** It covers "category pick, **or a packet filed before gates existed**" and ends "Otherwise re-file it: `cc-decide open --class B --supersedes <id>`" (D3:533-539).
- **D3's own control C2 names one such packet.** `d610f8473106` is a C10 self-modification packet filed before D3, so it is legacy (D3:1056). Under D3 it reads `gates_all=true, gate_hard=false`. With any ungated work it is challenged and can be superseded.
- **The no-change label does not constrain the default.** `--default-effect no-change` is a token check only (`bin/cc-decide:204-212`). The `--default` text is free, so a legacy C10 or C6 packet can become "class B, default: land it" and fire at its deadline.
- **What is new and what is not.** `cc-decide action` already closes any packet with no caller guard (`bin/cc-decide:364-388`), so the mechanical capability exists today. What D3 adds is the **policy**: a hook message and a validated verb that steer agents to retire hard gates.
- **Fix:**
  - treat legacy (`category ""`, no producer) as **hard** for both the challenge and `--supersedes`, so all 691 legacy packets behave exactly as today;
  - or require `scripts/gate-classify.sh "<what_plain>"` = B before a legacy packet may be superseded.

  Neither costs the B13 replay anything: that replay is about new packets (D3:1001-1031).

### D-3 (major): intake capture makes the shared DoD scope drift across sibling sessions, which can switch off the drain floor

- **The shared scope is per toplevel, not per session.**
  - `DOD_SCOPE` is the newest `Scope (frozen):` line in the toplevel-lineage stream (`scripts/wrap-ledger.sh:924-928`). It is filtered by worktree, not by session (`maps/wrap-ledger.md:123-126`).
  - `DRAIN_SCOPE` is derived from it (`:945`).
  - `CLOSE_FLOOR` (`:1490-1500`) and completion-assert's drain fact (`hooks/completion-assert.sh:1142-1144`) consume it.
- **D3 captures far more often than today.** Today a capture happens at PreCompact or on a manual `set` (`hooks/dod-persist.sh:6-18`). D3 adds one at **every session's first idle Stop** (D3 §5.1(b), D3:541-553). D3 session-scopes only `LOOP_OPEN` (D3:348), not `DOD_SCOPE`.
- **Measured exposure** (shell loop over `~/.claude/autonomy/dod/*.md` counting distinct `· session=` and `· toplevel=` values and frozen lines matching backlog|drain):
  - `fecdf34b97ed1726.md`: 14 sessions in 1 toplevel; 4 of 25 frozen lines are drain scopes;
  - `repo-86523465733a9afe.md`: 52 sessions over 26 toplevels; 18 of 76 are drain scopes.
- **Effect.** A sibling's intake of a non-drain scope clears a drain-scoped session's `CLOSE_FLOOR`: the gate is weakened and a ✅ is reached without closing a row. The reverse imposes a false 🔧. SessionStart also re-injects the durable file's content (`hooks/dod-persist.sh:7-9`), so every new session in that checkout is shown a sibling's contract.
- **Fix:** derive `DOD_SCOPE`/`DRAIN_SCOPE` from the session's own newest block when one exists, using the same awk `own` test as `compute_loop_floor`. Alternatively, keep intake captures out of the shared contract stream and read them only for `LOOP_OPEN`.

### D-4 (major): the supervisor's per-sweep nudge cap is dead code

- `nudge_subject` increments a shell global, `_NUDGES_THIS_SWEEP` (D3:658, D3:681).
- It is called from `assess()`'s STALL? branch (D3:648-650). `assess()` runs in a subshell: `r="$(assess "$f")"` (`scripts/lead-supervisor.sh:1362`).
- The same file records this exact trap: "a counter incremented there mutates a copy that dies with the subshell" (`scripts/lead-supervisor.sh:353-359`). It uses a file-backed `DIGEST_FILE` for that reason (`:361`).
- So D3 §10's "at most 3 per sweep" (D3:971) is false. When many sessions stall together (after a reboot or a usage reset), every one is woken in the same sweep.
- **Fix:** a file-backed per-sweep counter, plus an N-test asserting the cap. That test would be RED against the design as written.

### D-5 (major for goal d): the recorded grant cannot be exercised without a settings edit

- The auto-mode classifier refused `xverify.py` calls as "data exfiltration" at `2026-10-24T18:17:32Z`. That was **after** the operator's 18:11Z grant (TX:4683, read with `sed -n 4683p | jq`).
- D3 concedes `xvendor-review.sh` "does not get past" the classifier, and that the allow rule is a settings change (D3:762-764).
- Yet the always-loaded S bullet tells every session to act "unasked and with no packet … via `~/.claude/scripts/xvendor-review.sh`" (D3:891). A session that follows it hits a permission denial, which S:27 makes a stop-and-hand-back.
- The bullet also cites `config/standing-grants.json` as a repo-relative path. From any other repo that path does not resolve, and the file is not deployed: `ls ~/.claude/config` gives "No such file or directory" (measured). cc-decide reaches the file through `self_path` (`bin/cc-decide:395-402`, used the same way at `:429`).
- **Fix:**
  - make the S text conditional: "once the operator's allow rule for `xvendor-review.sh` exists; until then a denial is a `--category permission` packet that gates only the reviewer lane";
  - use the absolute path `~/Development/claude-infrastructure/config/standing-grants.json`.

### D-6 (minor): two pins D3 says stay green go red

- `tests/completion-assert.bats:1270` and `:1277` grep `'"reason":"ledger-clean:exonerated:blocked-answered"'`, including the closing quote.
- D3 §5.2 changes the token to `blocked-answered:ungated=<N>` (D3:574). The reason is assembled at `hooks/completion-assert.sh:1654`.
- D3 §14.4 A3 says these pins stay "green, unchanged" (D3:1180).
- **Fix:** append the suffix only when `UNGATED` is present and above 0 (stub ledgers lack it), or log `ungated` as a separate IDL field.

### D-7 (minor): the drive latch re-arms on other sessions' lands

- The progress key is `HEAD:trunk-sha` (D3:505). Trunk refs are shared across worktrees.
- Measured: 112 trunk commits since 2026-10-23T00:00Z, about 45 h (`git -C ~/Development/claude-infrastructure log origin/main --since=2026-10-23T00:00:00Z --format=%cI | wc -l`).
- So a sibling's land resets the 2-per-commit count, and the effective bound becomes `CC_SCOPE_FLOOR_TOTAL=16` per decision set.
- That contradicts D3 §10's "A new commit, which requires real work, re-arms" (D3:965).
- **Fix:** key the latch on `HEAD` plus an own-land bit (whether `HEAD` is an ancestor of trunk), not on the raw trunk sha.

### D-8 (minor): the supervisor reads a stale oracle

- `steps-surfaced` is logged only after a render (`hooks/operator-readout.sh:2537`). A latched close abstains first at `:2522` and writes no row.
- So the `scope_floor` value the nudge reads (D3:661-663) can be several states old.
- D3 already logs `fired/abstained scope-floor-{latched,budget,…}` rows with the sid (D3:512-517). "Latched or budget-spent, then idle" is exactly the nudge condition and is a fresher oracle.

### D-9 (minor): latency is reintroduced on the Stop path, and the floor fails open under load

- The busy probe brings back a process-table scan, `sb_busy_jobs` (`hooks/lib/session-busy.sh:274-300`). It includes an `lsof` pass. session-continue removed this scan for latency: "~60% of this hook's Stop time … hit its 5 s timeout on 45-59% of Stops" (`hooks/session-continue.sh:1093-1098`).
- It is bounded at 2 s and runs only on a Stop where the floor would fire. But "unknown ⇒ proceed" means that under load (measured `vm.loadavg` 292/256/230 now) the floor fires over running background jobs.
- A hook that hits its 10 s timeout loses its block silently.
- **Fix:** measure the p95 of the no-sentinel path with the floor before landing.

### D-10 (minor): the ledger's two outputs contradict each other on a part-gating ⛔

- On a part-gating ⛔, READOUT appends "drive anything else in your frozen scope first" (D3:381).
- `rung_next` still prints "STOP-ASK — … nothing below it closes" (`scripts/wrap-ledger.sh:3098-3102`), and D3 leaves it unchanged (D3:442).

### D-11 (minor): hermeticity seams

- session-continue gains an inline `${CC_TELEMETRY_DIR:-/tmp/cc-telemetry}` (D3:485). That is shape 5a (`scripts/test-hermeticity-lint.sh:106-111`) if it is written as an assignment.
- `CC_DECIDE_MEMSEARCH_BIN` (D3:1120) has no stated default. A bare `cc-memory-search` is shape 5b, because that is a tool this repo ships (`:166-171`).
- Every touched suite that names those subjects would have to pin the seam in `setup()`.
- **Fix:** resolve sibling absolute paths, as `CC_STANDING_GRANTS` already does (D3:226).

### D-12 (minor): "the same Stop sees the capture" is not guaranteed

- The ledger memo is keyed per event, never by store content (`maps/wrap-ledger.md:249-252`), and every Stop hook runs on each Stop (`hooks/completion-assert.sh:1245-1246`, citing `hooks/hook-chain.sh:78`).
- A body computed by another hook before the intake write can be served. The floor then fires one Stop later than D3:542-543 claims.

### D-13 (minor): text inaccuracies the new pins would freeze

- The new R:68 says "`cc-decide open` refuse[s] … N > 90" (D3:835). D18 makes class A accept N > 90 (D3:1126).
- A superseded class-C packet is written `status:"actioned"` (D3:184). The verb's documented meaning is "the decision was carried out" (`bin/cc-decide:38`). Every reader that treats "actioned" as "answered" (digest, board) needs a `superseded_by` guard, and D3 adds one only to the search corpus (D3:771-772).

### D-14 (major, scope): size

- **Files**, counted from D3 §2-§15:
  - 19 production or doc files: `bin/cc-decide`, `scripts/wrap-ledger.sh`, `hooks/session-continue.sh`, `hooks/dod-persist.sh`, `scripts/lead-supervisor.sh`, `bin/cc-memory-search`, `scripts/xvendor-review.sh` (new), `hooks/operator-readout.sh`, `hooks/completion-assert.sh`, `hooks/anti-deference-nudge.sh`, `hooks/dispatch-assert.sh`, `hooks/lib/why-tier.sh`, `commands/wrap.md`, `scripts/research-kit/lib/gate_sweep.py`, `config/standing-grants.json` (new), R, S, G, `scripts/supervisor-e2e.sh`;
  - 16 test files, 4 of them new;
  - **≈ 35 files in all, far past the 6-file threshold, so this needs teammates.** D3 never says so.
- **Lines**: about 2,000, including about 950 of tests (D3's own estimate, D3:1209-1225). It is plausible from the per-file sketches.
- **Tests per full pass**:
  - 928 existing tests in the touched suites (measured, `grep -c '^@test'` over the 13 suites);
  - plus about 90 new (counted from D3 §14);
  - ≈ 1,020 in all.
- **Run time**: about 6 s per test at load ~250 (estimated from the one measured rate, `maps/test-infra.md:65-72`). cc-bats admits only 2 bats roots under load (`bin/cc-bats:514-515`), so teammates cannot parallelise beyond 2. That puts a full pass at **≈ 50 min wall** (estimated).
- **Land smoke**: with more than 50 direct suites it will be cut or shed (`maps/test-infra.md:192-195`), so every suite must be hand-run with the `1..N` check.
- **What to do**: D3's 5-land rollout (D3:1194-1207) is the right split. Assign one owner per land and state the teammate plan.

## 3. Instruction budget, rule text and deploy path

**Budget, measured.** I reproduced D3's table with `python3 -I` over D3's `budget:` blocks and the live R/S lines (UTF-16 units, newline included):

| Block | Old | New | Delta |
|---|---|---|---|
| R:4 | 692 | 480 | −212 |
| R:13-18 | 630 | 149 | −481 |
| R:26 | 310 | 406 | +96 |
| R:38 | 171 | 307 | +136 |
| R:39 | 260 | 110 | −150 |
| R:68 | 896 | 973 | +77 |
| R:92 | 92 | 124 | +32 |
| R:103 | 103 | 151 | +48 |
| R:146 | 397 | 333 | −64 |
| R:160 | 518 | 676 | +158 |
| R:189 | 442 | 457 | +15 |
| R:217 | 733 | 525 | −208 |
| R:225 | 199 | 251 | +52 |
| S grant bullet | 0 | 495 | +495 |
| **R net / S / total** | | | **−501 / +495 / −6** |

- Every line matches D3:917-933 exactly.
- **One-in-one-out holds.**
- The user tier stays breached: 61,074 − 6 = 61,068 > 60,000 (estimated by arithmetic from `maps/rules-text.md:185-187`).
- Any slim edit triggers the deferred F1 re-gate debt, and D3 surfaces it as an operator question (D3:1236-1238).

**The cuts are true restatements.** Each cut sentence survives elsewhere (read with `sed -n`):

| Cut | Survives at |
|---|---|
| 🚀 parenthetical | R:96 |
| 👤 sentence | R:97, R:193 |
| background verifier | R:106 |
| PASS/FAIL | R:72 |
| unconvicted 🔧 | printed by `scripts/wrap-ledger.sh:2669` |

**Existing rule pins are untouched.** `tests/research-program-exemption-rules.bats:33-38` and `tests/close-research-pending-rules.bats:16-41` grep phrases D3 keeps.

**Deploy path is fine apart from D-5's relative path.**
- R and S deploy by copy through `install.sh:1113-1139`.
- G goes to `CLAUDE.full.md`, which no session loads; D3 treats it as the full-variant mirror.
- New scripts get per-file symlinks at converge. They read 🚀 (`LIVE_ADDS`) until then, which is normal.
- `config/standing-grants.json` is not deployed, but both readers resolve it through the real path into the checkout:
  - cc-decide: `self_path`, `bin/cc-decide:395-402`;
  - cc-memory-search: Python, `os.path.realpath`.

## 4. Testability ("RED without its change")

- **Every new check can be a bats test.**
  - The D, W, F, P, A, O, N and R series are RED today, because the flags, fields and floor do not exist.
  - Controls W2, W14 and A3 are labelled as controls.
  - The design also names mutants for the risky guards: W1 `has()` vs `//`, W5 session filter, F8 timeout-as-busy, F12 unwritable latch, D10 sid check.
- **Gaps:**
  - no test for the per-sweep cap (D-4);
  - no test for a part-gating packet plus foreign dirt plus a done-claim (D-1);
  - no test for superseding a legacy hard packet (D-2);
  - no test for sibling intake versus `DRAIN_SCOPE` (D-3);
  - A3's "unchanged" is wrong (D-6).
- **Host dependency.** F8 needs `timeout` or `gtimeout`. Both are at `/opt/homebrew/bin` on this box (measured, `command -v`). On a host without them the probe is skipped and the floor proceeds (D3:495-499), so F8's "busy ⇒ abstain" case would go red there.
- **Call-site churn is as stated.** Measured: `grep -c C_OK tests/cc-decide.bats` gives 20, and `grep -rn 'open --class C' tests/*.bats | grep -v C_OK | wc -l` gives 42, across 6 suites besides cc-decide.bats (cc-do, operator-readout, operator-readout-forks, research-kit-gate, wrap-ledger, wrap-ledger-memo).
- **No callers outside the repo.** `grep -rlE -- '--class C'` over `~/Development` (excluding .git, node_modules, worktrees and docs) found none outside claude-infrastructure (measured). In-repo production callers are only `gate_sweep.py` plus the text in dispatch-assert, why-tier and wrap.md, and D3 updates all of them.

## 5. What holds up, and is worth grafting

1. **Make cc-decide the one arbiter of what a packet gates.** Add a `gates` field and fold it once on the read side. An absent field means `all`. Consumers read it with `has()`, never `//`; jq's `//` turns `false` into the default (D3:312-314). That is a real trap, and the mutant W1 pins it.
2. **The class-C refusal is a safe escape path.** It prints a ready class-B command, built from the caller's own `--what`, conviction, receipt and options, as its **last** line. That survives the lead's `| tail -3` (D3:126-143). Refusing a missing declaration (never a similarity score) keeps the false-block cost at one re-run.
3. **The ruling hint at `open` is safe and effective.** It goes to stderr only, is bounded at 3 s, fails open, runs only for sessions, and is off on the Stop-hook path. D3 cites eb3dbe1e5e94 ranked first at ratio 2.88 for the B13 fork (D3:220, from `maps/ruling-discovery.md:174-175`).
4. **The loop floor is session-scoped.** `LOOP_OPEN` has an end marker, `Scope (done):`, and needs the `dod-persist.sh:487` prefix fix. It is kept **out of** `REMAINDER`, so handoff-fire's field-keyed self-close refusal is untouched.
5. **⛔ still outranks 📦 for every open class-C packet**, so the ship floor is never armed over a land that may be the gated act (D3:396-398).
6. **One keep-working predicate, `SCOPE_FLOOR`, computed in the ledger** and consumed by session-continue and the supervisor. The latch is per decision set with a total cap, never per session lifetime, and every stand-down on ⛔ is logged.
7. **The intake capture picks the right line.** It takes the **first** human or own-text `Scope (frozen):` line and filters by record type (TX:14 vs the TX:3875 lane brief). Graft it only together with the D-3 fix.
8. **A budget-neutral rule rewrite whose numbers reproduce exactly**, paid for by cuts that are verified restatements.
9. **The supervisor nudge goes straight to `cc-notify <sid>`**, not through the dead page channel. It runs in shadow mode for the first week and re-checks after 1 h following a `wake-path-armed` delivery. Graft it with a file-backed sweep cap.
10. **`xvendor-review.sh` moves the 80% meter guard and the API-key strip into tracked code**: `env -u OPENAI_API_KEY`, `git archive` export only, and a per-repo exclude list.
