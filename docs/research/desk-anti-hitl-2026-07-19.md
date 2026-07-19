# Desk anti-HITL design — cross-account visibility · permission autonomy · handoff-fire reliability

**Status:** design (Fable research, 2026-07-19). Implementation items in `cc-backlog` (source `desk-observed`).
**Rule for all three:** the *recovery/automation is the dangerous actor* — boundaries sit at **provable** safety (live state predicates, positive identity proof, fail-closed), never at pattern-matching worker-influenced content. A weak boundary is strictly worse than the human-in-the-loop status quo.

---

## Part A — full 4-account visibility before handoff

**Finding.** `bin/claude-accounts` always emits a `--json` row per account (auth + error set), but when auth is broken (`logged-out` / `token-invalid` / `keychain-error`, or `stale`+401) the **quota numbers are absent** and `_excluded()` (`:390-391`) drops it from routing. So the gap is not *whether* an account is seen — it's *how much quota is stranded* on it. Stale-with-live-sessions stays readable (live CC refreshes the token); stale+idle self-heals (`:235-267`, gated to zero-live-session, GH #54443 rotation race — never weaken). Uncovered autonomously: `logged-out`/`token-invalid`/`keychain-error` (relogin exists, `skills/account-relogin`, but nothing auto-triggers it) and `stale`+idle-live-session (un-healable by design). The `/handoff` bridge carries **no** account state (`commands/handoff.md`); `--rank` silently omits errored accounts; the `prev` snapshot survives one sweep and never populates a logged-out row → two sweeps after a logout the last-known number is gone everywhere.

**Recommendations (ranked).**
1. **Last-good quota ledger inside `claude-accounts`** (highest leverage, smallest diff): generalize the 429-fallback inheritance (`:341-355`) to all quota-absent states, sourced from a TTL-free per-account `last_good` block persisted **outside `/tmp`** (`~/.claude/logs/claude-accounts-lastgood.json`), always stamped `quota_as_of` + `stale_quota:true` so the **router still excludes** (no policy change) while `--json`/table/successor all see "next3 logged-out; last-known weekly 31% @ 09:40". Zero new consumer plumbing.
2. **Pre-handoff sweep duty**: before firing, `claude-accounts --fresh` (exercises auto-heal), and for any logged-out/token-invalid/keychain-error row run account-relogin Phase 1 (headless when `has_refresh_token:true`) or embed one bridge line naming the account + last-known quota + relogin pointer.
3. **Page the desk on `stale`+idle-live-session+401** so it can nudge the idle session (any API call self-refreshes). Never weaken the k==0 heal gate.
4. **Reject** per-account live self-reporting (anti-correlates: the states that lose visibility have no live session to report).

---

## Part B — permission-prompt autonomy

**Root cause correction.** Allow-sets are **byte-identical across all 5 config dirs** (349 allow / 6 ask / 41 deny). `git reset --hard:*` is in the **`ask`** array (`settings.json:404-410`) — a deliberate operator judgment point, everywhere. The 731f0968 worker prompted **by design**. The hang was **133 min** (not 30); the supervisor detected it at 30 min (`lead-supervisor.sh` STALL? at `STALL_S=1800`) but resolution took 2h13m because **nothing can answer a prompt** — approved manually.

**Verdict: the desk must never learn to press "1".** Keystroke-approval is fundamentally unsafe — screen-spoof (a worker renders a fake dialog in its own pane), TOCTOU (dialog changes between read and keystroke), and the **"Yes, don't ask again" ratchet** (one miskey → a *permanent* silent allowlist entry). Bounded loss (latency) vs unbounded loss (rewritten trunk / prod deploy / exfil).

**Solution (provably safe, in-band, fail-closed).**
1. **State-predicated auto-allow hooks** (extend `rm-safe-allowlist.sh` pattern; the binary supports `PermissionRequest` decision hooks with `tool_input`, harness-authored). For the incident class: allow ONLY the anchored single command `git reset --hard origin/main`/`@{u}` (compound/substitution/redirect/newline defer — ship-rail metachar guard `ship-rail-push-allow.sh:48-50`) **AND** `git status --porcelain` empty at decision time (clean tree ⇒ reflog-reversible) **AND** cwd in a sanctioned worktree. Same-process hook checks state atomically with the decision — keystrokes never can. Fail-closed: hook silence/parse-error ⇒ normal prompt.
2. **PermissionRequest beacon**: a hook writes `/tmp/cc-permission-pending/<sid>.json` {ts, tool_name, tool_input, cwd}; cleared by PostToolUse/PermissionDenied/SessionEnd. `lead-supervisor.sh assess` reads the dir → pages "PERMISSION-PENDING: `<cmd>` since `<ts>`". Unspoofable (harness-emitted).
3. **Wire Pushover** (`push-critical.sh:10-11`, one env-var from live) so escalations break through.
4. **Latent gaps found**: `ship-rail-push-allow.sh` + `smart-bash-allowlist.sh` committed (`9d2bf16`) but **wired nowhere**; deny-floor misses `git push --force-with-lease:*` and `+`-refspec pushes and doesn't executable-block `--dangerously-skip-permissions` (only prose at `settings.json:985`).
5. **Sequencing**: wire `ship-rail-push-allow.sh` → add beacon → add reset-hard shape hook in **shadow (log would-allow)** → arm after clean soak (`waiting-recycle.sh` arm/shadow discipline). Each step independently reversible.
**Desk keystroke-approval: keep at the empty set.** The PermissionRequest decision hook dominates it on every axis.

