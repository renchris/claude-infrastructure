# Security Review: claude-infrastructure

## Scope

The scan reviewed the canonical include paths and exclusions listed below.

- Scan mode: scoped_path
- Target kind: git_revision
- Target ID: claude-infrastructure
- Revision: 38eec335
- Inventory strategy: scoped_path
- Included paths: bin/, scripts/
- Excluded paths: hooks/
- Runtime or test status: not recorded
- Scan context: Scoped-path scan of the 152 tracked files under bin/ (47) and scripts/ (105) at revision 38eec335 — 40,961 lines, overwhelmingly bash with four Python tools. hooks/ was scanned separately at dc12c8db on 2026-07-29 and is excluded here. Artifacts reviewed: the deterministic in-scope file list at artifacts/02_discovery/in_scope_files.txt, the enriched candidate ledger at artifacts/02_discovery/candidate_ledger.jsonl, and two executable probes retained under artifacts/02_discovery/validation_artifacts/. Runtime status: two candidates were decided by running code rather than by reading it — probe_eval_jsondumps.sh reproduced the reported injection, and probe_osascript_notify.sh refuted the AppleScript-breakout candidate — and the live activation state of the affected daemon was read off the host (launchctl list, the deployed LaunchAgent plist, and the /tmp permission surfaces). Validation mode: compact standard-scan, one validation record per ledger row and one attack-path record per reportable or deferred row. Limitations: coverage is pattern-complete but not line-complete — every file was swept for every risk class in the threat model and every file with a hit was read around that hit, with roughly 20 read in full, but the remaining lines were not read individually; one candidate (lr-handoff.sh's unquoted heredoc launcher) is deferred with an unresolved reachability question rather than reported. The threat model was generated during Phase 1 of this scan, not supplied by the user.

Limitations and exclusions:
- Excluded hooks/\*\*: Scanned separately at dc12c8db on 2026-07-29; excluded here to avoid duplicating that bundle's findings.
- Excluded scripts/plan-phase-scan-tests/fixtures/\*\*: Static markdown and JSON fixtures with no runnable behaviour; the harness that consumes them (scripts/plan-phase-scan-tests/run.sh) was reviewed.

### Scan Summary

| Field | Value |
| --- | --- |
| Reportable DSS findings | 2 |
| Report instances | 2 |
| Report severity mix | medium: 1, low: 1 |
| Report confidence mix | high: 2 |
| Coverage | partial |
| Validation mode | not recorded |

Canonical artifacts: `scan-manifest.json`, `findings.json`, and `coverage.json`. This report is a deterministic projection of those files.

## Threat Model

claude-infrastructure is not an application but the control plane for a fleet of autonomous Claude Code sessions running 24/7 on one macOS workstation; it is also the source checkout that ~/.claude symlinks into. Everything in bin/ and scripts/ runs as the interactive user with no sandbox, so the assets at risk are the developer's filesystem and git history, four Claude Max OAuth refresh tokens held in the keychain, the integrity of automated decisions (which Bash commands are allowed, which sessions may be closed, which branches may be pushed to a remote trunk), and the session transcripts that are the durable record of all work. The primary trust boundary is model output reaching shell: these tools are invoked by the model through the Bash tool, so argv, stdin and environment all carry strings that untrusted content the model has read — repository files, web pages, subagent output, other sessions' mail — can steer. The model is not malicious but it is a confused deputy, and this fleet deliberately runs it unattended. A second boundary matters because much of scripts/ is the body of a launchd job: code that executes inside a daemon is not classified by the hooks/ PreToolUse layer, raises no permission prompt, and has no operator watching, so laundering a string into a daemon defeats the repository's own primary control even without any gain in uid. A third, thinner boundary is a foreign local uid, whose only shared writable surface is world-writable /tmp. The invariants that follow: no untrusted string is ever evaluated as code — the repository states this as a no-eval convention; every expansion reaching a destructive operation is quoted and validated; security decisions fail closed rather than emitting nothing; state a decision depends on lives where only this uid can write; credentials never reach argv, a log, or a notification body; and a predictable path in a shared directory is never written to, executed from, or trusted as a lock. The repository-wide failure modes that would matter most are command injection through a model-influenced string reaching eval, sh -c, a python -c program body or an osascript program body; guard bypass by input a classifier does not model; unquoted expansion into rm or git; /tmp symlink and pre-creation attacks against predictable names; credential exposure; subversion of the landing rail; and an unbounded external call wedging a daemon so that a fail-closed control never runs at all.

## Findings

| Findings | Reports | Severity | Confidence | Detailed write-up |
| --- | --- | --- | --- | --- |
| Parked-record fields are shell-quoted with json.dumps() and then eval'd inside a loaded launchd daemon | [occ_ea005f0dd3e7dbd00081c413](#finding-1) | medium | high | occ_ea005f0dd3e7dbd00081c413: inline below |
| Launcher scripts are written to predictable paths in world-writable /tmp, made executable, and then run | [occ_04ee6d85495389d4a3059773](#finding-2) | low | high | occ_04ee6d85495389d4a3059773: inline below |

### Confidence Scale

| Label | Meaning |
| --- | --- |
| high | Direct evidence supports the finding with no material unresolved blocker. |
| medium | Evidence supports a plausible issue, but material runtime or reachability proof remains. |
| low | Evidence is incomplete and the item is retained only for explicit follow-up. |

<a id="finding-1"></a>

### [1] Parked-record fields are shell-quoted with json.dumps() and then eval'd inside a loaded launchd daemon

| Field | Value |
| --- | --- |
| Severity | medium |
| Confidence | high |
| Confidence rationale | The injection was reproduced by executing the shipped emitter/consumer pair verbatim against a crafted record, and the daemon's live load state and deployed autofire setting were read off the host rather than assumed; the only unproven element is how often a directory name carrying shell metacharacters arises, which is captured in severity rather than confidence. |
| Category | Command injection via improper neutralization |
| CWE | CWE-78, CWE-116 |
| Affected lines | scripts/limit-recover/lr-reset-poller.sh:391-397, scripts/limit-recover/lr-reset-poller.sh:328-329, scripts/limit-recover/lr-reset-poller.sh:145-155, scripts/limit-recover/lr-reset-poller.sh:304, scripts/limit-recover/lr-reset-poller.sh:431-432 |

#### Summary

`lr-reset-poller.sh` reconstructs shell variables from each parked-session record by having Python print `key=<json.dumps(value)>` and passing the result to `eval`. JSON string escaping neutralises only backslash and double quote; `$`, backtick and `!` survive it untouched, and the emitted assignment is evaluated inside a shell double-quoted context where all three are active. A parked record whose `cwd` field contains `$(...)` or backticks therefore executes as a command. The value reaches the record from a session transcript's `cwd` field, written by an unescaped `printf '"cwd":"%s"'` at line 328, and the same unquoted `$cwd` is interpolated a second time with `%s` (not `%q`) into a generated executable launcher at line 431. What makes this materially different from the model simply running a command itself is where the execution lands: `com.reso.lr-reset-poller` is a loaded LaunchAgent, so nothing on this path passes through the PreToolUse command classifier, no permission prompt is raised, and no operator is watching.

#### Root Cause

The violated invariant is that no untrusted string is evaluated as code — an invariant this repository states as a no-`eval` convention. It breaks because JSON escaping is mistaken for shell escaping. `json.dumps` guarantees a valid JSON string literal: it escapes backslash, double quote and control characters, and it is explicitly not required to escape `$`, backtick or `!`, none of which mean anything in JSON. The consumer, however, is not a JSON parser — it is `eval` operating on a shell double-quoted context, where all three are active. The value arrives from a session transcript's `cwd` field (line 145), passes an existence-only gate (line 304), is written unescaped into the parked record (line 328), and is re-read a tick later and eval'd (line 391), then interpolated with `%s` into a generated executable (line 431). Two independent sinks, one broken control.

**cwd read out of a session transcript** — `scripts/limit-recover/lr-reset-poller.sh:145-155`

The value that will eventually be eval'd enters here as the `cwd` field of a session transcript record — the directory the session was launched in. It is returned verbatim, with no character-class validation, and is carried onward as `$cwd`.

```bash
# cwd_of <transcript> — the first cwd field (avoids lossy slug-decoding). Empty if none.
cwd_of() {
  python3 -c "
import json,sys
for ln in open(sys.argv[1],encoding='utf-8'):
    try: o=json.loads(ln)
    except: continue
    c=o.get('cwd')
    if c: print(c); break
" "$1" 2>/dev/null
}
```

**The only check applied to $cwd** — `scripts/limit-recover/lr-reset-poller.sh:304`

This is the sole gate on `$cwd` before it is recorded. It asserts the directory exists; it says nothing about the characters in its name, so `$(...)` and backticks pass so long as a directory with that literal name is present. This is the control that would have to change to close the class.

```bash
    [[ -n "$cwd" && -d "$cwd" ]] || continue
```

**Parked record built with unescaped printf** — `scripts/limit-recover/lr-reset-poller.sh:328-329`

`$cwd` is written into a JSON string with `%s` and no escaping, so the recorded value is byte-identical to the directory name. This carries the payload across the process and time boundary from the detecting tick to the resuming tick, and it is also why a `cwd` containing a double quote produces malformed JSON rather than a rejected record.

```bash
      printf '{"sid":"%s","acct":"%s","cfg":"%s","cwd":"%s","kind":"%s","reset_at_utc":"%s","parked_at":"%s"}\n' \
        "$sid" "$acct" "$cfg" "$cwd" "$kind" "$reset" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PARKED/$sid.json"
```

**json.dumps() output passed to eval** — `scripts/limit-recover/lr-reset-poller.sh:391-397`

`json.dumps` is being used as a shell quoter. It emits `cwd="$(touch FILE)"`; the outer `eval` then evaluates that assignment, and the shell performs command substitution before the assignment completes — so the command runs and `$cwd` ends up empty. Because the script is `set -uo pipefail` without `-e` (line 30), a record whose JSON is malformed makes this eval a silent no-op and leaves the previous iteration's `sid`/`cwd` bound, so the loop then operates on the wrong session.

```bash
  eval "$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
for k in ('sid','acct','cfg','cwd','reset_at_utc'):
    print('%s=%s'%(k,json.dumps(str(d.get(k,'')))))
" "$pf")"
```

**The same $cwd interpolated into a generated executable** — `scripts/limit-recover/lr-reset-poller.sh:431-432`

The same unvalidated `$cwd` is placed inside a double-quoted shell string in a file that is then made executable and run. Note the asymmetry that shows the author knew the hazard: the trailing `--prompt` argument uses `%q`, which shell-quotes correctly, while `$cwd` two positions earlier uses `%s`. This is a second, independent execution of the same value.

```bash
    { echo '#!/bin/bash'; printf 'exec "%s/lr-fire-resume.sh" "%s" "%s" "%s" --prompt %q\n' \
        "$LR" "$acct" "$cwd" "$sid" "/limit-recover"; } > "$launcher"; chmod +x "$launcher"
```

#### Validation

The injection was reproduced by executing the shipped emitter/consumer pair verbatim against a crafted record, and the daemon's live load state and deployed autofire setting were read off the host rather than assumed; the only unproven element is how often a directory name carrying shell metacharacters arises, which is captured in severity rather than confidence. Validation details were not recorded separately.

Validation method: Direct execution of the shipped emitter and consumer against a crafted parked record, plus live inspection of the daemon's load state and its deployed plist.

**json.dumps() output passed to eval** — `scripts/limit-recover/lr-reset-poller.sh:391-397`

`json.dumps` is being used as a shell quoter. It emits `cwd="$(touch FILE)"`; the outer `eval` then evaluates that assignment, and the shell performs command substitution before the assignment completes — so the command runs and `$cwd` ends up empty. Because the script is `set -uo pipefail` without `-e` (line 30), a record whose JSON is malformed makes this eval a silent no-op and leaves the previous iteration's `sid`/`cwd` bound, so the loop then operates on the wrong session.

```bash
  eval "$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
for k in ('sid','acct','cfg','cwd','reset_at_utc'):
    print('%s=%s'%(k,json.dumps(str(d.get(k,'')))))
" "$pf")"
```

**Parked record built with unescaped printf** — `scripts/limit-recover/lr-reset-poller.sh:328-329`

`$cwd` is written into a JSON string with `%s` and no escaping, so the recorded value is byte-identical to the directory name. This carries the payload across the process and time boundary from the detecting tick to the resuming tick, and it is also why a `cwd` containing a double quote produces malformed JSON rather than a rejected record.

```bash
      printf '{"sid":"%s","acct":"%s","cfg":"%s","cwd":"%s","kind":"%s","reset_at_utc":"%s","parked_at":"%s"}\n' \
        "$sid" "$acct" "$cfg" "$cwd" "$kind" "$reset" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PARKED/$sid.json"
```

**The only check applied to $cwd** — `scripts/limit-recover/lr-reset-poller.sh:304`

This is the sole gate on `$cwd` before it is recorded. It asserts the directory exists; it says nothing about the characters in its name, so `$(...)` and backticks pass so long as a directory with that literal name is present. This is the control that would have to change to close the class.

```bash
    [[ -n "$cwd" && -d "$cwd" ]] || continue
```

#### Dataflow

The canonical finding records the affected path at scripts/limit-recover/lr-reset-poller.sh:391-397, scripts/limit-recover/lr-reset-poller.sh:328-329, scripts/limit-recover/lr-reset-poller.sh:145-155, scripts/limit-recover/lr-reset-poller.sh:304, scripts/limit-recover/lr-reset-poller.sh:431-432, but no expanded source-to-sink narrative was recorded.

**The only check applied to $cwd** — `scripts/limit-recover/lr-reset-poller.sh:304`

This is the sole gate on `$cwd` before it is recorded. It asserts the directory exists; it says nothing about the characters in its name, so `$(...)` and backticks pass so long as a directory with that literal name is present. This is the control that would have to change to close the class.

```bash
    [[ -n "$cwd" && -d "$cwd" ]] || continue
```

**json.dumps() output passed to eval** — `scripts/limit-recover/lr-reset-poller.sh:391-397`

`json.dumps` is being used as a shell quoter. It emits `cwd="$(touch FILE)"`; the outer `eval` then evaluates that assignment, and the shell performs command substitution before the assignment completes — so the command runs and `$cwd` ends up empty. Because the script is `set -uo pipefail` without `-e` (line 30), a record whose JSON is malformed makes this eval a silent no-op and leaves the previous iteration's `sid`/`cwd` bound, so the loop then operates on the wrong session.

```bash
  eval "$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
for k in ('sid','acct','cfg','cwd','reset_at_utc'):
    print('%s=%s'%(k,json.dumps(str(d.get(k,'')))))
" "$pf")"
```

#### Reachability

Reachability was not recorded beyond the canonical finding summary and affected locations.

#### Severity

**Medium** — Execution at the sink is proven rather than inferred — running the shipped emitter over a record whose `cwd` was `$(touch FILE)` and eval'ing its output created the file — and the daemon carrying that sink is loaded and firing every 600 seconds with `LR_POLLER_AUTOFIRE=1` in its deployed plist. The consequence is arbitrary command execution as the interactive user inside an unattended launchd job, which defeats the hook-based command classifier that is this repository's primary control over model-influenced strings, and it happens with no operator present to see an `ask` prompt. It is held at medium rather than high because the payload has to arrive as the name of a directory that actually exists (line 304 requires `[[ -d "$cwd" ]]`) belonging to a session that then hits a usage limit, and because `$PARKED` sits under `$HOME/.reso` where only this uid can write — so the party who can seed the payload already holds the same uid, making this a control bypass rather than a privilege-boundary crossing. Evidence that a routine code path can name a directory from model-supplied text, or a second writer into the parked record, would raise it to high; validating `cwd` against a shell-safe character class before recording it would drop it to informational.

Rises to high if any routine path names a directory from model-supplied text, if `$PARKED` becomes writable by another uid, or if a second producer writes parked records from a less trusted source. Falls to informational once the parked fields are read without a shell round-trip.

#### Remediation

Stop round-tripping the parked record through the shell. Read the fields with `jq -r` into separate variables (`sid=$(jq -r '.sid' "$pf")`), or have the Python emitter print NUL- or tab-separated values consumed by `read -r`, so no value is ever evaluated. If a generated assignment is genuinely wanted, use `shlex.quote` rather than `json.dumps` — it is the quoter that matches the consuming interpreter. Independently, fix the second sink at line 431 by using `%q` for `$cwd` exactly as the adjacent `--prompt` argument already does, and write the parked record with `jq -n --arg` so a value containing a double quote produces valid JSON instead of a record that silently fails to parse and leaves stale variables bound.

Tests:
- Add a case to tests/lr-reset-poller.bats that writes a parked record whose cwd is `$(touch "$BATS_TEST_TMPDIR/pwned")`, runs one poller tick, and asserts the marker file does NOT exist.
- Add a case whose parked cwd contains a literal double quote and assert the tick logs a rejected/malformed record rather than proceeding with the previous iteration's sid — this pins the stale-variable behaviour that `set -u` without `-e` currently allows.
- Add a negative control with an ordinary cwd asserting the resume path still fires normally, so the fix cannot regress into rejecting valid records.
- Extend the repository's no-eval lint to fail on `eval "$(` anywhere under bin/ and scripts/, so this construction cannot reappear.

Preventive controls:
- Treat every serialisation format's escaping as valid only for its own parser; when a value crosses into a shell, quote it with a shell quoter (shlex.quote / printf %q) at the boundary.
- Prefer field-at-a-time reads (jq -r, read -r) over reconstructing variable assignments, so no on-disk state is ever a program.
- Any state file written by one process and consumed by another is untrusted input at the consumer, even when both run as the same uid — the daemon's lack of a hook layer is exactly why.

<a id="finding-2"></a>

### [2] Launcher scripts are written to predictable paths in world-writable /tmp, made executable, and then run

| Field | Value |
| --- | --- |
| Severity | low |
| Confidence | high |
| Confidence rationale | The write-then-execute construction is unambiguous in source at all three sites, and the predictability premise was checked against the live filesystem — session ids really are world-readable in /tmp — rather than assumed; only end-to-end exploitation was not attempted, since racing a launcher would disturb a running fleet. |
| Category | Insecure temporary file / link following |
| CWE | CWE-377, CWE-59 |
| Affected lines | scripts/limit-recover/lr-reset-poller.sh:430-433, scripts/limit-recover/lr-handoff.sh:159-168, scripts/handoff-fire.sh:2400-2402, bin/cc-context:28 |

#### Summary

Three scripts build a shell script at a predictable path under `/tmp`, `chmod +x` it, and then execute it by path: `lr-reset-poller.sh:431` (`/tmp/lr-poller-launch-<sid8>.sh`), `lr-handoff.sh:159` (`/tmp/lr-launch-<sid8>.sh`) and `handoff-fire.sh:2400` (`/tmp/handoff-recycle-cmd-<sid>-<epoch>.sh`). On macOS `/tmp` is mode 1777: the sticky bit stops another uid deleting or replacing a file this user already owns, but it does not stop that uid pre-creating a name that does not yet exist. A pre-created symlink turns the `>` redirect into an arbitrary-file clobber plus a `chmod +x` on the target; a pre-created mode-0666 regular file leaves attacker-writable bytes at a path this user subsequently executes. The names are predictable in practice because session ids are world-readable: `bin/cc-context` exports per-session telemetry to `/tmp/cc-telemetry`, observed on this host as a 0755 directory holding 78 files at mode 0644, each named `<session-uuid>.json`. The same repository already uses `mktemp "${TMPDIR:-/tmp}/..."` at roughly forty other sites, so the safe idiom is established in-tree and these three are the outliers.

#### Root Cause

The violated invariant is that a file which will be written and then executed must live in a directory only the trusting uid can write, under a name no one else can predict. All three sites break it in the same way: they compose a name from a fixed prefix plus a session identifier — an identifier the repository itself publishes world-readably into `/tmp/cc-telemetry` — and place it in mode-1777 `/tmp` instead of the per-uid `$TMPDIR`. Because the file is later opened by path (`/bin/bash $launcher`) rather than by the descriptor that wrote it, the content executed is whatever that name resolves to at execution time. `mktemp` would close it on both axes at once: unpredictable suffix, and `O_EXCL` creation that fails rather than following a pre-existing symlink.

**Session ids published world-readably in /tmp** — `bin/cc-context:28`

This is what makes the launcher names predictable rather than guessable. The statusline exports one `<session-uuid>.json` per session per turn boundary into this directory; on this host it was observed as `drwxr-xr-x` containing 78 files at `-rw-r--r--`, so any local uid can enumerate every live session id and derive every `<sid8>` launcher name in advance.

```bash
TDIR="${CC_TELEMETRY_DIR:-/tmp/cc-telemetry}"   # override for E2E isolation
```

**lr-reset-poller launcher: write, chmod +x, execute** — `scripts/limit-recover/lr-reset-poller.sh:430-433`

The default directory is `/tmp` and the name carries only eight hex characters of session id. The file is created by `>` (which follows a symlink), made executable, and then handed to `spawn_gui`/`spawn_tmux`, both of which run it as `/bin/bash $launcher` — an open-by-path at execution time, so the bytes executed are whatever the path resolves to then, not what was written.

```bash
    launcher="${LR_POLLER_LAUNCH_DIR:-/tmp}/lr-poller-launch-${sid:0:8}.sh"
    { echo '#!/bin/bash'; printf 'exec "%s/lr-fire-resume.sh" "%s" "%s" "%s" --prompt %q\n' \
        "$LR" "$acct" "$cwd" "$sid" "/limit-recover"; } > "$launcher"; chmod +x "$launcher"
```

**lr-handoff launcher: identical construction** — `scripts/limit-recover/lr-handoff.sh:159-168`

The same eight-character truncation and the same `/tmp` placement, here with the path hardcoded rather than seam-overridable. The launcher is subsequently typed into a new iTerm2 pane as `exec /bin/bash $LAUNCHER`.

```bash
LAUNCHER="/tmp/lr-launch-${SID:0:8}.sh"
cat > "$LAUNCHER" <<EOF
#!/bin/bash
...
EOF
chmod +x "$LAUNCHER"
```

**handoff-fire recycle command file** — `scripts/handoff-fire.sh:2400-2402`

This variant uses the full session id plus `date +%s`, so pre-creation needs the id (readable from /tmp/cc-telemetry) and a guess within a small window of seconds rather than a blind guess. The file is passed to a detached watcher that executes it once the old session exits.

```bash
  cmdfile="/tmp/handoff-recycle-cmd-$SID-$ts.sh"
  log="/tmp/handoff-recycle-$SID-$ts.log"
  printf '%s\n' "$CMD" > "$cmdfile"
```

#### Validation

The write-then-execute construction is unambiguous in source at all three sites, and the predictability premise was checked against the live filesystem — session ids really are world-readable in /tmp — rather than assumed; only end-to-end exploitation was not attempted, since racing a launcher would disturb a running fleet. Validation details were not recorded separately.

Validation method: Source review of all three write-then-execute sites, plus live inspection of the /tmp surfaces that make their names predictable.

**Session ids published world-readably in /tmp** — `bin/cc-context:28`

This is what makes the launcher names predictable rather than guessable. The statusline exports one `<session-uuid>.json` per session per turn boundary into this directory; on this host it was observed as `drwxr-xr-x` containing 78 files at `-rw-r--r--`, so any local uid can enumerate every live session id and derive every `<sid8>` launcher name in advance.

```bash
TDIR="${CC_TELEMETRY_DIR:-/tmp/cc-telemetry}"   # override for E2E isolation
```

**lr-reset-poller launcher: write, chmod +x, execute** — `scripts/limit-recover/lr-reset-poller.sh:430-433`

The default directory is `/tmp` and the name carries only eight hex characters of session id. The file is created by `>` (which follows a symlink), made executable, and then handed to `spawn_gui`/`spawn_tmux`, both of which run it as `/bin/bash $launcher` — an open-by-path at execution time, so the bytes executed are whatever the path resolves to then, not what was written.

```bash
    launcher="${LR_POLLER_LAUNCH_DIR:-/tmp}/lr-poller-launch-${sid:0:8}.sh"
    { echo '#!/bin/bash'; printf 'exec "%s/lr-fire-resume.sh" "%s" "%s" "%s" --prompt %q\n' \
        "$LR" "$acct" "$cwd" "$sid" "/limit-recover"; } > "$launcher"; chmod +x "$launcher"
```

#### Dataflow

The canonical finding records the affected path at scripts/limit-recover/lr-reset-poller.sh:430-433, scripts/limit-recover/lr-handoff.sh:159-168, scripts/handoff-fire.sh:2400-2402, bin/cc-context:28, but no expanded source-to-sink narrative was recorded.

**Session ids published world-readably in /tmp** — `bin/cc-context:28`

This is what makes the launcher names predictable rather than guessable. The statusline exports one `<session-uuid>.json` per session per turn boundary into this directory; on this host it was observed as `drwxr-xr-x` containing 78 files at `-rw-r--r--`, so any local uid can enumerate every live session id and derive every `<sid8>` launcher name in advance.

```bash
TDIR="${CC_TELEMETRY_DIR:-/tmp/cc-telemetry}"   # override for E2E isolation
```

**lr-reset-poller launcher: write, chmod +x, execute** — `scripts/limit-recover/lr-reset-poller.sh:430-433`

The default directory is `/tmp` and the name carries only eight hex characters of session id. The file is created by `>` (which follows a symlink), made executable, and then handed to `spawn_gui`/`spawn_tmux`, both of which run it as `/bin/bash $launcher` — an open-by-path at execution time, so the bytes executed are whatever the path resolves to then, not what was written.

```bash
    launcher="${LR_POLLER_LAUNCH_DIR:-/tmp}/lr-poller-launch-${sid:0:8}.sh"
    { echo '#!/bin/bash'; printf 'exec "%s/lr-fire-resume.sh" "%s" "%s" "%s" --prompt %q\n' \
        "$LR" "$acct" "$cwd" "$sid" "/limit-recover"; } > "$launcher"; chmod +x "$launcher"
```

#### Reachability

Reachability was not recorded beyond the canonical finding summary and affected locations.

#### Severity

**Low** — The primitive is real and there are two distinct outcomes: the symlink variant gives another local uid an arbitrary-file clobber and a `chmod +x` performed as this user, and the pre-created-file variant gives a window in which bytes that uid controls are executed as this user, because all three sites execute the file by path after writing it rather than by descriptor. Severity stays low because the attacker model is a distinct local uid on a single-operator workstation, where the other uids are essentially system accounts, and because the sticky bit forces pre-creation rather than the much easier replace-after-write race. The `/tmp/cc-telemetry` leak is what moves this from theoretical to mechanically reachable — without it the 8-hex-character launcher names would have to be guessed. Evidence of a routinely-present non-operator uid, or of any launcher name that is constant rather than session-derived, would raise this to medium.

Rises if these scripts ever run on a shared or multi-tenant host, or if a launcher name stops being session-derived. Drops to informational once all three allocate via mktemp under $TMPDIR.

#### Remediation

Allocate all three files with `mktemp` under the per-uid temporary directory — `launcher="$(mktemp "${TMPDIR:-/tmp}/lr-poller-launch-XXXXXXXX.sh")"` — which the repository already does at roughly forty other sites; this gives both an unpredictable name and `O_EXCL` creation that fails rather than following a pre-existing symlink. Keep the session id in the name only as a readability prefix, never as the whole entropy budget. Separately, move the telemetry export off `/tmp`: `bin/cc-context` should default `CC_TELEMETRY_DIR` to `$HOME/.claude/telemetry` (or `$TMPDIR`) rather than `/tmp/cc-telemetry`, since publishing live session ids world-readably is what makes the launcher names predictable in the first place.

Tests:
- Add a test asserting each launcher path matches the mktemp XXXXXXXX pattern and lies under $TMPDIR, so a future edit cannot silently move it back to /tmp.
- Add a test that pre-creates a symlink at the deterministic legacy path and asserts the script neither writes through it nor executes it — this is the RED case and it must fail against the current tree.
- Assert the telemetry directory is created with mode 0700 and is not under /tmp.

Preventive controls:
- Never write-then-execute by path in a shared directory; allocate with mktemp under $TMPDIR and, where practical, execute the descriptor you wrote.
- Treat any identifier the system publishes to a world-readable location as public, and never let it be the sole source of unpredictability in a filename.
- Add a lint that flags a literal /tmp/ path in bin/ or scripts/ that is redirected into or chmod'ed, so the established mktemp idiom is enforced rather than merely conventional.

## Reviewed Surfaces

| Surface | Risk Area | Outcome | Notes |
| --- | --- | --- | --- |
| Evaluation of data as shell code (eval, sh -c, generated scripts, interpolation into python -c and osascript program bodies) | Command injection | Reported | The primary surface for this scope. Enumerated every eval, every sh/bash/zsh -c, every python3 -c, every osascript -e and every generated-then-executed script across all 152 in-scope files. Reported: lr-reset-poller.sh's use of json.dumps() as a shell quoter feeding eval, reproduced by execution. Rejected: the three eval sites in lead-reconciler.sh, which read CC_RECON_ROSTER_\* variables documented at line 34 as 'a command line each' — every setter in the tree is either the script's own selftest, tests/lead-reconciler.bats, or operator activation documentation, so this is a config-as-command hook at the same trust level as $EDITOR, not data interpolated into code. Also rejected: the bash -c occurrences in bin/cc-dispatch, cc-respawn, cc-route, cc-run and cc-wave-plan, which are all selftest assertions over mktemp-derived paths. Evidence: artifacts/02_discovery/candidate_ledger.jsonl, artifacts/02_discovery/validation_artifacts/probe_eval_jsondumps.sh |
| Temporary file and generated-executable placement | Insecure temporary file / link following | Reported | Three write-then-execute sites in /tmp reported. The predictability premise was verified live: /tmp/cc-telemetry is a 0755 directory holding 78 world-readable \<session-uuid\>.json files, so launcher names derived from ${SID:0:8} are enumerable by any local uid. bin/claude-accounts' /tmp/claude-accounts-cache.json was reviewed and rejected: cache_write stages to a pid-suffixed name and os.replace()s it into place, and rename(2) does not traverse a symlink at the destination, so only the staging name is symlink-followable — a sub-second window whose payload is a fixed quota-JSON blob, guarded further by a cfg_key check and a 90s TTL, with routing integrity rather than execution as the consequence. Roughly forty other sites in scope use mktemp "${TMPDIR:-/tmp}/..." correctly. Evidence: artifacts/02_discovery/candidate_ledger.jsonl |
| AppleScript program construction (osascript -e / heredoc) from interpolated values | Improper output encoding | Rejected | Five notification helpers (desk-invariant.sh:183, nightly-regression.sh:74, postland-verify.sh:232, desk-recycle-invariant.sh:130, lr-reset-poller.sh:214) interpolate a message and title into an AppleScript string literal, stripping only the double quote via ${msg//\\"/}. The backslash escape survives that guard, so the construction looked breakable. Refuted by execution rather than argument: a message ending in a backslash yields a program osascript rejects with -2740, and the quote-free breakout attempt that appends ` & (do shell script (ASCII character 116)) & ` through the title yields -2741, because escaping the closing quote opens a string that nothing left in the input can close — a balanced breakout needs two quote characters and the guard strips both. A $(...) payload created no file. handoff-fire.sh and lr-handoff.sh build their AppleScript from heredocs carrying only script-derived pane ids and launcher paths. Evidence: artifacts/02_discovery/validation_artifacts/probe_osascript_notify.sh |
| Automated push-to-trunk rail and its escalation-surface gate | Protection mechanism failure | Rejected | scripts/ship-land.sh holds the only automated write path to a remote trunk, so its ESC_RE_DEFAULT denylist was examined as the same class that produced the hooks/ finding at dc12c8db. Rejected on specific counterevidence: unlike hooks/validate-bash.sh, where a sibling branch of the same alternation proved the missing anchor accidental, here lines 232-236 state the narrower scope and its reason in the file — auth/session/navigation lands are escalation-worthy but this repository's churn is saturated with those words, so a substring scan would self-park every land — and record it as surfaced to the lead as a design tradeoff, with SHIP_LAND_ESC_RE as the per-repository extension point. The enclosing control is also fail-closed: esc_scan uses grep -E -- with an explicit rc capture and emits a synthetic hit on rc\>=2, so a malformed pattern parks the land rather than reading clean. Evidence: artifacts/02_discovery/candidate_ledger.jsonl |
| Quoting of caller-supplied values into generated launcher scripts | Command injection | Needs follow-up | lr-handoff.sh:160-167 generates its launcher with an unquoted heredoc, so $TARGET, ${WT_TOP:-$CWD}, $BRANCH and $INGEST_PROMPT are expanded into double-quoted shell strings inside an executable file. Most of those come from the invoking caller's own --target/--cwd argv, which carries no authority gain. The unresolved input is $BRANCH, read from the working tree at line 91: git check-ref-format permits $, backtick, parentheses, semicolon and double quote, so a branch literally named $(cmd) is a valid ref that one session could create and another could later hand off. No caller was found that runs lr-handoff.sh against a worktree whose branch it did not itself choose, so the reaching path is unproven and the row is deferred rather than reported. Evidence: artifacts/02_discovery/candidate_ledger.jsonl |
| Destructive filesystem and git operations (rm -rf, worktree remove, branch -D, reset) | Unintended file deletion | No issue found | Swept every rm/mv/cp/chmod/chown/kill/rmdir occurrence with a variable operand across all 152 files. Every destructive operand is double-quoted; no unquoted expansion reaches a destructive command, which matters because the Bash tool's zsh does not word-split but the scripts run under bash, which does. scripts/worktree-gc.sh is written defensively by design: removal is always `git worktree remove` and never --force, so git refuses when a tree changed since the gates ran, and the refusal is reported as KEEP rather than escalated. |
| OAuth refresh tokens, keychain reads, and push credentials | Credential exposure | No issue found | bin/claude-accounts reads refresh tokens via /usr/bin/security find-generic-password and passes them to the heal child through the environment, never through argv; the file documents this choice and its ~90s same-uid ps -E exposure explicitly at lines 31-34. bin/claude-kimi writes its API key under (umask 077) into a 0700 directory. scripts/push-send.sh does place PUSHOVER_TOKEN in curl argv via --form-string, but the value originates in the caller's own environment, so a same-uid reader gains nothing it did not already have, and the channel is inert on this host (unset token exits 3). No credential reaches a log, a notification body, or a world-readable path. |
| jq filter construction from shell variables | Query/filter injection | No issue found | Eight tools interpolate $CELL into a jq program. $CELL is a fixed literal `def cell(ph): ...` helper defined in each file (cc-context:53, cc-decide:58, cc-value:81, cc-blockers:188, cc-board:38, cc-backlog:118, cc-wave-plan:60, cc-audit:62) and is never assigned from input. Every variable datum reaching jq goes through --arg or --argjson, which binds it as a value rather than as program text. |
| Outbound network calls | Data exfiltration | Not applicable | Three call sites only: scripts/push-send.sh (Pushover, inert without credentials), scripts/relogin-probes/e2-launchd-browser-survival.sh (127.0.0.1 CDP probe), and bin/claude-accounts' usage API read. No curl-pipe-to-shell, no base64 decode-and-execute, and no attacker-controlled destination anywhere in scope. |
| argv/stdin parsing in the cc-\* tools the model invokes directly | Improper input handling | No issue found | The cc-\* tools are the surface where model-influenced strings arrive most directly. Their record writers build JSON with jq -nc --arg (cc-backlog:236, cc-announce:79, cc-await-ping:122, cc-run:56), which is safe by construction. The printf-built JSON records elsewhere (cc-teardown:152, cc-decide:64, land-lock.sh:74 and others) carry script-derived enum values, timestamps and uuids rather than free text; the one printf-built record that does carry an unconstrained value into a later shell context is lr-reset-poller.sh:328 and it is reported above. IFS is assigned only in read-scoped form; no unsafe xargs and no find -exec appear in scope. |

## Open Questions And Follow Up

- The deployed ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist sets LR_POLLER_AUTOFIRE=1, but the committed template at scripts/limit-recover/com.reso.lr-reset-poller.plist ships that block commented out with the comment 'Auto-resume is OFF by default'. Which side is authoritative, and should the committed template match the deployed reality?
  - Follow-up prompt: Diff scripts/limit-recover/com.reso.lr-reset-poller.plist against ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist and decide whether LR_POLLER_AUTOFIRE=1 is the intended production posture; if it is, land the template change so the repository stops understating what the daemon does.
- bin/cc-context publishes one \<session-uuid\>.json per live session into world-readable /tmp/cc-telemetry. Beyond making the /tmp launcher names predictable, does anything else in the fleet treat a session id as a secret or as a capability?
  - Follow-up prompt: Grep bin/ and scripts/ for paths and locks whose only unpredictability is a session id, and decide whether CC_TELEMETRY_DIR should default to $HOME/.claude/telemetry instead of /tmp/cc-telemetry.
- lr-reset-poller.sh runs under 'set -uo pipefail' with no -e, so a parked record containing a double quote produces malformed JSON, makes the eval at line 391 a silent no-op, and leaves the previous loop iteration's sid/acct/cwd bound. Has that ever caused a resume to fire against the wrong session?
  - Follow-up prompt: Search ~/.reso/limit-recover/poller.log for RESUMED or LISTED lines whose sid does not match the parked record processed in that tick, and add an explicit per-iteration reset of sid/acct/cfg/cwd/reset_at_utc regardless of the quoting fix.
- lr-handoff.sh:160-167 expands $BRANCH into a double-quoted shell string inside a generated executable via an unquoted heredoc, and git permits $, backtick and parentheses in a ref name. Whether a branch named by one session is ever handed off by a different, unattended caller was not traced, so neither reachability nor severity could be fixed. Resolve by enumerating every caller of lr-handoff.sh and checking whether any runs without an operator present against a worktree whose branch it did not create.
  - Follow-up prompt: Review deferred unit deferred_lr_handoff_branch_name and close its stated proof gap. Paths: scripts/limit-recover/lr-handoff.sh. Surfaces: surface_generated_launcher_quoting.
- Coverage is pattern-complete but not line-complete. All 152 in-scope files were swept for every risk class in the threat model (shell evaluation, generated executables, temp-file placement, destructive operands, credential flow, jq and AppleScript program construction, network egress, unsafe parsing), and every file with a hit was read around that hit; roughly 20 files were read in full. The remaining ~41k lines were not read line by line, so a defect that matches none of the swept patterns would have been missed. Resolve by re-running this scope with a per-file review pass rather than a class-driven sweep.
  - Follow-up prompt: Review deferred unit deferred_line_by_line_review and close its stated proof gap. Paths: bin/, scripts/.
- ship-land.sh's esc_scan greps the textual diff body, so a destructive change committed in a file marked binary via .gitattributes would render as 'Binary files differ' and present no scannable lines. This was reasoned about but not tested, and is recorded rather than asserted. Resolve by committing a .gitattributes-binary file containing a DROP TABLE line on a scratch branch and confirming whether esc_scan parks the land.
  - Follow-up prompt: Review deferred unit deferred_esc_scan_binary_diff and close its stated proof gap. Paths: scripts/ship-land.sh. Surfaces: surface_landing_rail.
