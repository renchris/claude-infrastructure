#!/usr/bin/env bats
#
# cc-autodeny-census.bats — bin/cc-autodeny-census, the local record of Claude Code's timed
# auto-denied permission prompts (docs/research/autodeny-prompts-2026-10-11/, candidate C4 with the
# reviewers' revisions in verdicts.md).
#
# Every fixture is a small synthetic transcript written under a temp HOME; no real transcript is
# read. HOME is the only seam the tool reads stores and writes its log through, so pinning it seals
# the suite: the operator's ~/.claude*/projects and ~/.claude/logs are never touched.
#
# What the suite pins:
#   * outcome (timed_out / capped / immediate), cause group G1-G5, context and agent type;
#   * stores discovered by glob, deduplicated by realpath (a symlinked store counts once), rows
#     deduplicated by tool_use_id across stores (a copied transcript counts once, both stores listed);
#   * the log and the --json output never hold a full command: cmd_head <= 200 chars + cmd_sha256;
#   * --log is idempotent (dedup by tool_use_id against the existing log);
#   * the classifier denial-limit inference: rule allows do NOT reset the streak, a classifier allow
#     does; only the 3rd consecutive deny at >= 120 s qualifies; "Stage 2 classifier error" is
#     labelled inferred_fallback_or_slow_classifier; every inferred row says inferred:true + method;
#   * the probably-answered safety dialog (user_temporary accept + the shape predicate), under both the
#     inline predicate copy and whatever hooks/lib/rm_prompt_shape.py provides;
#   * a user_reject safetyCheck row is a person's answer, not an auto-deny; a cross-store copy that
#     holds the tool_use replaces a result-only copy; a legacy streak yields one row; no __pycache__;
#   * the launchd shape: env -i, PATH=/usr/bin:/bin (so /usr/bin/python3 and grep, no rg).
#
# DEAD-ASSERTION DISCIPLINE: bats runs bodies under `set -e`, which exempts `[[ ]]` and `! cmd` when
# not final. This suite uses `[ ]` and `case` arms that call `false`.

# shellcheck disable=SC2034  # consumed by bats itself
BATS_TEST_TIMEOUT=120

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO/bin/cc-autodeny-census"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"
  mkdir -p "$HOME/.claude/projects" "$HOME/.claude-secondary/projects" "$HOME/.claude-next"
  ln -s "$HOME/.claude/projects" "$HOME/.claude-next/projects"
  GEN="$D/gen.py"
  cat > "$GEN" <<'PY'
import datetime, json, os, sys

SAFETY = ("Permission for this command was denied by a built-in Claude Code safety check, not by the user. "
          "The command was NOT run; do not claim it succeeded. ")
CLS = "Permission for this action was denied by the Claude Code auto mode classifier. Reason: "
T0 = datetime.datetime(2026, 10, 10, 10, 0, 0, tzinfo=datetime.timezone.utc)
SECRET = "SECRETTOKEN_" + "Z" * 12


def iso(d):
    return d.strftime("%Y-%m-%dT%H:%M:%S.000Z")


def pair(out, n, tid, at_s, el_s, cmd, res, pd=None, sid="sess-1", ver="2.1.293", tool="Bash"):
    t = T0 + datetime.timedelta(seconds=at_s)
    use = {"type": "assistant", "timestamp": iso(t), "sessionId": sid, "version": ver,
           "message": {"role": "assistant", "content": [{"type": "tool_use", "id": tid, "name": tool,
                                                         "input": {"command": cmd}}]}}
    r = {"type": "user", "timestamp": iso(t + datetime.timedelta(seconds=el_s)), "sessionId": sid, "version": ver,
         "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": tid, "is_error": True,
                                                  "content": res}]}}
    if pd is not None:
        r["permissionDecision"] = pd
    out.write(json.dumps(use, separators=(",", ":")) + "\n")
    out.write(json.dumps(r, separators=(",", ":")) + "\n")


