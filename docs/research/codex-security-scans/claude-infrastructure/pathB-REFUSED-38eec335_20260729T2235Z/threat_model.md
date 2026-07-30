# Threat Model

## Overview

This repository is local infrastructure for operating Claude Code sessions, worktrees, landing gates, and deployment into `~/.claude`. Its shell hooks are runtime controls rather than ordinary developer utilities: `PreToolUse` hooks inspect model-proposed tool calls and may return absolute `deny` decisions before a command executes. The primary installation uses repository-backed hooks, while deployment and verification workflows distribute the configuration across multiple local sessions and accounts.

The reviewed `hooks/validate-bash.sh` surface protects the local operating-system account, repositories, databases, Git history, and concurrent landing gates from destructive or policy-bypassing Bash commands. It also writes a forensic command log.

## Threat Model, Trust Boundaries, and Assumptions

- The `.tool_input.command` string is lower-trust data. It can be influenced by user prompts, repository content, indirect prompt injection, or model error, and it contains shell syntax rather than a pre-parsed argument vector.
- Claude Code's hook dispatcher, settings files, hook installation, local environment, and operator-controlled kill switches are trusted. A hostile local user who can rewrite the hook or its environment is outside the primary boundary.
- Hook stdout crosses a security-decision boundary: a valid `deny` prevents execution, while silence leaves the request to remaining hooks and permission policy.
- The hook runs with the desktop user's privileges. A bypass can affect same-user files, repositories, local databases, logs, and peer sessions, but it does not by itself grant root privileges.
- The repository's live deployment model makes hook correctness important across sessions. An accepted source change may become active runtime behavior after the repository's verifier and deploy controls.
- Audit logs are integrity and confidentiality assets because they support attribution and incident reconstruction; they must not be assumed trustworthy if attacker-influenced fields are not framed or redacted.

Security objectives are to deny catastrophic deletion, preserve Git and migration safety policies, prevent one worktree from terminating peer gate processes, emit parseable decisions, avoid exposing secrets, and preserve attributable audit records.

## Attack Surface, Mitigations, and Attacker Stories

The principal attack surface is shell-language ambiguity: wrappers, global options, quoting, concatenation, variables, substitutions, comments, multiline commands, aliases, and equivalent option spellings can make executed semantics differ from raw text. `validate-bash.sh` mitigates selected cases with an argv-aware helper, database-context checks, per-occurrence destructive-command checks, JSON escaping, and a focused regression suite. Adjacent static permissions and other hooks provide defense in depth, but a neighboring control is not assumed to cover an exact missed syntax without repository evidence.

Realistic attacker stories include repository content steering an autonomous model toward a semantically destructive spelling that the raw matcher misses; a session issuing a broad process kill that terminates other worktrees' gates; shell or SQL concatenation bypassing Git or schema policy; literal credentials entering an audit log; and multiline commands forging log records.

Malformed hook payloads and an unavailable `jq` intentionally fail open with an audit signal. That availability choice is not itself a vulnerability absent evidence that lower-trust command input controls the hook host or payload framing. Operator-controlled `VALIDATE_BASH_DISABLED` and `VALIDATE_BASH_LEGACY` are likewise configuration assumptions, not attacker capabilities.

## Severity Calibration

- **Critical:** a reliable unauthenticated path beyond the local-user boundary, root-level compromise, or a broadly deployed control bypass causing irreversible cross-system compromise.
- **High:** a directly reproducible bypass that permits same-user destructive deletion, sensitive database destruction, or reliable cross-session safety-gate termination without another demonstrated absolute control.
- **Medium:** a reachable local policy bypass with meaningful integrity or availability consequences, or secret exposure to other local principals, where exploitation requires a crafted shell form or deployment assumptions.
- **Low:** bounded audit-integrity defects, repository-policy bypasses without a demonstrated downstream security consequence, or local issues whose impact is substantially constrained by operator review or downstream enforcement.

Repository: target_sha256_1b084a9031e4c848c85ab69af9609b2a5c86ed417b969367fb20678f7cbdaad2
Version: ebf916f42524833e913931e7376afd10e99b3a00
