---
name: manual-command-delivery
description: >-
  How to hand work back to the USER when something remains that involves them — an interactive login (gcloud auth login, /login), sudo, a classifier- or permission-blocked action, a destructive op they must own, a GUI-only step, or a judgment only they can make. Load the MOMENT you are about to ask the user to do anything. THE RULE: a hand-off is a PROGRAM, not a worksheet — write ONE executable /tmp/<topic>-<purpose>.sh that DRIVES every drivable step, verifies its own work via exit codes (never grep-for-a-phrase), is safe to re-run, and hand it over as one command that RUNS; making the human the runtime is the defect. Sort steps by BLAST RADIUS, not by "could a shell run it": reversible ones are driven silently, while irreversible / production-mutating / money-spending / credential-writing / blocked ones are GATED behind a printed resolved command and a typed yes. NEVER script your own authorization — no permission grants, settings*.json, allowlists or credential writes in a file you hand over; ask in chat, alone. Residue named in the close is only what a shell genuinely cannot do; if what remains is a DECISION there is no script, ask it as the ⛔ rung. Triggers: "you need to run this", "run this yourself", "silver platter", "walk me through", an interactive login, sudo, a classifier refusal, or any step needing their terminal/credentials/eyes. NOT for commands you (the agent) run yourself.
---

## Manual-Command Delivery (All Projects)

🚨 **A hand-off is a PROGRAM, not a worksheet.** When work remains that involves the user, the
deliverable is a single executable, handed over as one command that RUNS —
`bash /tmp/<topic>-<purpose>.sh` — never a file they read and interpret. **Making the human the
runtime is the defect.** If they must execute your steps in order, you have written a worksheet and
delegated the interpreter to a person.

The script **drives every drivable step**, verifies its own work, stops at the first failure naming
step N of M and the way back, and is safe to re-run from the top. It uses only THEIR shell — never
your PATH, cwd, env, or shell functions/aliases (`claude` is a zsh function on this machine; a
`#!/bin/bash` script never sees it). A step needing their interactive TTY is the LAST step or is
residue — never buried mid-run.

### Sort steps by BLAST RADIUS, never by "could a shell run it"

That test is a category error: it answers a question about *the shell's capability* to settle a
question about *the human's consent*. A shell can `DROP TABLE` and `git push --force` too.

- **Reversible** ⇒ driven silently. This is most steps, and driving them is the whole point.
- **Irreversible, production-mutating, money-spending, credential-writing, or refused by a
  classifier or permission prompt** ⇒ **GATED**. Print the RESOLVED command (account · target ·
  row count), one line on what it cannot undo, and why it was blocked; then require a typed `yes`,
  defaulting to no. Declining skips that step and reports it. Support `--dry-run`.

**A block bought a human READING that specific command. A keystroke over an unread program does not
pay it.** Bundling a refused command into a 200-line run converts per-command review into one
undifferentiated `bash` — the consent obtained is "run the hand-off", never "delete these rows".

⚠️ **Permission-blocked ≠ classifier-blocked.** A permission prompt is ALREADY a per-command silver
platter: it fires at execution, shows the exact command, and the human answers in real time.
Burying it in a batch replaces a working consent UI with one upfront yes — strictly worse than
doing nothing. Leave it to fire.

### 🚨 NEVER script your own authorization

No permission grants, no `settings*.json`, no allowlists, no credential writes — not in a script
you hand over, not ever. If you need a permission, **ask for it in chat, alone, as its own thing.**

*Learned the hard way, 2026-08-25:* a classifier correctly refused to let the agent write its own
`.claude/settings.json`. The agent then put that same grant into a hand-off script as step 4 of 5,
and the user ran it. The user had explicitly asked for the grant twice, so nothing was done behind
their back — but **as a standing pattern this is agent-authored, human-rubber-stamped privilege
escalation**, and the refusal it routed around exists precisely to prevent it. An agent that can
put its own permissions into a file a human executes does not have permissions.

### Verdicts fail closed

Success is an **exit code**, or a value **read back by a different call than the one that made the
change**. Never grep-for-a-phrase; never treat empty output as success. A driving script that lies
about outcomes is worse than a worksheet, because the human has stopped watching.

*Measured the same day:* the hand-off script called a perfect run (`PASS 60 / FAIL 0 / SKIP 0`) a
FAILURE, because it grepped for `READY` while the gate — already live — prints `HEALTHY — LIVE` on
that path. The gate had been `exit 0`-ing the whole time. The check was keyed to a world the system
had already left, which is the same defect the hand-off existed to fix, reproduced inside the tool
written to fix it.

### Residue — the only thing the close names

GUI-only · a credential only they hold · something physical · a judgment that is theirs.

**Not every residue is a command.** If what remains is a DECISION, there is no program to write — a
script that prints a question is a worksheet with extra steps. Ask it as the `⛔` rung.

### What this superseded, and the part of it that is still true

This skill used to say: write `/tmp/<topic>-<purpose>.sh` as "plain shell, one clean block per step,
each preceded by a `# comment`", open it with `cursor`, and give a chat walk-through that POINTS at
the file. Its stated **Why** — copy-paste fidelity — remains correct and is why the file still
exists at all: a wrapped/smart-quoted heredoc pasted from chat silently breaks, and a file is exact.

But that spec describes a **document**, so that is what got produced: commands interleaved with
prose, for a human to run in order. The user opened it and asked, *"you wanted me to open it not run
it?"* — then, *"Silver platter / hand-hold / spoon feed us through this."* The artifact had complied
with the skill exactly. Fidelity was never the whole job; **agency** was the missing half.

Still true, and unchanged: `/tmp` only — regenerable, disposable, never committed. Open it with
`cursor` so they CAN read it before running (`--dry-run` and the gates are what make reading
optional rather than mandatory). The chat carries the walk-through; the file carries the work.