def flagged(text):
    return SAFETY + "What was flagged: " + text


def w(path, meta=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if meta is not None:
        with open(path[:-len(".jsonl")] + ".meta.json", "w") as m:
            json.dump(meta, m)
    return open(path, "a")


RJ = {"decision": "reject", "source": "config", "reasonType": "safetyCheck"}
home, scen = sys.argv[1], sys.argv[2]
P = os.path.join(home, ".claude", "projects", "-proj-a")

if scen == "safety":
    with w(os.path.join(P, "sess-1.jsonl")) as o:
        pair(o, 0, "tu_g1", 0, 120.4, "bash -c 'f(){ \"$@\"; }; f true'",
             flagged("This shell -c script runs rm and could not be checked."))
        pair(o, 0, "tu_g2", 300, 121.0, "cd /tmp/x; rm -f a/*",
             flagged("This command changes directories before the removal, so the relative glob target cannot be statically resolved."))
        pair(o, 0, "tu_g3", 600, 0.3, "rm -f $D/*.jpg",
             flagged("rm target uses a shell variable that may be unset. It has already gone unanswered 3 times."), pd=RJ)
        pair(o, 0, "tu_g5", 900, 125.0, "bash -c 'rm -f \"\"'",
             flagged("This command would remove a workspace directory (the working directory)."))
        pair(o, 0, "tu_ok", 1200, 1.0, "ls", "file1\nfile2", pd={"decision": "accept", "source": "config", "reasonType": "rule"})
    wf = os.path.join(P, "sess-1", "subagents", "workflows", "wf_1", "agent-a1.jsonl")
    with w(wf, {"agentType": "workflow-lean"}) as o:
        pair(o, 0, "tu_g4", 1500, 130.0, "bash -c 'T=$1; g(){ rm -rf $T; }; g'",
             flagged("This shell -c script runs rm and could not be checked."))
    sa = os.path.join(P, "sess-1", "subagents", "agent-b1.jsonl")
    with w(sa, {"agentType": "deep-research"}) as o:
        pair(o, 0, "tu_imm", 1800, 0.2, "cd /tmp/y && rm -f b/*",
             flagged("This command changes directories before the removal."))
elif scen == "copy":
    # The same tool call copied into a second account store.
    src = os.path.join(P, "sess-1.jsonl")
    dst = os.path.join(home, ".claude-secondary", "projects", "-proj-a", "sess-1.jsonl")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(src) as a, open(dst, "w") as b:
        b.write(a.read())
elif scen == "longcmd":
    cmd = "bash -c 'f(){ \"$@\"; }; f echo " + "x" * 300 + " " + SECRET + "'"
    with w(os.path.join(P, "sess-2.jsonl")) as o:
        pair(o, 0, "tu_long", 0, 120.2, cmd, flagged("This shell -c script runs rm and could not be checked."), sid="sess-2")
    print(cmd, end="")
elif scen == "fallback_new":
    DEN = {"decision": "reject", "source": "config", "reasonType": "classifier"}
    RULE = {"decision": "accept", "source": "config", "reasonType": "rule"}
    with w(os.path.join(P, "sess-3.jsonl")) as o:
        pair(o, 0, "c1", 0, 3, "curl -X POST x", CLS + "[Exfil]", pd=DEN, sid="sess-3")
        pair(o, 0, "r1", 10, 1, "git status", "clean", pd=RULE, sid="sess-3")   # rule allow: NO reset
        pair(o, 0, "c2", 20, 3, "curl -X POST y", CLS + "[Exfil]", pd=DEN, sid="sess-3")
        pair(o, 0, "c3", 40, 125, "kitty @ launch", CLS + "[Create Public Surface]", pd=DEN, sid="sess-3")
elif scen == "fallback_reset":
    DEN = {"decision": "reject", "source": "config", "reasonType": "classifier"}
    CA = {"decision": "accept", "source": "config", "reasonType": "classifier"}
    with w(os.path.join(P, "sess-4.jsonl")) as o:
        pair(o, 0, "d1", 0, 3, "a", CLS + "[x]", pd=DEN, sid="sess-4")
        pair(o, 0, "d2", 10, 3, "b", CLS + "[x]", pd=DEN, sid="sess-4")
        pair(o, 0, "ca", 20, 2, "c", "ok", pd=CA, sid="sess-4")                  # classifier allow: reset
        pair(o, 0, "d3", 30, 130, "d", CLS + "[x]", pd=DEN, sid="sess-4")       # only the 1st of a new streak
        pair(o, 0, "d4", 200, 3, "e", CLS + "[x]", pd=DEN, sid="sess-4")
        pair(o, 0, "d5", 300, 60, "f", CLS + "[x]", pd=DEN, sid="sess-4")       # 3rd, but < 120 s
elif scen == "fallback_slow":
    DEN = {"decision": "reject", "source": "config", "reasonType": "classifier"}
    with w(os.path.join(P, "sess-5.jsonl")) as o:
        pair(o, 0, "s1", 0, 3, "a", CLS + "[x]", pd=DEN, sid="sess-5")
        pair(o, 0, "s2", 10, 3, "b", CLS + "[x]", pd=DEN, sid="sess-5")
        pair(o, 0, "s3", 20, 240, "c", CLS + "Stage 2 classifier error - blocking based on stage 1", pd=DEN, sid="sess-5")
elif scen == "user_reject":
    # A person clicking No on the safety dialog: reasonType safetyCheck, source user_reject. Not an auto-deny.
    UR = {"decision": "reject", "source": "user_reject", "reasonType": "safetyCheck"}
    with w(os.path.join(P, "sess-7.jsonl")) as o:
        pair(o, 0, "ur1", 0, 130, "bash -c 'f(){ \"$@\"; }; f true'",
             "The user doesn't want to proceed with this tool use. The tool use was rejected.", pd=UR, sid="sess-7")
        # positive control for the same arm: source config, no deny text, still counted
        pair(o, 0, "cf1", 300, 121, "rm -f $D/*.jpg", "Permission denied.", pd=RJ, sid="sess-7")
elif scen == "split_copy":
    # One store holds only the tool_result; the other holds tool_use + tool_result. The result-only
    # copy is in ~/.claude-secondary, whose realpath sorts first, so it is scanned first.
    import io
    buf = io.StringIO()
    pair(buf, 0, "tu_split", 0, 121.0, "cd /tmp/x; rm -f a/*",
         flagged("This command changes directories before the removal."), sid="sess-8")
    use, res = buf.getvalue().splitlines()
    with w(os.path.join(home, ".claude-secondary", "projects", "-proj-a", "sess-8.jsonl")) as o:
        o.write(res + "\n")
    with w(os.path.join(P, "sess-8.jsonl")) as o:
        o.write(use + "\n" + res + "\n")
elif scen == "legacy":
    # 2.1.280: no permissionDecision on any row, so only the 600 s legacy window applies.
    with w(os.path.join(P, "sess-9.jsonl")) as o:
        pair(o, 0, "l0", -1000, 3, "a", CLS + "[x]", sid="sess-9", ver="2.1.280")   # outside the window
        pair(o, 0, "l1", 0, 3, "b", CLS + "[x]", sid="sess-9", ver="2.1.280")
        pair(o, 0, "l2", 10, 3, "c", CLS + "[x]", sid="sess-9", ver="2.1.280")
        pair(o, 0, "l3", 20, 125, "d", CLS + "[x]", sid="sess-9", ver="2.1.280")    # 3rd in window, >= 120 s
        pair(o, 0, "l4", 160, 130, "e", CLS + "[x]", sid="sess-9", ver="2.1.280")   # same streak: no 2nd row
elif scen == "answered":
    UT = {"decision": "accept", "source": "user_temporary"}
    with w(os.path.join(P, "sess-6.jsonl")) as o:
        pair(o, 0, "ans1", 0, 40, "bash -c 'f(){ \"$@\"; }; f true'", "done", pd=UT, sid="sess-6")
        pair(o, 0, "ans2", 100, 5, "ls -la", "x", pd=UT, sid="sess-6")          # answered, but not the shape
PY
}

