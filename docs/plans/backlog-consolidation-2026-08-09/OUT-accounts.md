# cluster-C-accounts — triage vs origin/main @ 51bdb524720aeb6c2fd49d14c1c584dce1456650

(`51bdb524 test(it2-kitty-operator-safety): …` 2026-08-09 16:51:57 -0700. All checks are git
reads / file reads / grep + two keychain existence probes. No suite was run; load was 10.08/core.)

## Summary

counts: PRUNE 1 / UPDATE 3 / KEEP 10 / MERGE 0   (= 14, slice size 14)

## Verdicts

`f82a43651c00` | PRUNE | Both halves refuted. (a) The item's own date list ends **Jul 31**; it was filed Aug 9, so the phenomenon had already self-terminated for 9 days. (b) Its hypothesised mechanism — "resolving the ERASED `~/.claude` credential" from `docs/research/forced-relogin-rootcause-2026-08-02.md` §4 ("`~/.claude` is logged out RIGHT NOW") — is dead: measured today, **both** keychain spellings are PRESENT (`Claude Code-credentials` and `Claude Code-credentials-7b461744` = sha256(`~/.claude`)[:8], per `bin/claude-accounts:190-194` `keychain_service()`). No erased credential ⇒ no daily login prompt to burn. Not re-run `auth-error-rate.py` (contract forbids long runs); the two premises above are sufficient positive evidence.

`14bcdfee2eb8` | KEEP | Re-verified on trunk today: `hooks/plan-agent-teams-default.sh:16-27` sets `IS_PLAN` from plan-file path patterns only, then `[ "$IS_PLAN" = false ] && exit 0`; `hooks/validate-plan-structure.sh:52-65` does the same. Neither can fire on an operator-feedback implementation path. **Park condition is worse, not better**: item parked at load 2.09/core, machine is now at **10.08** — re-fire is further away than when filed. ⚠️ Landmine: the cited brief `docs/ground-up-payloads/LOCUS-GAP-BRIEF-2026-08-08.md` is **UNTRACKED** — `git ls-tree origin/main` returns nothing and `git log -- <path>` is empty. It exists only in the shared checkout's working tree and dies with the next `git clean`.

`f272b30e66f5` | UPDATE | Premise "no instrument records a forced logout" is **refuted**: `tools/auth/auth-timeseries.sh` and `tools/auth/auth-error-rate.py` are both on trunk, landed by `2ec33a27 docs(auth): the forced-relogin investigation, and the instrument that had never existed` and `7954996f feat(auth-timeseries): record the keychain write time, not just the token hashes`. What is still true is narrower: the sampler is **manual and time-bounded** — `auth-timeseries.sh <out.jsonl> [interval_s=60] [duration_s=21600]`, i.e. a 6-hour ad-hoc run writing to a caller-supplied path. Nothing schedules it (the only LaunchAgent in the family is `com.claude.relogin.plist`), and no durable per-account store accumulates. Item should now read: *schedule the existing sampler and give it a durable append store, so a forced logout leaves a trace after the session that observed it ends.* (Its `needs:` "persistent thrash / worker cannot land" is a store-level flag about the worker, not about this premise.)

`2203b8190752` | KEEP | Genuinely operator-only and unrefuted. `docs/research/cloud-observability-2026-08-07.md` is on trunk (blob b8678d29); `bin/cc-cloud` still ships `poll`/`--state`, and nothing on disk records a cloud session ever reaching a non-`NOT-STARTED` state. Requires a human to open the web transcript — no CLI path exists (teleport stops at the folder-trust dialog; the REST path needs the account OAuth token). ⚠️ Belongs in a **cloud** cluster, not accounts — see Notes.

`62a4fb787e85` | KEEP | Premise verified intact today. `bin/cc-relogin:161 def live_sessions()` still carries the docstring *"Mirrors claude-accounts concurrency() (bin/claude-accounts:268-315) exactly"*; `bin/claude-accounts:268 def concurrency()`. Both cited shas are ancestors of trunk (`f8178bfe fix(accounts): a rejected grant must outlive the sweep that found it`, `8eb83ed1 fix(cc-relogin): "mirrors concurrency() exactly" is a claim this file cannot check, and it went false`). **No parity test exists**: the only adjacent coverage is `tests/cc-relogin.bats:281-305`, whose own comment says it is *"Pinned per-file rather than trusting live_sessions()'s 'mirrors concurrency() exactly' docstring"* — i.e. it exercises one implementation against a fixture and deliberately does **not** compare the two. Nothing feeds one ps fixture to both and asserts equal counts.

