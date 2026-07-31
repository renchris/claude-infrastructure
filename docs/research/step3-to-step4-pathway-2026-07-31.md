# Step 3 → Step 4: the actual blocker is legibility, not permissions — 2026-07-31

**Frame:** Cherny's *Steps of AI Adoption*. Step 3 (Supervised autonomy, ~100 agents) names its own
bottleneck as *"the agent tree is too deep to babysit"*, and its trap as *"scaling agent count
before the loop has earned widespread trust."* Step 4 (AI-native) is *"steer by intent and monitor
by exception."*

**Verdict from measurement: we are not blocked by permission prompts. We are blocked because a
blocked agent cannot reach anyone.** Three independent channels were measured tonight, and all
three drop the message. Until they carry, adding agents makes the invisibility worse, which is
precisely the named trap.

---

## 1. The permission premise is false — measured

`bin/cc-permission-audit` over 41,829 Bash invocations / 1,004 transcripts:

| | count | share |
|---|---|---|
| matched an `allow` rule | 33,097 | 79.1% |
| matched nothing (prompt candidates, **upper bound**) | 8,678 | 20.7% |
| **hit an `ask` rule** | **22** | **0.05%** |
| hit a `deny` rule | 32 | 0.08% |

The six deliberate gates (`fly deploy`, `git push`, `git reset --hard`, `git restore`,
`git stash clear|drop`) fired **22 times in 41,829 calls, all of them `git push`**. They are not
what stops work, and loosening them buys nothing.

**And the allow-list is the wrong lever anyway.** Of the 8,678 unmatched, **7,666 (88.3%) are
compound shell programs** — `;`, `&&`, `||`, pipes, `$( )`, `for`/`until`/`while`, function
definitions. A static `Bash(prefix:*)` rule structurally cannot express them. The static ceiling is
**~2.4% of all Bash calls**. Only a hook that inspects a command can decide about the other 88%,
which is why `hooks/smart-bash-allowlist.sh` exists and why `sed -n` (the single largest slice, 730
of the 1,014 simple-verb candidates) landed there rather than in `settings.json` (`76964484`).

> Honest bound, pinned by a test in the tool: this is an **upper** bound. Auto mode's classifier
> approves much of what matches no literal rule, and it can also raise a prompt on a command that
> *does* match. The true set is unmeasurable today — see §2c.

---

## 2. The real blocker: three channels, all silently dropping

### 2a. Permission → pager addressed to a dead pane

`hooks/cc-permission-beacon.sh` (wired on `PermissionRequest`, 18 tests) correctly writes
`{ts,tool_name,tool_input,cwd}` to `/tmp/cc-permission-pending/<sid>.json`. `lead-supervisor.sh` is
loaded, running, and reads that exact seam to emit `⛔ PERMISSION-PENDING`.

Measured: a session blocked **7.1 hours** on a git ref-name injection probe (correctly gated). The
record was there the whole time. `send_page` resolves its target from `~/.claude/cc-roles/desk` →
`D40A5752-…` → **DEAD, no such pane**. The page evaporated; `send_page` returned non-zero and
nothing surfaced.

The address rots on **every** iTerm2 restart (it re-rotted at 22:04 tonight). Same class as
[[mailbox-writer-reads-different-key-than-reader]].

### 2b. Notification → anonymous and lossy — **FIXED 2026-07-31 (`f5651bbd`)**

`hooks/notify.sh` *does* fire an OS notification on every `PermissionRequest` — pane-independent,
no address to rot. Two defects made it useless at 30 sessions:

- **No identity.** `EVENT_TYPE="${1:-complete}"` is the hook's *entire* input; it reads no stdin and
  no payload. The notification says `"Claude needs your approval"` — with 30 sessions that names
  nothing, so the operator still hunts panes.
- **Lossy debounce.** `DEBOUNCE_FILE=/tmp/claude-notify-${_ACCT}-${EVENT_TYPE}.lock` with a 2 s
  window is keyed per *account*, not per session. Two sessions blocking within 2 s → one
  notification. At 30 sessions that is a routine drop.

