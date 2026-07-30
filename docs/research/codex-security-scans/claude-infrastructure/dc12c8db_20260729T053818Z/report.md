# Security Review: claude-infrastructure

## Scope

The scan reviewed the canonical include paths and exclusions listed below.

- Scan mode: scoped_path
- Target kind: git_revision
- Target ID: claude-infrastructure
- Revision: dc12c8db
- Inventory strategy: scoped_path
- Included paths: hooks/
- Excluded paths: hooks/tests/
- Runtime or test status: not recorded

Limitations and exclusions:
- Excluded hooks/tests/\*\*: Test fixtures, not executed by the harness as a hook.

### Scan Summary

| Field | Value |
| --- | --- |
| Reportable findings | 2 |
| Severity mix | medium: 1, low: 1 |
| Confidence mix | high: 2 |
| Coverage | complete |
| Validation mode | not recorded |

Canonical artifacts: `scan-manifest.json`, `findings.json`, and `coverage.json`. This report is a deterministic projection of those files.

## Threat Model

Claude Code hooks are shell scripts the harness executes automatically on every tool call, receiving a JSON payload on stdin whose tool_input fields (command, file_path, prompt) are influenced by model output and therefore by any untrusted content the model has read: repository files, web pages, subagent output. Several hooks are not merely observers but security CONTROLS: they emit a permissionDecision of deny, ask or allow for Bash commands. The primary attacker is prompt injection steering the model into emitting a command that a guard fails to classify correctly; the secondary attacker is a local process running as another uid on a shared macOS host. Assets at risk: the developer's filesystem and home directory, the git history, and the integrity of the auto-approval decision itself.

## Findings