`01487ffd8417` | UPDATE | Core work live, stated precondition stale. Still live: `scripts/relogin-probes/e1-concurrent-logins.sh` on trunk, and `docs/plans/RELOGIN_BUILD_CONTRACT.md:543` — *"Built behind a flag, inert by default, **not activated**. Gated on E1's verdict and the operator's §4.4 Variant-A-vs-B call."* So the de-sharing stack is still built-and-inert behind exactly this decision. Stale: the item's *"next3 (0 live sessions)"* is refuted by today's measurement — **next3 carries 4 live sessions**. Item should state the zero-live-session requirement as a **precondition to re-check at fire time** (and name which account is idle then — today that is next2), not as a fact about next3.

`f3e662d4e2a8` | KEEP | Unrefuted value decision, no code to decay. `docs/plans/CONCURRENCY_PROGRAM.md` on trunk (blob eb9a0ce6) with the subscription reasoning intact at :587 (*"Claude Code on the web is subscription-billed"*), :602, :605 (*"There is no subscription-backed path"* for Managed Agents). Nothing has decided a target session count. `blocked`/`needs` is worker thrash, not a fact about the item.

`e9245cc24dff` | KEEP | Standing guard, and today it has **zero enforcement surface**: `grep -rn -i 'usage credit'` over `bin/` and `docs/plans/` returns nothing, and `~/.claude/accounts.json` (the account SSOT) carries no credits field. Nothing asserts the toggle, nothing renders it, no test pins it — the guard exists only as this backlog row, which is exactly the "advisory behind a diode" failure. Keep, and fold into M-C-3 where it becomes an assertion instead of a memo.

`9d514681fb84` | KEEP | Every number in the item re-verified today, unchanged. `~/.claude/accounts.json` `"login_warn_h": 72.0`; `bin/claude-accounts:2056 RELOGIN_TRIGGER_H = 7 * 24` and :2122-2123 renders `DUE` inside it with a `NEXT ACTION` column (:2148); `bin/cc-relogin:65 WARN_H = float(_env("CC_RELOGIN_WARN_H", "72"))` and :645 `raise Bail(EXIT_REFUSED, f"no re-auth needed — {why}")`. No `--force` flag anywhere in `bin/cc-relogin`. The 72h→168h dead band is fully intact.

`37a0b651bcce` | KEEP — and **sharper than filed: it is now three spellings, and one is live-wrong.** `bin/cc-claude-bin` landed (`24e2a44a fix(claude-bin): one resolver, because two copies of the pin had already drifted`, ancestor) and resolves correctly to `~/.claude-220/node_modules/.bin/claude`. Branch `fix/accounts-eval-bin-resolver` (tip `1a2c536a fix(accounts): derive the eval binary instead of trusting a hand-copied pin`) is **NOT** an ancestor of origin/main — still parked. Meanwhile `scripts/handoff-fire.sh:230 _resolve_eval_bin()` is a second, independent implementation on trunk (with its own stale fallback literal `~/.claude-219`), and `~/.claude/accounts.json:13 "claude_bin": "~/.claude-219/node_modules/.bin/claude"` is a third — a hardcoded literal that is **stale today**: `~/.claude-219` is 2.1.219, `~/.claude-220` is 2.1.220, and `claude()` (.zshrc:497) launches 220. That literal is consumed by `bin/claude-accounts:378, :2194` and `bin/cc-relogin:277, :465`, so account certification and the relogin gate are measuring 2.1.219 while every session runs 2.1.220 — verbatim the recurrence `_resolve_eval_bin`'s own header warns about (*"for a week probe_account() certified accounts against ~/.claude-183 while every successor launched ~/.claude-219"*).

`d5842487233e` | KEEP | Operator-only, unrefuted. `docs/plans/CLOUD_OBSERVABILITY.md` on trunk (blob e80ac71e); the token is mintable only in the web UI ("shown once, CLI cannot mint it") and no token field exists in `~/.claude/accounts.json`. ⚠️ Belongs in a **cloud** cluster — see Notes.