gen() { python3 -I "$GEN" "$HOME" "$@"; }

# Read one field set out of the --json document: prints "tool_use_id outcome cause_group context agent_type stores".
rows() {
  python3 -I -c '
import json, sys
d = json.load(sys.stdin)
for r in d["rows"]:
    print(r["tool_use_id"], r["outcome"], r["cause_group"], r["context"], r.get("agent_type"), ",".join(r["stores"]),
          "inferred" if r["inferred"] else "measured", r.get("method"))
'
}

@test "census: outcome, cause group, context and agent type per measured row" {
  gen safety
  run "$SCRIPT" --since 2026-10-01 --json
  [ "$status" -eq 0 ]
  out="$(printf '%s' "$output" | rows)"
  echo "$out"
  case "$out" in *"tu_g1 timed_out G1 main None"*) ;; *) false ;; esac
  case "$out" in *"tu_g2 timed_out G2 main"*) ;; *) false ;; esac
  case "$out" in *"tu_g3 capped G3 main"*) ;; *) false ;; esac
  case "$out" in *"tu_g5 timed_out G5 main"*) ;; *) false ;; esac
  case "$out" in *"tu_g4 timed_out G4 workflow workflow-lean"*) ;; *) false ;; esac
  case "$out" in *"tu_imm immediate G2 subagent deep-research"*) ;; *) false ;; esac
  case "$out" in *tu_ok*) false ;; *) ;; esac
  [ "$(printf '%s\n' "$out" | grep -c measured)" -eq 6 ]
}

