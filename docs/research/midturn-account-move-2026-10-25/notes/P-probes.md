# Probes — measured on this machine, 2026-10-25 02:05–02:40 CDT (Claude Code 2.1.293, load 560–620 on 10 cores)

Every probe ran a THROWAWAY Claude Code session that this session started itself, in a hermetic config
dir under `/tmp/mtam/probe/cfg-*` (no hooks, no settings, no shared transcripts). No live pane was touched,
no keychain item of next/next2/next3/next4 was written, no settings.json was edited, no slash command was run.
Credentials were read from the account keychain items READ-ONLY (`security find-generic-password … -w`
captured inside the probe process, never printed) and appear below only as `sha256[:10]` fingerprints:
next2 = `9f8496d402`, next3 = `cf40551134`. Billing is identified by the response header
`anthropic-organization-id` (prefix shown): next2 = `fb09ef51`, next3 = `1a71eca0`; corroborated by
`anthropic-ratelimit-unified-7d-utilization` (next2 0.02, next3 0.17, matching `claude-accounts --readout`
at 02:10: next2 2%, next3 18%). Model `claude-haiku-5-5` throughout; total probe spend ≈ $0.03 list.

Harness (kept in `/tmp/mtam/probe/`, not committed): `tok.py` (read-only token reader, inference-only copy
writer: refreshToken forced to null), `proxy.py` (stdlib HTTP→HTTPS forwarder; logs identity headers with
credentials fingerprinted only; optional bearer swap on `/v1/messages*` only, per a plan like
`passthrough:1,next3`), `launch.py` (env-token throwaway launcher), `m3.py`/`m3d.py`/`ia.py`/`intr.py`/`fork.py`
(the probes below), `revoke-watch.py` (accruing, see P9).

## P1 — a subscription (OAuth) session honors a localhost ANTHROPIC_BASE_URL

`launch.py next2 … ANTHROPIC_BASE_URL=http://127.0.0.1:18433` → `HEAD /api/hello 200`, `POST /v1/messages?beta=true 200`,
result `OK`, rc 0, 3.1 s. Request carries `authorization: Bearer <next2>`, `anthropic-beta: oauth-2025-04-20,…`,
`x-claude-code-session-id`, `user-agent claude-cli/2.1.293`; NO `x-api-key`. Response carries
`anthropic-organization-id` and all `anthropic-ratelimit-unified-*` headers.
First attempt failed on the PROXY's own TLS trust (python lacked a CA bundle → 502): the client retried the
502 11–12 times before giving up — i.e. a dead local hop is retried, not instantly fatal (log-pt.tlsfail.jsonl).

## P2 — what a non-first-party base URL turns off, and the override

Same prompt, with vs without `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1`:

| | no override | override |
|---|---|---|
| request bytes | 89,031 | 49,164 |
| tools sent | 24 inline (CronCreate, Monitor, WebFetch, WebSearch, SendMessage … all inline) | 12 + `ToolSearch` + `DeferredToolPlaceholder` (deferred tools) |
| body keys | no `diagnostics` | + `diagnostics` |
| headers | — | + `x-claude-code-prompt-id`, `x-claude-code-request-class: main`, `x-client-request-id`, `anthropic-dispatch-id` |
| `metadata.user_id.account_uuid` | **empty** | `76570e6e…` (next2) |
| input tokens (cache create + read) | 31,807 | 16,886 |

So a proxy WITHOUT the override silently degrades the session (no tool search → ~2× request size, no
account identity). The override restores the `pi()`-gated paths but not the `Of()`-gated ones (S03, S09:
server-side message threads and Remote Control stay off behind any non-`api.anthropic.com` host).

## P3 — DECISIVE: per-request bearer swap at a proxy, mid-turn, one process, no restart

Client started on next2 (env token), proxy plan `passthrough:1,next3`, prompt = three sequential Bash tool calls.

| inference call | client bearer | sent bearer | billed org | 7d util |
|---|---|---|---|---|
| 1 | 9f8496d402 | 9f8496d402 | fb09ef51 (next2) | 0.02 |
| 2 | 9f8496d402 | cf40551134 | 1a71eca0 (next3) | 0.17 |
| 3 | 9f8496d402 | cf40551134 | 1a71eca0 (next3) | 0.17 |
| 4 | 9f8496d402 | cf40551134 | 1a71eca0 (next3) | 0.17 |

Result `DONE 1792913047 1792913052 1792913056`, `is_error false`, 4 turns, wall 17.6 s. Transcript
`cfg-swap/projects/…/ff924790….jsonl`: 29 records, one root, no parent with 2 children, 3 tool_use / 3
tool_result matched — linear, no fork. Per-call cache: call 1 create 6,101 / read 10,873; call 2 (first on
next3) create 6,203 / read 10,873; call 3 create 102 / read 17,076; call 4 create 102 / read 17,178. The
~10.9K shared system/tool prefix was ALREADY warm on next3 (it is identical across sessions of this CC
version); only the conversation-specific part (~6.1K here) was re-created once, then caching resumed.

