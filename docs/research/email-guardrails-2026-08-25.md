# Email guardrails — drafts-only, and alias continuity

**Date:** 2026-08-25
**Artifact:** `hooks/enforce-email-formatting.py` (one file; symlinked to `~/.claude/hooks/` and wired
as a PreToolUse hook in all five account config dirs, so one edit propagates everywhere)
**Tests:** `tests/email-drafts-only-and-alias.bats` (25) · `tests/email-reply-quote-guard.bats` (11)

## The invariant

Two classes of outbound-email mistake the agent can make **alone** and **cannot undo** are now
refused at the tool call rather than discouraged in prose:

> **R1 — The agent composes into Drafts. The operator presses Send.**
> **R2 — An outgoing message uses the alias the counterparty already has for that thread.**

Prose in a skill is obeyed probabilistically; a PreToolUse deny is obeyed always. That difference is
the entire point of the change — the operator's framing was *"deterministic / reliably read
instructions for both so it's not just sometimes we listen."*

## R1 — never send programmatically

A Microsoft Graph send is immediate and irreversible. Outlook's "undo send" is a client-side delay
in the Outlook client; it does not exist on the Graph path. There is no window in which a
programmatic send can be recalled.

| Tool | Decision | Why |
|---|---|---|
| `send-mail` | **DENY** → `create-draft-email` | transmits |
| `reply-mail-message` | **DENY** → `create-reply-draft` | transmits |
| `reply-all-mail-message` | **DENY** → `create-reply-all-draft` | transmits |
| `forward-mail-message` | **DENY** → `create-forward-draft` | transmits |
| `send-draft-message` | **DENY** (no replacement) | transmits an already-composed draft |
| `create-draft-email`, `create-reply-draft`, `create-reply-all-draft`, `create-forward-draft` | ALLOW | compose only |
| `update-mail-message` | ALLOW | revises a draft in place |
| all read tools | ALLOW | — |

Each deny **names the draft-creating tool that replaces the blocked one**, so the model's next call
is correct rather than a retry in a slightly different shape.

### It is absolute, and that was deliberate

No model-assertable override. R1 is checked **above** the `CLAUDE_EMAIL_FORMAT_GATE_DISABLED` kill
switch (which still disables the formatting rules) and above the `GATED_TOOLS` scoping, so it cannot
be reached around by disabling the gate, by sending a short body, or by any later arm that would
have allowed the call.

An escape hatch conditioned on *"the user said to send it"* would be worthless, because **a model
asserting that consent is exactly the failure that already happened**: 2026-08-24, three sends in
one evening, only the first authorized, the third a legally operative Cal. Civ. Code §1950.5(f)
notice in a live deposit dispute. An override the model can talk its way through re-creates
"sometimes we listen." The break-glass is the operator pressing Send in Outlook — one tap.

### It fails CLOSED, alone among the arms

The formatting rules fail **open** by design: a hook bug must never strand a legitimate draft. R1 is
the exception. The crash handler re-inspects the raw payload and denies if it names a send tool,
because a crash is not consent for the one call that cannot be undone. The check is a substring
match on the raw bytes, not a re-parse, since the crash may itself have been a parse failure — and
it is scoped to the send-tool names so a malformed **read** still fails open. That scoping is
load-bearing: this hook fires on every ms365 call across five account config dirs, so a
bad deny takes email down for every session on the machine.

Both properties are tested directly rather than assumed: `kill_switch_cannot_reopen_a_send` sets the
documented override and asserts the send is still refused (with a control proving the switch is not
merely inert), and `crash_denies_a_send` feeds malformed JSON so the interpreter genuinely dies
inside `main()`.

## R2 — alias continuity

The mailbox has two aliases: **`ichris96@hotmail.com`** and **`ren.chris@outlook.com`**. The
invariant is that an outgoing message must use the alias the counterparty already has for that
thread — derived from the original's `toRecipients`/`ccRecipients`, never from a global default.

### The Montway evidence — read from the mailbox, not recalled

Verified 2026-08-25 by direct read of the live mailbox:

- Every Montway message on order #3414154 — booking confirmation, payment receipt, pickup checklist,
  order-status link, and the Dispatch Notification (Aug 25 18:55:54Z) — is addressed
  **To: `ichris96@hotmail.com`**.
- The operator's dispatch-hold request (Aug 25 02:41:03Z = Aug 24 7:41 PM PDT), to `info@montway.com`
  cc `premium@montway.com`, went **From: `ren.chris@outlook.com`** — an address Montway had never
  seen on that order.
- Montway dispatched and charged $1,779 the next morning.

⚠️ **This is correlation, not proof, and it should not be sold as more.** A broker CRM matching
inbound mail to an order by the customer's address on file explains the outcome completely — but so,
partly, does a sales rep not watching a shared inbox. Both remain live. **The rule is correct either
way**: replying from an address the counterparty has never seen on the thread is wrong on its own
terms, whatever Montway's CRM did with it.

### What the old rule actually did

RECIPE rule 5 read, verbatim: *"SENDER. Set from = ren.chris@outlook.com; Graph otherwise defaults
to the ichris96 alias."*

The sharp finding is that **this rule did not merely fail to help — it was the active cause.** Graph's
default for this mailbox is `ichris96@hotmail.com`, which was the *correct* alias for the entire
Montway thread. The instruction overrode a default that was already right. Rule 5 now states the
match-the-thread invariant and names both aliases instead of hardcoding one.

### Graph does NOT derive the alias for you — verified