@test "census: summary table, totals and date range" {
  gen safety
  run "$SCRIPT" --since 2026-10-01 --summary
  [ "$status" -eq 0 ]
  echo "$output"
  case "$output" in *"deduped by tool_use_id: 6"*) ;; *) false ;; esac
  case "$output" in *"outcome: timed_out 4, capped 1, immediate 1"*) ;; *) false ;; esac
  case "$output" in *"range: 2026-10-10T10:02:00"*" -> 2026-10-10T10:30:00"*) ;; *) false ;; esac
  case "$output" in *"timed_out  G1     main         1"*) ;; *) false ;; esac
}

@test "census: a symlinked store counts once; a copied transcript dedups by tool_use_id and lists both stores" {
  gen safety
  gen copy
  run "$SCRIPT" --since 2026-10-01 --json
  [ "$status" -eq 0 ]
  out="$(printf '%s' "$output" | rows)"
  echo "$out"
  [ "$(printf '%s\n' "$out" | grep -c '^tu_g1 ')" -eq 1 ]
  case "$out" in *"tu_g1 timed_out G1 main None ~/.claude-secondary/projects,~/.claude/projects"*) ;; *) false ;; esac
  # ~/.claude-next/projects is a symlink to ~/.claude/projects: never listed as a separate store.
  case "$output" in *".claude-next/projects"*) false ;; *) ;; esac
  [ "$(printf '%s\n' "$out" | grep -c measured)" -eq 6 ]
}

