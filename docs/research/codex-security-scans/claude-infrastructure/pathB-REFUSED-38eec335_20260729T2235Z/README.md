# Path B partial bundle — REFUSED by OpenAI's cyber classifier

**Not a sealed bundle. There is no `findings.json`, `coverage.json`, or `report.md`** — the run was
terminated before validation and severity calibration, so nothing here has passed the pass that
suppresses false positives. Treat every line of `candidate_ledger.jsonl` as an **unvalidated lead**.

| | |
|---|---|
| Path | B — `npx @openai/codex-security@0.1.4 scan . --path hooks/validate-bash.sh --effort medium` |
| Scope | `hooks/validate-bash.sh` (see `in_scope_files.txt`) |
| Outcome | **refused mid-scan** after ~2 min, at the worker-delegation/validation boundary |
| Message | `This content was flagged for possible cybersecurity risk. … To get authorized for security work, join the Trusted Access for Cyber program: https://chatgpt.com/cyber` |

The refusal is **content-triggered, not account-gated** — the same credential completed a full scan
of `doc_classifier/reviewapp/api/auth.py` minutes later. A hook whose body is a denylist of
`rm -rf /`, fork bombs, and process-kill patterns reads to a cyber classifier like the thing it
exists to prevent. Consequence: **Path B cannot scan this repo's core security surface**, so Path A
(Claude-native) is the only path here. Full context:
[`../../codex-security-three-repos-2026-07-29.md`](../../codex-security-three-repos-2026-07-29.md) §3.

## What survived, and why it is kept

`threat_model.md` is complete and good — it correctly frames the hooks as runtime controls over
lower-trust `tool_input` and calibrates severity to the local-user boundary. Reusable as a starting
threat model for a Path A scan of this repo.

`candidate_ledger.jsonl` holds **10 candidates**, each with its own `evidence` string. One
(`rm-equivalent-option-spellings`) independently reproduces the already-filed finding
`c3568d7982af`, which is what makes the other nine worth running down:

| Candidate | CWE | Status |
|---|---|---|
| `rm-equivalent-option-spellings` | CWE-184 | already filed → `c3568d7982af` |
| `database-ddl-obfuscation` | CWE-184 | unvalidated |
| `drizzle-push-obfuscation` | CWE-184 | unvalidated |
| `git-force-add` | CWE-184 | unvalidated |
| `git-precommit-bypass` | CWE-184 | unvalidated |
| `git-signing-bypass` | CWE-184 | unvalidated |
| `unscoped-gate-process-kill` | CWE-184 | unvalidated |
| `rm-safe-prefix-path-traversal` | CWE-22 | unvalidated |
| `bash-audit-log-injection` | CWE-117 | unvalidated |
| `literal-command-secret-logging` | CWE-532 | unvalidated |

**Six of the nine are one family: shell token concatenation defeats every raw-text matcher.**
`drizzle-kit pu''sh` and `sqlite3 app.db 'DR''OP TABLE users'` execute as `push` and `DROP TABLE`
but match no regex over the raw command string. Our denylist does not model this. Validating the
family on Path A is free and needs no classifier approval — that is the recommended next step.