## P4 — DECISIVE: client-native swap via a session-private credential store (no bearer injection)

Client launched with `CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/mtam/probe/ss-m3` holding an inference-only copy of
next2's claudeAiOauth (refreshToken null) in `.credentials.json`; no env token; proxy passthrough as an
OBSERVER only. After call 1 was logged, the file was atomically replaced with next3's inference-only copy.

| call | bearer the CLIENT sent | billed org | 7d |
|---|---|---|---|
| 1 | 9f8496d402 | fb09ef51 | 0.02 |
| 2 (≈4.5 s after the rewrite) | cf40551134 | 1a71eca0 | 0.17 |
| 3, 4 | cf40551134 | 1a71eca0 | 0.17 |

Result `DONE …`, rc 0. Keychain item for the private store before/after: absent (rc 44) both times — the client
created no keychain item. The client adopted the new credential at the very next request (wA() mtime
change-check, S01/S14).

## P5 — the same store swap DIRECT to api.anthropic.com (no proxy anywhere; server-side threads ON)

`m3d.py`, observer = the SDK's own debug log (`ANTHROPIC_LOG=debug`; authorization printed as `***`).
Response org ids in order: `fb09ef51, fb09ef51, 1a71eca0 ×7`; statuses `200, 200, 404, 200 ×6`. The 404 is the
first call on next3: the server-side message thread lives on next2's org (request bodies carry `thread: {…}`).
The client's thread layer (`Hhe()` classifies 404 thread_not_found, S09/12372944) re-sent the full request and
continued on next3. Result `DONE 1792913544 1792913548 1792913552`, `is_error false`, 4 turns. Per-call cache:
create 6,312 / read 10,873 → create 8,438 / read 10,873 (switch) → create 125 / read 19,311 → create 125 / read 19,436.
Cost of a switch in production mode = one ~225 ms 404 round trip + one re-creation of the conversation prefix.

## P6 — interactive client (the real TUI), store swap mid-turn, private tmux socket

`ia.py` on `tmux -L mtamprobe` (a private tmux server, killed at the end), hermetic config, store swap after
inference call 2. Calls 1–3 next2; calls 4–9 next3 (`1a71eca0`), including an idle-time follow-up prompt
26 s later ("OK" rendered). **`metadata.user_id.account_uuid` stayed `76570e6e` (next2) on every call after
the swap**, including the follow-up — the interactive sibling-login watch did not re-key request identity.
Same in P3 and P4. ⇒ every zero-restart mechanism leaves bearer-account ≠ metadata-account until the session
next restarts on the target account's config dir. (Call 1 used `claude-haiku-4-5-20251001`: the TUI's own
side query; irrelevant to the result.)

## P7 — restart fallback: mid-turn kill + `--resume` on another account with the interrupted-turn flag

`intr.py`: background Bash `sleep 25; echo BGDONE >> marker` + a foreground step; SIGTERM at +18 s; resume
`claude -p --resume <same uuid> "Continue from where you left off."` on next3 with
`CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1`. Findings: the background job DIED with the process (marker absent at
+30 s, after the job's 25 s); the resumed session continued the SAME transcript file under the same id and saw
the job as `[killed]`, then re-ran the work in a new background job + Monitor (marker `BGDONE` only from the
re-run). ⇒ a restart-based move loses running background work and depends on the model re-running it (safe
only if idempotent). (CC's own sleep guard blocked the foreground `sleep 30`; the background axis is the result.)

## P8 — two live writers on one transcript

`fork.py`: two concurrent `claude -p --resume <same uuid>` (next2 and next3). Both rc 0, both returned their
reply, ONE transcript file, the two prompts attached to different parents and one message record gained two
children — a branch, with no lock, refusal or warning. This is the hazard the incumbent waits on; the
zero-restart mechanisms (P3–P6) never create a second writer.

## P9 — ACCRUING: does an account's own refresh revoke its previous access token?

`revoke-watch.py` (started 02:31:38 CDT, bounded 9,000 s; the held token expires ≈04:02 CDT) holds next3's current
access token in memory only, polls next3's keychain item read-only every 60 s, and on the first fingerprint change
(next3's own sessions refresh within 5 min of expiry, so ≈03:57 CDT) sends one prompt through the official client with the OLD token, then the NEW one as
positive control, then the OLD one again after 2 min. Log: `/tmp/mtam/probe/revoke-watch.log`. Third-party
report (S09: claude-swap #381) says refresh revokes the old access token immediately. The design does not
depend on the answer (the 401 → re-read → retry path in `Khe()` at 12388136 recovers either way, see REPORT §4).
