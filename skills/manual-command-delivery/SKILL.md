---
name: manual-command-delivery
description: How to hand a command to the USER to run themselves — anything you cannot or should not run: interactive logins (gcloud auth login, /login), sudo, a safety-classifier-blocked action, a force-push / destructive op they must own, or any command needing their terminal or credentials. Load the MOMENT you are about to give the user a command to paste. The rule: never scatter copy-paste commands inline in chat (TUI line-wrapping + smart quotes corrupt heredocs, quotes, and URLs on paste); instead write ALL of it to one /tmp/<topic>-<purpose>.sh with a per-step # comment (what it does, why, required vs optional, expected output), open it with `cursor`, and give a SHORT walk-through in chat that POINTS at the file rather than restating the commands. Triggers: "you need to run this", "run this yourself", an interactive login is required, sudo is needed, or any command that needs the user's own terminal/credentials.
---

## Manual-Command Delivery (All Projects)

When you need the USER to run something themselves — anything you can't or shouldn't run: interactive
logins (`gcloud auth login`), `sudo`, a safety-classifier-blocked action, a force-push / destructive op
they must own, or any command needing their terminal/credentials — do NOT scatter copy-paste commands
inline in chat. TUI line-wrapping, smart quotes, and markdown fences corrupt them on paste (heredocs and
anything with quotes/URLs especially). Instead, EVERY time:

1. Write ALL of it to one `/tmp/<topic>-<purpose>.sh` — plain shell, one clean block per step, each
   preceded by a `# comment` (what it does, why, required vs optional, expected output).
2. Open it: `cursor /tmp/<topic>-<purpose>.sh` (print the path if the `cursor` CLI is absent).
3. In chat, give a SHORT walk-through that POINTS at the file (step names + effect + expected output) —
   never restate the commands inline.

Standing pattern for every manual hand-off, in all sessions and repositories. `/tmp` only —
regenerable, disposable, never committed. **Why:** copy-paste fidelity — a wrapped/smart-quoted heredoc
pasted from chat silently breaks; a file opened in Cursor is exact. The inline chat carries the
*walk-through*, the file carries the *commands*.
