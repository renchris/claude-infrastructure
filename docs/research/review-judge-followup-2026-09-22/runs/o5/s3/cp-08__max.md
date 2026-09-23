I read the whole file. Line numbers below are counted from line 1 = `#!/bin/bash`; each quoted line is verbatim, so a small counting drift won't make them ambiguous.

---

## 1. The `--agent-id` identity proof is still a text match on a flattened command line

**What** — `resolve_assignee`'s "real `--agent-id` argv token" guard is a substring test on `ps -o args=` output, so a prose argument containing the same text satisfies it, and the value is extracted from the *first* textual occurrence rather than from the flag.

**Where** — lines 270–271:
```bash
    case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac
    agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag
```

**Why it is wrong** — `ps -o args=` joins argv into one space-separated string; nothing distinguishes an argument boundary from a space inside an argument. The header at lines 230–232 names the exact input: a sibling session carrying the literal string `--agent-id <name>@session-8891c11f` inside a prose TASK argument. That prose has spaces around the flag text, so it matches `*" --agent-id "*`; `${rargs#*--agent-id }` then takes that occurrence (the first one anywhere in the line, flag or not); the value ends in `@session-<lead>` and is charset-clean, so both remaining checks pass. The process is a real `claude.exe`, so the argv[0] check passes too. `paneUUID`/`pid` are set from an unrelated live session, which step 3 then TERMs and KILLs — the outcome the comment asserts cannot happen.

---

## 2. Effect-verify leg 1 reports "process gone" when no pid was ever known

**What** — an empty `pid` makes `pid_alive` false, which the verifier reads as "the process is gone", so a teardown can be reported as both-legs-verified without any process ever being observed or signalled.

**Where** — line 182, and lines 613–614:
```bash
pid_alive()  { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
```
```bash
  if ! pid_alive "$pid"; then
    proc_gone=1
```

**Why it is wrong** — `resolve()` only requires a pane uuid (line 337 `[ -n "$paneUUID" ] || return 1`); `pid` comes from `pid="$(printf '%s'      "$obj" | jq -r '.pid // empty')"` and is empty whenever the registry row lacks `pid` (the `record` jq at line 144 explicitly handles that case, so it is an expected state). With an empty pid: the tty-exclusivity guard at line 577 is skipped (`if pid_alive "$pid"`), no `kill` is issued at 599–606, and line 613 concludes `proc_gone=1`. If the pane close succeeds, line 623 writes `TEARDOWN … both legs effect-verified … 1` and exits 0 — asserting a process was verified gone when nothing was looked at. That is the "false success" the header (lines 11–12, 27–28) says the design excludes.

---

## 3. The assignee already-gone branch claims both legs verified with no process leg at all

**What** — the `--assignee-of` "pane absent" path records `both_legs_verified=true` and exits 0, although the function returns before any pid is resolved.

**Where** — line 422:
```bash
        1) record ALREADY-GONE idempotent "assignee pane '$TARGET' is absent from a READABLE it2 enumeration — nothing to close" 1
```

**Why it is wrong** — `resolve_assignee` returns 1 at line 253 (`[ -n "$obj" ] || return 1`), i.e. before leg 3 (`tty → pid`) runs, so `pid` is still empty and no process was ever enumerated or probed. The record's final argument `1` sets `both_legs_verified:true`. Whenever an assignee `claude.exe` outlives its pane (the pane closed but the process was not reaped), the caller — the lead-crash watchdog, which per lines 211–213 already treats cc-teardown's answers as trusted verdicts — receives exit 0 plus a record asserting the process leg was verified, and stops trying.

---

## 4. The kill/confirm loop has no lstart pin, though the comment says it does

**What** — the SIGKILL escalation and the "confirm dead" polling decide from pid existence alone, so the pin that line 598 credits with beating pid-recycling is never applied before signalling.

**Where** — lines 598 and 602–603:
```bash
  # leg 1 — process: TERM, poll, escalate KILL, confirm dead (lstart pin beats pid-recycling).
```
```bash
    if pid_alive "$pid"; then
      kill -KILL "$pid" 2>/dev/null || true
```

