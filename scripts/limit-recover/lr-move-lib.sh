#!/bin/bash
# lr-move-lib.sh — the shared primitives of the move lane (`cc-lr plan` / `cc-lr move`,
# design-swap-v3, 2026-10-04). SOURCED, after lr-lib.sh, by bin/cc-lr, lr-move-batch.sh and
# lr-move-worker.sh. Everything here READS, except the slot semaphore and the event appender.
#
# WHY A SEPARATE FILE AND NOT lr-lib.sh: lr-lib.sh is sourced by hooks and by every poller tick;
# these functions are used by one lane and cost nothing to the rest when they are not loaded.
#
#   lr_move_verdict        the outcome of one move, re-derived from disk and `ps` every time
#   lr_session_location    which stores hold a LIVE transcript of a session
#   lr_swap_slot_*         the one shared resource: a semaphore taken BEFORE /exit
#   lr_move_event          per-stage timestamps (events.jsonl), the lane's only telemetry
#
# THE VERDICT IS NEVER PARSED FROM PROSE. The lane it replaces decided SWITCHED / NOTMOVED from the
# subject's last assistant text and from "two calm reads" of a transcript mtime; on 2026-10-04 it
# quoted a 23-hour-old reply as a fresh decline (pane 222), reported SWITCHED for a session that
# could no longer take a prompt (762a6daa, a stale tombstone in its target), and one NOTMOVED was
# false nine minutes later (98aae987). Every conjunct below is a file or a process fact, and
# `cc-lr move --status` recomputes all of them at any time, after a crash or a reboot.

lr_move_state() { printf '%s' "${LR_STATE_DIR:-$HOME/.reso/limit-recover}"; }
lr_move_dir() { printf '%s/move/%s' "$(lr_move_state)" "$1"; }

# ONE ACCOUNT, TWO SPELLINGS (critic 8). ~/.claude and ~/.claude-next are one account: the registry
# writes `claude` or `claude-next` for it, `~/.claude-next/projects` is a symlink to
# `~/.claude/projects`, and lr-handoff relaunches target `next` under ~/.claude-next. A raw compare
# of names or of config dirs would fail every move onto or off `next`. So accounts are compared
# FOLDED and stores by the PHYSICAL path of projects/; only the process environment (P2) is compared
# byte-exact, because that string is what selects among `next`'s three Keychain items.
lr_move_fold() { # $1=a config dir, its basename, or a registry .account → the folded account key
  local b="${1%/}"; b="${b##*/}"; b="${b#.}"
  case "$b" in claude|claude-next) printf 'claude' ;; *) printf '%s' "$b" ;; esac
}
lr_move_phys() { # $1=config dir → the physical path of its projects/ (the string itself when absent)
  (cd "$1/projects" 2>/dev/null && pwd -P) || printf '%s/projects' "${1%/}"
}

