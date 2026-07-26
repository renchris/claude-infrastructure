---
status: open
owner: operator (every step below is human-gated by construction)
built-by: relogin-build session 2026-07-25 — Phases 0-4 code + Phase-5 inert scaffolding
spec: docs/research/autonomous-relogin-100pct-design-2026-07-25.md
contract: docs/plans/RELOGIN_BUILD_CONTRACT.md
---

# Relogin — operator activation runbook

The autonomous re-auth system is **built and tested, and deliberately inert.** Nothing
below has been run: no account was touched, no sign-in performed, no LaunchAgent loaded.
This is the ordered list of steps that turn it on, each with the exact command.

> **Why nothing was auto-activated.** Every step here crosses a boundary an agent must not
> cross alone: a real OAuth sign-in (E1/E3), a LaunchAgent load (C10), or a change to how
> every session starts (Phase 5). The build stops precisely at that line.

## The shape of the thing

Two components, uniform across `next` / `next2` / `next3` / `next4`:

1. **The executor** — a dedicated, per-account, **directly-executed** Chrome
   (`bin/cc-authbrowser`) that completes the standard OAuth Authorize in that account's own
   warm profile, driven by `bin/cc-relogin`, re-anchoring the ~30-day deadline. Runs under
   the existing per-account heal lock, at `k==0`, and is **verified by effect** (the moved
   `login_expires_at`), never by the binary's own "Login successful." claim.
2. **Token de-sharing** (`bin/cc-config-slot`) — stops 5-6 concurrent sessions sharing one
   rotating refresh token. **Inert by default**; gated on E1 below.

Component 1 works regardless of *which* death mode fires, which is why it is load-bearing
and component 2 is an optimisation (how *often* the executor runs, not whether it works).

---

## Step 1 — run the experiments (each needs one human action)

Cheap-to-costly order. Each script **refuses to run without `CONFIRM=1`** and prints what
it touches and how to undo it. Record every verdict in
`docs/research/RELOGIN_E1_E3_VERDICT_TEMPLATE.md`.

▶ `scripts/relogin-probes/e2-launchd-browser-survival.sh`
  Decides whether headed-offscreen Chrome survives launchd proper. Loads a **throwaway**
  LaunchAgent. No account involved, no sign-in.
  - **Survives** → keep the default headed-offscreen posture. Nothing to change.
  - **Does not survive** → flip the substrate to `--headless=new`. This is a **config flip,
    not a rewrite** — `cc-authbrowser --headless` already implements it. Cost: the UA then
    advertises `HeadlessChrome`.

▶ `scripts/relogin-probes/e1-concurrent-logins.sh`
  ★ **Highest value — it decides the §4.4 variant.** Needs one real browser Authorize.
  Target `next3` (already logged out, so it costs nothing not already lost).
  - **Logins coexist** → **Variant A**: per-session-class config-dir isolation, full scope
    everywhere. Proceed to step 4.
  - **They do not coexist** → **Variant B**: setup-token supplement. Variant A collapses —
    **delete `bin/cc-config-slot` rather than enabling it**, and keep full-scope keychain
    sessions few (ideally one per account), with bulk fleet work on setup-tokens
    (inference-only: no Remote Control, no hosted connectors *in those sessions*).

▶ `scripts/relogin-probes/e3-warm-profile-authorize.sh`
  Proves the whole executor end to end against a real authorize URL. This is the first
  moment a real sign-in occurs. Success = a moved `login_expires_at`.

---

## Step 2 — prove one renewal by hand before automating it

▶ `bin/cc-relogin next3 --dry-run`     (gate reads + phase plan; mutates nothing)
▶ `bin/cc-relogin next3`               (the real thing, once E3 has passed)

Exit codes: `0` PROVEN · `2` REFUSED (healthy / `k>0` / lock busy) · `3` HEADLESS-EXHAUSTED ·
`4` BROWSER-FAILED · `5` UNVERIFIED (**treat as NOT re-authed**) · `6` FALLBACK-REQUIRED.
`7` is retained for consumer compatibility and is never emitted.

Do not proceed to step 3 until an exit `0` has been observed at least once.

---

## Step 3 — load the cadence (C10)

The plist is **staged, not loaded**. Loading it is the operator's activation:

▶ `cp launchd/staged/com.claude.relogin.plist ~/Library/LaunchAgents/`
▶ `launchctl load ~/Library/LaunchAgents/com.claude.relogin.plist`

Hourly poll · renew at **T−7d** (not the 72 h warn — that converts one fragile attempt into
~168 hourly chances to catch a `k==0` window) · escalate at **T−48h** if no window was ever
caught. Success is silent; failure is loud.

