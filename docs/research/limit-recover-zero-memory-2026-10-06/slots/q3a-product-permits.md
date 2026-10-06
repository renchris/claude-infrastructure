# q3a — What the product permits for changing a session's paying account without a second full process

Date 2026-10-06. Installed: `claude` 2.1.278 (MEASURED: `/opt/homebrew/bin/claude --version`). Latest changelog entry: 2.1.291 (MEASURED: `curl -sL https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md`, 8402 lines, saved at `/tmp/q3a-changelog.md`; "CL:n" below is a line number in that file).

Tags: MEASURED = I ran it. READ = vendor doc, changelog or repo source. INFERRED = my conclusion from those.

## Verdict table

| Alternative | Verdict | Why (one line) | Second process needed |
|---|---|---|---|
| In-session `/login` | PERMITTED by the product, not usable by this fleet as built | Docs: "/login ... switches the current session to the new login". It is an interactive browser OAuth, it rewrites the store entry of the whole config dir, and the safety rules forbid typing into panes | No |
| Credential swap under a live process (rewrite the keychain entry / `.credentials.json` of a config dir from outside) | UNSUPPORTED (no documented contract); mechanism partly exists; outcome for a cross-account swap UNKNOWN | Changelog shows live sessions do pick up a login written by another process, but only as bug fixes; nothing promises it for an account change, and 2.1.278 predates two of the fixes | No |
| Lazy transcript loading on `--resume` | NOT AVAILABLE as a flag or env var | Docs: resume restores "the full history"; no documented variable reduces resume memory | n/a |
| Shared / linked session store | PARTLY PERMITTED | `claude --resume <transcript-path>` (absolute `.jsonl`) is documented, so a process under account B can resume a transcript that lives under account A's dir with no copy. Symlinked `projects/` is undocumented | Yes (a new process, after the old one exits) |
| Change `CLAUDE_CONFIG_DIR` of a live process | NOT PERMITTED | Read at startup; the keychain entry is keyed to it | n/a |
| `CLAUDE_CODE_OAUTH_TOKEN` rewritten for a live process | UNSUPPORTED | Docs: "uses the token you set for the whole session. To replace an expired token, generate a new one and restart" | n/a |

## Q1 — Does a running session re-read credentials; what does `/login` do live

| # | Claim | Tag | Receipt |
|---|---|---|---|
| 1.1 | `/login` changes the account of the running session in place | READ | code.claude.com/docs/en/iam, Authentication precedence item 5: "If you run `/login` while the variable is set, Claude Code switches the current session to the new login". support.claude.com article 11145838: "run /login from within Claude Code to switch to your subscription plan" |
| 1.2 | The conversation survives `/login` in the same process | READ | CL:1565 (2.1.273): "Fixed `/login`, `/upgrade`, and `/extra-usage` discarding earlier thinking from the conversation, which forced a full prompt-cache rewrite on the next request" |
| 1.3 | Cost of 1.2: the installed 2.1.278 is after that fix, but the prompt cache is account-scoped, so the first request after an account change re-ingests the full history once | INFERRED | From 1.2 plus sessions doc "Resume from a summary": "the next request processes the full history once" |
| 1.4 | The credential store is per config dir: one keychain entry per `CLAUDE_CONFIG_DIR` | READ + MEASURED | iam doc: "keys the macOS Keychain entry to that directory too, so a session with a different `CLAUDE_CONFIG_DIR` reads a different entry". `security dump-keychain \| grep 'svce.*Claude Code'`: 1 unsuffixed service `Claude Code-credentials` (2 items) + 32 suffixed `Claude Code-credentials-<8 hex>` services (33 items). No `.credentials.json` in `~/.claude` or `~/.claude-secondary` (`ls`) |
| 1.5 | Consequence of 1.1 + 1.4: `/login` in one session rewrites the entry every session of that config dir reads; it moves the whole dir, not one session | INFERRED | 1.1, 1.4 |
| 1.6 | Live sessions pick up a login written by another process | READ | CL:1003 (2.1.281): "Fixed the 'Not logged in · Run /login' footer and missing claude.ai connectors persisting in a session after logging in from another Claude Code process". CL:441 (2.1.286): same for a leftover `.credentials.json`. 2.1.178: "Fixed model requests continuing to fail with auth errors after credentials were refreshed outside the session, due to a stale cached request configuration". 2.1.271 (CL:1637): org policy now refreshes "when the credential changes mid-session" |
| 1.7 | 2.1.278 lacks the 2.1.281 and 2.1.286 fixes, so on the installed version a session can keep stale login state after an outside change | INFERRED | Version order: 278 < 281 < 286 |
| 1.8 | Outside credential writes have a failure history under parallel sessions | READ | 2.1.133: "Fixed parallel sessions all dead-ending at 401 after a refresh-token race wiped shared credentials". 2.1.126: "a concurrent credential write could clear a valid OAuth refresh token". 2.1.248 / 2.1.282: refresh-lock errors across processes. Binary strings on 2.1.278: "another Claude Code process is holding the refresh lock" (MEASURED: `/usr/bin/grep -a -o` on `claude.exe`) |
| 1.9 | When a live session re-reads the store (timer, expiry, 401 only) is not documented | READ (absence) | iam doc "Credential management" gives refresh rules only for `apiKeyHelper` |
| 1.10 | The repo's own record says `/login` cannot be driven by an agent | READ | `docs/plans/RELOGIN_AUTOMATION_PLAN.md:80` "`/login` is not callable by an agent. It is an interactive TUI slash command"; `:195` "Never `/logout`... it revokes the grant and deletes the keychain item" |

