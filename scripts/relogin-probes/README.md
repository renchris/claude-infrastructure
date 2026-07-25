# relogin probes — E1 / E2 / E3

The three Phase-1 experiments that settle every `[SPECULATIVE]` claim in
`docs/research/autonomous-relogin-100pct-design-2026-07-25.md`. This directory holds the
**harness only**. Nothing here has been run.

Record every result in **[`docs/research/RELOGIN_E1_E3_VERDICT_TEMPLATE.md`](../../docs/research/RELOGIN_E1_E3_VERDICT_TEMPLATE.md)** —
each script also drops a machine-readable artifact under `/tmp/` so the verdict is evidence,
not memory.

## Run order — cheap to costly

| # | Script | Decides | Human gate | Cost if it goes wrong |
|---|---|---|---|---|
| 1 | `e2-launchd-browser-survival.sh` | design §5.1 — does headed-offscreen Chrome survive launchd-proper, or does `cc-authbrowser` need `--headless=new`? | **C10 operator activation** — you run `launchctl bootstrap`; the script only stages the throwaway plist | a stray offscreen Chrome + an open loopback CDP port; teardown kills both. No credential involved |
| 2 | `e1-concurrent-logins.sh` ★ | design §4.4 — **Variant A vs Variant B**, the single open operator decision. Phase 5 (de-sharing) is blocked on it | **two real `claude auth login` runs** — the script pauses and hands you each command | worst case IS the verdict: the primary login is invalidated. `next3` is already logged out, so nothing is lost that is not already lost |
| 3 | `e3-warm-profile-authorize.sh` | proves the whole executor (`cc-relogin` → `cc-authbrowser` → real OAuth → a moved `login_expires_at`) | **the first real sign-in of the build** | one spent re-auth + possibly a stray browser |

E2 first because it is the only one that costs nothing but a process. **E1 is the highest
value** — it is the one verdict the rollout is waiting on, so if you run exactly one, run E1.
E3 last: it needs `cc-relogin` and `cc-authbrowser` installed, a warm profile, and (today) a
`login_expires_at` field that only exists on branch `feat/accounts-login-cliff` — without it
E3 exits **3 DETECTION-UNAVAILABLE** rather than claim an unmeasurable success.

## The one rule every script obeys

**Nothing acts without `CONFIRM=1`.** A bare invocation prints the full pre-flight inventory —
account, config dirs, profiles, ports, plists, artifacts, the exact rollback for each, and
what it costs if it goes wrong — then exits **2 REFUSED** having touched nothing.

```bash
./e1-concurrent-logins.sh                    # read the plan; nothing happens
CONFIRM=1 ./e1-concurrent-logins.sh          # run it
./e1-concurrent-logins.sh --help             # same text, no side effects
```

**Run them from the repo checkout.** `install.sh` globs `scripts/*.sh` — top level only — so
this subdirectory is not deployed to `~/.claude/scripts/` (same shape as `scripts/limit-recover/`
before it got an explicit installer branch). That is fine here: nothing invokes these by
absolute path, and a probe harness is not fleet infrastructure. If any of them is ever promoted
to something a launchd job or another script calls, it needs an installer branch first.

They also, uniformly: assert their own preconditions (`k==0`, port free, profile seeded,
derivation self-check) and **refuse loudly** rather than proceed ambiguously; print the exact
teardown at the end *and* on failure; never `/logout`, never raw-POST a refresh token, never
widen `oauth_scopes` — only the official `claude` binary touches a token.

## Per-script notes

**`e2-launchd-browser-survival.sh`** — stages `/tmp/com.claude.probe-e2-browser.plist`, then
prints the `launchctl bootstrap` line for you. Deliberately uses port **9349**, never one of
the frozen account ports 9341-9344, so it cannot collide with, adopt, or kill a real account's
browser. After you bootstrap it: `CONFIRM=1 ./e2-launchd-browser-survival.sh --assert` watches
60 s and records the verdict (including whether the UA carries a `HeadlessChrome` token).

**`e1-concurrent-logins.sh`** — targets `next3` by default. Creates a probe slot store at
`<config_dir>-e1probe`; because the keychain item is
`Claude Code-credentials-<sha256(config_dir)[:8]>`, that slot gets its own credential item —
the mechanism under test. The script cross-checks its own sha derivation against
`claude-accounts --relogin-info` and refuses on mismatch, so it cannot silently watch the wrong
item. It reads the primary twice afterwards (`--no-heal` raw, then heal-allowed) because raw
alone cannot distinguish *revoked* from *access token merely expired*. Re-observe later with
`--recheck` — durable refresh-chain independence is a T+24h observation, not a T+0 one.

**`e3-warm-profile-authorize.sh`** — rehearse first with `cc-relogin <acct> --dry-run`, which
exercises every gate for free. Records `PROVEN` **only** if `login_expires_at` moved forward; a
green exit code with an unmoved deadline is recorded as `UNVERIFIED`, which is a bug in the
executor's verify-by-EFFECT gate and blocks the cadence. An exit 7 is recorded as
`CONSENT-GATE` — that code is supposed to be structurally impossible on the dedicated-profile
substrate, so seeing it means the §5.1 premise is wrong and the design must be re-opened.

## Teardown

Every script prints its own teardown block (on success and on failure). Run it once the verdict
is transcribed. E1's teardown deliberately leaves the **primary** store logged in — that is the
desired end state regardless of which variant wins.