Tested read-only on 2026-08-25 and then cleaned up: a `create-reply-draft` with **no `from` set**, on
an inbound message addressed to `ren.chris@outlook.com`, came back **`from: ichris96@hotmail.com`**.

So Graph applies the **mailbox default**, not the thread's alias. This kills the tempting simple
rule *"just omit `from` and let Graph do the right thing"* — it would be wrong on every ren.chris
thread. Practically:

- thread on `ichris96` → the default is already correct; omit `from`.
- thread on `ren.chris` → you **must** set `Message.from` explicitly.
- **`Comment` mode cannot set `from` at all**, so a ren.chris thread requires `Message.body` plus an
  appended quote (rule 3).

### Mechanically enforced vs merely surfaced — the honest split

| | Status |
|---|---|
| `from`/`sender` outside the two known aliases | **ENFORCED — DENY.** Catches a typo, a hallucinated address, or another account's identity. Case-insensitive, and it reads all four envelope shapes: `body.Message.from`, `body.Message.sender`, `body.from`, `body.sender`. |
| Whether the chosen alias **matches the thread** | **NOT ENFORCEABLE HERE — surfaced only.** A permitted call carrying an explicit `from` gets an advisory naming the check and the Montway incident. |

**Why the second row is structural, not lazy.** A PreToolUse hook receives only `tool_name` and
`tool_input`. Graph's **responses are invisible to it**, and a reply's `tool_input` carries just a
`messageId` — never the original's recipients. So the thread's alias cannot be derived inside this
hook at all. The alternative — having the hook call Graph itself — is rejected: it fires on every
ms365 call across five config dirs, so it would add network latency and a hang risk to every mail
operation and would need its own auth.

**R1 mitigates R2 structurally**, which is worth stating plainly: under drafts-only, every outgoing
message is now reviewed in Outlook before it leaves, and Outlook displays the From address. The
alias error became visible-before-send as a side effect of R1.

## The dry-run conflict, resolved by measurement

RECIPE rule 4 mandated a **send**: *"Drafts have no MIME, so to check a draft do a DRY RUN: build it,
swap recipients to the user alone, send, inspect that copy's MIME."* Under R1 that is unfollowable.

The brief asked whether to replace it or drop it. **The premise turned out to be false**, so neither:

> **Drafts DO have MIME.** `get-mail-message-mime` on a draft's own messageId returned the complete
> RFC-822 source — both `text/plain` and `text/html` MIME parts, plus `From:`, `In-Reply-To:` and
> `References:` headers. Verified 2026-08-25 on a real draft in the mailbox.

Rule 4 now says: build the draft, then run `get-mail-message-mime` on **that draft's own id**. The
dry-run send is deleted outright — it existed only to work around a constraint that was never real.
Draft verification is now strictly cheaper than the thing it replaced (one read, no send), and the
same read also exposes `From:`, which is the recommended confirmation step for R2.

## Adjacent members of the same class

The brief asked that adjacent irreversible-outbound failures be treated as in scope. Assessed:

- **A reply that silently detaches from its thread** — already guarded (pre-existing): a fresh-send
  tool carrying a `RE:`/`FW:` subject is denied and steered to a reply tool. Under R1 the only
  fresh-send tool left is `create-draft-email`, which keeps that guard. Now *fully* recoverable
  regardless, since the detached message is a draft.
- **A reply that threads but arrives with no visible history** — already guarded (2026-08-24): a
  reply tool passing `Message.body` with no quoted chain is denied.
- **A recipient set quietly widened** — `reply-all-mail-message` is denied by R1; the surviving
  `create-reply-all-draft` produces a draft whose recipient list the operator sees in Outlook before
  it leaves. Widening is no longer irreversible, so it does not need its own deny.

The common structure: R1 converts each of these from *irreversible* to *reviewable*. That is why R1,
not R2, is the load-bearing half of this change.

## Test design

Both suites follow the discipline the existing `email-reply-quote-guard.bats` established: literal
PreToolUse payloads through the real entrypoint, red-proof cases replayed against a **pinned
pre-change blob** so the suite cannot rot into vacuity, and controls that make "deny everything"
fail. `create-reply-all-draft` is asserted ALLOW by name — it is the only working path for a
threaded reply, so if it ever denies, the guardrail has eaten the workflow it was built to protect.

Two things worth recording because they were caught *by* the tests rather than by review:

1. **The alias arm was originally a bypass.** It returned `allow()` the moment it saw a well-formed
   address, which skipped every formatting and quote check below it — so setting a valid `from`
   would have disabled R3 entirely. Now it stashes an advisory and falls through. Pinned by
   `setting a valid from does NOT become a bypass for the quote guard`.
2. **The red-proof instrument control was itself vacuous on first run.** It grepped the pre-R1 blob
   for `SEND_TOOLS` expecting zero matches, but that file already defines `FRESH_SEND_TOOLS`. The
   pattern is now anchored to `^SEND_TOOLS`. A control that passes for the wrong reason is worse
   than no control.

The existing quote-guard suite was **re-pointed onto the draft tools**. Its fixtures previously ran
through `reply-mail-message` / `send-mail` / `forward-mail-message`, which R1 now denies before the
quote guard is consulted. That had two effects: four ALLOW controls went red, and — the dangerous
half — three red-proof DENY cases went green *for the wrong reason*, and would have stayed green
with the entire quote guard deleted. Every fixture now knocks on the draft door, where the guard
genuinely runs. The decisions asserted are unchanged.

## Deployment note

`~/.claude/hooks/enforce-email-formatting.py` symlinks to the **root checkout**, not to a worktree,
so this change is inert until it lands on trunk. Landing is what makes it live.
