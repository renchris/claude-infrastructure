# agent-secrets adopted on this box — and the one setting that must stay unwired

**2026-09-17.** Installed `agent-secrets` v0.1.2 to hold an OpenRouter API key for the Union Alpha
capability probe (`docs/research/union-alpha-drain-2026-09-17/`). Recording the state and one
non-obvious trap, because the tool's own `doctor` actively nudges you into the trap.

---

## 🚨 NEVER PUT `ANTHROPIC_API_KEY` IN THE STORE

`~/.agent-secrets/bin/apiKeyHelper` does exactly one thing:

```sh
store_extract "ANTHROPIC_API_KEY"
```

Claude Code's `apiKeyHelper` setting makes Claude Code authenticate with whatever that prints. **An
API key takes Claude Code off the Max subscription and onto per-token billing** — the same hazard
as `ANTHROPIC_AUTH_TOKEN` on a gateway, by a different door, and the box's cost gate
(`accounts.json spend.usage_credits_authorized=false`) is not a mechanical defence against it.

**The safe posture is to leave `ANTHROPIC_API_KEY` out of the store.** The helper then returns
empty and Claude Code falls back to OAuth subscription auth.

**Consequence, and this is the trap:** `agent-secrets doctor` will permanently report

```
✗ [injection] apiKeyHelper — empty output
✗ [injection] settings.json apiKeyHelper — not wired
    → agent-secrets setup
```

**Those two ✗ are the CORRECT state for this machine, not a defect to fix.** Doctor is written for
the general case, where feeding Claude Code an API key is the flagship use. Here it is the one thing
that would start billing. Do not "green up" those rows.

We do not need `apiKeyHelper` at all: batch jobs run under `agent-secrets run -- <cmd>`, which
injects the named secret as an env var for that one process.

---

## State as of this writing

| | |
|---|---|
| Installed | v0.1.2, `~/.agent-secrets`, symlinked into `~/bin` (`agent-secrets`, `claude-agent`, `cursor-agent`, `apiKeyHelper`); PATH block added to `~/.zshenv`; weekly launchd smoke job `com.agent-secrets.smoke` |
| `agent-secrets setup` | **NOT RUN.** The installer detected a coding-agent session and deferred the key ceremony to a real terminal — correct behaviour, since an agent transcript is plaintext |
| Store | present and decrypting (canary readable). Holds `AWS_BACKUP_ACCESS_KEY_ID` (the shipped inert canary) and `CODA_API_TOKEN` |
| Custody | **macOS Keychain, primary** — *not* a `~/.config/sops/age/keys.txt` file. Searching for that path finds nothing and does not mean the tool is unconfigured |
| `settings.json apiKeyHelper` | absent — and per the section above, must stay that way |
| Pending | `agent-secrets setup` in Terminal.app/iTerm; first secret to be named **`OPENROUTER_API_KEY`** |

## Why an agent did not know this tool existed

The installer offers an opt-in that adds agent-secrets rules to `~/.claude/CLAUDE.md` "so agents in
EVERY repo know to use it." It **skipped that opt-in** because it ran inside a coding-agent session.

That is not cosmetic. In this same session, asked how to receive an API key securely, I recommended
building a macOS Keychain entry from scratch — reinventing a tool the operator had already written,
shipped and open-sourced, sitting in `~/Development/agent-secrets`. Nothing in my instructions
mentioned it, and I had not looked. The operator caught it.

**Fix: re-run the installer from a real terminal and accept the opt-in.** It is the systemic
correction — the discovery problem is what produced the wrong recommendation, not the reasoning.

## Open items

- `⚠ canary — INERT decoy` — no breach detection until armed (`agent-secrets add AWS_BACKUP_ACCESS_KEY_ID`).
- `⚠ off-machine backup — none` — `agent-secrets backup` pushes **ciphertext only, never the age key**.
- The CLAUDE.md discovery opt-in, above.
