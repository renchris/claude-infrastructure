# W2 managed round trip — the VM's side

Written from inside the Claude Code on the web container, 2026-08-11.

This is the VM's half of the **W2 managed round trip**: the laptop briefs a cloud session,
the cloud session writes and pushes, the laptop lands. I only own the middle.

## What the clone looks like from in here

- **Shallow-clone depth:** `git rev-list --count HEAD` → **50**. The container gets a
  truncated history, not the full trunk — enough to commit and push onto, not enough to
  reason about the repo's past.
- **Branch I am pushing to:** `claude/fire-20260811T185616Z-188-1` — pre-created for this
  session; I neither chose it nor may push anywhere else.

## What I could not do here

There is no operator `~/.claude` layer on this machine — the home directory holds only the
harness's own scratch (sessions, projects, backups), with no `hooks/`, no `bin/`, and no
global `CLAUDE.md` — so `cc-backlog`, `cc-bats`, and `ship-land` do not exist to be run;
the `gh` CLI is likewise absent (GitHub reaches me only through MCP tools).

Consequence for the round trip: everything this repo's close protocol computes from the
live layer — the ledger, the gates, the land — is structurally unreachable from the VM.
My job ends at the push, and the laptop is the only side that can land it.
