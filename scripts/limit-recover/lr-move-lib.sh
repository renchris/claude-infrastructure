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

lr_session_location() { # $1=sid → one "<config dir>\t<transcript>" per LIVE <sid>.jsonl, one per physical store
  local sid="$1" c f
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
  local p1=0 p2=0 p3=0 p4=0 p5=0 p6=0 p7=0 fto ffrom
  regdir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
  fto="$(lr_move_fold "$to")"; ffrom="$(lr_move_fold "$from")"
  holders="$(lr_move_holders "$sid")"
  [ -z "$holders" ] || nh="$(printf '%s\n' "$holders" | grep -c .)"
  locs="$(lr_session_location "$sid")"
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

lr_move_event() { # $1=batch dir $2=sid $3=stage [$4=detail] → one {stage,t_ms,detail} line; always rc 0
  local ms
  ms="$(/usr/bin/python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo "$(date +%s)000")"
  jq -nc --arg st "$3" --argjson t "$ms" --arg d "${4:-}" '{stage:$st, t_ms:$t} + (if $d != "" then {detail:$d} else {} end)' \
    >> "$1/$2.events.jsonl" 2>/dev/null || true
  return 0
}
