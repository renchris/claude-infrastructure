#!/usr/bin/env bash
# lr-lib.sh — the ONE home for the limit-recover predicates that more than one caller needs
# (LIMIT_RECOVER_100P, 2026-09-09). Source, don't execute. Pure functions; no side effects at load.
#
# Callers: scripts/limit-recover/lr-handoff.sh (the per-session front end), lr-reset-poller.sh (the
# launchd daemon), lr-fleet.sh (the fleet driver). Two spellings of one predicate is how sibling
# auditors end up disagreeing about one population (memory: sibling-auditors-must-share-the-state-
# model) — the tier read, the liveness census, the transplant read and the engagement oracle all
# used to be re-derived per caller, and each divergence was an incident:
#   · tier: the poller minted tier-less launchers, so every unattended Fable recovery landed on Opus
#     (measured 2026-09-09 on 52e35019: transcript said claude-fable-5-1/xhigh, argv said opus/high);
#   · liveness: `pgrep -f "resume <sid>"` is blind to a fresh launch's argv, so the poller resumed a
#     session whose original pane was alive — two writers, one transcript, one account.
# shellcheck shell=bash

[ -n "${LR_LIB_LOADED:-}" ] && return 0 2>/dev/null
LR_LIB_LOADED=1

# ── the four account stores ──────────────────────────────────────────────────────────────────────
lr_config_dirs() { # → one config dir per line; ~/.claude and ~/.claude-next are ONE account (mirror)
  if [ -n "${LR_CONFIG_DIRS:-}" ]; then printf '%s\n' "$LR_CONFIG_DIRS" | tr ':' '\n'; return 0; fi
  local h
  for h in "$HOME/.claude" "$HOME/.claude-next" "$HOME/.claude-secondary" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary"; do
    [ -d "$h/projects" ] && printf '%s\n' "$h"
  done
  return 0
}

# ── TIER: what the session was ACTUALLY running when it hit the limit ────────────────────────────
# The transcript carries (message.model, effort) per assistant turn; argv carries only the LAUNCH
# tier and the registry row carries neither. The tail of a transcript may belong to a rescuer (a
# same-account duplicate appending by path), so the pick is the last NON-ERROR turn BEFORE the last
# limit error, and only when there is no limit error at all the last turn overall.
lr_tier_from_transcript() { # $1=cfg $2=sid → "model effort" on stdout / rc 1 when nothing on disk
  local f
  for f in "$1"/projects/*/"$2".jsonl "$1"/projects/*/"$2".jsonl.handed-off; do
    [ -f "$f" ] || continue
    /usr/bin/python3 - "$f" <<'PY' && return 0
import json, sys
last_limit = None; turns = []
for line in open(sys.argv[1], errors="replace"):
    if '"assistant"' not in line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("type") != "assistant":
        continue
    ts = d.get("timestamp") or ""
    m = d.get("message") if isinstance(d.get("message"), dict) else {}
    if d.get("isApiErrorMessage"):
        c = m.get("content")
        txt = c if isinstance(c, str) else " ".join(x.get("text", "") for x in (c or []) if isinstance(x, dict))
        if "hit your" in txt:
            last_limit = ts
        continue
    model = m.get("model") or ""
    if not model or model.startswith("<synthetic"):
        continue
    turns.append((ts, model, d.get("effort") or ""))
if not turns:
    sys.exit(1)
pick = None
if last_limit:
    before = [t for t in turns if t[0] < last_limit]
    pick = before[-1] if before else None
if pick is None:
    pick = turns[-1]
print(pick[1], pick[2])
PY
  done
  return 1
}

