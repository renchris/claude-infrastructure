# Where the permission prompts actually come from — 2026-08-23

**The allowlist was the wrong lever.** The operator asked to "improve our allowlist so we get prompted
less in auto-mode." Measured against every store that records a prompt, `permissions.allow` is not what
is producing them: **our own PreToolUse hooks are**, and two of them account for nearly all of it.

## 0. The stores, and which one is the oracle

| Store | What it holds | Verdict |
|---|---|---|
| `~/.claude/autonomy/permission-archive/*.jsonl` | 2,684 resolved `PermissionRequest` events with full `tool_input`, 2026-07-31 → | **THE ORACLE.** Written by `hooks/cc-permission-beacon.sh` on the harness's own event |
| `~/.reso/curl-audit.jsonl` | 3,135 curl-gate decisions + reasons, 2026-05-19 → | the only store carrying a *reason* |
| `~/.claude/logs/bash-commands.log` (+5 rotations) | 228,347 Bash tool calls | the command corpus — **not** a prompt corpus |
| session transcripts (4 account roots) | `toolDenialKind` on the failed `tool_result` | **under-reports ~13x** — an APPROVED prompt leaves no trace at all |

⚠️ **The command log is not a prompt log, and conflating them is how every inflated estimate in this
investigation was produced.** "This rule would cover N uncovered commands" is a statement about
`bash-commands.log`; it says nothing about whether those commands ever prompted. Under auto-mode almost
none of them did. See §3.

## 1. The shape of the problem

2,684 archived prompts: **Bash 2,592 · AskUserQuestion 90 · WebFetch 1 · Monitor 1.** Read, Write,
Edit and every `mcp__*` tool: **zero**. A `Read`/`WebFetch`/MCP allow rule would act on an empty set.

Cumulative agent wall-clock spent waiting at a prompt: **911 hours** (median 8s, p90 866s, max 22.6h).
2026-08-23 alone: **605** — the worst day on record, and the day the operator raised it.

Over the seven days to 2026-08-23: **1,189 Bash prompts, 947 of them (80%) containing `curl`.**

## 2. The two hooks, and the four defects

### `hooks/curl-gate.py` — 91% of its own asks were its own bugs

Fixed in `6bf610045` / `d8b517b28`. Replaying all 3,135 audited decisions through both versions:
`ask 2,002 → 181`, `deny 428 → 36`, **35/35 genuine security denies preserved**, exceptions 8 → 0.

1. **The parse bug.** `parse_curl` knew ~8 value-taking curl flags; every other flag's VALUE fell into
   the positional branch, and the URL test was `"." in tok and "/" in tok`. So
   `-A "Mozilla/5.0 (Macintosh; …)"` became `https://Mozilla/5.0 …` and the gate asked about **host
   "mozilla" — 894 asks, 45% of the log.** `-e/--referer` produced the same class as
   `Non-HTTP scheme: referer`.
2. **The hard blocks.** 370 of 428 denies read `curl-gate: not a curl command` — the whole command was
   handed to a parser checking `tokens[0] != "curl"`, so `flyctl status … && curl https://x/health` was
   **refused outright**. Not a prompt: a refusal, on 86% of all denies.
3. **The wrong axis.** Even parsed correctly, the read rule was "is this host on a list" — 382 distinct
   public hosts asked about (an unbounded research tail no list can chase) while `api.github.com`
   carrying `Authorization: token ghp_…` was **allowed**, because the host was listed.
4. **A latent crash.** `urlparse(…).port` raises on `http://localhost:3000$CHUNK`; the `ValueError`
   escaped to `main()`'s catch-all and became a fail-closed deny. 20 ordinary localhost reads blocked.

**The rule now gates on what a request SENDS, not who it reads FROM.** A GET can hurt in five ways;
four (SSRF/IMDS, pipe-to-shell, TLS downgrade, clobbering a secret path) already have their own deny
arm that runs first and is independent of the host. The fifth is exfiltration — so any public host may
be read from, and the prompt is spent on a request carrying a credential to a host nobody vetted. That
is **stricter** than the incumbent on the axis that matters.

### `hooks/validate-bash.sh` — the rm guard could only see a spelling agents never use

Fixed in `b5668f7d`. The scratchpad category (added 2026-08-18 after four dispatched sessions were lost
to its absence) only recognises a **literal absolute path**, because `_sp_resolve` refuses any token
containing `$`. Agents write `D=<path> && rm -rf "$D"`.

    non-curl prompts                          1,297
      containing a recursive rm                 968   (75%)
        whose target is a variable              717
          resolving into a session scratchpad   223   ← now permitted

