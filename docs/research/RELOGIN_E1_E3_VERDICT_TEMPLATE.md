---
status: UNRUN — no experiment in this document has been executed
harness: scripts/relogin-probes/ (E1 · E2 · E3), all CONFIRM-gated
spec: docs/research/autonomous-relogin-100pct-design-2026-07-25.md
contract: docs/plans/RELOGIN_BUILD_CONTRACT.md §7
---

# Relogin Phase-1 verdicts — E1 / E2 / E3

The three experiments that settle every `[SPECULATIVE]` claim in the design. **Every verdict
below is BLANK because none of them has been run.** Fill each section in from the run's own
`/tmp/` artifact — never from memory — and change `status:` above when all three are recorded.

| # | Experiment | Decides | Verdict | Recorded |
|---|---|---|---|---|
| E1 ★ | concurrent same-account logins | §4.4 **Variant A vs B** — the single open operator decision | `UNRUN` | — |
| E2 | launchd-proper browser survival | §5.1 headed-offscreen vs `--headless=new` | `UNRUN` | — |
| E3 | warm-profile Authorize, end to end | whether the executor actually works | `UNRUN` | — |

Run order is E2 → E1 → E3 (cheap to costly); see `scripts/relogin-probes/README.md`. **If only
one is ever run, run E1** — it is the verdict the rollout is waiting on.

---

## E1 — concurrent same-account logins ★

`CONFIRM=1 scripts/relogin-probes/e1-concurrent-logins.sh next3` · artifact
`/tmp/relogin-probe-e1-<acct>.json`

**The question.** The keychain item is `Claude Code-credentials-<sha256(config_dir)[:8]>`, so a
second `CLAUDE_CONFIG_DIR` gets its own credential item *locally*. Unknown: whether the vendor
keeps only **one active login per account** server-side. If it does, per-slot isolation
collapses.

### What was run

- account / date / operator: <!-- e.g. next3 · 2026-07-26 · chris -->
- primary store + keychain item:
- probe slot store + keychain item:
- preconditions at start (`k`, primary `auth`):

### Raw observation