**Why it is wrong** — `lstart_before` is captured at line 596 but is used only at line 617, after the signals. If `$pid` stops denoting the original process between line 596 and line 602 (the target exits and the pid is reused), `pid_alive` is true for the new holder and SIGKILL is delivered to it; line 617 then sees a changed lstart and sets `proc_gone=1`, so the stranger's death is recorded as a verified teardown. The reuse window here is short (the TERM grace, 5s by default) so this is much narrower than the classify→act window the pin at 449–456 covers — but it is exactly the class line 598 claims to cover, and the pin is available and unused.

---

## 5. A malformed hold value silently disables the operator-adoption belt

**What** — any non-decimal value of `CC_CLASSIFY_INTERACTIVE_HOLD_S` turns the belt off entirely instead of refusing, creating an undocumented second kill switch in the fail-open direction.

**Where** — line 481:
```bash
  case "$INTERACTIVE_HOLD_S" in ''|*[!0-9]*|0) hold_on=0 ;; esac
```

**Why it is wrong** — with `CC_CLASSIFY_INTERACTIVE_HOLD_S` set to `6h`, `21600 ` (trailing space), or any typo, `hold_on=0`, so the entire block at 482–530 is skipped: no WHO-oracle, no beat, no `beat_or_refuse`, no `operator-adopted` REFUSE. An autonomous reap then proceeds to close a pane that may hold a live operator conversation — the 2026-07-24 incident described at line 470. The file treats the identical situation the opposite way three sections later: a malformed `DECIDED_AT` REFUSES at lines 541–548. Line 477 documents exactly one kill switch, `CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE=1`.

---

## 6. The "transcript did not resolve" gap never reaches the second presence oracle

**What** — `beat_or_refuse` documents that an unresolved transcript routes to it, but no call site does that; when `find_transcript` returns nothing the belt makes no presence determination at all and the beat oracle is never consulted.

**Where** — lines 357, 501 and 509 (the `if` has no `else`):
```bash
  #   (b) the lib is present but its answer is "unreadable" or its transcript did not resolve
```
```bash
      atj="$(find_transcript "$sess_id" 2>/dev/null || true)"
```
```bash
      if [ -n "$atj" ]; then
```

**Why it is wrong** — the only two entries into `beat_or_refuse` are the lib-absent case (line 498) and the rc-2 unreadable case (line 515). `find_transcript` returns 1 immediately on an empty sid (line 343 `[ -n "$sid" ] || return 1`), and `sess_id` is empty for any registry row without `session_id`/`sessionId`, and for **every** `--assignee-of` adoption where `--assignee-sid` was not passed, since line 288 sets `sess_id="$ASSIGNEE_SID"`. It also returns 1 for the handoff case the comment itself names (`<sid>.jsonl.handed-off`). For all of those targets the belt is a no-op: the `operator-adopted` REFUSE at 522–525 cannot fire, and the independent beat oracle — which can answer "absent" and let the close proceed — is never asked. Nothing requires `--assignee-sid` to be supplied, yet the usage text at line 129 describes it as what "keeps the operator-adoption belt ARMED".

---

## 7. Gate failures other than 2/10 are recorded as a safety DEFER and exited with an out-of-contract code

**What** — the gate's raw exit status is passed through as cc-teardown's own, and an empty gate output is labelled a work-safety deferral, so an infrastructure failure is reported as a policy decision under a code the caller contract does not define.

**Where** — lines 565, 569 and 573:
```bash
  gate_out="$("$GATE" decide --cwd "$cwd" --done-evidence "$done_ev" 2>/dev/null)"; grc=$?
```
```bash
    [ -n "$gdec" ] || { [ "$grc" = 2 ] && gdec=REFUSE || gdec=DEFER; }
```
```bash
    say "$gdec — $greason (exit $grc)"; exit "$grc"
```