Resolution runs *before* the predicates and changes neither, so a wrong expansion can only permit
something by landing inside the session's own scratchpad — the safe case by construction. Ambiguity
(`D=$(mktemp -d)`, a name assigned twice) is refused rather than guessed.

## 3. 🚨 The negative result: `permissions.allow` additions buy approximately nothing

This is the part worth keeping, because it contradicts the obvious reading of the ask.

**Structural reason.** Claude Code's `Bash(cmd:*)` matcher is a *prefix* matcher over each component of
a command, and one uncovered component forces a prompt for the whole command. Of the 1,331 non-curl
prompts: **97% are compound**, **71% are multi-line**, **67% contain a shell construct** (`for`, `if`,
a heredoc, a command substitution). Only **39 (3%)** are a simple single command a prefix rule could
cover — and 34 of those 39 are empty strings. **A prefix matcher cannot allowlist a shell program.**

**Empirical reason.** A six-source census proposed ~40 allowlist additions with counts derived from
`bash-commands.log`. Every one of the top proposals was then handed to an independent adversarial
verifier. **9 of 9 were REFUTED** — counts inflated **2× to 174×**, two would have newly permitted
arbitrary code execution (`Bash(bash:*)`, `Bash(python3:*)`), and one verifier's corrected figure for
the largest proposal was **"0 prompts eliminated under the live config."**

**What that leaves.** 165 of the 1,297 non-curl prompts already have zero uncovered components — they
came from a hook, not a rule gap. Only 121 would clear with one new rule, **61 of those needing
`Bash(rm:*)`**, which is a real loosening and is what the guard fix in §2 addresses properly instead.
The 255 existing Bash allow rules are not the constraint, and adding to them is not the remedy.

## 4. Open — the auto-mode classifier config (operator-owned)

Verified from the binary, not from docs:

    claude auto-mode defaults  →  environment 20 · soft_deny 65
    claude auto-mode config    →  environment  7 · soft_deny 30      ← live

The binary's own schema: *"Include the literal string `"$defaults"` to inherit the built-in entries at
that position."* Our `settings.json` sets `autoMode.environment` **without** it, and the docs put this
in a `<Danger>` block: setting the key without `"$defaults"` **replaces** the shipped list.

13 shipped environment entries are gone, including **Trusted repo** ("the git repository the agent
started in and its configured remotes"). All 7 survivors are reso-specific, so a session working in
`claude-infrastructure` runs with a trust block that never names the repo it is standing in — the
classifier is blind to its own working directory, and refuses things it would otherwise allow.

- **Filed `d26bf99b6e9a`** — add `"$defaults"` to `autoMode.environment` across all five forked
  settings files. Script: `/tmp/automode-restore-defaults.sh`. *The agent is blocked from writing this
  file by the auto-mode classifier itself, correctly — it is permission config, so it is the
  operator's to run.*
- **Filed `b19974f7ba82`** — decide whether to also add `"$defaults"` to `autoMode.soft_deny`. Same
  footgun, but it cuts the other way: it restores 35 shipped SAFETY rules, which is a security
  improvement that can also make the classifier block *more*. Deliberately not bundled.

⚠️ **`settings.json` is forked across five real files with five different md5s**
(`~/.claude`, `-next`, `-secondary`, `-tertiary`, `-quaternary`). The config mirror does not heal it
(task #70). Any settings change must be applied to all five or it silently applies to one account.

## 5. Method notes worth reusing

- **Two self-inflicted bugs in the credential guard were caught by the corpus and the controls, not by
  review.** `re.IGNORECASE` made `-e` (referer) read as `-E` (client cert) — curl's short flags are
  case-sensitive and the opposites sit one bit apart. And a raw-text scan for credential flags
  convicted `curl … | grep -oE '(a|b)'` of carrying a client certificate: **123 of 155 residual asks
  were curl being blamed for grep's flags on the far side of a pipe.**
- `shlex.split()` does not split on `;` or `|`, so the argv walk had been running on into the *next*
  command all along. `shlex.shlex(..., punctuation_chars=True)` fixes it generally while leaving a
  quoted `;` (as in the Mozilla user-agent) inside its token.
- `pgrep -f ship-land.sh` matched a **sibling session's watcher** whose command line merely contained
  the string, and skipped a land that should have fired. Anchor on argv position, per
  MEMORY.md `pgrep-f-matches-agent-briefs`.