`80e6637dfd9e` | KEEP | Both halves verified exactly as filed. SSOT: `~/.claude/model-config.yaml:331-332 effort_defaults: default: max`. Launcher: `.zshrc:451 claude()` → `:497 local _eff="${CLAUDE_EFFORT:-${CLAUDE_OPUS5_EFFORT:-high}}"` → `:498/:502 --effort "$_eff"` = **high**. The re-sweep genuinely never ran, and the SSOT convicts itself at `:68-70` — *"RE-SWEEP effort (see effort_defaults § opus5): Opus 5's own default is `high`, NOT max … Our global default:max is WRONG-SIGNED for Opus 5."* (Trap for whoever fixes it: `tests/effort-parity.bats:20-24` hard-codes `default: max` in its hermetic fixture, and its final case runs `scripts/effort-parity-assert.sh` against the **real live host** — flipping the SSOT moves that live assertion. Fixture edit + live re-check both required. Note the stable track is unaffected: `claude-prev()` at .zshrc:173/175 does pass `--effort ${CLAUDE_DEFAULT_EFFORT:-max}` with `:80 CLAUDE_DEFAULT_EFFORT="${CLAUDE_DEFAULT_EFFORT:-max}"` — so `max` is correct *there* and the disagreement is `claude()`-only.)

`791345455b58` | UPDATE | The sweep landed and is gated; the item's numbers are superseded. `3dcac1f3 fix(pipefail): an early-exit pipe consumer reads FALSE on a match, and 22 sites were doing it` (ancestor, HEAD~4) landed `scripts/pipefail-sigpipe-lint.sh` (476 lines), `tests/pipefail-sigpipe-lint.bats` (158 lines / 14 tests) and `scripts/pipefail-sigpipe-allow.txt`, and it is **wired into the land gate** at `scripts/ship-land.sh:1499` (`PF_LINT="${SHIP_LAND_PIPEFAIL_LINT:-scripts/pipefail-sigpipe-lint.sh}"`, with explicit selftest-failed and could-not-run arms) — i.e. it reached the chokepoint, not just its own suite. The cited 66% false negative in `cc-relogin-poll` was fixed separately by `43bfa756 fix(relogin): §2 help probe inverted by pipefail — the poller went blind 66% of the time`, and `bin/cc-relogin-poll:181-183` now carries the standing rule. The census "358 candidate sites / 102 files" is explicitly retracted in `docs/plans/RELOGIN_BUILD_CONTRACT.md:161-167` and re-derived: 615 candidates → 315 files enabling pipefail → **367** in a status-consuming position → 22 fixed, **30 grandfathered by file** in the allowlist. Item should now read: *burn down the 30 grandfathered sites across 17 files in `scripts/pipefail-sigpipe-allow.txt`* — the lint is a **downward ratchet** (it reds both when a file gains a violation and when it loses one without the count being lowered, `pipefail-sigpipe-lint.sh:43-57`), so this is mechanical, self-policing, and cannot silently become a permanent exemption.

`39aae25d401b` | KEEP | Premise verified, still blocked for the reason stated. `d022242d fix(cc-authbrowser): the frozen CDP port was a hard requirement, so phase 2 could never launch` **is** an ancestor of trunk (launch blocker fixed+landed, as the item says); `scripts/relogin-probes/e3-warm-profile-authorize.sh` is on trunk. And the gate would still refuse today: `bin/cc-relogin:65` `WARN_H=72`h vs the lead's live measurement of **no login expiry inside 20 days** on all four accounts, so `need_relogin()` (:223-224) is False and `run()` bails `EXIT_REFUSED` "no re-auth needed". Human-gated by design — spends one real re-auth.

## Master item(s)

Three, and the third is the weakest-justified — see its own note.

### M-C-1 — Every account/runtime fact gets ONE derivation and ONE assertion that its consumers agree

**Encompasses:** `62a4fb787e85`, `9d514681fb84`, `37a0b651bcce`, `80e6637dfd9e`, `791345455b58`, `14bcdfee2eb8`

**Why one effort:** six instances of a single defect — *a fact with one true source is re-spelled in each consumer, and nothing checks the copies agree*. Live-session count is written twice (`live_sessions()` / `concurrency()`, drifted 5 days). The login-cliff threshold is written three times (72 / 168 / 72) and the middle one prescribes a command the third refuses. The eval binary is written three times (`cc-claude-bin`, `_resolve_eval_bin`, `accounts.json:claude_bin`) and the third is stale by a whole minor version *right now*. The effort default is written twice (SSOT `max`, launcher `high`) and the SSOT documents its own wrongness. The last two are the same family one step out: `791345455b58`'s residual is *"the assertion exists, the exemption list has not been burned down"*, and `14bcdfee2eb8` is *"the rule reaches only one of its two paths, and nothing checks the other"*. Every fix has the identical shape — collapse to one derivation, then land an assertion at the chokepoint that reds when a copy reappears. This is one session's muscle memory applied six times, not six investigations.