Watch it with:
▶ `claude-accounts --relogin-status`
▶ `cc-blockers`   (a `relogin-blocked` row carries the exact runnable recovery command)

✅ **The step-5 gap is CLOSED (verified 2026-07-26).** `feat/accounts-login-cliff` has landed:
`--login-status` and all four cliff fields (`login_expires_at` / `_h` / `login_expired` /
`login_fixable`) are on `main`, and the branch is gone. The poller resolves real detection —
`cc-relogin-poll --dry-run --json` returns `"detection":"login-status"`, not
`DETECTION-UNAVAILABLE`. Nothing here is inert-by-dependency any more; the only thing keeping the
cadence off is that this plist is not loaded.

✅ **The interpreter prerequisite is already satisfied — measured, not assumed.** The CLI contract
warns that `/usr/bin/python3` lacks `websocket-client` and launchd's PATH resolves exactly that
interpreter. It does not apply to this plist: `ProgramArguments` runs `/bin/zsh -lc`, and a
**login** shell picks up `/etc/zprofile`'s `path_helper`, which puts the Framework 3.11 (which
HAS the dep) ahead of `/usr/bin/python3`. Confirm before loading:

▶ `/bin/zsh -lc 'export PATH="$HOME/.claude/bin:$PATH"; command -v python3; python3 -c "import websocket"'`

Expect a Framework/Homebrew path and **no output** from the import. ⚠️ This is a property of the
**login shell**, not of launchd — do not "simplify" the plist to a bare exec or drop the `-l`, or
the `/usr/bin/python3` fault the contract warns about comes back.

---

## Step 4 — Phase 5 de-sharing (only if E1 returned Variant A)

Inert by default and safe to leave that way indefinitely — with the flag off,
`cc-config-slot` resolves to each account's canonical config dir, byte-identically to
today's launchers (20 tests pin exactly this).

▶ `scripts/relogin-desharing-activate.sh`            (dry-run: plan + rollback, writes nothing)
▶ `CONFIRM=1 scripts/relogin-desharing-activate.sh`  (writes the enable flag)

The second half is **yours by hand**: the launchers are shell *functions* in `~/.zshrc`
(live operator state, outside this repo), so no agent edits them. The exact one-line change
is printed by the script. Rollback: remove the flag file and revert that line — the
resolver fails closed.

Do not enable this before the executor has proven a renewal: de-sharing multiplies the
number of stores needing renewal (4 accounts × 3 slots = 12/month). Enabling it earlier
would multiply an unproven process — which is why the design puts this phase last.

---

## Step 5 — the one landing dependency ✅ RESOLVED 2026-07-26

`claude-accounts --login-status` and the `login_expires_at` / `login_expires_h` /
`login_expired` / `login_fixable` fields were on the unlanded local branch
`feat/accounts-login-cliff`. **They are now on `main`** and that branch no longer exists —
verified by content, not by count:

▶ `git show origin/main:bin/claude-accounts | grep -c login_expires_at`   # non-zero
▶ `cc-relogin-poll --dry-run --json`   # "detection":"login-status" ⇒ real detection resolved

The version-tolerant degradation path (exit 3 DETECTION-UNAVAILABLE, `--relogin-status`
reporting `UNKNOWN` instead of a confident wrong `OK`) stays in the code deliberately — it is
what a *future* SSOT change degrades into. It is simply no longer the live path.

**No landing dependency remains.** Steps 1-3 are the whole activation.

---

## Security posture (unchanged from the design)

Our own credentials, our own machine, our own accounts, our own OAuth consent, in our own
warm sessions.

- **Only the official `claude` binary performs token operations.** No hand-rolled exchange,
  no raw refresh POST, no credential-blob injection — a discarded rotation is a logout.
- Never `/logout` as a fix · never re-auth an account with live sessions (`k>0`) · never
  widen `oauth_scopes` beyond the SSOT.
- Cross-account contamination is structurally impossible: each executor run carries exactly
  one account's dedicated profile.
- Dedicated automation profiles hold **only** `claude.ai` credentials. The operator's
  personal Dia profile (`Personaly`, which `next` maps to today) is never opened or copied.
- The CDP port binds `127.0.0.1`, exists only during a renewal, and is torn down
  unconditionally — with a TTL watchdog that fires even if the caller dies.
- **No evasion, by design.** Headed-offscreen is preferred over headless precisely because
  it is *honestly* a normal browser. No fingerprint spoofing, no proxy rotation, no captcha
  services. A genuinely challenged session is re-warmed or surfaced — never evaded.