| Finding | Severity | Confidence | Detailed write-up |
| --- | --- | --- | --- |
| [Catastrophic-command denylist is bypassed by equivalent flag spellings, downgrading deny to ask or to no decision](#finding-1) | medium | high | inline below |
| [Notification hook appends to fixed, predictable paths in world-writable /tmp](#finding-2) | low | high | inline below |

### Confidence Scale

| Label | Meaning |
| --- | --- |
| high | Direct evidence supports the finding with no material unresolved blocker. |
| medium | Evidence supports a plausible issue, but material runtime or reachability proof remains. |
| low | Evidence is incomplete and the item is retained only for explicit follow-up. |

<a id="finding-1"></a>

### [1] Catastrophic-command denylist is bypassed by equivalent flag spellings, downgrading deny to ask or to no decision

| Field | Value |
| --- | --- |
| Severity | medium |
| Confidence | high |
| Confidence rationale | Bypass reproduced by feeding crafted payloads directly to the hook and reading the emitted permissionDecision; the deny/ask/none split is observed, not inferred. |
| Category | Protection mechanism failure / incomplete denylist |
| CWE | CWE-184, CWE-693 |
| Affected lines | hooks/validate-bash.sh:94-96, hooks/validate-bash.sh:195 |

#### Summary

The hard-deny regex that is supposed to stop catastrophic filesystem destruction matches only the literal short-flag bundle `-rf` followed by a character. Equivalent invocations with identical destructive effect — `--recursive --force`, `-fr`, `-r -f`, and the bare `rm -rf /` form at end of input — are not matched, so the guard emits `ask`, or no decision at all, instead of `deny`.

#### Root Cause

The alternation `rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]` encodes one specific flag spelling and requires a character to follow the slash. `[^a-zA-Z]` consumes a character rather than permitting end-of-input, so the bare form cannot match. The adjacent `~` branch in the very same regex is written `~(/|$|[[:space:]])` and does anchor on `$` — that internal inconsistency shows the missing `$` in the `/` branch is an oversight, not a deliberate choice. The secondary ask-level clause at line 195 extracts targets with `rm[[:space:]]+-(r|rf|fr)[[:space:]]+`, which likewise cannot see long-form flags, so both layers miss the same spellings.

#### Validation

Bypass reproduced by feeding crafted payloads directly to the hook and reading the emitted permissionDecision; the deny/ask/none split is observed, not inferred. Validation details were not recorded separately.

Validation method: Direct execution of the hook with crafted PreToolUse payloads, reading the emitted permissionDecision.

#### Dataflow

The canonical finding records the affected path at hooks/validate-bash.sh:94-96, hooks/validate-bash.sh:195, but no expanded source-to-sink narrative was recorded.

#### Reachability

Reachability was not recorded beyond the canonical finding summary and affected locations.

#### Severity

**Medium** — Reproduced directly against the hook: `rm -rf /*` returns deny, while `rm --recursive --force /*` returns no decision at all and the bare `rm -rf /` form returns only ask. Impact if reached is destruction of the user's filesystem. It is not critical because this hook is defence-in-depth by its own header comment, and rm-safe-allowlist.sh correctly defers rather than auto-allowing these forms, so the command still falls through to the base Bash(rm:\*) ask rule — an attended operator would still be prompted.

Rises to high or critical if the ambient permission posture stops prompting for Bash(rm:\*) — an unattended or auto-approving session, a broadened allow-list, or any future hook that auto-allows long-form flags. This repository explicitly runs 24/7 autonomous sessions, so that posture is a live configuration, not a hypothetical.

#### Remediation

Normalise the command to argv before classifying instead of pattern-matching raw text: reuse the existing lib/is-true-flag.sh shlex-aware helper to detect recursive+force semantics regardless of spelling (-r, -R, --recursive, -f, --force, bundled or split), then test the resolved target. As a minimum immediate fix, anchor the slash branch as `/([^a-zA-Z]|$)` and cover the -fr, -r -f and long-form spellings.

Tests:
- Add a table-driven case to hooks/tests/validate-bash.test.sh asserting permissionDecision == deny for each spelling: `rm -rf /`, `rm -rf /*`, `rm -fr /*`, `rm -r -f /*`, `rm --recursive --force /*`, `rm --recursive --force ~`.
- Add a negative control asserting that a command merely mentioning the pattern in a quoted commit message body is NOT denied, so the fix does not regress the existing message-body handling.

Preventive controls:
- Classify shell commands on a parsed argv representation, never on raw text.
- Every denylist clause needs a table-driven test enumerating equivalent spellings of the same dangerous operation.

<a id="finding-2"></a>

### [2] Notification hook appends to fixed, predictable paths in world-writable /tmp

| Field | Value |
| --- | --- |
| Severity | low |
| Confidence | high |
| Confidence rationale | Paths and the append are read directly from source; /tmp permissions verified on the live host. |
| Category | Insecure temporary file / link following |
| CWE | CWE-377, CWE-59 |
| Affected lines | hooks/notify.sh:35, hooks/notify.sh:88, hooks/notify.sh:39 |

#### Summary

The notification hook writes its log and debounce lock to hardcoded `/tmp` paths. `/tmp` is world-writable on macOS, so a process running as another uid can pre-create either path as a symlink and have the hook's append or touch follow it, writing to a file of the attacker's choosing with the invoking user's privileges.

#### Root Cause

LOG_FILE and DEBOUNCE_FILE are fixed literals under the shared /tmp root rather than a per-user directory or an O_NOFOLLOW/mktemp-created file, so the hook cannot distinguish its own file from an attacker-planted symlink of the same name.

#### Validation

Paths and the append are read directly from source; /tmp permissions verified on the live host. Validation details were not recorded separately.

Validation method: Source review plus live verification of /tmp permissions.

#### Dataflow

The canonical finding records the affected path at hooks/notify.sh:35, hooks/notify.sh:88, hooks/notify.sh:39, but no expanded source-to-sink narrative was recorded.

#### Reachability

Reachability was not recorded beyond the canonical finding summary and affected locations.

#### Severity

**Low** — Confirmed world-writable sticky /tmp (drwxrwxrwt) and a real append at line 88. Impact is limited to appending attacker-influenceable log text or updating an mtime, not arbitrary content control, and it requires a hostile local process under a different uid — uncommon on a single-user developer workstation.

Rises if the host is shared or multi-user, if the log path is later consumed by anything that parses or executes it, or if a future writer truncates rather than appends.

#### Remediation

Place both files under a user-owned directory such as $TMPDIR (per-user on macOS) or ~/.claude/logs, create the directory with mode 700, and do not follow symlinks when opening.

Tests:
- Pre-create the target path as a symlink to a canary file, run the hook, and assert the canary is unchanged.

Preventive controls:
- Never use a fixed name directly under /tmp for a file the process will write; prefer $TMPDIR or an application-owned directory.

## Reviewed Surfaces

| Surface | Risk Area | Outcome | Notes |
| --- | --- | --- | --- |
| Bash command permission guards (validate-bash, smart-bash-allowlist, rm-safe-allowlist, ship-rail-push-allow, reset-hard-shadow-allow) | Protection mechanism failure | Reported | The security-decision surface. validate-bash.sh reported. rm-safe-allowlist.sh reviewed and found sound: it is allow-only against an explicit regenerable-path whitelist, rejects globs, ~, .., the bare root and outside-repo absolutes, refuses compound commands, and defers silently rather than allowing when a target is not provably safe. |
| Command injection via untrusted tool_input | Command injection | No issue found | No eval with interpolation and no sh -c / bash -c with interpolated untrusted data anywhere in scope; the repository enforces an explicit no-eval convention. The three yq eval occurrences in teammate-auto-shutdown.sh are the yq subcommand, not shell eval. |
| Integrity of emitted permission decisions | Improper output encoding | No issue found | validate-bash.sh json_escape() escapes backslash before quote and strips control characters, so a command echoed back into a deny reason cannot break out of the JSON string and silently void the decision. Peer hooks build decision JSON with jq -nc --arg, which is safe by construction. |
| Temporary file and lock handling | Insecure temporary file | Reported | notify.sh reported. Other hooks use mktemp or paths under $HOME/.claude. |
| Filesystem paths derived from tool_input.file_path | Path traversal | No issue found | backup-before-write.sh consumes .tool_input.file_path but gates on a regular-file test, quotes every expansion, and derives backup names via basename into a fixed $HOME/.claude/backups root; no attacker-controlled component reaches the destination directory. |
| Destructive filesystem operations inside hooks | Unintended file deletion | No issue found | Every deletion, move and copy occurrence in scope quotes its operands and targets paths under $HOME/.claude or a mktemp directory; no unquoted expansion reaches a destructive command. |
| Network egress from hooks | Data exfiltration | Not applicable | No curl, wget, nc, ssh or scp invocation exists anywhere in scope; hooks are local-only. |

## Open Questions And Follow Up

- Whether the ambient permission posture prompts for Bash(rm:\*) during unattended autonomous sessions determines whether the validate-bash finding is medium or critical; this scan covered hooks/ only and did not audit the settings.json permission arrays.
- bin/ and scripts/ (about 39k lines) are out of scope for this scan and contain further command-construction surface.