@test "census: the log and --json never hold the full command, only cmd_head <= 200 + sha256" {
  full="$(gen longcmd)"
  [ "${#full}" -gt 300 ]
  run "$SCRIPT" --since 2026-10-01 --json --log
  [ "$status" -eq 0 ]
  case "$output" in *SECRETTOKEN_*) echo "full command leaked into --json"; false ;; *) ;; esac
  log="$HOME/.claude/logs/autodeny.jsonl"
  [ -s "$log" ]
  if grep -q SECRETTOKEN_ "$log"; then echo "full command leaked into the log"; false; fi
  want="$(printf '%s' "$full" | shasum -a 256 | cut -d' ' -f1)"
  got="$(python3 -I -c 'import json,sys; r=json.loads(open(sys.argv[1]).readline()); assert len(r["cmd_head"])<=200, len(r["cmd_head"]); print(r["cmd_sha256"])' "$log")"
  [ "$got" = "$want" ]
}

@test "census: --log appends only rows it has not logged (dedup by tool_use_id)" {
  gen safety
  run "$SCRIPT" --since 2026-10-01 --log
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$HOME/.claude/logs/autodeny.jsonl" | tr -d ' ')" -eq 6 ]
  run "$SCRIPT" --since 2026-10-01 --log
  [ "$status" -eq 0 ]
  case "$output" in *"logged 0 new row(s)"*"6 already present"*) ;; *) echo "$output"; false ;; esac
  [ "$(wc -l < "$HOME/.claude/logs/autodeny.jsonl" | tr -d ' ')" -eq 6 ]
}

@test "census: without --log nothing is written" {
  gen safety
  run "$SCRIPT" --since 2026-10-01 --summary
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude/logs/autodeny.jsonl" ]
}

@test "fallback: rule allows do not reset the streak; the 3rd deny at >= 120 s is inferred" {
  gen fallback_new
  run "$SCRIPT" --since 2026-10-01 --json
  [ "$status" -eq 0 ]
  out="$(printf '%s' "$output" | rows)"
  echo "$out"
  case "$out" in *"c3 inferred_fallback_timeout F1 main None ~/.claude/projects inferred classifier_streak_3rd"*) ;; *) false ;; esac
  [ "$(printf '%s\n' "$out" | grep -c inferred)" -eq 1 ]
}

@test "fallback: a classifier allow resets the streak; a 3rd deny under 120 s does not qualify" {
  gen fallback_reset
  run "$SCRIPT" --since 2026-10-01 --json
  [ "$status" -eq 0 ]
  out="$(printf '%s' "$output" | rows)"
  echo "$out"
  [ -z "$out" ]
}

@test "fallback: a slow Stage 2 classifier error is labelled inferred_fallback_or_slow_classifier" {
  gen fallback_slow
  run "$SCRIPT" --since 2026-10-01 --json
  [ "$status" -eq 0 ]
  out="$(printf '%s' "$output" | rows)"
  echo "$out"
  case "$out" in *"s3 inferred_fallback_or_slow_classifier F1 main"*" inferred classifier_streak_3rd"*) ;; *) false ;; esac
}

@test "answered: a user_temporary accept of the prompt shape is a probable answered dialog (inline predicate)" {
  gen answered
  CC_AUTODENY_SHAPE_MODULE=none run "$SCRIPT" --since 2026-10-01 --json
  [ "$status" -eq 0 ]
  out="$(printf '%s' "$output" | rows)"
  echo "$out"
  case "$out" in *"ans1 answered_probable G1 main"*" inferred user_temporary_accept+rm_prompt_shape"*) ;; *) false ;; esac
  case "$out" in *ans2*) false ;; *) ;; esac
  case "$output" in *'"predicate": "inline prototype copy'*) ;; *) false ;; esac
}

@test "answered: the same verdict through whatever predicate the run resolves (module when present)" {
  gen answered
  run "$SCRIPT" --since 2026-10-01 --json
  [ "$status" -eq 0 ]
  out="$(printf '%s' "$output" | rows)"
  echo "$out"
  case "$out" in *"ans1 answered_probable G1"*) ;; *) false ;; esac
  case "$out" in *ans2*) false ;; *) ;; esac
}