| Field | Value |
|---|---|
| `before_auth` | |
| `slot_keychain` (must be `present`, else the probe tested nothing) | |
| `primary_keychain` after the second login | |
| `after_auth_no_heal` (raw — the primary exactly as login #2 left it) | |
| `after_auth_healed` (decisive — did the primary's refresh chain survive?) | |
| T+24h `--recheck` (durable independence, not just same-session) | |

> Read `after_auth_no_heal` carefully: a bare `stale` means the access token merely expired and
> proves **nothing** about revocation. Only `after_auth_healed` separates *survived* from
> *revoked*.

### Verdict

`UNRUN` — one of `COEXIST` / `INVALIDATED` / `INCONCLUSIVE`.

### 🚨 What it decides downstream — the Variant-A-vs-B call

**This is the single operator decision the whole rollout waits on.** Everything else in the
design is identical under both variants; Component 1 is unaffected either way.

| If E1 says | Adopt | What that means for every session |
|---|---|---|
| **COEXIST** | **VARIANT A** — per-slot `CLAUDE_CONFIG_DIR` isolation, ~3 slots per account | **No capability boundary anywhere.** Every slot holds a real full-scope login: Remote Control and first-party connectors work in *every* session. The token race is eliminated by construction. |
| **INVALIDATED** | **VARIANT B** — setup-token supplement | **A real capability loss.** Sessions on `CLAUDE_CODE_OAUTH_TOKEN` are built with `refreshToken: null` and are **inference-only** — no Remote Control, no hosted connectors *in them*. Keep full-scope keychain sessions few (ideally one per account) and put bulk fleet work (agent-teams, research subagents, builds) on setup-tokens. |
| **INCONCLUSIVE** | neither — **re-run** | Do not guess. Phase 5 stays blocked; a wrong guess here either loses capability needlessly (B when A was available) or leaves the rotation race in place (A when it never worked). |

Until this row is filled in, **Phase 5 (de-sharing) stays DEFAULT OFF and unactivated** per
contract §8.

<details>
<summary><b>Worked example — the shape to record. EXAMPLE ONLY, NOT A RESULT.</b></summary>

> Every value below is invented to show the format. It is **not** an observation and must never
> be cited as one.

```text
What was run   next3 · 2026-07-26 14:02 PT · chris
               primary  /Users/chrisren/.claude-tertiary          kc Claude Code-credentials-6a49a3e4
               slot     /Users/chrisren/.claude-tertiary-e1probe  kc Claude Code-credentials-9cda391b
               preconditions  k=0 · primary auth=logged-out
Raw            before_auth=logged-out
               slot_keychain=present          <- the second login did land its own item
               primary_keychain=present       <- not deleted locally
               after_auth_no_heal=stale       <- inconclusive on its own
               after_auth_healed=healed       <- DECISIVE: the primary refreshed successfully
               T+24h --recheck: after_auth_healed=ok
Verdict        COEXIST
Decides        VARIANT A. Per-slot CLAUDE_CONFIG_DIR isolation, 3 slots/account, full scope in
               every slot. Phase 5 may proceed; no session loses Remote Control or connectors.
```

</details>

---

## E2 — launchd-proper browser survival

`CONFIRM=1 scripts/relogin-probes/e2-launchd-browser-survival.sh` → you run
`launchctl bootstrap gui/<uid> /tmp/com.claude.probe-e2-browser.plist` →
`CONFIRM=1 … --assert` · artifact `/tmp/relogin-probe-e2.json`

**The question.** The design's survival probe ran in a backgrounded+disowned shell inside a GUI
login session — the class that reaps Dia in <5 s. A LaunchAgent in `gui/<uid>` is the same Aqua
session, so the expectation transfers, but it is `[SPECULATIVE]` until observed.

### What was run

- date / operator:
- plist staged / bootstrapped at:
- port + profile:

### Raw observation

| Field | Value |
|---|---|
| `alive_at_end` (process still up at the end of the window) | |
| `cdp_answered` (`/json/version` responded) | |
| `watched_s` (how long it actually survived) | |
| `user_agent` | |
| `headless_ua` (does the UA carry a `HeadlessChrome` token?) | |
| launchd log tail (`~/.claude/logs/probe-e2-browser.err.log`) | |

### Verdict

`UNRUN` — one of `SURVIVED` / `DIED` / `CDP-DEAD`.

### What it decides downstream

| If E2 says | Then |
|---|---|
| **SURVIVED** | `cc-authbrowser` keeps its **default headed-offscreen** posture. `--headless` stays opt-in and unused. The authorize page sees an ordinary Chrome UA. |
| **DIED** | Flip `cc-authbrowser` to `--headless=new` (design §5.1 fallback ladder). One flag, no rewrite — that is exactly why the launch posture was parameterized. Cost: the UA now advertises `HeadlessChrome` on the authorize page. |
| **CDP-DEAD** | Neither. The process lived but the port never answered — a binding/port problem. Diagnose that **before** touching `--headless`; flipping it would hide the real fault. |

E2's verdict changes a config flag only. Nothing else in the build depends on it.

---

## E3 — warm-profile Authorize, end to end

`CONFIRM=1 scripts/relogin-probes/e3-warm-profile-authorize.sh next3` · artifact
`/tmp/relogin-probe-e3-<acct>.json`

**The question.** E1 and E2 each settle one assumption. E3 is the integration: does
`cc-relogin` → `cc-authbrowser` → real OAuth actually move `login_expires_at`? Nothing else in
the build demonstrates that the pieces compose.

**Blocked until the detection surface exists.** `login_expires_at` is not on `main` (it lands
with branch `feat/accounts-login-cliff`). Without it E3 exits **3 DETECTION-UNAVAILABLE** —
record that as the verdict rather than running an unmeasurable re-auth.

### What was run

- account / date / operator:
- `cc-relogin` + `cc-authbrowser` versions/paths:
- warm profile used, and when it was last signed in on claude.ai:
- dry-run rehearsal result (`cc-relogin <acct> --dry-run`):

### Raw observation

| Field | Value |
|---|---|
| `before_login_expires_at` | |
| `executor_exit` | |
| `after_login_expires_at` | |
| `deadline_moved` | |
| executor output (verbatim) | |

### Verdict

`UNRUN` — one of `PROVEN` / `UNVERIFIED` / `CONSENT-GATE` / `FAILED-rc<N>` /
`DETECTION-UNAVAILABLE`.

### What it decides downstream

| If E3 says | Then |
|---|---|
| **PROVEN** | The unattended executor works end to end. The cadence (§5 poller) and observability (§6) may be activated — that activation is still the operator's C10 call. |
| **UNVERIFIED** | `cc-relogin` exited 0 but the deadline did not move. Its verify-by-EFFECT gate is not doing its job. **Fix that before any cadence is activated** — an hourly poller that believes its own exit code will silently do nothing until the account is dead. |
| **CONSENT-GATE** (exit 7) | Structurally impossible on the dedicated-profile substrate — so the §5.1 premise is **wrong**. Stop and re-open the design; do not work around it. |
| **FAILED-rc\<N\>** | Read the frozen §4 code: `1` ERROR · `2` REFUSED · `3` HEADLESS-EXHAUSTED · `4` BROWSER-FAILED · `5` UNVERIFIED · `6` FALLBACK-REQUIRED. The code names which stage broke; record it verbatim. |
| **DETECTION-UNAVAILABLE** (exit 3) | Land `feat/accounts-login-cliff` first. Never substitute "cc-relogin exited 0" for the measurement — that is precisely the failure E3 exists to catch. |

---

## Sign-off

Phase 5 (de-sharing) and the poller's activation both remain **blocked** until E1 and E3
respectively are recorded above with a non-`UNRUN` verdict.

| | Verdict | Artifact path | Date | By |
|---|---|---|---|---|
| E1 | | | | |
| E2 | | | | |
| E3 | | | | |