---

## Part C — handoff-fire reliability (focus-steal, mis-injection, detect, recover)

**Headline defect — the fire STEALS OS FOCUS.** `handoff-fire.sh:1095` calls `it2 session focus "$id"` → `async_activate(order_window_front=True)` (iterm2 `session.py:619-637`; "brought to the front and given keyboard focus") — the it2 0.2.3 CLI hardcodes the raise, **no suppress flag**. *Plus* the split itself (`async_split_pane`) makes the child the active session **within the tab regardless of any focus call**, so a default `split-right` of the operator's own active window jumps keyboard focus off the desk pane. Collision chain (matches the incident): operator typing "could o…" → desk fires → focus yanked onto the child mid-keystroke → remaining keystrokes interleave with the injected `cd …` → "ould ocd" → zsh autocorrect holds → launcher never runs → the brief (`"$(cat F)"` arg) hits a broken line → shell parses fragments (Rails/gate/C10 not-found). `d662845` fixed app-frontmost *drift* (wrong window) but left the *raise of the right pane* — drift ≠ steal.

**Compounding cause.** cc-backlog fold recognizes only `done|claimed|open` (`:78-81`); the worker-blocker brief says `cc-backlog reopen $id` (`cc-dispatch:212`) → `open` → re-dispatchable next tick. **No "blocked/hold" state**, so operator-gated items thrash (63fab19b9a27 Kimi ×3, T-P10-7).

**Recommendations.**
1. **PRIMARY — fire without stealing focus:** never `session focus`/`order_window_front=True` on an autonomous fire (extend the `~/.claude/bin/it2` shim with a `focus --no-raise` / background-create verb, or drive the iterm2 Python API with `order_window_front=False, select_tab=False`); **don't split the operator's active pane** — create the fired surface in the **background** (new tab in a non-frontmost window, or a window created without `activate`). Keep the raise only behind explicit `--follow` for manual `/handoff`. Post-condition: capture active-session-id before/after the fire, assert unchanged, fail loud.
2. **DETECT (echo-back, fast):** the `HANDOFF-ENGAGE-<pid>-<ts>-<rand>` marker + `verify_engagement` (`:253-271`) already exist but catch a shell-corrupted fire only after the 120s transcript wait. Add an echo-back probe: `it2 session read -s "$pane"` post-inject, confirm the launch line appears intact-and-alone (no interleaved chars, no `command not found`, no `zsh: correct`). Treat no-engagement-in-Ns OR echo-mismatch OR focus-changed-post-condition as one failure class. **Un-swallow**: `cc-dispatch:219` (`>/dev/null 2>&1`) must capture the fire's stderr to the IDL.
3. **RECOVER only on positively-identified scratch pane:** reopen the item; re-fire onto a **new** background pane — **never** re-send into the same pane (fix `verify_engagement:262`'s in-place re-send, which currently compounds mis-injection). Clear a mis-targeted pane ONLY if the desk can PROVE ownership (UUID == the `it2_split`-returned pane AND in cc-registry as desk-spawned AND no foreign `HANDOFF-ENGAGE`) — else **surface, never clear**. Never inject into / `/exit` / clear the operator's active pane (the recycle path `:1205,1228` needs the same refusal split got).
4. **Add a `blocked`/`hold` state to cc-backlog** (new fold event, `:78-81`) excluded by cc-dispatch's filter (`:116`); change the worker-blocker instruction from `reopen` to `hold`. Removes the thrash.
5. **Adversarial:** recovery is the dangerous actor — a "clear the scratch pane" heuristic can wipe the operator's live shell on mis-ID; boundary = positive UUID-provenance proof, never content pattern-match (spoofable). Input-idle gate (tty-mtime / KeystrokeMonitor) is **defense-in-depth only** (it races, can be starved → strands work, is a proxy) — the load-bearing fix is architectural: a background fire that never moves focus has no race to lose and no operator to starve.