## Q2 — Is `--resume` eager; is there a memory knob

| # | Claim | Tag | Receipt |
|---|---|---|---|
| 2.1 | Resume loads the full history | READ | code.claude.com/docs/en/sessions "What a resumed session restores": "Conversation history: the full history, including tool calls and results" |
| 2.2 | No documented flag or env var reduces resume memory | READ + MEASURED | env-vars page: resume variables are `CLAUDE_CODE_RESUME_INTERRUPTED_TURN`, `..._MAX_AGE_MS`, `CLAUDE_CODE_RESUME_PROMPT` only; `claude --help` on 2.1.278 lists `--resume`, `--fork-session`, `--session-id`, no lazy/partial option |
| 2.3 | "Resume from summary" reduces tokens sent, not load memory; it fires on Pro/Max for sessions idle over about 1 hour and over 100,000 tokens, after the conversation is restored | READ | sessions doc "Resume from a summary" |
| 2.4 | Undocumented names exist in the 2.1.278 binary: `CLAUDE_CODE_RESUME_TOKEN_THRESHOLD`, `CLAUDE_CODE_RESUME_THRESHOLD_MINUTES`, `CLAUDE_CODE_RESUME_FROM_SESSION`, `CLAUDE_CODE_RESUME_SOURCE_ALIVE`, `CLAUDE_CODE_TRANSCRIPT_LOCAL_GC`. Meaning unverified; the first two look like the thresholds of 2.3 | MEASURED (names), INFERRED (meaning) | `/usr/bin/grep -a -o -E "CLAUDE_CODE_[A-Z_]*(RESUME\|TRANSCRIPT\|HEAP\|MEMORY)[A-Z_]*" claude.exe` |
| 2.5 | Resume improvements that landed after the installed version | READ | 2.1.290 (CL:148) "responsiveness while resuming large sessions: timers, input and rendering keep running while the transcript loads"; 2.1.282 (CL:914) "Improved the time to resume very large sessions"; 2.1.281 (CL:965) "Fixed resuming a very large session sometimes restoring only its last few messages"; 2.1.288 (CL:244) truncated load when the file is rewritten during load |
| 2.6 | Resume memory fixes already in 2.1.278 | READ | 2.1.243 "40–70 MB less memory per session"; 2.1.208 "Reduced memory usage when resuming sessions with background agents or forks"; 2.1.202 and 2.1.153 multi-GB resume-by-name / resume-by-path fixes |
| 2.7 | Live fleet footprint at the time of this run: 53 `claude` processes, sum RSS 11,401 MB, mean 215 MB, max 858 MB, on a 64 GiB machine; 24 of them were launched with `--resume <uuid>` | MEASURED | `ps -axo pid,rss,etime,command \| grep -E "claude(\.exe)?( \|$)"` summed with awk; one sample |

## Q3 — Is `CLAUDE_CONFIG_DIR` per-process and fixed at launch