@test "census: a person rejecting the safety dialog (source user_reject) is not an auto-deny" {
  gen user_reject
  run "$SCRIPT" --since 2026-10-01 --json
  [ "$status" -eq 0 ]
  out="$(printf '%s' "$output" | rows)"
  echo "$out"
  case "$out" in *ur1*) false ;; *) ;; esac
  case "$out" in *"cf1 timed_out "*" measured reasonType_safetyCheck"*) ;; *) false ;; esac
  [ "$(printf '%s\n' "$out" | grep -c measured)" -eq 1 ]
}

@test "census: a cross-store copy holding the tool_use replaces a result-only copy (outcome + cmd_head)" {
  gen split_copy
  run "$SCRIPT" --since 2026-10-01 --json
  [ "$status" -eq 0 ]
  got="$(printf '%s' "$output" | python3 -I -c '
import json, sys
rows = [r for r in json.load(sys.stdin)["rows"] if r["tool_use_id"] == "tu_split"]
assert len(rows) == 1, rows
r = rows[0]
print(r["outcome"], r["elapsed_s"], bool(r["cmd_head"]), ",".join(r["stores"]))
')"
  echo "$got"
  [ "$got" = "timed_out 121.0 True ~/.claude-secondary/projects,~/.claude/projects" ]
}

@test "fallback: a legacy (no permissionDecision) streak yields one row, consecutive counted in the window" {
  gen legacy
  run "$SCRIPT" --since 2026-10-01 --json
  [ "$status" -eq 0 ]
  got="$(printf '%s' "$output" | python3 -I -c '
import json, sys
for r in json.load(sys.stdin)["rows"]:
    print(r["tool_use_id"], r["method"], r["consecutive"])
')"
  echo "$got"
  [ "$got" = "l3 classifier_streak_legacy_window 3" ]
}

@test "census: loading the shape module writes no __pycache__ beside it" {
  [ -f "$REPO/hooks/lib/rm_prompt_shape.py" ] || skip "hooks/lib/rm_prompt_shape.py not present"
  mkdir -p "$D/shape"
  cp "$REPO/hooks/lib/rm_prompt_shape.py" "$D/shape/rm_prompt_shape.py"
  gen answered
  run env -u PYTHONDONTWRITEBYTECODE CC_AUTODENY_SHAPE_MODULE="$D/shape/rm_prompt_shape.py" \
    "$SCRIPT" --since 2026-10-01 --json
  [ "$status" -eq 0 ]
  case "$output" in *'rm_prompt_shape.py:'*) ;; *) echo "module did not load"; false ;; esac
  [ ! -e "$D/shape/__pycache__" ]
}

@test "census: --since excludes older rows" {
  gen safety
  run "$SCRIPT" --since 2026-10-11 --json
  [ "$status" -eq 0 ]
  [ -z "$(printf '%s' "$output" | rows)" ]
}

@test "census: usage errors exit 2, success exits 0 on empty stores" {
  run "$SCRIPT" --since bogus
  [ "$status" -eq 2 ]
  run "$SCRIPT" --frobnicate
  [ "$status" -eq 2 ]
  run "$SCRIPT" --since
  [ "$status" -eq 2 ]
  run "$SCRIPT" --since 3d
  [ "$status" -eq 0 ]
  case "$output" in *"deduped by tool_use_id: 0"*) ;; *) false ;; esac
}

@test "census: runs under the launchd shape (env -i, PATH=/usr/bin:/bin: system python3, grep fallback)" {
  [ -x /usr/bin/python3 ] || skip "no /usr/bin/python3 on this machine"
  gen safety
  run env -i HOME="$HOME" PATH=/usr/bin:/bin "$SCRIPT" --since 2026-10-01 --summary
  [ "$status" -eq 0 ]
  echo "$output"
  case "$output" in *"prefilter hits (grep)"*) ;; *) false ;; esac
  case "$output" in *"deduped by tool_use_id: 6"*) ;; *) false ;; esac
}
