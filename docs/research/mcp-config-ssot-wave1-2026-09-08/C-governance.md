# Wave 1 item 4 — what `tests/mcp-no-inherit.bats` + `tests/session-start-mcp-probe.bats` actually govern

Read-only research. Repo: `/Users/chrisren/Development/.worktrees/wt-9f203fa60cd0`. Nothing written outside this scratchpad.

## VERDICT (item 4): **PARTIALLY** — orthogonal in INTENT, coupled in MECHANISM, and the coupling fails SILENTLY with the guard suite GREEN.

- **"MCP servers must not be inherited" does NOT mean "accounts must not share a server set."** It means: *a session fired by `handoff-fire.sh` must not start the **PROJECT-scope `.mcp.json` stdio servers of the repo it lands in***, because a `-p`/headless/SDK worker loads **every** stdio server in the cwd's `.mcp.json` **without consulting any approval list** (measured 2.1.220, `04-spawn-semantics` Runs E/E2) — 312 MB per chrome-devtools chain. The rule is scoped to **project** scope and to **fired/headless** sessions.
- **The same mechanism goes out of its way to PRESERVE the account's user-scope servers** — that is the entire reason it composes `--strict-mcp-config` **plus** a `--mcp-config=<passthrough>` instead of `--strict-mcp-config` alone. So the SSOT's *goal* (every account resolves the same user-scope set) is what no-inherit already tries to protect. **No contradiction of intent.**
- **But the passthrough is BUILT BY READING `$CONFIG_DIR/.claude.json .mcpServers`.** The plan's DoD #2 ("MCP servers defined in exactly one place; **no user-scope duplicates remain**") deletes precisely that input. Consequences C1–C5 below. Two of them (C1, C3) are the plan *undoing a deliberate decision*; C5 revives a defect that was explicitly fixed.

---

## 1. Per-test invariant tables

### `tests/mcp-no-inherit.bats` (434 lines, 17 cases; subject = `scripts/lib/mcp-noinherit.sh` + its wiring in `scripts/handoff-fire.sh`)

Layer 1 — the composition decision (`cc_mcp_noinherit_args CONFIG_DIR [BRIEF]`):