**Impact, from evidence:**
- **Loss of an account is the worst case, and it is live.** `62a4fb787e85`'s drift *opens* the rotation-safety gate: `run()` refuses only on `k != 0`, so an undercount green-lights a token redemption alongside live sessions that rotate it — the loser holds a retired grant and takes a `400 invalid_grant` with the calendar cliff still weeks away (`bin/cc-relogin:161-183` docstring, measured next3 showing 10 where 15 ran).
- **Two enforcing stores are wrong today, not hypothetically.** `accounts.json:claude_bin` → 2.1.219 while `claude()` launches 2.1.220, consumed by 4 call sites in `claude-accounts` + `cc-relogin`; `model-config.yaml effort_defaults.default: max` is the SSOT every routing reader quotes.
- **`791345455b58` already blocks the land rail** — its lint runs inside `ship-land.sh`, so its allowlist is on the path of *every* land.
- Closing this retires 6 of the 10 surviving items in this slice.

**DoD:** one parity test feeding a single `ps` fixture to both `live_sessions()` and `concurrency()` and asserting equal counts; one SSOT constant for the login-renewal threshold read by `claude-accounts --relogin-status` **and** `cc-relogin` (or an explicit `ADVISORY` band for 72–168h with `DUE` reserved for what `cc-relogin` accepts — the item names both options and either satisfies this); `accounts.json:claude_bin` and `handoff-fire.sh:_resolve_eval_bin` both collapsed onto `bin/cc-claude-bin` (land or retire `fix/accounts-eval-bin-resolver`); `effort_defaults.default` re-swept to match `claude()` with `tests/effort-parity.bats`'s fixture and live case updated together; `scripts/pipefail-sigpipe-allow.txt` at zero entries; the Execution-Locus gate reaching the non-plan-authoring path. Landed on trunk, gates green.

**Falsifier** (exit 0 ⇒ the whole effort is unnecessary):

```
cd ~/Development/claude-infrastructure && git ls-files tests/ | xargs grep -lq 'live_sessions' 2>/dev/null && python3 -c "import json,os,subprocess,sys;c=json.load(open(os.path.expanduser('~/.claude/accounts.json')));sys.exit(0 if os.path.expanduser(c['claude_bin'])==subprocess.run(['bash','bin/cc-claude-bin'],capture_output=True,text=True).stdout.strip() else 1)" && ! grep -qE '^\s+default:\s+max\b' ~/.claude/model-config.yaml && [ "$(grep -cvE '^\s*#|^\s*$' scripts/pipefail-sigpipe-allow.txt)" -eq 0 ]
```

**First move:** `37a0b651bcce`'s third spelling — `~/.claude/accounts.json:13` still pins `~/.claude-219` while `claude()` runs 220. It is a one-line change with four consumers, it makes the whole class concrete in ten minutes, and it is the only member currently producing a wrong measurement.

