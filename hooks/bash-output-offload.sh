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
#
# THE LESSON ARM (truememory-2026-09-27.md §3.6, #6). Before the size early-exit, the head and tail
# 32 KB of stdout+stderr are scanned against hooks/lib/lesson-symptoms.tsv by hooks/lib/lesson_recall.py
# (imported in-process, in its OWN try: an exception there writes one IDL `failed` row and the offload
# below runs unchanged). On a hit the ONE output object carries additionalContext beside any
# updatedToolOutput; with no hit the output is byte-identical to the offload alone. CC_LESSON_RECALL=off
# disables the arm; CC_BASH_OFFLOAD=0 now disables only the offload. The lib dir is resolved through the
# DEREFERENCED self-path: live, this file is a symlink and the .tsv/.jq are never linked (X1).
[ "${CC_BASH_OFFLOAD:-1}" = 0 ] && [ "${CC_LESSON_RECALL:-}" = off ] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0
IFS= read -r -d '' INPUT || true
[ -n "$INPUT" ] || exit 0
_bo_deref() { # <path> → the real file behind any symlink chain (readlink -f, BSD-safe fallback)
  local p="$1" t n=0
  readlink -f "$p" 2>/dev/null && return 0
  while [ -L "$p" ] && [ "$n" -lt 20 ]; do
    t="$(readlink "$p")"
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
    n=$(( n + 1 ))
  done
  printf '%s\n' "$p"
}
printf '%s' "$INPUT" | CC_BO_CHARS="${CC_BASH_OFFLOAD_CHARS:-8000}" \
  CC_BO_DIR="${CC_BASH_OFFLOAD_DIR:-${TMPDIR:-/tmp}/claude-bash-output}" \
  CC_BO_OFF="${CC_BASH_OFFLOAD:-1}" CC_BO_LIB="$(dirname "$(_bo_deref "${BASH_SOURCE[0]}")")/lib" \
  PYTHONDONTWRITEBYTECODE=1 python3 -c '
import hashlib, json, os, re, sys, time
LRH = "bash-output-offload:lesson"
def lr_blind(d, reason):
    # lesson_recall.py itself is unimportable: the one row it would have written, once per session.
    try:
        h, sid = os.environ.get("HOME", ""), str(d.get("session_id") or "?")
        mk = os.path.join(os.environ.get("CC_LESSON_RECALL_STATE_DIR") or os.path.join(h, ".claude", "state", "lesson-recall"),
                          "once", "-".join(re.sub(r"[^A-Za-z0-9_.-]", "_", x)[:96] for x in (LRH, reason, sid)))
        os.makedirs(os.path.dirname(mk), exist_ok=True)
        os.close(os.open(mk, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
        rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "hook": LRH, "sid": sid,
               "disposition": "abstained", "reason": reason, "tool_use_id": str(d.get("tool_use_id") or "")}
        with open(os.environ.get("CC_IDL") or os.path.join(h, ".claude", "autonomy", "idl.jsonl"), "a") as fh:
            fh.write(json.dumps(rec) + "\n")
    except Exception:
        pass
try:
    d = json.load(sys.stdin)
    if d.get("tool_name") not in (None, "Bash"):
        sys.exit(0)
    resp = d.get("tool_response")
    cmd = (d.get("tool_input") or {}).get("command") or ""
    if not isinstance(resp, dict) or resp.get("isImage") or resp.get("backgroundTaskId"):
        sys.exit(0)
    out, err = resp.get("stdout") or "", resp.get("stderr") or ""
    LR, pend = None, None
    try:
        sys.path.insert(0, os.environ.get("CC_BO_LIB") or "")
        try:
            import lesson_recall as LR
        except ImportError:
            lr_blind(d, "lib-missing")
        if LR is not None:
            pend = LR.evaluate(d, [out, err], LRH)
    except Exception as e:
        pend = None
        if LR is not None:
            LR.log_failed(LRH, d, e)
        else:
            lr_blind(d, "lib-missing")  # the module is there but will not load
    def finish(new=None):
        if pend:
            try:
                print(LR.emit(pend, new))
                sys.exit(0)
            except SystemExit:
                raise
            except Exception as e:
                LR.log_failed(LRH, d, e)
        if new is not None:
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "updatedToolOutput": new}}))
        sys.exit(0)
    if os.environ.get("CC_BO_OFF") == "0":
        finish()
    limit = int(os.environ["CC_BO_CHARS"])
    if len(out) <= limit:
        finish()
    READ = re.compile(r"(^|[\s;&|(`$])(cat|sed|head|tail|awk|less|more|nl|bat|jq|grep|egrep|rg|diff)(\s|$)"
                      r"|git\s+(-C\s+\S+\s+)?(show|diff|log|blame)\b")
    if READ.search(cmd):
        finish()
    dirp = os.environ["CC_BO_DIR"]
    os.makedirs(dirp, exist_ok=True)
    path = os.path.join(dirp, "%d-%s.txt" % (time.time(), hashlib.sha1(out.encode("utf-8", "replace")).hexdigest()[:8]))
    with open(path, "w", encoding="utf-8", errors="replace") as fh:
        fh.write(out)
    lines = out.split("\n")
    H, T = 40, 60
    if len(lines) <= H + T + 10:
        finish()  # long lines, few of them: a line preview would not shrink it honestly
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
    finish(new)
except SystemExit:
    raise
except Exception:
    sys.exit(0)
' 2>/dev/null
exit 0