> **Landed.** The alert now renders `title: Permission · <dir>`, `subtitle: <sid8> · <tool>`,
> `message: <the actual blocked command>`, and the debounce key carries the session id. Fail-open is
> preserved end to end: no stdin, no jq, or malformed JSON ⇒ the original anonymous strings still
> fire, because a hook that renders *nothing* is worse than the anonymous one it replaced.
> Two defects surfaced during the build, both of which would have reproduced the very drop being
> fixed, so they are kept visible here:
> - Escaping `"` as `\'` is a hard AppleScript **syntax error** (-2741) — so every alert whose
>   command contained a quote (`git commit -m "…"`, the common case) would have rendered nothing.
>   The test now compiles the real artifact via `if false then <script>`, with a RED control
>   proving that check can fail.
> - Splitting the payload on `IFS=$'\t'` drops empty fields, because tab is IFS *whitespace* and
>   bash collapses runs of it. A payload with no `tool_name` — i.e. **every** `Notification` event,
>   which is the live `permission_prompt` path — shifted the message into the subtitle and left the
>   body empty. The separator is now US (`0x1f`): non-whitespace, so empties survive positionally.
>
> Seams `CC_NOTIFY_DIR` / `CC_NOTIFY_JQ`; `tests/notify.bats`, 21 tests, new file.

### 2c. Agent Teams → lead polls a channel its teammates cannot write

Measured: **8 assignees of lead `2dea4469`, alive 6.5 h**, several holding finished work; one
(`@pack-world`) sitting on three verified hunks in `.wt/emote-preview` explicitly awaiting a
decision.

The lead is **not dead**. It is blocked in **4 stacked `cc-await-ping … --timeout 14400`** calls,
polling `~/.claude/mailbox/2dea4469-….md` — **a file that has never existed**, while 114 mailbox
entries exist for other sessions. Lead → assignee works (in-process `SendMessage`); assignee → lead
pings go to a substrate the lead is not reading. Deadlock, re-arming every 4 hours.

This is also why §1's "true prompt set" was unmeasurable: the beacon `rm -f`d each record once
answered (`cc-permission-beacon.sh:85`), so **no history of actual prompts existed anywhere**.
**FIXED 2026-07-31 (`bfc40579`, `40f93e05`)** — every resolution is now appended to a durable
archive first, and `bin/cc-permission-audit` reports the measured set beside the inferred bound.
The archive accumulates **forward only**, so §1's table stays the best estimate for history; it is
the *future* weeks that stop being guesswork.

---

## 3. Pathway — every stage has a measurable exit trigger

### Stage A — make a block legible (days, not weeks). Prerequisite for everything else.

**All four items are now landed. The exit trigger below is NOT yet claimed** — see the verification
note at the end of this section.

1. ~~**Give the notification an identity.**~~ **LANDED `f5651bbd`.** `notify.sh` reads the hook
   payload and renders session + cwd + the actual command. Anonymous pages cannot be triaged.
2. ~~**Key the debounce per session**~~ **LANDED `f5651bbd`.** Was per account, so concurrent
   blocks were dropped by construction at exactly the scale we care about.
3. ~~**Make the page address self-healing.**~~ **LANDED 2026-07-30** (`e6d789a8`, the `send_page`
   verdict fix). `send_page` resolves the desk role *at page time* and fails loud when the target
   is dead, as `resolve_headless_anchor` already did. Note this escalates **future** pages only —
   it does not re-page a block that was already damped.
