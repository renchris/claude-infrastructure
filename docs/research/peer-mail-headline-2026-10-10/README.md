# Peer-mail headline — decisions (2026-10-11)

Ask (operator, 2026-10-11): when a session receives peer mail, the operator should see which session
sent it (pane + session title, surviving forwards), a short answer-first title, when it was sent and
how late it arrived; and the receiving session should acknowledge mail in chat without flooding it.

Research: five read-only slots and one critic (`slot-*.md`, `critic.md` here). The critic's
integrated design (§5) is what was built, with the deviations listed below.

## What was decided, and why

| Decision | Choice | Why (measured) |
|---|---|---|
| Where the metadata lives | One `[@v1;pane=…;sid=…;title=…;subj=…;by=flag]` token right after `[<from>]`, written by `bin/cc-notify` (both write sites) | `[@` occurs 0 times in 31,140 historical lines; every first-bracket reader, every `] <body>` test grep and the custody parser keep working; the token rides inside the original line, which forwards copy byte for byte (slot-compat, critic §1). A sidecar file is lost on the first forward. |
| Sender identity | `pane` = the sender's registry row `.paneUUID`; `title` = custom-title > agent-name > ai-title from the tail of its own transcript; captured under `--from` too (`by=flag`) | 40 of 43 live rows have an ai-title in the last 64 KB; capture costs 30-131 ms under load ~850 (slot-identity). Skipped when `CLAUDE_CODE_SESSION_ID` disagrees with the row (a reused kitty window id). |
| Title | `--subject` when given, else T0: the body with routing tags, status glyphs and `HANDOFF-PING <slug>:` stripped, UUIDs shortened, capped at 72 on a word boundary | T0 scores 144/160 and 60/70 out of sample, tying the tuned A4.1 (critic §3); the subject is optional because ~349 call sites would otherwise change. |
| Lag | `arrived N min late` from the ORIGIN stamp once ≥10 min (`CC_MAIL_LATE_MIN`) | No surfaced line fell between 9.9 and 26 min; forward stamps hid lags up to 6.7 h (slot-lag-ack). |
| Idle-wake headline row | Unchanged (static `rewakeSummary`) | Claude Code 2.1.293 takes a per-wake summary only from an official-marketplace plugin's stdout (slot-rewake, from the bundle). The woken turn's drain re-delivers the same lines 1-35 s later (13 of 14) and shows the headline line then (critic §2.3). The wake's stderr now leads with the headlines for the model. |
| Empty wakes | A stood-down watcher (rc 0, no body, `verdict=stood-down`) no longer wakes | 15 of 26 measured wakes were this empty "(…returned no body…)" line. |
| Acknowledgement | Asked only by the drain and the stop fold (both commit a cursor); only for another pane's token (not `by=flag`) or a HANDOFF-PING, not lifecycle noise, not older than 24 h; one line per text block | ~0.81 agent deliveries per active hour (p90 3.75); the wake and the drain would otherwise ask twice (critic §4). |
| Socket wake frame (`bin/cc-wake`) | Unchanged | It is a user-role message: putting peer-derived text there would give it the operator's authority, and its suite pins "carries no mail body". |

## Deviations from the critic's design

- Operator line stays ONE line per drain (the brief's hard constraint), not the critic's 3-line block:
  one message renders its full headline; several render `N peer message(s) from <3 senders> · first: <headline>`.
- The renderer is python (`hooks/lib/mail_headline.py`), not awk: one ~0.1 s fork per delivery
  (measured at load ~300), shared by the drain, the stop fold, the wake and the bats fixture.

## Also fixed (found on the way)

- `bin/cc-inbox-guard` took the class tag from a forward's first bracket (`forwarded:<box>`), so a
  forwarded reaper or supervisor page lost its urgent deadline (critic §1.2).
- Anti-forgery: `--from` with `]` or a leading `forwarded:`, and a body opening with `[@` or an ISO
  stamp, are neutralised at send (0 of 14,725 live lines affected).

## Residuals

- The 10-minute lag threshold rests on 8 lines above it; re-measure on a wider window.
- If a future Claude Code drops the plugin-only gate on `rewakeSummary`, the wake hook could print
  `{"rewakeSummary":"<headline>"}` on stdout; re-check on each version bump.
- `cc-await-ping` writes some lines straight into the box (16% of unique lines) with no token; they
  render by their `[from]` as before.