**Order:**
1. `37a0b651bcce` — collapse the three eval-bin spellings onto `bin/cc-claude-bin`; land or retire `fix/accounts-eval-bin-resolver`. (Smallest, live-wrong, teaches the pattern.)
2. `62a4fb787e85` — the parity test. (Highest consequence; one test, no production change, per the item's own scope line.)
3. `9d514681fb84` — unify the login threshold or add the ADVISORY band. (Depends on nothing; blocked by no decision — the item states both acceptable fixes.)
4. `80e6637dfd9e` — effort re-sweep; fixture + live case in `tests/effort-parity.bats` move in the same diff.
5. `791345455b58` — burn the 17-file / 30-site allowlist to zero. (Mechanical; the ratchet reds on any regression, so it can be done incrementally without a flag day.)
6. `14bcdfee2eb8` — extend the Execution-Locus gate past the plan-authoring path. **Do first**: `git add` the untracked brief `docs/ground-up-payloads/LOCUS-GAP-BRIEF-2026-08-08.md`, or it is one `git clean` from gone.

### M-C-2 — Prove the re-login stack end to end, with a recorder running that outlives the session

**Encompasses:** `01487ffd8417` (E1), `39aae25d401b` (E3), `f272b30e66f5` (auth time series)

**Why one effort:** the phase-5 de-sharing stack is already **built, flagged off, and gated on exactly one decision** — Variant A vs B — and `RELOGIN_BUILD_CONTRACT.md:543` says only E1's verdict settles it. E3 is the never-completed other half of the same proof (launch blocker fixed and landed at `d022242d`; the OAuth drive *after* launch has still never run to completion). And `auth-timeseries.sh` is the instrument that would record what either probe does — but it is a 6-hour manual sampler nothing schedules, so today a forced logout during a probe would leave no trace once the observing session ends. Running the two probes *with the recorder already scheduled* is one sitting; running them separately wastes the one real re-auth E3 spends.

**Impact:** unblocks a fully-built, currently-inert subsystem whose stated purpose is fixing the 6–12h logout race — the failure that costs an account until a human re-logs in. Both probes require a real browser Authorize, so this effort is the *only* place in the slice where operator presence buys something irreversible; batching them makes that presence cost one window instead of two.

**DoD:** E1 run and its verdict written into `docs/research/RELOGIN_E1_E3_VERDICT_TEMPLATE.md`'s filled successor; the Variant A/B call recorded; phase 5 either activated or explicitly retired on the verdict; E3 run to completion with the OAuth drive proven; `auth-timeseries.sh` scheduled (LaunchAgent alongside `com.claude.relogin.plist`) appending to a durable per-account store outside `/tmp`. Landed on trunk.

**Falsifier:**

```
cd ~/Development/claude-infrastructure && git ls-files docs/research | grep -iE 'relogin.*(verdict|e1|e3)' | grep -qv 'TEMPLATE' && launchctl list 2>/dev/null | grep -qi 'auth-timeseries'
```

(Deliberately the weakest of the three falsifiers — E1/E3's completion has no machine-readable footprint today. The scheduled-sampler half is exact; add a `verdict=` token to the filled verdict doc when E1 runs so this becomes checkable, per memory *claimed-outcome-vs-checked-outcome*.)

**First move:** schedule `tools/auth/auth-timeseries.sh` **before** touching either probe — the recorder must be running when the probes are. Then pick the idle account at fire time (today next2 at 0 live sessions; **not** next3, which now has 4) and run E1.

**Order:** 1. `f272b30e66f5` (recorder first — it is the instrument for the other two) → 2. `01487ffd8417` (E1; unblocks the Variant call and the inert stack) → 3. `39aae25d401b` (E3; spends the one real re-auth, so last, and only when an account is genuinely near its cliff — no account is inside 20 days today).

### M-C-3 — Put a measured floor under the four-subscription pool that cloud and scale spend from

**Encompasses:** `e9245cc24dff`, `f3e662d4e2a8`, `2203b8190752`, `d5842487233e`

**Why one effort:** all four are the same ceiling — the rate-limit pool of four Max subscriptions. `f3e662d4e2a8` says the ~100-session target is a subscription-count question because cloud is free of compute but *not* of pool. `e9245cc24dff` is the one guard that stops pool exhaustion from becoming a bill, and firing more cloud sessions is precisely what raises the chance of hitting it. `2203b8190752` and `d5842487233e` are the two blockers on ever *observing* what a cloud session spends — 11 fired, none with a remote-visible action. You cannot decide the target count without observing the spend, and you must not raise the count without the guard asserted. One effort, one decision.

**Weakness, stated:** its first two steps (`2203b8190752`, `d5842487233e`) are genuinely operator-only web actions with no CLI path, so a session picking this up will stall at step 1 unless the operator is present. If the lead prefers, split those two into a cloud cluster's master and leave this as the two-item spend-governance effort — that is a clean cut, and the reason this master is third rather than first.

**Impact:** `e9245cc24dff` currently has **zero enforcement surface** (no grep hit in `bin/`, `docs/plans/`, or `accounts.json`) — a standing cost guard that exists only as a backlog row is the "advisory behind a diode" failure, and the thing it guards against is a real bill. `2203b8190752` blocks *every* S5 cloud claim by its own text.

**DoD:** the `usage credits` state asserted from the SSOT (a field in `~/.claude/accounts.json` + a check that renders it, so the guard can go red instead of being remembered); one cloud session observed in a state other than `NOT-STARTED`, written up; the routine bearer token minted and stored; a target session count decided and recorded in `docs/plans/CONCURRENCY_PROGRAM.md` §S5b.

**Falsifier:**

```
cd ~/Development/claude-infrastructure && grep -q 'usage_credits' ~/.claude/accounts.json && git ls-files docs/research | grep -qi 'cloud.*transcript.*verdict' && grep -qiE '^\s*-?\s*target session count:' docs/plans/CONCURRENCY_PROGRAM.md
```

(Names artifacts this effort creates; exit 0 only once all three exist.)

**First move:** `e9245cc24dff` — the only member with no operator dependency. Add the credits field to `~/.claude/accounts.json` and a check in `bin/claude-accounts` that surfaces it, converting a memo into an assertion. Then queue the two web actions for the operator in one batch.

**Order:** 1. `e9245cc24dff` (agent-drivable now, no gate) → 2. `d5842487233e` (mint the token — unblocks the `/fire` path, which is proven to exist via the 401-vs-404 control) → 3. `2203b8190752` (read the web transcript — the only remaining instrument) → 4. `f3e662d4e2a8` (decide the target count, now with observed spend behind it).

## Notes for the lead

1. **Two items are mis-clustered into "accounts" and belong in a cloud slice.** `2203b8190752` and `d5842487233e` are both `docs/plans/CLOUD_OBSERVABILITY.md` / `docs/research/cloud-observability-2026-08-07.md` work; they landed here only because they touch account OAuth. If another agent's slice owns cloud observability, **merge both there** and drop M-C-3 to its two spend-governance members (`e9245cc24dff`, `f3e662d4e2a8`) — I flagged that cut inside M-C-3 rather than pre-empting your view of the other slices.

2. **`14bcdfee2eb8` also does not belong here** — it is a plan/hooks-gate item (`hooks/plan-agent-teams-default.sh`, `hooks/validate-plan-structure.sh`), not accounts. I assigned it to M-C-1 because its defect is genuinely the same family ("the rule reaches one path, nothing checks the other"), but if a plans/hooks cluster exists it is a better home. **Do not lose the untracked-brief warning in the move.**

3. **One live wrong measurement, worth surfacing above the triage.** `~/.claude/accounts.json:13` pins `claude_bin` at `~/.claude-219` (2.1.219) while `claude()` (.zshrc:497) launches `~/.claude-220` (2.1.220). Four consumers read it: `bin/claude-accounts:378, :2194`, `bin/cc-relogin:277, :465`. So account certification and the relogin gate are describing a binary no session runs — the exact recurrence `scripts/handoff-fire.sh:225-228` documents from the `~/.claude-183`-vs-`~/.claude-219` week. It is a one-line fix and it is wrong *today*; consider hoisting it out of M-C-1 into whatever "fix now" bucket you have.

4. **Cross-cluster duplicate risk on `791345455b58`.** Its dodRef is `RELOGIN_BUILD_CONTRACT.md`, but its subject is repo-wide shell hygiene and the lint sits in `scripts/ship-land.sh`. If a shell-hygiene or land-rail cluster also holds a pipefail item, these are the same work — canonicalise on whichever id carries the allowlist burn-down, since the census in *this* item's title is retracted upstream.

5. **`needs:` "persistent thrash — N fast claim→reopen cycles" appears on 6 of my 14 items** (`f272b30e66f5`, `f3e662d4e2a8`, `e9245cc24dff`, `9d514681fb84`, `37a0b651bcce`, `791345455b58`). That is a fact about a worker that cannot land, not about any of these items' premises — I ignored it for triage. But six items in one 14-item slice sharing one failure mode suggests a **store/worker-level defect worth its own item**; if other clusters report the same ratio, that is your real finding.

6. **Refuted-by-live-state check, as instructed:** nothing in this slice asserts an account is logged out, expiring, or that the Fable window has a deadline. `~/.claude/model-config.yaml:119-124` confirms `end: "2099-12-31"` (sentinel) and `active: true` "PERMANENTLY". `39aae25d401b` correctly *already* says "all 4 are healthy now, so cc-relogin's gate would refuse" — the live state confirms rather than refutes it. The one thing the live state *did* refute is `01487ffd8417`'s "next3 (0 live sessions)" — next3 now has 4, and next2 is the idle account.

7. **`f82a43651c00` is my only PRUNE and the only one resting partly on a probe rather than a git read.** The keychain probes were `security find-generic-password -s <name> -a chrisren` (existence only, no `-w`, no secret read) against both spellings from `bin/claude-accounts:190-194`. If you want a second confirmation before dropping it, the cheap one is re-reading `docs/research/forced-relogin-rootcause-2026-08-02.md` §4's premise against a fresh probe — but the item's own date list ending Jul 31 is independent and sufficient.