| # | Test | Invariant, in one sentence |
|---|---|---|
| 1 | "default: composes strict-mcp-config and preserves the user-scope http servers" | By default a fire gets `--strict-mcp-config` **and** a `--mcp-config=` passthrough whose contents are exactly the account's user-scope non-stdio servers (`motion,motion-plus`), stdio dropped. |
| 2 | "an ALLOWLISTED user-scope stdio server survives the passthrough (the ms365 case)" | A user-scope **stdio** server named in `CC_MCP_USERSCOPE_STDIO_ALLOW` (default `ms365`) survives while an unlisted stdio server does not — i.e. it is an allowlist, not "stdio is fine now". |
| 3 | "CONTROL: with an empty allowlist the stdio server is filtered out again" | Set-but-empty `CC_MCP_USERSCOPE_STDIO_ALLOW=` reproduces the pre-2026-08-15 filter exactly, so the allowlist and nothing else is what admits ms365 (mutant control: a wholesale deletion of the stdio filter must fail here). |
| 4 | "the allowlist jq must not break the http passthrough (empty-passthrough regression)" | The allowlist jq must still emit ≥2 servers — a jq error would empty `pass` and fall through to **bare** `--strict-mcp-config`, dropping http servers too. |
| 5 | "ms365 is wired into every account config dir, and the wiring is idempotent" | `scripts/ms365-mcp-wire.sh` **merges** `mcpServers.ms365` into **every** account's `.claude.json` (per `accounts.json`), preserving `numStartups`/other servers, and `--check` re-runs clean saying "already correct". |
| 6 | "the passthrough uses `--mcp-config=VALUE` — the space form eats the prompt" | The `=` form is mandatory at the composer **and** on the typed line: `--mcp-config` is variadic and the space form swallows the fire's own prompt positional (real ENAMETOOLONG death, commit `03ae59251`). |
| 7 | "POSITIVE CONTROL: a brief that declares browser work leaves the servers ON" | A brief naming `mcp__*`/`browsermcp`/`chrome-devtools`/`agent-browser`/`claude-in-chrome` **disarms** the control entirely (empty args) and says why. |
| 8 | "the reason is never empty" | `CC_MCP_NOINHERIT_REASON` is always populated, including when the caller invokes the function the natural (previously subshell-swallowing) way. |
| 9 | "no user-scope servers → still isolates, and SAYS the http servers went too" | With an empty `.claude.json`, the composer emits **bare `--strict-mcp-config`** (all servers gone) and the reason must say so and name `--with-mcp`. **← this is the test that will NOT go red under the SSOT strip.** |
| 10 | "`CC_MCP_NOINHERIT=off` disarms it entirely" | The kill switch produces no flags and says `off`. |
| 11 | "handoff-fire --dry-run: default fire carries the isolation flags" | A real dry run's typed command carries `--strict-mcp-config` and prints `mcp:      project .mcp.json stdio servers OFF`. |
| 12 | "POSITIVE CONTROL: handoff-fire --with-mcp does NOT carry them" | `--with-mcp` produces no isolation flags and prints "project .mcp.json servers left ON". |
| 13 | "LIVE: a default-flagged session starts NO project stdio server, --with-mcp shape DOES" | Opt-in (`CC_MCP_LIVE_PROBE=1`): a real `claude -p` in a scratch project with a logging fake stdio server spawns ≥1 START unflagged and **0** with `--strict-mcp-config`, attributed by recorded parent argv (never by line count, because the SessionStart hook's own `claude mcp list` writes START lines into the same log). |

Layer 4 — the project `.mcp.json` **approval** axis (`cc_mcp_project_decision_args DIR MODE`), a *separate* axis from which servers load:

| # | Test | Invariant |
|---|---|---|
| 14 | "decision: a dir with NO .mcp.json costs no flag at all" | No project file ⇒ no question ⇒ no `--settings` flag. |
| 15 | "decision: MODE=off pre-REJECTS every declared server" | A no-inherit fire writes `{"disabledMcpjsonServers":[…]}` and **never** an `enabled…` key — a rejection may not be spelled as an approval. |
| 16 | "decision: MODE=on pre-APPROVES them" | `--with-mcp` (or an MCP-declaring brief) writes `enabledMcpjsonServers` and no `disabled…` key. |
| 17 | "decision: the two modes never share a file" | The off/on decision files have different paths, so an `--with-mcp` fire can never read a rejection left by a no-inherit fire. |
| 18 | "decision: a serverless or malformed .mcp.json emits nothing" | Never an empty-list flag (decides nothing, costs a flag). |
| 19 | "decision: `CC_MCP_DECIDE=off` restores the pre-change behaviour and SAYS so" | Kill switch, with a reason string. |
| 20 | "E2E: a fire into a dir carrying .mcp.json puts `--settings=` on the typed command" | End-to-end through `handoff-fire.sh --dry-run`: `--settings=<file>` (never the space form) whose file rejects `srvA,srvB`. |
| 21 | "E2E: `--with-mcp` flips the SAME fire to an approval" | Polarity follows the fire, so a fire launched to USE a repo's servers is not silently blinded to them. |

(The suite's own `setup()` pins `$HOME`, `CC_FIRE_CAPACITY_GATE`, `CC_ACCOUNTS_BIN`, `HANDOFF_ACCOUNT_SWEEP_STAMP`, `CC_HEAL_LOCK_PREFIX`, `KITTY_WINDOW_ID` — hermeticity, not MCP semantics.)

### `tests/session-start-mcp-probe.bats` (395 lines, 20 cases; subject = `hooks/session-start.sh`, the MCP *connectivity probe*)

| # | Test | Invariant |
|---|---|---|
| a | "(a) reports the RUNNING session binary's count, not the stale PATH binary's" | The probe must ask the binary the *session actually is* (resolver rung / PPID), never `command -v claude`. |
| a-ctl | "(a-control) the PRE-FIX artifact answers with the stale PATH binary" | Replays `54555bed1:hooks/session-start.sh` (a **pinned sha**, `37ef2489c^`) and asserts the old artifact reports 1 where the session holds 3 — the control that makes (a) non-vacuous. |
| a-b | "(a-b) degraded rows are not counted as connected" | `✔ Connected` counts; `! Connected` / `timed out` are reported as *degraded*, not connected (the old bare `grep -c Connected` said 3). |
| b | "(b) unresolvable binary says UNKNOWN, and a real zero says zero" | "could not ask" and "answered zero" must be **different strings**; UNKNOWN says "NOT a report of zero connected servers". |
| b-b | "(b-b) both states emit ONE parseable JSON object" | SessionStart output stays a single valid JSON doc in both states. |
| c / c-b | "(c) the probe child is PANELESS" (+ no-timeout fallback) | The `claude mcp list` child runs under `env -u CC_PANE_ID -u ITERM_SESSION_ID` so it cannot emit a phantom SessionEnd against a live pane; `CLAUDE_CONFIG_DIR` **is** inherited (positive control). |
| d / d-b / d-c | timeout arms | The probe is bounded per-attempt *and* whole-probe (UNKNOWN + "timed out" on a hang, ≤8 s), while a healthy probe slower than the ~2.6 s median still ANSWERS on shipped defaults. |
| f / f-b | PPID rung | With no resolver, a `claude` **parent process** resolves; a non-claude parent must NOT ("no claude binary resolved"). |
| h … h-f | cache arms | Stale-while-revalidate: a fresh cache is served **without spawning the CLI at all** (paired with h-b proving the same fixture does spawn it without a cache); an over-age cache is refused; an UNKNOWN is **never** cached; corrupt/truncated/wrong-version records are treated as ABSENT; `--refresh-mcp-cache` writes the cache, emits no stdout and logs no session start. Cache is per **config dir**. |
| g / g-b | other duties | The effort tripwire rides the same JSON object; the session line and the resolved-binary rung are logged. |

**This second suite is a sensor-integrity suite, not a policy suite.** It pins *how the probe answers*, and contains no rule about which servers may exist. Its only relevance to the SSOT is C5 below.

## 2. Subjects

| Test | Subject(s) read |
|---|---|
| `mcp-no-inherit.bats` | `scripts/lib/mcp-noinherit.sh` (two composers), its wiring in `scripts/handoff-fire.sh` (:8403-8466, `--with-mcp` at :7288, dry-run line at :10381), `scripts/ms365-mcp-wire.sh`, fixture `tests/fixtures/mcp-noinherit/fake-stdio-server.py` |
| `session-start-mcp-probe.bats` | `hooks/session-start.sh` (`_resolve_claude_bin` :209, `_mcp_probe` :240-272, cache + `--refresh-mcp-cache`) |
| `claude-launcher-router.bats` | `lib/claude-launcher.zsh` (`_cc_route_config_dir`, `_cc_record_launch`, `_cc_install_router` :198-260) |

## 3. Rationale commits (`git log --follow`), with quoted bodies

| sha | date | what it established |
|---|---|---|
| **`ff49e1e36`** | 2026-08-11 | **The no-inherit rule itself.** |
| `03ae59251` | 2026-08-11 | `--mcp-config` is variadic and ate the fire's own prompt ⇒ `=` form mandatory. |
| `2b0977be7`, `75f48d552`, `f75699212`, `206f289b1`, `d6804bad7` | 2026-08-11/15 | shellcheck/hermeticity/dead-assertion hygiene — no semantics. |
| **`3aa963042`** | 2026-08-15 | **The stdio filter was scope-blind; ms365 allowlist + per-account wiring.** |
| `7f3cd743e` | 2026-08-15 | The approval-modal axis (`--settings=`). **Body is subject-only — the rationale lives in `scripts/lib/mcp-noinherit.sh` § `cc_mcp_project_decision_args` and `docs/research/mcp-modal-fire-stall-2026-08-15.md`.** |
| `37ef2489c` | 2026-08-11 | Probe answered from a 2.0.5 binary while the session ran 2.1.220. |
| `deaa9e8ff` | 2026-08-11 | The probe's only real control replayed a moving ref (`origin/main`) — repinned to `54555bed1`. |
| `d0f5966b4` | 2026-08-11 | Probe moved to stale-while-revalidate (257 MB CLI per start). |

### `ff49e1e36` — why inheritance was prevented (quoted)

> "An `Agent({name})` teammate IS a separate claude.exe --agent-id process that bootstraps MCP from its cwd, and with the project server approved it starts its OWN chain (fake-server ppid == the teammate pid). … reso sets `enableAllProjectMcpServers`, so every teammate there really does pay for its own chrome-devtools."

> "**No per-fire flag can reach one.** The teammate's launch argv is an enumerated set (--agent-id/--agent-name/--team-name/--agent-color/--parent-session-id, plus permission-mode/effort/model) with no MCP flag in it … So `disabledMcpjsonServers` in the scope's settings is not a nice-to-have floor here; it is the only teammate control that exists."

> "The flag this was specced to use is the one form that must not be used: `--setting-sources` excluding project also drops a repo's `.claude/settings.json`, and reso's carries hooks and permissions. **Bare `--strict-mcp-config` errs the other way and takes the user-scope http servers with it — servers that hold no process, so blocking them saves nothing.** Shipped: `--strict-mcp-config` plus a `--mcp-config` passthrough carrying the account's user-scope non-stdio servers."

> "Deliberately not changed: `hooks/session-start.sh`'s `claude mcp list`, a flagless child that health-starts every approved server on every session start — **its purpose is counting them, so the flag would make it report 0 forever**."

The driving incident (from the library header): a `-p`/headless/SDK worker **loads every stdio server in the cwd's `.mcp.json` unconditionally — the approval list is not consulted at all in that mode** — so a fired research session in a repo carrying chrome-devtools pays **312 MB** it never asked for. Motive = **RAM on a box with a memory-storm panic history**, not security and not config hygiene.

### `3aa963042` — the *other* deliberate decision, and the one the SSOT collides with (quoted)

> "**ROOT CAUSE.** Every fired session launches `--strict-mcp-config --mcp-config=<generated>`, so its servers come ONLY from that passthrough and **`.claude.json` is structurally invisible**."

> "**WHY THE FILTER IS WRONG.** The control exists to block a repo's PROJECT-scope `.mcp.json` stdio servers — already excluded by construction, since the passthrough is built from the ACCOUNT's config. Applying the stdio test there bans a population it never aimed at."

> "mcp-noinherit.sh: `CC_MCP_USERSCOPE_STDIO_ALLOW` (default ms365). **An allowlist, not a deletion — a user-scope stdio server costs ~139 MB/session.**"

> "ms365-mcp-wire.sh (new): idempotent per-account merge from accounts.json. … **install.sh: runs it every install, so the 1-of-4 drift cannot return. config-mirror cannot do this — `.claude.json` is in the isolate-set of all four dirs.**"

`scripts/ms365-mcp-wire.sh` header states the structural reason there are N copies: `.claude.json` is in `lib/config-mirror.zsh`'s `_CC_ISOLATE` for **every** account dir (verified: `lib/config-mirror.zsh:39-42`), "deliberately, because it is the one state file that races between concurrent Claude Code processes. `mcpServers` lives in that file. **So the mirror is structurally unable to share an MCP server**".

## 4. THE CRUX — five concrete couplings

**C1 (highest risk) — the SSOT strip removes the passthrough's only input, and the guard suite stays GREEN.**
`cc_mcp_noinherit_args` builds the passthrough from `$cfg/.claude.json .mcpServers` (`scripts/lib/mcp-noinherit.sh` :~105-126). DoD #2 removes `mcpServers` from all five `.claude.json` files ⇒ `srv_count=0` ⇒ `pass=""` ⇒ the composer falls to **bare `--strict-mcp-config`** ⇒ **every fired session sees ZERO MCP servers** (no motion, no ms365 — which is the capability `MS365_MCP_ALL_ACCOUNTS.md` just spent a wave restoring). It does print a reason line, but test #9 ("no user-scope servers → still isolates") asserts that exact degraded path as CORRECT, so `mcp-no-inherit.bats` **passes on the regression**. DoD #6 ("all three suites green") therefore cannot detect it. *Fix direction: the passthrough builder must read the SSOT file, not `$cfg/.claude.json` — that is a one-function change and it makes C1 disappear.*

**C2 — flag collision on one typed line, and the plan's chokepoint cannot use `--strict`.**
`handoff-fire.sh` types `${LAUNCHER}${ARGS} "$(cat …)"` (`:8935/9083/9092`), i.e. fired sessions run **through** the launcher function. A launcher-appended `--mcp-config=<SSOT>` therefore lands on the same argv as the fire's `--strict-mcp-config --mcp-config=<passthrough>` — two `--mcp-config` occurrences whose merge/last-wins precedence is unmeasured (this is Wave 1 item 1, now with a second consumer). Separately, the launcher **must not** append `--strict-mcp-config`: the measured table in the library header shows `--strict-mcp-config` ⇒ project `.mcp.json` **not loaded**, which violates the plan's own Scope + DoD #5 ("project layering must survive"). So the SSOT chokepoint flag is `--mcp-config=` **alone**, and the merge-vs-replace question is load-bearing exactly as the plan says.

**C3 — the plan's DoD #2 directly contradicts a landed, tested, installer-enforced decision.**
`scripts/ms365-mcp-wire.sh` exists to write the *same* server into *every* account `.claude.json`; `install.sh:618-628` re-asserts it on every install; test #5 asserts it. That is N-copy fan-out **by design**, chosen because config-mirror structurally cannot share `.claude.json`. "No user-scope duplicates remain" cannot hold while that installer step runs — a strip is silently undone by the next `install.sh`. This is the *real* "about to undo a deliberate decision", and it belongs to `MS365_MCP_ALL_ACCOUNTS.md` (still `open`), not to no-inherit. Wave 1 item 5's fork must be settled first: either the SSOT **supersedes** `ms365-mcp-wire.sh` (delete the wiring, rewrite test #5, re-verify ms365 per account) or the plan's DoD #2 is wrong.

**C4 — the allowlist's memory decision is silently discarded if the SSOT is passed wholesale.**
`CC_MCP_USERSCOPE_STDIO_ALLOW` exists so a fired session gets *named* stdio servers only ("~139 MB resident" each; "never every stdio server the config grows"). A launcher- or fire-level `--mcp-config=<SSOT>` handed over unfiltered re-admits **every** stdio server in the SSOT to every fired session — reversing a deliberate cost decision with no test failing. Any SSOT design must keep the allowlist filter applied *to the SSOT file* on the fired path.

**C5 — the SessionStart probe and the upgrade gate both call the binary DIRECTLY, bypassing the launcher.**
`hooks/session-start.sh:270-272` runs `"$CLAUDE_BIN" mcp list` (resolved binary, `env -u` pane vars) — **not** the zsh `claude` function — so a launcher-appended `--mcp-config` is invisible to it. If servers live only behind that flag, the probe reports a count that no longer describes the session: precisely the "confident wrong number" `37ef2489c` was written to kill, and `session-start-mcp-probe.bats` cannot catch it (it fixtures its own binary). `ff49e1e36` already anticipated the general shape: *"its purpose is counting them, so the flag would make it report 0 forever."* Same for `lib/cc-upgrade-gate/check13_mcp.sh`, which runs `CLAUDE_CONFIG_DIR=… $GATE_BIN mcp list` and **SKIPs** when it sees no servers — a launcher-only SSOT turns MCP check #13 into a permanent silent SKIP.

### Bottom line for the plan
- **Not a contradiction of the no-inherit RULE.** Project-scope isolation for fired sessions and one user-scope SSOT are different scopes and different populations; nothing in the plan proposes re-inheriting a repo's `.mcp.json`.
- **A contradiction of the no-inherit MECHANISM's input**, of the allowlist's cost decision, and of the sibling ms365 plan's per-account wiring. Three of the five couplings fail *silently* and *green*.
- Therefore Wave 2 must add: (i) repoint the passthrough builder at the SSOT; (ii) resolve the `ms365-mcp-wire.sh` / `install.sh` fork explicitly; (iii) a **positive-control** test that fires a session and asserts the resulting server set is non-empty and equals the SSOT set (DoD #7 as written — "fails if a server is added to one config dir and not the SSOT" — does not cover the "SSOT strip leaves fired sessions with zero servers" direction).

## 5. `tests/claude-launcher-router.bats` — would appending a flag break it?

**No. It contains zero assertions about argv or the command line.** The subject is `lib/claude-launcher.zsh`, and every case drives it through a stub that *discards* `"$@"`:

```
runlauncher() {
  CC_LAUNCHER_ACCOUNTS_BIN="$STUB" zsh -f -c "
    claude() { print \"cfg=\${CLAUDE_CONFIG_DIR:-unset}\" }
    source '$LIB'
    $1
  " 2>/dev/null
}
```

Every assertion is of one of four shapes — none of them argv:

- config-dir routing: `[[ "$output" == *"cfg=$HOME/.claude-next"* ]]`, `*"cfg=$HOME/.claude-quaternary"*`, `*"cfg=unset"*`
- which *body* ran, after an rc re-source: `[[ "$output" == *"body=V2"* ]]`, and `functions claude | grep -c _CC_ROUTED_DIR` ⇒ `[[ "$output" =~ ^[1-9] ]]`
- the decision note: `[[ "$out" == *"note=routed → next4"* ]]`, `*"pinned — no fresh quota data"*`
- telemetry rows: `grep -q '"slot":"launch"'`, `'"outcome":"routed"'`, `'"outcome":"pinned"'`, `'"acct":"next4"'`

The only argv-adjacent assertions are the resume guards — `@test "--resume never routes"` / `@test "-c never routes"` — which drive `runlauncher "claude --resume abc123"` and `"claude -c"` and assert `cfg=unset`. They exercise the loop at `lib/claude-launcher.zsh:224-225`:

```
for _arg in "$@"; do
  case "$_arg" in --resume|--resume=*|-r|--continue|-c) _resume=1; break ;; esac
done
```

An added `--mcp-config=<path>` matches none of those patterns, so routing behaviour is unchanged.

**Two caveats that matter more than the "no break" answer:**

1. **The suite is BLIND to an appended flag.** Because the stub ignores `"$@"`, a botched append (space form, wrong quoting, flag on the wrong side of `_claude_pinned`) passes this suite silently. If Wave 2 appends here, it must add a case that records `"$@"` — e.g. `claude() { print "args=$*" }` — or the change ships untested.
2. **`lib/claude-launcher.zsh` does not compose argv at all.** It sets `CLAUDE_CONFIG_DIR` and forwards `"$@"` to `_claude_pinned`, which is a byte-copy of the `claude()` body in **`~/.zshrc:451` — untracked, outside this repo, covered by no test**. That body is where `--permission-mode`/`--model`/`--effort`/`$_bin` live and where the user's `"$@"` is appended last. So the plan's sentence *"The launcher at `lib/claude-launcher.zsh` already wraps every single launch … one flag, appended there"* is half true: the repo file is a *routing* wrapper. A flag can be inserted there (`_claude_pinned --mcp-config=X "$@"`), but note it would then flow through the rc body's `_cc_resume_pin "$_cfg" "$@"` rewrite of `CC_RESUME_ARGS`. Use the **`=` form** — `--mcp-config` is variadic and the space form swallows the next positional (commit `03ae59251`, a real ENAMETOOLONG death).

Also: `claude1()`/`claude2..4` are `CLAUDE_CONFIG_DIR=… _claude_pinned "$@"` — they never enter `claude()`, so a flag appended inside `claude()` only would reach **routed launches** and miss all four pinned launchers. It must go in `_claude_pinned`'s call sites (all five) or in the rc body.

## 6. Everything else in the repo that fires on an MCP config change

| Surface | What it does / would do |
|---|---|
| `scripts/lib/mcp-noinherit.sh` | The two composers. Reads `$cfg/.claude.json`. **C1/C4 live here.** |
| `scripts/handoff-fire.sh` :7288, :8017-8036, :8403-8466, :10381 | `--with-mcp`; `--strict-mcp-config` on `probe_account`; composes MCP args + the `--settings=` decision; prints the `mcp:` line. |
| `scripts/ms365-mcp-wire.sh` + `install.sh:611-628` | Re-asserts `mcpServers.ms365` into **every** account `.claude.json` on every install. **C3.** |
| `hooks/session-start.sh` (96 mentions) | The connectivity probe + per-config-dir `.mcp-probe-cache`. **C5.** |
| `lib/cc-upgrade-gate/check13_mcp.sh` | Upgrade gate #13: `mcp list` on the candidate binary; PASS needs ≥1 `✔ Connected`, **SKIP if it sees none**. **C5.** |
| `.claude/settings.json` :3-4 | `disabledMcpjsonServers: ["chrome-devtools","browsermcp"]` — the MODE-INDEPENDENT floor, the **only** control that reaches an `Agent({name})` teammate. Unaffected by the SSOT, but must not be deleted in a "tidy the MCP config" pass. |
| `scripts/headless-precondition-probe.sh` :116-122 | Passes `--strict-mcp-config` (a probe must measure the CLI, not the cwd). |
| `hooks/model-permission-decider.py` :387 | Child runs `--setting-sources "" --strict-mcp-config` (recursion fence) — invoked as the binary, so a launcher flag never reaches it (desired). |
| `bin/cc-notify` / `tests/cc-notify.bats:1043,1050` | **Asserts a contiguous argv substring**: `grep -qF -- "-p unrouted --strict-mcp-config --cloud $CLOUD_ID"`. Any flag inserted into *that* command line reds this test (it already reded once for exactly that reason). |
| `bin/reso-resume-one` / `tests/reso-resume-one.bats:560-576` | A second spawn engine that pre-**approves** a worktree's `.mcp.json` on the launch line (`enabledMcpjsonServers`), asserting the opposite polarity because it passes no `--strict-mcp-config`. Any global launcher flag change must be re-checked here. |
| `hooks/lib/pane-modal.sh:146`, `tests/pane-modal.bats`, `tests/cc-spawn-verify.bats:218-246`, `tests/handoff-fire-pane-parked.bats:281-290` | Classify a pane stuck on "New MCP server found in this project" as `mcp-trust-modal`; the remedy string names `enabledMcpjsonServers` in the PROJECT `.claude/settings.json` and warns **never** to hand-edit `.claude.json` ("every running session rewrites" it — a hard constraint on any SSOT migration touching those files). |
| `tests/cc-permission-prune.bats:48,114` | Asserts the pruner preserves `enabledMcpjsonServers: ["ms365"]` in a settings fixture. |
| `tests/session-registry.bats:205-210`, `tests/session-end.bats:70-84` | The `claude mcp list` **phantom SessionEnd** tenancy guard — depends on the probe continuing to spawn a child; a "the probe no longer spawns" change would make these vacuous. |
| `lib/config-mirror.zsh:39-42` | `.claude.json` is in `_CC_ISOLATE` for every account dir ⇒ the mirror **cannot** be the SSOT transport. |
| `scripts/mcp-modal-probe.py`, `scripts/mcp-modal-e2e-probe.py` | Vendor-contract probes for the approval flags (`BASE = ["--strict-mcp-config", f"--mcp-config={MCPCFG}"]`). Re-run these to answer Wave 1 items 1-2 empirically. |

## 7. Adversarial self-pass — what I looked for after the first answer

1. *"Maybe 'no-inherit' really does mean user-scope."* Checked the library header, both rationale commits and the passthrough jq. It does not: the passthrough exists **specifically** to re-add user-scope servers, and `3aa963042` calls applying the stdio ban to user scope a bug. Ruled out.
2. *"Maybe the launcher never touches fired sessions, so C2 is imaginary."* Checked `handoff-fire.sh:8935/9083/9092` — the typed command is `${LAUNCHER}${ARGS}`, i.e. `claude4 …`, the zsh function. C2 is real.
3. *"Maybe the existing suite would catch the strip."* Read test #9 line by line — it asserts bare `--strict-mcp-config` is the correct output for an empty config. It would pass on the regression. This is the finding that changes the plan's DoD.
4. *"Which surfaces bypass the launcher?"* Found two that read MCP state directly (`session-start.sh`, `check13_mcp.sh`) and would silently under-report / permanently SKIP. Neither is in the plan's DoD.
5. *Unresolved / needs measurement (I did not run anything — read-only):* (a) does `--mcp-config` **merge** with config-dir servers when `--strict-mcp-config` is absent? (b) what happens with **two** `--mcp-config=` on one argv? (c) does `claude mcp list` honour `--mcp-config` (would give C5 a cheap fix)? All three are answerable with `scripts/mcp-modal-probe.py`-style throwaway probes and are prerequisites for Wave 2.
