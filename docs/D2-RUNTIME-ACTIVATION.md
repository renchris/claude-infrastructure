# D2 — Runtime-phase activation runbook (C10, operator-only)

The runtime primitives (boundary hook + supervisor) are **built, tested, and premortem-green**.
Activating them modifies agent configuration and installs persistence — that is **ruling class C10
(self-modification / persistence), permanently human-only** (audit §2b). The agent does all the work
and hands you this runbook + a self-contained activation script; **the agent never activates.**

## What gets activated

| Primitive | File | Activation act | Blast radius |
|---|---|---|---|
| Boundary hook | `hooks/boundary-handoff.sh` | add a **Stop** hook entry to `~/.claude/settings.json` | every session's Stop event (latched, advisory) |
| Supervisor | `scripts/lead-supervisor.sh` | `launchctl load` a `KeepAlive` daemon | one background daemon per machine |

Both are **safe by construction**:
- The hook exits 0 always (never costs a session), fires only at a committed+green boundary past
  threshold, is one-shot-latched (+used_pct re-arm), and logs every decision to the IDL.
- The supervisor **PAGES, never auto-recovers** (ruling #1). It is bash and physically cannot close a
  live pane. Its only writes are: checkpoint-preserve (git plumbing, safe), page records, and the IDL.

## Activation

The self-contained script is written to `/tmp/d2-activate.sh` (regenerable; not committed). It:
1. **Backs up** `~/.claude/settings.json` to a timestamped copy.
2. Merges the boundary Stop-hook entry with `jq` (surgical — touches only `.hooks.Stop`).
3. Generates + `launchctl load`s the supervisor plist (`~/Library/LaunchAgents/com.claude.lead-supervisor.plist`).
4. **Effect-checks**: confirms the hook entry is present, the daemon is `launchctl list`-visible, and one
   sweep wrote a `heartbeat` line to the IDL.
5. Prints the **rollback one-liner**.

Run it yourself (the agent will not):
```
bash /tmp/d2-activate.sh
```

## Rollback

```
# hook: restore the pre-activation settings backup the script printed
cp ~/.claude/settings.json.pre-d2-<ts> ~/.claude/settings.json
# supervisor: unload + remove the daemon
launchctl unload ~/Library/LaunchAgents/com.claude.lead-supervisor.plist
rm ~/Library/LaunchAgents/com.claude.lead-supervisor.plist
```

## Remaining integration (named, not blocking — the hook is safe-inert without it)

The boundary hook's condition (a) checks `.git/gate-green == HEAD` — a marker written after a green
gate at a commit. **That marker-writer does not exist yet** (blueprint §3.2 build-dep B2), so the hook
currently **always abstains with `gate-not-green-at-head`** (fail-safe: it never advises a handoff on an
unproven-green tree). It is therefore SAFE to activate but INERT until a `/ship`/commit-time step writes
`git rev-parse HEAD > "$(git rev-parse --git-common-dir)/gate-green"` on a green gate. The **supervisor
is fully functional now** and covers the higher-value B-1 case (past-threshold ∧ not-Stopping) that the
hook is structurally blind to — so activating the supervisor is the high-value step; the hook becomes
useful once the marker-writer lands.

## Verify after activation (the four zeros / effect-check discipline)

```
tail -f ~/.claude/autonomy/idl.jsonl          # heartbeats every sweep; pages/abstentions as they happen
launchctl list | grep lead-supervisor          # daemon present
./scripts/premortem-gate.sh                     # still green
```