| # | Claim | Tag | Receipt |
|---|---|---|---|
| 3.1 | Set at start, per process | READ | iam doc "Log in with multiple accounts": "When you start `claude`, set the `CLAUDE_CONFIG_DIR` environment variable ... Each directory has its own settings, session history, and claude.ai login or API key". env-vars doc: "Claude Code reads shell environment variables at startup, so changes to them take effect the next time you launch `claude`" |
| 3.2 | Project settings can no longer set it | READ | CL:2414 (2.1.251): project `.claude/settings.json` `env` no longer sets `CLAUDE_CONFIG_DIR` |
| 3.3 | Settings-file `env` values are re-applied to a running session on save, but nothing says a config-dir change takes effect live; the docs' only live-change statements about it are VS Code reload bugs | READ | env-vars "In settings files"; CL:1705, CL:1521 |
| 3.4 | On this machine the per-account stores are separate real directories; shared pieces are symlinks | MEASURED | `ls -la ~/.claude-secondary`: `projects`, `sessions`, `session-env`, `file-history`, `history.jsonl`, `.claude.json` are real; `settings.json`, `todos`, `mailbox`, `autonomy` are symlinks into `~/.claude` |

## Q4 — Where usage limits attach

| # | Claim | Tag | Receipt |
|---|---|---|---|
| 4.1 | Limits attach to the subscription account, shared across Claude and Claude Code | READ | support.claude.com 11145838: "usage limits that are shared across Claude and Claude Code, meaning all activity in both tools counts against the same usage limits"; support 11647753 via search summary: "Weekly limits reset at a fixed time each week that is assigned to your account" |
| 4.2 | The credential in use picks the payer, by a fixed precedence; subscription OAuth from `/login` is last | READ | iam doc "Authentication precedence", 7 items |
| 4.3 | Org-level controls exist for Team/Enterprise (`forceLoginOrgUUID`, usage-credit requests to admins) | READ | iam doc "Restrict login to your organization"; commands doc `/usage-credits` |
| 4.4 | Therefore the only ways to change the payer of a conversation are: change which credential the process reads (1.1, 1.6), or start a process that reads a different one | INFERRED | 4.1, 4.2, 3.1 |

## What the repo already tried (VOLUNTARY_ACCOUNT_SWITCH.md)

- The plan never tried a credential swap or an in-session `/login`; `grep -n -i -E "credential|keychain|/login"` over the 485-line file returns no hit on those (MEASURED).
- Its mechanism is exit-then-relaunch in the same pane: `:92` quotes "A recycle is exit-then-relaunch in the same pane"; scope `:10-11` "same window id, same session uuid, new account". So the two processes do not overlap (READ).
- The transcript is cloned between account stores, APFS clone first: `scripts/limit-recover/lr-transplant.sh:466` and `:901` `cp -c -p "$SRC" "$DST" 2>/dev/null || cp -p`, then `rsync -a` of the session side dir (`:470`, `:904`) (READ).
- What worked for a healthy peer was a poller request telling the session to run `cc-lr switch --target next2`: plan `:244-246` (READ).

## Alternatives considered

| Option | Result |
|---|---|
| Swap the config dir's keychain entry to another account's tokens, sessions keep running | No vendor contract. Moves every session of that dir at once. Pickup latency unknown. On 2.1.278 the stale-state fixes of 2.1.281/2.1.286 are absent. Refresh-token race history (2.1.133, 2.1.126). Two dirs holding the same refresh token is untested |
| Skip the transcript copy by `--resume <absolute path>` from the target account | Documented entry point. Where the new process then appends (source file or its own `projects/`) is not documented; needs a test on a throwaway session |
| Symlink `projects/` across account dirs | Undocumented. Cross-project lookup refuses duplicates ("resolves the ID only when exactly one other project holds a transcript"), which a linked store would avoid, but two dirs writing one store is untested |
| Upgrade to 2.1.290+ | Gains the resume responsiveness and large-session fixes of 2.5; does not add lazy load |

## Uncertainties

1. Latency and trigger for a live 2.1.278 session to adopt a store entry written from outside (timer, token expiry, or 401 only). Not documented; not tested here because it needs a credential write.
2. Whether a session that already shows a usage-limit state retries cleanly after the store flips account.
3. Whether one account's refresh token held in two keychain entries survives rotation.
4. Append target after `--resume <transcript-path>` across config dirs.
5. Meaning of the undocumented `CLAUDE_CODE_RESUME_*` names in 2.4.
6. 2.7 is a single sample; per-session peak RSS during resume was not measured in this slot.

## Not done, and why

- No experiment that writes a credential, types into a pane, or launches `claude`: outside the read-only brief.
- Binary context around the names in 2.4 was not extracted: the context grep exceeded its 120 s limit.