**Why it is wrong** — if `$GATE` is missing or non-executable — precisely the deploy case the symlink resolution at lines 72–73 exists to prevent, and the case the selftest walks into (defect 9) — then `grc=127` and `gate_out` is empty. The record written at line 572 reads `DEFER` / `gate` / `safety gate blocked teardown` (the defaults at 570–571), indistinguishable in the audit trail from a genuine dirty-tree deferral, and the process exits **127**, which is none of the four codes the contract at lines 15–18 defines. The same passthrough means a gate that ever exits 5 makes cc-teardown exit 5, which the contract defines as "acted, but effect-verify says the pane/process SURVIVED", although nothing was acted on.

---

## 8. `tty_foreign`'s whitelist tests a field this file says is truncated

**What** — the foreign-process whitelist basenames a `ps -o comm=` value that, per this file's own measurement, is cut at 16 characters, so the longer-path entries in the list can never match.

**Where** — lines 301 and 317–318:
```bash
  tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"
```
```bash
    base="${c##*/}"
    case "$base" in -zsh|zsh|-bash|bash|-sh|sh|login|tmux|screen|gitstatusd*|caffeinate) continue ;; esac
```

**Why it is wrong** — lines 261–263 state as measured fact that "macOS truncates comm to 16 chars … and a basename test on it can never match anything." Under that premise `/usr/bin/caffeinate` (19 chars) arrives as `/usr/bin/caffein`, so `base` is `caffein` and the `caffeinate` arm never matches; gitstatusd's cache path truncates to a directory prefix, so `${c##*/}` is empty and `gitstatusd*` never matches. Those processes are children of the pane's shell, not descendants of the target pid, so they are not marked at 304–313; each one increments `fp`, and lines 583–585 DEFER the teardown permanently for any pane whose shell runs them. Note that lines 261–263 and this whitelist cannot both be correct: if `comm` is not truncated in this environment, the defect is the claim at 261 rather than this code.

---

## 9. `--selftest` resolves its own paths from unresolved `$0`

**What** — the selftest derives the script and gate paths from `$0` instead of the symlink-resolved `HERE`, so running it through the deployed symlink points `CC_TEARDOWN_GATE_BIN` at a nonexistent file.

**Where** — lines 641–642:
```bash
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  GATE_SELF="$(cd "$(dirname "$0")" && pwd)/cc-teardown-safety-gate.sh"
```

**Why it is wrong** — lines 72–73 establish the deployment shape: `~/.claude/bin/cc-teardown` is a symlink and "deploy only this one file", with the gate sibling living in the repo `bin/`; that is why `HERE` (line 79) and `GATE="${CC_TEARDOWN_GATE_BIN:-$HERE/cc-teardown-safety-gate.sh}"` (line 82) exist. Invoked as `~/.claude/bin/cc-teardown --selftest`, `dirname "$0"` is `~/.claude/bin`, so `GATE_SELF` is a path that does not exist; every gate-dependent scenario gets `grc=127` and exits 127. Scenarios 1, 2 and 12 fail because 127 ≠ 0/5, and scenarios 3, 4, 5 and 10 fail because 127 ≠ 10/2 — i.e. the suite goes RED for a reason unrelated to any branch it is testing.

---

## 10. Two REFUSE-coded exits write no decision record

**What** — the `die()` paths exit with code 2, the caller-facing REFUSE code, without writing the outcome record the file states every decision branch writes.

**Where** — lines 121, 403 and 407:
```bash
die()  { say "$*"; exit 2; }
```
```bash
      --*) die "unknown option '$1'" ;;
```
```bash
  [ "${#args[@]}" -ge 1 ] || die "usage: cc-teardown <pane-uuid|name> --done-evidence <text>"
```

**Why it is wrong** — line 134 ("NO silent teardown: every decision branch writes one outcome record") and step 5 at line 29 make the record the audit surface, and line 17 defines exit 2 as REFUSE. An autonomous caller that passes an unrecognised flag, or that computes an empty target argument, gets a REFUSE exit with nothing in `$RECORDS_DIR` — so those refusals are invisible to anyone auditing a sweep, and are indistinguishable at the exit code from the recorded REFUSE families. The same applies to the `jq required` exit at line 111.
