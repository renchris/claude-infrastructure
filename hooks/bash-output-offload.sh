#!/bin/bash
# bash-output-offload.sh — PostToolUse(Bash): a LARGE result from a command that is not a deliberate
# read is saved to a file, and the model gets its head, its tail, the lines from the elided middle
# that look like failures, and the path — instead of the whole text re-read on every later turn.
#
# Why (token-efficiency rank 12, wave 2). Tool output is 18% of list-weighted spend and is re-read at
# every later request of its context; Bash is 84% of calls. The pass measured the non-read subset over
# 8,000 chars at <= $453 per 14.96 days (docs/research/token-efficiency-2026-09-23/OPPORTUNITIES.md
# rank 12). It was filed as "no user-space mechanism"; Claude Code 2.1.280 has one:
# hookSpecificOutput.updatedToolOutput "replaces the tool output before it is sent to the model", and
# for Bash it must be the tool_response OBJECT with stdout replaced (a bare string is ignored; probed
# 2026-09-24).
#
# What counts as a deliberate read, and is never touched: any command naming a read verb (cat, sed,
# head, tail, awk, less, more, nl, bat, jq, grep, rg, git show/diff/log/blame, diff). The agent asked
# for that text; a preview would only make it read again (59% of the gross for the settings-level
# cap, rank 16). Also untouched: background launches, images, and anything under the threshold.
#
# Knobs: CC_BASH_OFFLOAD=0 disables; CC_BASH_OFFLOAD_CHARS (8000) is the threshold;
# CC_BASH_OFFLOAD_DIR (${TMPDIR:-/tmp}/claude-bash-output) holds the full outputs.
# Fail-open by construction: any error exits 0 with no output, so the model sees the original result.
[ "${CC_BASH_OFFLOAD:-1}" = 0 ] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0
IFS= read -r -d '' INPUT || true
[ -n "$INPUT" ] || exit 0
printf '%s' "$INPUT" | CC_BO_CHARS="${CC_BASH_OFFLOAD_CHARS:-8000}" \
  CC_BO_DIR="${CC_BASH_OFFLOAD_DIR:-${TMPDIR:-/tmp}/claude-bash-output}" python3 -c '
import hashlib, json, os, re, sys, time
try:
    d = json.load(sys.stdin)
    if d.get("tool_name") not in (None, "Bash"):
        sys.exit(0)
    resp = d.get("tool_response")
    cmd = (d.get("tool_input") or {}).get("command") or ""
    if not isinstance(resp, dict) or resp.get("isImage") or resp.get("backgroundTaskId"):
        sys.exit(0)
    out, err = resp.get("stdout") or "", resp.get("stderr") or ""
    limit = int(os.environ["CC_BO_CHARS"])
    if len(out) <= limit:
        sys.exit(0)
    READ = re.compile(r"(^|[\s;&|(`$])(cat|sed|head|tail|awk|less|more|nl|bat|jq|grep|egrep|rg|diff)(\s|$)"
                      r"|git\s+(-C\s+\S+\s+)?(show|diff|log|blame)\b")
    if READ.search(cmd):
        sys.exit(0)
    dirp = os.environ["CC_BO_DIR"]
    os.makedirs(dirp, exist_ok=True)
    path = os.path.join(dirp, "%d-%s.txt" % (time.time(), hashlib.sha1(out.encode("utf-8", "replace")).hexdigest()[:8]))
    with open(path, "w", encoding="utf-8", errors="replace") as fh:
        fh.write(out)
    lines = out.split("\n")
    H, T = 40, 60
    if len(lines) <= H + T + 10:
        sys.exit(0)  # long lines, few of them: a line preview would not shrink it honestly
    head, tail, mid = lines[:H], lines[-T:], lines[H:-T]
    head = [l[:300] for l in head]
    tail = [l[:300] for l in tail]
    FAIL = re.compile(r"\b(not ok|FAIL(ED|URE)?|ERROR|Error|error:|Traceback|Exception|panic|fatal|WARN(ING)?|warning:|assert)", re.I)
    hits = [(H + 1 + i, l[:300]) for i, l in enumerate(mid) if FAIL.search(l)]
    shown = hits[:30]
    note = ("… [bash-output-offload: %d lines / %d chars in total; lines %d-%d are not shown. Full output: %s"
            " — read a range with sed -n \x27A,Bp\x27 or search it with grep -n. %d line(s) in the hidden range look like"
            " failures or warnings%s]" % (len(lines), len(out), H + 1, len(lines) - T, path, len(hits),
                                          (", the first %d below with their line numbers:" % len(shown)) if shown else ""))
    body = head + [note] + ["%d: %s" % (n, l) for n, l in shown] + (["…"] if shown else []) + tail
    new = dict(resp)
    new["stdout"] = "\n".join(body)
    if len(err) > limit:
        new["stderr"] = err[:2000] + "\n… [bash-output-offload: stderr cut at 2000 of %d chars]" % len(err)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "updatedToolOutput": new}}))
except SystemExit:
    raise
except Exception:
    sys.exit(0)
' 2>/dev/null
exit 0