# ── ENGAGEMENT after a baseline: the one thing a husk can never produce ──────────────────────────
# A content-bearing, NON-ERROR assistant turn newer than the baseline, in the named store's copy.
# `isApiErrorMessage` is the limit hitting again; "No response requested." is the synthetic entry a
# resume inserts; neither is a turn. Byte-identical core to handoff-fire.sh's resume_engaged (the
# parity test in tests/lr-lib.bats pins that).
lr_engaged_after() { # $1=cfg $2=sid $3=baseline (UTC, %FT%T) → 0 engaged / 1 not
  local cfg="${1:-}" sid="${2:-}" t0="${3:-}" f
  { [ -n "$cfg" ] && [ -n "$sid" ]; } || return 1
  for f in "$cfg"/projects/*/"$sid".jsonl; do
    [ -f "$f" ] || continue
    /usr/bin/python3 - "$f" "$t0" <<'PY' && return 0
import json, sys
f, t0 = sys.argv[1], sys.argv[2]
for line in open(f, errors="replace"):
    if '"assistant"' not in line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("type") != "assistant" or d.get("isApiErrorMessage"):
        continue
    if (d.get("timestamp") or "") <= t0:
        continue
    m = d.get("message") if isinstance(d.get("message"), dict) else {}
    c = m.get("content")
    txt = c if isinstance(c, str) else (json.dumps(c) if c else "")
    if not txt.strip() or txt.strip() == "No response requested.":
        continue
    sys.exit(0)
sys.exit(1)
PY
  done
  return 1
}

# ── THE DEATH RECORD: Q3 predicate 2, for any caller that needs it cheaply ───────────────────────
# "The LAST assistant record is an api error" — ANY `error` value, not just the quota spellings
# (docs/plans/NONLIMIT_RESUME_LADDER.md § W1.1 Q3). Three callers had already grown their own
# spelling of this before it lived here: lr-fleet's inline census python, lr-audit.py's
# scan_lead_transcript, and hooks/recover-inject.sh. That is exactly the divergence this file
# exists to prevent — see the header's liveness and tier incidents.
#
# TAIL-BOUNDED ON PURPOSE. A UserPromptSubmit hook runs on EVERY prompt, so it cannot afford a full
# pass over a transcript that grows to tens of MB. The predicate only ever asks about the LAST
# assistant record, so a fixed tail answers it exactly; a caller that needs the whole population of
# delegations must use `lr-audit.py --ledger-only` instead, which reads the file once.
#
# THE ENVELOPE IS THE GATE, never the text: `type:"assistant"` + `isApiErrorMessage:true`. That pair
# is what makes a text-widened read safe -- a session merely DISCUSSING "ENOTFOUND" or quoting a
# limit message in prose (this repo does constantly, including the session that wrote this) is not a
# synthetic api-error record and can never match. `No response requested.` turns are skipped for the
# same reason lr_engaged_after skips them: they are not a real turn.
lr_last_api_error() { # $1=transcript → "<uuid>\t<error>\t<kind>\t<timestamp>"; rc 1 when the last assistant record is NOT an api error
  local f="${1:-}" bytes="${LR_TAIL_BYTES:-131072}"
  [ -n "$f" ] && [ -f "$f" ] || return 1
  tail -c "$bytes" "$f" 2>/dev/null | /usr/bin/python3 -c '
import hashlib, json, sys
last = None
for line in sys.stdin:
    if "\"assistant\"" not in line: continue
    try: d = json.loads(line)
    except Exception: continue          # a tail starts mid-record; a partial line is not a verdict
    if d.get("type") != "assistant": continue
    m = d.get("message") if isinstance(d.get("message"), dict) else {}
    c = m.get("content")
    txt = c if isinstance(c, str) else " ".join(
        x.get("text", "") for x in (c or []) if isinstance(x, dict))
    if txt.strip() == "No response requested.": continue
    last = (d, txt)
if last is None or not last[0].get("isApiErrorMessage"):
    sys.exit(1)
d, txt = last
# The LATCH KEY. A death record carries a uuid in practice, but a latch that silently degrades to
# "no key" would re-emit on every prompt forever, so fall back to a digest of the fields that
# identify this record. Never fall back to a constant: that would latch the FIRST death for the
# life of the session and go silent on every later one.
uid = d.get("uuid") or "sha-" + hashlib.sha256(
    ((d.get("timestamp") or "") + "\x00" + txt[:400]).encode("utf-8")).hexdigest()[:24]
print("%s\t%s\t%s\t%s" % (uid, d.get("error") or "unknown",
                          "limit" if "You'"'"'ve hit your" in txt else "other",
                          d.get("timestamp") or "-"))
' || return 1
}

# ── Q3 predicate 3: a NON-SUCCESS task-notification in the tail ──────────────────────────────────
# The harness's third and last way to end delegated work: fail the task. Shape is quoted, not
# inferred -- a real record from this repo's corpus (docs/research/pane-theft-composer-guard.md:33):
#   {"type":"queue-operation","operation":"enqueue","content":"<task-notification>\n
#    <task-id>bfpgwlzqu</task-id>\n<tool-use-id>toolu_01RwHg...</tool-use-id>\n
#    <output-file>...</output-file>\n<status>killed</status>\n<summary>...</summary>\n
#    </task-notification>"}
# Status vocabulary measured over 300 recent transcripts: completed 5979 · failed 358 · killed 180 ·
# running 29 · stopped 4. `running` is the only non-terminal value, and `completed` is the only
# success -- so this fires on failed/killed/stopped and stays quiet on the other two.
#
# TAIL-BOUNDED for the same reason as lr_last_api_error, and with the same consequence: this answers
# "did something just fail" cheaply, and CANNOT answer "which delegations are still open" -- that
# needs the whole file, so a caller confirms with `lr-audit.py --ledger-only` before acting.
lr_tail_nonsuccess_notification() { # $1=transcript → "<task_id>\t<tool_use_id>\t<status>"; rc 1 when none
  local f="${1:-}" bytes="${LR_TAIL_BYTES:-131072}"
  [ -n "$f" ] && [ -f "$f" ] || return 1
  tail -c "$bytes" "$f" 2>/dev/null | /usr/bin/python3 -c '
import json, re, sys
TID = re.compile(r"<tool-use-id>\s*([^<\s]+)\s*</tool-use-id>")
TASK = re.compile(r"<task-id>\s*([^<\s]+)\s*</task-id>")
ST = re.compile(r"<status>\s*([^<\s]+)\s*</status>")
hit = None
for line in sys.stdin:
    if "<task-notification>" not in line: continue
    try: d = json.loads(line)
    except Exception: continue
    # Both carriers: the queue-operation ENQUEUE (.content) and the delivered user record.
    body = d.get("content")
    if not isinstance(body, str):
        m = d.get("message") if isinstance(d.get("message"), dict) else {}
        c = m.get("content")
        body = c if isinstance(c, str) else " ".join(
            x.get("text", "") for x in (c or []) if isinstance(x, dict))
    if not isinstance(body, str) or "<task-notification>" not in body: continue
    s = ST.search(body)
    status = (s.group(1) if s else "")
    if status in ("completed", "running", ""): continue
    t, k = TASK.search(body), TID.search(body)
    hit = ((t.group(1) if t else "-"), (k.group(1) if k else "-"), status)
if hit is None: sys.exit(1)
print("%s\t%s\t%s" % hit)
' || return 1
}

# ── LIVENESS: the registry, not argv ─────────────────────────────────────────────────────────────
# One line per LIVE process holding the sid: "<pane>\t<pid>\t<account>\t<cwd>". A row whose pid is
# dead is a stale row and is skipped; a row is written by the session's own SessionStart hook
# (hooks/session-register.sh) and is the only store keyed by pane that names the sid.
lr_registry_live_rows() { # $1=sid → rows on stdout; rc 0 when at least one is live, 1 when none
  local sid="${1:-}" regdir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}" f pid pane acct cwd n=0
  [ -n "$sid" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  for f in "$regdir"/*.json; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in .*) continue ;; esac
    [ "$(jq -r '.session_id // .sessionId // empty' "$f" 2>/dev/null)" = "$sid" ] || continue
    pid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$pid" 2>/dev/null || continue
    pane="$(jq -r '.paneUUID // empty' "$f" 2>/dev/null)"; [ -n "$pane" ] || pane="$(basename "$f" .json)"
    acct="$(jq -r '.account // empty' "$f" 2>/dev/null)"
    cwd="$(jq -r '.cwd // empty' "$f" 2>/dev/null)"
    # PAD AT THE EMITTER. Tab is IFS-whitespace, so an empty cell does not read back empty — it
    # shifts every later column LEFT, silently, exit 0. `account` is the one non-last cell that can
    # be absent from a registry row (`.account // empty`); `pane` falls back to the filename and
    # `pid` is digit-validated above, so both are non-empty by construction, and `cwd` is LAST.
    printf '%s\t%s\t%s\t%s\n' "$pane" "$pid" "${acct:--}" "$cwd"; n=$((n + 1))
  done
  [ "$n" -gt 0 ]
}

lr_resume_procs() { # $1=sid → pids of `--resume <sid>` processes (the argv census), one per line; rc 0 when any
  local sid="${1:-}" out
  [ -n "$sid" ] || return 1
  # THE PATTERN MUST NOT RIDE IN ARGV. `awk -v s="--resume $sid"` puts the very string being searched
  # for into the awk process's OWN command line, and `ps -axo command=` — started concurrently in the
  # same pipeline — prints it, so `index($0, s)` matched AWK ITSELF and this census answered YES for
  # every sid ever asked about. Measured 2026-09-09: `lr-fleet --locate` called a session with one
  # registry pane DUPLICATE and a session with none RESUMING, and the poller retired parked records
  # as already-running. pgrep excludes itself; a hand-rolled `ps | awk` does not (memory:
  # pgrep-excludes-the-callers-ancestors — a census is in its own population unless it says otherwise).
  # The sid travels in the ENVIRONMENT, which ps does not print.
  out="$(ps -axo pid=,ppid=,command= 2>/dev/null | LR_RP_SID="$sid" awk 'index($0, "--resume " ENVIRON["LR_RP_SID"]) { print $1"\t"$2 }' || true)"
  [ -n "$out" ] || return 1
  # ONE SESSION IS ONE PROCESS, NOT A CHAIN. A resume is launched through bin/cc-close-attrib, which
  # stays alive as the PARENT of the real `claude` and carries the whole command line in its own
  # argv — so this census saw TWO processes for ONE session. Measured 2026-09-09: `lr-fleet
  # --duplicates` called b418b97a a split brain over pids 16125 (the wrapper) and 16212 (its child),
  # one pane, one session — and its prescription was to retire a LIVE pane. Keep only the leaves:
  # a pid that is the PARENT of another pid in this set is the wrapper, not the session.
  out="$(printf '%s\n' "$out" | awk -F'\t' '{ pid[NR]=$1; par[$2]=1 } END { for (i=1;i<=NR;i++) if (!(pid[i] in par)) print pid[i] }')"
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# ── TRANSPLANT: where did this session go? ───────────────────────────────────────────────────────
# Reads the split-brain lock lr-transplant.sh writes. Prints the target config dir when the lock
# names a target OTHER than $2 and that target still holds the transcript (the successor exists);
# rc 1 otherwise (never transplanted, or transplanted and the successor is gone — both mean "this
# store's copy is the one to act on").
lr_transplanted_to() { # $1=sid $2=this cfg → target cfg on stdout / rc 1
  local sid="${1:-}" here="${2:-}" state="${LR_STATE_DIR:-$HOME/.reso/limit-recover}" lock to to_real here_real
  lock="$state/locks/$sid.lock"
  [ -f "$lock" ] || return 1
  to="$(sed -n '/"to":"/{s/.*"to":"\([^"]*\)".*/\1/p;q;}' "$lock")"
  [ -n "$to" ] || return 1
  to_real="$(cd "$to" 2>/dev/null && pwd -P || printf '%s' "$to")"
  here_real="$(cd "$here" 2>/dev/null && pwd -P || printf '%s' "$here")"
  [ "$to_real" != "$here_real" ] || return 1
  ls "$to"/projects/*/"$sid".jsonl >/dev/null 2>&1 || return 1
  printf '%s' "$to"
}

# ── KITTY from ANY context (launchd has no $KITTY_WINDOW_ID) ─────────────────────────────────────
lr_kitty_socket() { # → unix:/tmp/kitty-<pid> of a LIVE kitty, via bin/cc-kitty-socket; rc 1 when none
  [ -n "${CC_TERM_KITTY_TO:-}" ] && { printf '%s' "$CC_TERM_KITTY_TO"; return 0; }
  local c out
  # CC_KITTY_SOCKET_BIN is THE resolver when set (a test pins "no kitty" by pointing it at nothing);
  # it never falls through to the installed one.
  if [ -n "${CC_KITTY_SOCKET_BIN:-}" ]; then
    [ -x "$CC_KITTY_SOCKET_BIN" ] || return 1
    out="$("$CC_KITTY_SOCKET_BIN" 2>/dev/null)" && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    return 1
  fi
  for c in "${LR_LIB_DIR:-}/../../bin/cc-kitty-socket" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/cc-kitty-socket" "$HOME/.claude/bin/cc-kitty-socket"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    if out="$("$c" 2>/dev/null)" && [ -n "$out" ]; then printf '%s' "$out"; return 0; fi
  done
  return 1
}
lr_kitty_bin() {
  local c
  for c in "${CC_TERM_KITTY:-}" "${LR_LIB_DIR:-}/../../bin/cc-kitty-bin" "$HOME/.claude/bin/cc-kitty-bin"; do
    [ -n "$c" ] || continue
    if [ -x "$c" ] && [ "$(basename "$c")" = cc-kitty-bin ]; then out="$("$c" 2>/dev/null)" && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    elif command -v "$c" >/dev/null 2>&1; then printf '%s' "$c"; return 0; fi
  done
  command -v kitty >/dev/null 2>&1 && { printf 'kitty'; return 0; }
  return 1
}
lr_runner_bin() { # → bin/cc-pane-runner, or rc 1
  local c
  for c in "${CC_PANE_RUNNER_BIN:-}" "${LR_LIB_DIR:-}/../../bin/cc-pane-runner" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/cc-pane-runner" "$HOME/.claude/bin/cc-pane-runner"; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# ── THE PANE ARGV every recovered window is launched with ────────────────────────────────────────
# RUNNER-ROOTED (MEASURED, docs/research/lr100p-2026-09-09/q-survivability-spawn.md § PA): the window
# runs `$SHELL -l -i -c 'exec "$CC_PANE_RUNNER"'`; bin/cc-pane-runner runs `bash <launcher>` under an
# interactive login shell and then execs a shell. The command arrives by ARGV (no typing race), the
# window SURVIVES a launcher refusal with the message on screen, ~/.zshrc synthesises ITERM_SESSION_ID
# (the registry row is written), and pane_shell_root reads `yes` — the pane is recyclable next time.
# `-- /bin/bash <launcher>` (today's shape) dies with the launcher and is what left panes 625/632
# un-recyclable; it survives only as the fallback when no runner is installed.
# shellcheck disable=SC2034  # this lib's OUTPUT contract, read by lr-handoff.sh / the poller (a directive binds to the NEXT construct only, hence one line)
LR_LAUNCH_TAIL=(); LR_SPAWN_SHAPE=""
# SC2034: LR_LAUNCH_TAIL/LR_SPAWN_SHAPE are this lib's OUTPUT contract, read by lr-handoff.sh and
# the poller — the directive above the declarations binds to that ONE construct, never into here.
# SC2016: the single quotes are the point — $CC_PANE_RUNNER must expand in the SPAWNED shell.
# shellcheck disable=SC2034,SC2016
lr_launch_tail() { # $1=launcher path → fills LR_LAUNCH_TAIL[] and LR_SPAWN_SHAPE (runner|argv)
  local r
  if r="$(lr_runner_bin)"; then
    LR_LAUNCH_TAIL=(--env "CC_PANE_CMD=bash $1" --env "CC_PANE_CMD_INTERACTIVE=1" --env "CC_PANE_RUNNER=$r"
                    -- "${SHELL:-/bin/zsh}" -l -i -c 'exec "$CC_PANE_RUNNER"')
    LR_SPAWN_SHAPE="runner"
  else
    LR_LAUNCH_TAIL=(-- /bin/bash "$1")
    LR_SPAWN_SHAPE="argv"
  fi
}

# ── A VISIBLE kitty window for a recovery, from any context ──────────────────────────────────────
# os-window when there is no anchor; a vsplit BESIDE the anchor pane (never beside the caller) when
# one is given — --source-window pins `current` to the anchor (without it kitty resolves against the
# operator's ACTIVE window: the 2026-08-07 pane-theft class, re-measured 2026-09-09). No --title (it
# is sticky and would freeze the ✳/◐ liveness glyph); provenance rides in --var, which kitty @ ls
# exposes as user_vars and no child can forge. Prints the new window id; rc 1 when nothing launched.
lr_kitty_spawn() { # $1=launcher $2=cwd $3=sid $4=target account [$5=anchor pane id]
  local launcher="$1" cwd="$2" sid="$3" acct="$4" anchor="${5:-}" sock="" kb id
  # A socket addresses a kitty from ANY context (launchd); inside a kitty pane kitty resolves its own
  # listener from the environment, so a missing socket is not a refusal there.
  sock="$(lr_kitty_socket 2>/dev/null || true)"
  { [ -n "$sock" ] || [ -n "${KITTY_WINDOW_ID:-}" ]; } || return 1
  kb="$(lr_kitty_bin)" || return 1
  lr_launch_tail "$launcher"
  local to=(); [ -n "$sock" ] && to=(--to "$sock")
  local common=(--var "lr_continuation_of=$sid" --var "lr_source_pane=${anchor:-}" --var "lr_target_account=$acct")
  local surface=os-window
  case "$anchor" in
    ''|*[!0-9]*)
      id="$("$kb" @ ${to[@]+"${to[@]}"} launch --type=os-window --cwd="$cwd" "${common[@]}" "${LR_LAUNCH_TAIL[@]}" 2>/dev/null)" || return 1 ;;
    *)
      surface=window
      id="$("$kb" @ ${to[@]+"${to[@]}"} launch --type=window --location=vsplit --match "window_id:$anchor" --next-to "id:$anchor" \
            --source-window "id:$anchor" --cwd=current --dont-take-focus "${common[@]}" "${LR_LAUNCH_TAIL[@]}" 2>/dev/null)" || return 1 ;;
  esac
  id="$(printf '%s' "$id" | tr -d '[:space:]')"
  case "$id" in ''|*[!0-9]*) return 1 ;; esac
  # The row belongs HERE, where the surface is actually created — not in each caller. The log's
  # whole inference is "no row ⇒ this tree did not spawn it", and a primitive whose only rows are
  # written by whoever remembered to call afterwards cannot support it (pane-spawn coverage ratchet).
  command -v cc_log_pane_spawn >/dev/null 2>&1 && \
    cc_log_pane_spawn "$surface" kitty "$id" "$cwd" "lr_kitty_spawn ${LR_SPAWN_SHAPE:-?}-rooted continuation_of:${sid:0:8} target:$acct${anchor:+ anchor:$anchor}"
  printf '%s' "$id"
}