4. ~~**Archive the beacon.**~~ **LANDED `bfc40579` + `40f93e05`.** Every resolution is appended to
   a durable append-only JSONL under `~/.claude/autonomy/permission-archive` before `rm -f`, and
   `bin/cc-permission-audit` consumes it. Deliberately **not** under `CC_PERMPEND_DIR`: that is
   `/tmp`, wiped on reboot, and the archive must outlive uptime.

   Outcome attribution needed a correction found during the build, and it is worth recording
   because the wrong version is the intuitive one. "Cleared by `PostToolUse` ⇒ approved" is
   **false**: `PostToolUse` fires for *every* tool, not just the prompted one, so after a **denial**
   the turn can continue, run some other tool, and have that tool's `PostToolUse` clear the still-
   pending beacon — archiving a refusal as an approval, and overstating how permissive the
   classifier is, which is the single number this archive exists to inform. The record therefore
   carries `cleared_tool` alongside `resolved_by`, and a grant is only claimed when the clearing
   tool matches the prompted one; a mismatch is reported as **unknown**, in neither bucket.

**Exit trigger:** a deliberately blocked session is surfaced, with its identity, in < 60 s, twice
running, at ≥ 20 live sessions.

**Status of that trigger: UNVERIFIED.** The code paths are unit-green (21 + 27 + 16 tests) and
proven end to end against the real hooks, but the trigger is a *fleet-scale behavioural* claim and
has not been run at ≥ 20 live sessions. Do not record Stage A as exited until it has. The cheapest
honest check: with ≥ 20 sessions up, have one deliberately request a gated command, and time how
long until the operator can name *which* session from the alert alone.

### Stage B — one substrate for agent↔lead (weeks)

Assignees and leads must use the **same** channel. Either `cc-await-ping` learns the in-process
teammate inbox, or teammates also write the file mailbox. Today they are disjoint and a lead can
wait forever on an empty file.

**Exit trigger:** kill a lead mid-wave; its assignees are detected and adopted or reaped within one
sweep. Note `com.claude.team-orphan-reaper` is **staged but NOT LOADED** — the detector for exactly
this is written and inert.

### Stage C — reduce prompt rate on real data (ongoing, weekly — Stage A.4 has now landed)

Re-run `bin/cc-permission-audit`. It now prints an **OBSERVED** section from the archive: the
commands that *actually* blocked, with approved-vs-denied attribution. **Rank from that list, not
from the inferred candidates above it** — the candidate ranking is a bound over what the static
rules fail to match, whereas the observed list is what really stopped a session. Give it a week or
two of accumulation before drawing conclusions; the archive only fills forward from 2026-07-31.

Move the top compound classes into
`hooks/smart-bash-allowlist.sh` — never into `settings.json`, per §1. Each rule is a **positive
whitelist** with a whole-command anchor and `[^;&|]`; a blacklist enumerates spellings, not the
class ([[denylist-enumerates-spellings-not-the-class]] — the `sed -n` rule's first draft made
exactly this error and admitted `sed -n 'w /tmp/out' f`).

**Exit trigger:** unmatched share falls below 10% of Bash calls, measured, two weeks running.

### Stage D — sandboxing: the principled way to widen (weeks)

`settings.json` has **no `sandbox` key**. Sandboxing is Step 3's listed guardrail and the only
honest alternative to `--dangerously-skip-permissions`: it shrinks the **consequence** rather than
removing the **check**. This is what lets agent count grow without loosening gates.

**Exit trigger:** a sandboxed agent class exists whose blast radius is bounded well enough to run
with a materially wider allow set.

### Stage E — then, and only then, scale the tree

With blocks legible (A), a single agent↔lead substrate (B), a measured prompt floor (C), and
bounded blast radius (D), agent count can rise without adding invisible work. **Attempting E first
is the trap the framework names**, and tonight is what it looks like: 8 agents idle 6.5 h, one
permission unseen for 7.1 h, and an operator watching 30 panes because that was the only channel
that worked.

---

## 4. What this reframes

The visibility requirement — ~30 panes on screen at all times — is not a preference to be designed
around. It is a **compensating control for three broken channels**. Fix them and it dissolves:
sessions need no rendered pane when a block finds you, which retires the whole Metal/WindowServer
axis of [[iterm2-freeze-30-sessions-2026-07-30]] rather than optimising it.

Related: `docs/research/iterm2-freeze-30-sessions-2026-07-30.md` ·
`docs/research/terminal-config-30-sessions-decision-2026-07-30.md` · tasks #66, #67, #57