lr_session_location() { # $1=sid [$2=cwd] → one "<config dir>\t<transcript>" per LIVE <sid>.jsonl, one per physical store
  local sid="$1" cwd="${2:-}" c f slug hits=""
  # THE KNOWN PATH BEFORE THE GLOB. `projects/*/<sid>.jsonl` walks ~18,200 dirs in each of 4 stores:
  # 1.0 CPU-s a verdict, and the prove step ran 604-685 s after rc 6 on 2026-10-18 (lr-inplace-
  # immediacy raw/F § 4). Claude Code writes a transcript at projects/<slug(cwd)>/ — the encoder
  # lr_team_member uses, every non-alphanumeric byte → `-` — and the move lane relaunches with the
  # plan row's cwd, so a copy left in the source and the one in the target sit at the same slug.
  # So with a cwd every store is stat'ed at that slug; any hit answers and NO store is globbed. Only
  # when no store holds it there (a cwd that changed, a symlinked spelling) does the glob run, in
  # every store. Kill switch: LR_MOVE_LOCATION_FAST=off globs always.
  if [ -n "$cwd" ] && [ "$cwd" != - ] && [ "${LR_MOVE_LOCATION_FAST:-on}" != off ]; then
    slug="$(printf %s "$cwd" | LC_ALL=C sed 's/[^a-zA-Z0-9]/-/g')"
    hits="$(lr_config_dirs | while IFS= read -r c; do
      [ -n "$c" ] && [ -f "$c/projects/$slug/$sid.jsonl" ] && printf '%s\t%s\n' "$c" "$c/projects/$slug/$sid.jsonl"
    done)"
    [ -z "$hits" ] || { printf '%s\n' "$hits"; return 0; }
  fi
  lr_config_dirs | while IFS= read -r c; do
    [ -n "$c" ] || continue
    for f in "$c"/projects/*/"$sid".jsonl; do
      [ -f "$f" ] && { printf '%s\t%s\n' "$c" "$f"; break; }
    done
  done
  return 0
}

# The environment of a live process, for P2. `ps -E` prints it after the argv for the caller's own
# processes; a config dir holds no blank, so the token ends at the next one. Seam: LR_MOVE_ENV_DIR
# holds one file per pid (a fixture's stand-in for `ps -E`).
lr_move_pid_cfg() { # $1=pid → the CLAUDE_CONFIG_DIR that process was started with, or nothing
  if [ -n "${LR_MOVE_ENV_DIR:-}" ]; then cat "$LR_MOVE_ENV_DIR/$1" 2>/dev/null || true; return 0; fi
  ps -E -o command= -p "$1" 2>/dev/null | tr ' ' '\n' | sed -n 's/^CLAUDE_CONFIG_DIR=//p' | sed -n '1p'
}

lr_move_holders() { # $1=sid → the DISTINCT live pids holding it (registry rows ∪ --resume leaves), one per line
  { lr_registry_live_rows "$1" 2>/dev/null | cut -f2; lr_resume_procs "$1" 2>/dev/null; } | awk 'NF && !s[$1]++'
}

# THE PLAN ROW'S PID, the holder neither list above can see. On 2026-10-18 e3dedc17 was alive in
# pane 201 with no registry row (session-register.sh loses rows under load) and no `--resume` in its
# argv, so the verdict said STRANDED "no live process holds the session" over a live session
# (lr-inplace-immediacy raw/C, batch 20261018T020022Z). The census that wrote the plan saw its pid.
# That pid still names the session only if it is the SAME process: alive, a claude (argv[0], or a
# wrapper's — cc-close-attrib runs `bash <wrapper> <claude> …` — within its first three words), and
# started no later than the plan was written, so a pid reused since the census does not count. The
# 2 s of slack covers etime's whole-second truncation against a plan written in the same second.
lr_move_plan_holder() { # $1=pid $2=plan.json → 0 when that pid is still the process the plan's census saw
  local pid="$1" plan="$2" et age mt
  case "$pid" in ''|-|*[!0-9]*) return 1 ;; esac
  [ -f "$plan" ] && kill -0 "$pid" 2>/dev/null || return 1
  ps -o command= -p "$pid" 2>/dev/null \
    | awk '{ for (i = 1; i <= 3 && i <= NF; i++) if ($i ~ /(^|\/)claude$/) f = 1 } END { exit !f }' || return 1
  et="$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')"
  age="$(printf '%s\n' "$et" | awk -F'[-:]' 'NF == 4 { print $1*86400 + $2*3600 + $3*60 + $4; next }
    NF == 3 { print $1*3600 + $2*60 + $3; next } NF == 2 { print $1*60 + $2 }')"
  mt="$(date -r "$plan" +%s 2>/dev/null)"
  case "$age$mt" in ''|*[!0-9]*) return 1 ;; esac
  [ $(( $(date +%s) - age )) -le $(( mt + 2 )) ]
}

# ── THE VERDICT ──────────────────────────────────────────────────────────────────────────────────
#   P1  the registry row for the ORIGINAL pane names this session on the target account, and its
#       (pid, lstart) is a live process;
#   P2  that process was started with CLAUDE_CONFIG_DIR == the target config dir, byte-exact;
#   P3  exactly one live transcript exists, and it is in the target store;
#   P4  no tombstone beside that transcript names another account (the A→B→A deafness);
#   P5  the session has exactly one live holder, and it is the P1 process;
#   P6  the batch was admitted with the target ranked by the router (its auth was ok at admit), or
#       on the operator's explicit --target-unverified;
#   P7  the session's resume debt is not open.
# Verdicts (the action-partitioned vocabulary of VOLUNTARY_ACCOUNT_SWITCH §6):
#   MOVED               P1-P7
#   MOVED-NEW-PANE      P2-P7 with the live row in ANOTHER pane (the debt rescue relaunched it)
#   MOVED-UNREGISTERED  P2-P7 by process alone: no registry row names the session, and its one
#                       holder runs under the target. session-register.sh has a 5 s timeout and
#                       loses rows at load 30-50 (critic 7); a lost row is not a failed move, so
#                       this is reported and does not page.
#   NOTMOVED            the session is live in its original pane on the source, one copy: untouched
#   STRANDED            no live holder at all
#   FAILED              anything else, naming the first conjunct that does not hold
# stdout: "<VERDICT>\t<reason>\t<pid or ->\t<p1..p7 as 0/1>". Always rc 0; it writes nothing.
lr_move_verdict() { # $1=sid $2=pane $3=source config dir $4=target config dir [$5=batch dir]
  local sid="$1" pane="$2" from="$3" to="$4" bdir="${5:-}" regdir rows holders nh=0 pid="" shape=""
  local r_pane r_pid r_acct row_lst locs nloc=0 lcfg="" ltx="" tomb tto dstate got
  local p1=0 p2=0 p3=0 p4=0 p5=0 p6=0 p7=0 fto ffrom pcwd="-" ppid="-"
  regdir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
  fto="$(lr_move_fold "$to")"; ffrom="$(lr_move_fold "$from")"
  # The batch's plan row: its cwd is where the transcript sits (lr_session_location's known path),
  # its pid the holder its census saw (lr_move_plan_holder). Padded at the emitter: tab is IFS
  # whitespace, so an empty cwd would shift the pid into it.
  if [ -n "$bdir" ] && [ -f "$bdir/plan.json" ]; then
    IFS=$'\t' read -r pcwd ppid <<EOF
$(jq -r --arg s "$sid" 'first(.rows[] | select(.sid == $s)) | [(if (.cwd // "") == "" then "-" else .cwd end), (if (.pid // "") == "" then "-" else (.pid | tostring) end)] | @tsv' "$bdir/plan.json" 2>/dev/null)
EOF
    pcwd="${pcwd:--}"; ppid="${ppid:--}"
  fi
  holders="$(lr_move_holders "$sid")"
  [ -z "$holders" ] || nh="$(printf '%s\n' "$holders" | grep -c .)"
  # Kill switch: LR_MOVE_PLAN_PID_HOLDER=off reads only the registry and the --resume census.
  if [ "$nh" -eq 0 ] && [ "${LR_MOVE_PLAN_PID_HOLDER:-on}" != off ] && lr_move_plan_holder "$ppid" "$bdir/plan.json"; then
    holders="$ppid"; nh=1
  fi
  locs="$(lr_session_location "$sid" "$pcwd")"
  [ -z "$locs" ] || nloc="$(printf '%s\n' "$locs" | grep -c .)"
  if [ "$nloc" -ge 1 ]; then
    lcfg="$(printf '%s\n' "$locs" | sed -n '1p' | cut -f1)"; ltx="$(printf '%s\n' "$locs" | sed -n '1p' | cut -f2)"
  fi
  rows="$(lr_registry_live_rows "$sid" 2>/dev/null || true)"
  while IFS=$'\t' read -r r_pane r_pid r_acct _; do
    [ -n "$r_pane" ] || continue
    if [ "$r_pane" = "$pane" ] && [ "$(lr_move_fold "$r_acct")" = "$fto" ]; then shape=moved; pid="$r_pid"; break; fi
    if [ "$r_pane" = "$pane" ] && [ "$(lr_move_fold "$r_acct")" = "$ffrom" ]; then shape=source; pid="$r_pid"; continue; fi
    if [ "$(lr_move_fold "$r_acct")" = "$fto" ] && [ -z "$shape" ]; then shape=newpane; pid="$r_pid"; fi
  done <<EOF
$rows
EOF
  if [ "$nh" -eq 0 ]; then
    dstate="$(jq -r '.state // empty' "${CC_RESUME_DEBT_DIR:-$HOME/.claude/autonomy/resume-debt}/meta/$sid.json" 2>/dev/null || true)"
    printf 'STRANDED\tno live process holds the session (resume debt: %s)\t-\t0000000\n' "${dstate:-none}"; return 0
  fi
  if [ "$shape" = source ]; then
    if [ "$nh" -eq 1 ] && [ "$nloc" -eq 1 ] && [ "$(lr_move_phys "$lcfg")" = "$(lr_move_phys "$from")" ]; then
      printf 'NOTMOVED\tlive in pane %s on the source, one copy\t%s\t0000000\n' "$pane" "$pid"; return 0
    fi
    printf 'FAILED\tsource-ambiguous: pane %s still shows the session on the source, with %s holder(s) and %s live transcript(s)\t%s\t0000000\n' "$pane" "$nh" "$nloc" "$pid"; return 0
  fi
  if [ -z "$shape" ]; then
    # No registry row places it. One holder, running under the target, is a move whose row was lost.
    pid="$(printf '%s\n' "$holders" | sed -n '1p')"
    shape=unregistered
    # ...and one holder running under the SOURCE, with its one transcript there, is a session the
    # move never touched (e3dedc17: lr-handoff refused it for want of a row): NOTMOVED, as a row would say.
    if [ "$nh" -eq 1 ] && [ "$nloc" -eq 1 ] && [ "$(lr_move_phys "$lcfg")" = "$(lr_move_phys "$from")" ] \
       && [ "$(lr_move_phys "$(lr_move_pid_cfg "$pid")")" = "$(lr_move_phys "$from")" ]; then
      printf 'NOTMOVED\tlive on the source, one copy, held by pid %s with no registry row\t%s\t0000000\n' "$pid" "$pid"; return 0
    fi
  fi
  # P1: the row's process is the one that is alive (a row with no recorded lstart is judged by pid).
  if [ "$shape" != unregistered ]; then
    row_lst="$(jq -r --arg s "$sid" 'select((.session_id // .sessionId) == $s) | .lstart // empty' "$regdir"/*.json 2>/dev/null \
      | sed -n '1p' | tr -s '[:blank:]' ' ' | sed -e 's/^ //' -e 's/ $//')"
    got="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$pid" 2>/dev/null | tr -s '[:blank:]' ' ' | sed -e 's/^ //' -e 's/ $//')"
    if kill -0 "$pid" 2>/dev/null && { [ -z "$row_lst" ] || [ -z "$got" ] || [ "$row_lst" = "$got" ] \
         || [ "$row_lst" = "$(ps -o lstart= -p "$pid" 2>/dev/null | tr -s '[:blank:]' ' ' | sed -e 's/^ //' -e 's/ $//')" ]; }; then p1=1; fi
  fi
  [ "$(lr_move_pid_cfg "$pid")" = "${to%/}" ] && p2=1
  if [ "$nloc" -eq 1 ] && [ "$(lr_move_phys "$lcfg")" = "$(lr_move_phys "$to")" ]; then p3=1; fi
  if [ -n "$ltx" ]; then
    tomb="${ltx%.jsonl}.HANDOFF.json"
    if [ ! -f "$tomb" ]; then p4=1
    else
      tto="$(jq -r '.handed_off_to // empty' "$tomb" 2>/dev/null || true)"
      if [ -z "$tto" ] || [ "$(lr_move_fold "$tto")" = "$fto" ]; then p4=1; fi
    fi
  fi
  if [ "$nh" -eq 1 ] && [ "$(printf '%s\n' "$holders" | sed -n '1p')" = "$pid" ]; then p5=1; fi
  if [ -z "$bdir" ]; then p6=1
  else
    # `unverified-accepted` is the operator's own --target-unverified, recorded by the batch runner.
    case "$(jq -r 'if .admitted == true then (.target_auth // "") else "" end' "$bdir/admit.json" 2>/dev/null || true)" in
      ok|unverified-accepted) p6=1 ;;
    esac
  fi
  dstate="$(jq -r '.state // empty' "${CC_RESUME_DEBT_DIR:-$HOME/.claude/autonomy/resume-debt}/meta/$sid.json" 2>/dev/null || true)"
  case "$dstate" in open|retrying|escalated) p7=0 ;; *) p7=1 ;; esac
  local flags="$p1$p2$p3$p4$p5$p6$p7" why=""
  if [ "$p2$p3$p4$p5$p6$p7" = 111111 ]; then
    case "$shape" in
      moved)        if [ "$p1" = 1 ]; then printf 'MOVED\tpane %s runs the session on the target, one copy\t%s\t%s\n' "$pane" "$pid" "$flags"; return 0; fi ;;
      newpane)      if [ "$p1" = 1 ]; then printf 'MOVED-NEW-PANE\tthe session runs on the target in another pane (the resume-debt rescue relaunched it)\t%s\t%s\n' "$pid" "$flags"; return 0; fi ;;
      unregistered) printf 'MOVED-UNREGISTERED\tthe session runs on the target, but no registry row names it (a lost SessionStart row)\t%s\t%s\n' "$pid" "$flags"; return 0 ;;
    esac
  fi
  if   [ "$p1" = 0 ] && [ "$shape" != unregistered ]; then why="P1 registry: the row's process (pid $pid) is not the live one it recorded"
  elif [ "$p2" = 0 ]; then why="P2 environment: pid $pid runs under '$(lr_move_pid_cfg "$pid")', not $to"
  elif [ "$p3" = 0 ]; then why="P3 transcript: $nloc live transcript(s); the one read is under ${lcfg:-nothing}, not $to"
  elif [ "$p4" = 0 ]; then why="P4 tombstone: $tomb names $tto, so the prompt guard blocks this session (cc-lr repair-markers --sid $sid)"
  elif [ "$p5" = 0 ]; then why="P5 holders: $nh live holder(s) ($(printf '%s' "$holders" | tr '\n' ' ')), expected only pid $pid"
  elif [ "$p6" = 0 ]; then why="P6 admission: the batch has no admission record with the target ranked by the router"
  elif [ "$p7" = 0 ]; then why="P7 resume debt: still $dstate"
  else why="unclassified shape $shape"
  fi
  printf 'FAILED\t%s\t%s\t%s\n' "$why" "${pid:--}" "$flags"
  return 0
}

# ── THE SLOT SEMAPHORE: taken BEFORE /exit, released at the first proof read ─────────────────────
# The lane's only shared resource. What it bounds is the burst the box has never been measured
# above: more than 4 concurrent kitty RPC streams, and more than 4 overlapping TUI boots (the
# largest overlap in the 49 boots on record). A slot is held from before the actuator's first pane
# read until the session is seen running on the target, so a queued move waits with its claude
# still ALIVE in its pane. The two rejected designs took a boot slot after /exit, where a queued
# pane waits at a bare shell past the point of no return.
#   · indexed mkdir slots under <state>/locks/swap-slots, each holding (pid, lstart): a dead or
#     pid-reused holder is taken over by the next acquirer (lr_pidlock_live);
#   · the SAME directory is the reconciler's boot-slot mirror (lr_recon/admit.py BootSlots), so the
#     two dispatchers are bounded together rather than each by its own counter (critic 11);
#   · width LR_MOVE_SLOTS, default 4 until a canary measures a safe width.
lr_swap_slot_dir() { printf '%s/locks/swap-slots' "$(lr_move_state)"; }
LR_SWAP_SLOT=""
lr_swap_slot_acquire() { # $1=width → 0 taken (LR_SWAP_SLOT set) · 1 none free
  local w="${1:-4}" root i=1 d
  case "$w" in ''|*[!0-9]*) w=4 ;; esac
  [ "$w" -ge 1 ] || w=1
  root="$(lr_swap_slot_dir)"
  mkdir -p "$root" 2>/dev/null || return 1
  while [ "$i" -le "$w" ]; do
    d="$root/slot-$i"; i=$((i + 1))
    if mkdir "$d" 2>/dev/null; then
      lr_pidlock_stamp "$d" "$$" || { rmdir "$d" 2>/dev/null; continue; }
      LR_SWAP_SLOT="$d"; return 0
    fi
    lr_pidlock_live "$d" && continue
    # A holder that is gone. A slot younger than 10 s with no pid yet is a taker between its mkdir
    # and its stamp, not an orphan.
    if [ ! -s "$d/pid" ] && [ -z "$(find "$d" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then continue; fi
    if mv "$d" "$d.dead.$$" 2>/dev/null; then
      rm -f "$d.dead.$$/pid" "$d.dead.$$/lstart" 2>/dev/null; rmdir "$d.dead.$$" 2>/dev/null || true
      if mkdir "$d" 2>/dev/null; then
        lr_pidlock_stamp "$d" "$$" || { rmdir "$d" 2>/dev/null; continue; }
        LR_SWAP_SLOT="$d"; return 0
      fi
    fi
  done
  return 1
}
lr_swap_slot_release() { # removes ONLY a slot this process holds
  local d="${LR_SWAP_SLOT:-}"
  [ -n "$d" ] && [ -d "$d" ] || { LR_SWAP_SLOT=""; return 0; }
  if [ "$(cat "$d/pid" 2>/dev/null || true)" = "$$" ]; then
    rm -f "$d/pid" "$d/lstart" 2>/dev/null; rmdir "$d" 2>/dev/null || true
  fi
  LR_SWAP_SLOT=""
}
lr_swap_slots_held() { # → the number of slots whose holder is alive
  local d n=0
  for d in "$(lr_swap_slot_dir)"/slot-*; do
    [ -d "$d" ] || continue
    case "$d" in *.dead.*) continue ;; esac
    lr_pidlock_live "$d" && n=$((n + 1))
  done
  printf '%s' "$n"
}

# ── THE BATCH SUMMARY: EVERY MEMBER, A CASUALTY FIRST ─────────────────────────────────────────────
# Moved here from lr-move-batch.sh so a worker whose verdict lands AFTER its batch closed can
# rewrite the summary. Batch 20261017T073813Z-next2-next-26358 had 6 members: its watch bound
# passed at 08:04:43 with 9f6593c5's worker still running, the summary and its one mail at 08:06:37
# read "done: NOTMOVED=5", and that worker wrote STRANDED at 08:07:08, to a summary nobody re-read.
# Three rules now (record: tests/fixtures/move-lane-2026-10-17/batch):
#   · a driven member with no result is COUNTED, as RUNNING, and a batch holding one is `running`,
#     never `done`;
#   · STRANDED leads: the verdicts are ranked STRANDED, FAILED, RUNNING, then the rest, and each
#     stranded member is named with its reason ahead of the counts, in the summary and the mail;
#   · a late verdict rewrites the summary (lr_move_summary_late), and mails when it is a casualty or
#     settles the batch (no member left running; that mail is sent once).
# LEADING-PAREN CASE PATTERNS inside `$( )`, as everywhere in the lane: launchd runs the batch under
# /bin/bash 3.2, which ends a command substitution at a bare pattern's `)`.
lr_move_summary() { # $1=batch dir $2=batch $3=status $4=note $5=target auth after $6=batch start epoch → summary.json; LR_MOVE_SUMMARY_* set
  local bdir="$1" batch="$2" st="$3" note="$4" auth_after="${5:-unchecked}" t0="${6:-}" plan rows pend counts classes acts lead running stranded f sid
  plan="$bdir/plan.json"
  LR_MOVE_SUMMARY_FROM="$(jq -r '.from // empty' "$plan" 2>/dev/null)"
  LR_MOVE_SUMMARY_TO="$(jq -r '.to // empty' "$plan" 2>/dev/null)"
  LR_MOVE_SUMMARY_BY="$(jq -r '.requested_by // empty' "$plan" 2>/dev/null)"
  [ -n "$t0" ] || t0="$(jq -r '.ts // empty' "$plan" 2>/dev/null)"
  case "$t0" in (''|*[!0-9]*) t0="$(date +%s)" ;; esac
  # AN ABORT IS ITS OWN STATUS (D9, 2026-10-11). Batch 20261011T032613Z was aborted 18 s before it
  # was admitted and its summary and mail still read "done: NOTMOVED=7", the same words a failure
  # earns; the operator could not tell that the stop they asked for was the stop they got.
  [ ! -e "$bdir/abort" ] || st=aborted
  # ONE jq per row: verdict, reason class, the row's own instruction, sid8, and a stranded row's reason
  # up to its first `;`. The class is the reason's leading `word:` tag (became-limited, claim-held,
  # worker-died ...) or `aborted`; a MOVED row gets none. The instruction is the first `cc-lr <verb>
  # ...` the reason names — the "Recover it: cc-lr recover <sid8>" a became-limited row carries.
  rows="$(for f in "$bdir"/*.json; do
            case "${f##*/}" in (plan.json|admit.json|summary.json|request*.json|*.watcher.json) continue ;; esac
            jq -r '(.verdict // "") as $v | (.reason // "") as $r | select($v != "")
                   | [$v,
                      (if ($v | startswith("MOVED")) then ""
                       elif ($r | test("^[a-z][a-z-]*:")) then ($r | sub(":.*$"; ""))
                       elif ($r | test("abort")) then "aborted"
                       elif ($r | startswith("batch refused")) then "refused"
                       else "" end),
                      (($r | [match("cc-lr [a-z][a-z-]*[^;)]*"; "g").string] | first // "") | sub("[ .]+$"; "")),
                      ((.sid // "") | .[0:8]),
                      (if $v == "STRANDED" then ($r | sub(";.*$"; "") | .[0:160]) else "" end)] | @tsv' "$f" 2>/dev/null
          done)"
  # Every driven member (act move|wait) with no result yet is RUNNING: its worker outlived the watch.
  pend="$(jq -r '.rows[]? | select(.act == "move" or .act == "wait") | .sid // empty' "$plan" 2>/dev/null \
          | while IFS= read -r sid; do
              [ -n "$sid" ] && [ ! -e "$bdir/$sid.json" ] && printf 'RUNNING\t\t\t%s\t\n' "${sid:0:8}"
            done)"
  [ -z "$pend" ] || rows="$rows${rows:+$'\n'}$pend"
  counts="$(printf '%s\n' "$rows" | awk -F'\t' '$1 != "" { print $1 }' | sort | uniq -c \
            | awk '{ r = 3; if ($2 == "STRANDED") r = 0; else if ($2 == "FAILED") r = 1; else if ($2 == "RUNNING") r = 2
                     printf "%d\t%s=%s\n", r, $2, $1 }' \
            | sort -t "$(printf '\t')" -k1,1n -k2,2 | cut -f2 | awk '{ printf "%s%s", (NR > 1 ? " " : ""), $0 }')"
  classes="$(printf '%s\n' "$rows" | awk -F'\t' '$1 != "" && $2 != "" { print $1 "/" $2 }' | sort | uniq -c \
             | awk '{ printf "%s%s=%s", (NR > 1 ? " " : ""), $2, $1 }')"
  acts="$(printf '%s\n' "$rows" | awk -F'\t' '$3 != "" { printf "%s%s: %s", (n++ ? "; " : ""), $4, $3 }')"
  lead="$(printf '%s\n' "$rows" | awk -F'\t' '$1 == "STRANDED" { printf "%sSTRANDED %s%s", (n++ ? "; " : ""), $4, ($5 != "" ? ": " $5 : "") }')"
  stranded="$(printf '%s\n' "$rows" | awk -F'\t' '$1 == "STRANDED" { printf "%s%s", (n++ ? " " : ""), $4 }')"
  running="$(printf '%s\n' "$rows" | awk -F'\t' '$1 == "RUNNING" { printf "%s%s", (n++ ? " " : ""), $4 }')"
  LR_MOVE_SUMMARY_RUNNING="$(printf '%s' "$running" | awk '{ print NF }')"
  : "${LR_MOVE_SUMMARY_RUNNING:=0}"
  if [ "$LR_MOVE_SUMMARY_RUNNING" -gt 0 ]; then
    [ "$st" != "done" ] || st=running
    note="${note:+$note }$LR_MOVE_SUMMARY_RUNNING member(s) had no verdict yet ($running): each worker writes its own, and this summary is rewritten and mailed again when the last one lands."
  fi
  jq -nc --arg b "$batch" --arg st "$st" --arg note "$note" --arg c "${counts:-none}" --arg a "$auth_after" \
        --arg cls "$classes" --arg acts "$acts" --arg lead "$lead" --arg str "$stranded" --arg run "$running" \
        --argjson wall "$(( $(date +%s) - t0 ))" --arg from "$LR_MOVE_SUMMARY_FROM" --arg to "$LR_MOVE_SUMMARY_TO" \
        '{batch:$b, status:$st, note:$note, lead:$lead, verdicts:$c, reasons:$cls, actions:$acts,
          stranded:($str | split(" ") | map(select(. != ""))), running:($run | split(" ") | map(select(. != ""))),
          target_auth_after:$a, wall_s:$wall, from:$from, to:$to}' \
        > "$bdir/summary.json.$$.tmp" 2>/dev/null && mv -f "$bdir/summary.json.$$.tmp" "$bdir/summary.json" 2>/dev/null
  LR_MOVE_SUMMARY_TEXT="$st: ${lead:+$lead — }${counts:-no rows}${classes:+ ($classes)}"
  # shellcheck disable=SC2034  # read by lr-move-batch.sh's summary(), the caller that says it
  LR_MOVE_SUMMARY_LINE="$LR_MOVE_SUMMARY_TEXT (target auth after: $auth_after) $note${acts:+ Still to do: $acts.}"
  LR_MOVE_SUMMARY_MAIL="cc-lr move $batch ($LR_MOVE_SUMMARY_FROM -> $LR_MOVE_SUMMARY_TO) $LR_MOVE_SUMMARY_TEXT; target auth after the batch: $auth_after. $note${acts:+ Still to do: $acts.} Details: cc-lr move --status $batch"
  return 0
}

lr_move_summary_mail() { # → mails LR_MOVE_SUMMARY_MAIL to the requester only, never to a moved pane (a mailed no-prompt resume takes a turn)
  local notify="${CC_NOTIFY_BIN:-$HOME/.claude/bin/cc-notify}" by="${LR_MOVE_SUMMARY_BY:-}"
  if [ "${CC_LR_MOVE_MAIL:-on}" != off ] && [ -n "$by" ] && [ "$by" != "?" ] && [ -x "$notify" ]; then
    "$notify" "$by" "$LR_MOVE_SUMMARY_MAIL" >/dev/null 2>&1 || true
  fi
  return 0
}

# A VERDICT THAT LANDS AFTER ITS BATCH CLOSED (the 9f6593c5 row above). Called by the worker after its
# result is written, and by the batch itself after a `running` close, for a row that landed between
# its scan and its summary. Rewrites the summary from disk (status `running` becomes `done` once no
# member is left), and mails when a member that was running is now STRANDED or FAILED, or when the
# batch settles; the settle mail is claimed once (summary.settled), so two last workers send one.
# A batch not yet closed (no summary.json) is left alone: its own close counts this row.
lr_move_summary_late() { # $1=batch dir $2=batch → rc 0 always
  local bdir="$1" batch="$2" st auth was v s f n=0 casualty="" mail=0
  [ -s "$bdir/summary.json" ] || return 0
  until mkdir "$bdir/summary.lock" 2>/dev/null; do
    n=$((n + 1)); [ "$n" -lt 50 ] || break        # a wedged holder costs a possible duplicate mail, never the mail
    sleep 0.2
  done
  st="$(jq -r '.status // "done"' "$bdir/summary.json" 2>/dev/null)"; [ "$st" != running ] || st="done"
  auth="$(jq -r '.target_auth_after // "unchecked"' "$bdir/summary.json" 2>/dev/null)"
  was="$(jq -r '(.running // [])[]' "$bdir/summary.json" 2>/dev/null)"
  for s in $was; do
    for f in "$bdir/$s"*.json; do
      case "${f##*/}" in (*.watcher.json) continue ;; esac
      [ -f "$f" ] || continue
      v="$(jq -r '.verdict // empty' "$f" 2>/dev/null)"
      case "$v" in (STRANDED|FAILED) casualty="${casualty:+$casualty, }$s $v" ;; esac
    done
  done
  lr_move_summary "$bdir" "$batch" "$st" "${casualty:+Late verdict: $casualty.}" "$auth" ""
  [ -z "$casualty" ] || mail=1
  if [ "$LR_MOVE_SUMMARY_RUNNING" = 0 ] && mkdir "$bdir/summary.settled" 2>/dev/null; then mail=1; fi
  if [ -n "$was" ] && [ "$mail" = 1 ]; then lr_move_summary_mail; fi
  rmdir "$bdir/summary.lock" 2>/dev/null || true
  return 0
}

lr_move_event() { # $1=batch dir $2=sid $3=stage [$4=detail] → one {stage,t_ms,detail} line; always rc 0
  local ms
  ms="$(/usr/bin/python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo "$(date +%s)000")"
  jq -nc --arg st "$3" --argjson t "$ms" --arg d "${4:-}" '{stage:$st, t_ms:$t} + (if $d != "" then {detail:$d} else {} end)' \
    >> "$1/$2.events.jsonl" 2>/dev/null || true
  return 0
}
