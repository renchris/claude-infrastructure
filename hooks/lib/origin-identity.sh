#!/usr/bin/env bash
# hooks/lib/origin-identity.sh — the ONE sourceable origin/fired-peer oracle (CLOSE_INTEGRITY W1).
#
# WHY THIS LIB EXISTS (docs/plans/CLOSE_INTEGRITY_2026-08-10.md, recon report-seams §0/§7):
#   · The origin-vs-fired-peer discriminator — the fired-peer stamp
#     ${CC_FIRED_DIR:-~/.claude/cc-fired}/<paneUUID>.json, ABSENT ⇒ origin — was readable only via
#     inline functions in scripts/handoff-fire.sh (a 7660-line dispatcher no hook can source) plus a
#     SECOND, divergently-modelled copy in bin/cc-classify:413. Zero Stop hooks could ask the one
#     question the Session Close Protocol turns on ("is this an ORIGIN session?"), and a third
#     hand-rolled copy is the exact trap hooks/lib/agent-identity.sh:4-11 was extracted to close.
#   · These function BODIES moved here verbatim from scripts/handoff-fire.sh (which now sources this
#     lib), so producer and consumers share one state model — MEMORY.md
#     sibling-auditors-must-share-the-state-model.
#
# THE SPENT STATE (new here, CLOSE_INTEGRITY W1 — the 1b hole in report-seams):
#   fired_stamp_tenancy previously answered cwd-tenancy only and NEVER read `closedAt`, so a stamp
#   already used up by a completed self-close still read `valid` for the next tenant of a REUSED
#   kitty id in the same cwd. Consequences, both real: a genuine ORIGIN session inherited a
#   self-retiring contract (the exact "watched pane vanishes" polarity the tenancy check was built
#   against), and any origin-gated consumer silently skipped it. `spent` names that state. A spent
#   stamp authorises nothing by itself; the fire MARKER recorded in the stamp is the proof that
#   separates the two spent cases (same session retrying an interrupted close — marker IS in its
#   transcript — vs a new tenant — marker is not).
#
# CONSUMER POLARITY (deliberately different, stated so it cannot drift):
#   · self-close (handoff-fire origin gate): ambiguity REFUSES the close — refusing never loses
#     work; closing wrongly does. `unknown` keeps its pre-spent meaning there (old behavior).
#   · close-contract hooks (completion-assert D6): ambiguity maps to ORIGIN — the consumer is a
#     bounded, latched, capped block, so a false fire costs ≤MAX blocked stops, while a false
#     "fired-peer" silently exempts a real origin session from the close contract forever. That
#     mapping lives in oi_origin_class below and ONLY there.
#
# Env seams: CC_FIRED_DIR · CC_SELFCLOSE_TENANCY (=0 ⇒ tenancy answers `unknown`, R8 kill switch).
# Dependencies: jq + shasum only. No caller globals — _oi_now is self-contained (handoff-fire's
# _iso_now stays its own; the two emit the identical format).
# shellcheck shell=bash

_oi_now() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true; }

oi_fired_dir() { printf '%s' "${CC_FIRED_DIR:-$HOME/.claude/cc-fired}"; }

# ---- THE cwd INDEX (item 1467ea1dad4f) --------------------------------------------------------
# THE DEFECT. The stamp store is keyed on the pane id, and the pane id is VOLATILE: a resume, a
# crash-recreate or a kitty restart renumbers the pane and orphans its stamp under the old id.
# Measured 2026-08-07: pane 353 was found holding pane 351's orphaned stamp, and the lookup a
# self-closing session makes — `$FIRED_DIR/$my_pane.json` — simply MISSES. A miss is then read as
# "this session was never fired", which is the strongest possible wrong answer: it is the origin
# gate's REFUSE verdict, and the pane that earned the right to retire is told it never had it.
#
# THE DURABLE KEY IS cwd, for the reasons fired_stamp_tenancy states in its own header — the same
# writer records it, the closing pane knows its own with certainty without asking the terminal or
# the process table, and it is INDEPENDENT of the id namespace that is the entire defect. An id
# CHANGE moves the pane and keeps the cwd; an id REUSE keeps the number and changes the cwd.
#
# WHY AN INDEX AND NOT A RE-KEY OF THE STORE. Twenty-plus test files and thirteen readers construct
# `$FIRED_DIR/<pane>.json` directly, and mark_fired_peer's own header declares the record
# ADDITIVE-ONLY because bin/cc-reaper keys auto-reap on that exact path. So the RECORD stays
# pane-keyed and single, and only the LOOKUP gains a durable key — one pointer per cwd.
#
# WHY A SUBDIRECTORY, AND WHY THAT IS LOAD-BEARING. Three readers enumerate the store with
# `for f in "$FIRED_DIR"/*.json` and treat the FILENAME as a pane id (bin/cc-classify:406,
# selfclose_inventory_warn, scripts/desk-invariant.sh:288 — the last feeds max-mtime to heal_role).
# A glob does not recurse, so `by-cwd/` is invisible to all three by construction.
#
# WHY A POINTER AND NOT A COPY. record_close_succession writes `closedAt` to exactly one path — a
# twin would keep `closedAt:null` forever and every liveness test that reads it would read a spent
# stamp as OPEN. The pointer holds no state that can diverge.
_fired_cwd_key() { # $1=cwd → echoes a stable filesystem-safe key, or nothing
  local d="${1:-}" r
  [ -n "$d" ] || return 0
  # Resolve first: macOS hands out /tmp and /private/tmp for one directory and a worktree can be
  # reached through a symlink, so an unresolved path would mint two keys for one cwd — the same
  # normalisation fired_stamp_tenancy applies before comparing.
  r="$(cd "$d" 2>/dev/null && pwd -P)" || return 0
  [ -n "$r" ] || return 0
  printf '%s' "$r" | shasum -a 256 2>/dev/null | cut -c1-32 | tr -d '[:space:]'
}

write_fired_cwd_index() { # $1=fired-dir $2=pane $3=cwd → best-effort, always 0
  local dir="${1:-}" pane="${2:-}" cwd="${3:-}" key idx tmp
  [ -n "$dir" ] && [ -n "$pane" ] && [ -n "$cwd" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  key="$(_fired_cwd_key "$cwd")"; [ -n "$key" ] || return 0
  idx="$dir/by-cwd"
  mkdir -p "$idx" 2>/dev/null || return 0
  tmp="$idx/.$key.$$"
  # LAST WRITER WINS, deliberately. Two peers in one cwd is the collision this cannot resolve, and
  # the index is not the authority — every consumer re-validates against the pane-keyed RECORD and
  # falls back to the directory scan when the pointer does not check out. So a wrong pointer costs a
  # scan, never a wrong verdict (make-the-actuator-the-arbiter: the record is the arbiter).
  if jq -n --arg paneUUID "$pane" --arg cwd "$cwd" --arg at "$(_oi_now)" \
        '{paneUUID:$paneUUID, cwd:$cwd, indexedAt:$at}' > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv -f "$tmp" "$idx/$key.json" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

read_fired_cwd_index() { # $1=fired-dir $2=cwd → echoes the pane id, or nothing
  local dir="${1:-}" cwd="${2:-}" key f
  [ -n "$dir" ] && [ -n "$cwd" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  key="$(_fired_cwd_key "$cwd")"; [ -n "$key" ] || return 0
  f="$dir/by-cwd/$key.json"
  [ -s "$f" ] || return 0
  jq -r '.paneUUID // ""' "$f" 2>/dev/null || true
}

# ---- STAMP TENANCY (2026-08-05, item aba6bcbff6de; spent state added CLOSE_INTEGRITY W1) -------
# The origin gate used to ask ONE question of the stamp: is the file non-empty. cc-classify has
# never been satisfied with that: a later session reusing a previously-fired pane id inherited the
# stale self-retiring contract. Under iTerm2 the id is a 128-bit UUID and collision is not a thing;
# kitty ids are SMALL INTEGERS AND KITTY REUSES THEM (measured 2026-08-05: numeric stamps at 33…497
# against live ids 2–37 — id 33 was simultaneously a live window and an open stamp). A stale stamp
# authorising a live pane's suicide is the FALSE-POSITIVE polarity: refusing to close costs an idle
# pane; closing wrongly is a watched pane vanishing (memory handoff-succession-legibility).
#
# THE ORACLE IS cwd, NOT startedAt. The SAME writer records it (mark_fired_peer), the closing pane
# knows its own with certainty, and it is INDEPENDENT of the id namespace that is the defect. An id
# CHANGE moves the pane and keeps the cwd; an id REUSE keeps the number and changes the cwd.
#
# CALIBRATED TO ABSTAIN. Only a POSITIVE REFUTATION — both paths resolve, and they differ — returns
# `stale`. Everything unresolvable (no jq, no cwd field, a worktree since removed) returns
# `unknown`, which the self-close gate treats exactly as it treated every stamp before tenancy
# existed. CC_SELFCLOSE_TENANCY=0 disables it outright (R8).
#
# FIVE states: absent | valid | spent | stale | unknown.
#   `spent` (cwd matches AND closedAt is set): the contract under this id was already used up by a
#   completed self-close. It is NOT `valid` — the commonest way to reach it is kitty reusing the id
#   of a retired peer for a brand-new session in the same worktree, and before this state existed
#   that new tenant read `valid` and inherited a self-retiring contract it was never granted. The
#   one legitimate same-session case (a retry after record_close_succession ran but the physical
#   close failed) is distinguished by the fire MARKER in the session's own transcript — the caller
#   proves it via fired_marker_is_mine / a transcript grep, exactly as adoption does. Gated behind
#   the same CC_SELFCLOSE_TENANCY switch: =0 restores the pre-tenancy answer for every state.
fired_stamp_tenancy() { # $1=stamp-path $2=this-pane-cwd → echoes absent|valid|spent|stale|unknown
  local stamp="${1:-}" here="${2:-}" want got closed
  [ -n "$stamp" ] && [ -s "$stamp" ] || { printf 'absent'; return 0; }
  [ "${CC_SELFCLOSE_TENANCY:-1}" != 0 ] || { printf 'unknown'; return 0; }
  command -v jq >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  want="$(jq -r '.cwd // ""' "$stamp" 2>/dev/null || true)"
  [ -n "$want" ] || { printf 'unknown'; return 0; }
  # Resolve BOTH sides the same way. macOS hands out /tmp and /private/tmp for one directory, and a
  # worktree path can be reached through a symlink, so a raw string compare would manufacture a
  # mismatch and refuse a genuine peer. An unresolvable side is `unknown`, never `stale`.
  want="$(cd "$want" 2>/dev/null && pwd -P)" || true
  got="$(cd "${here:-.}" 2>/dev/null && pwd -P)" || true
  [ -n "$want" ] && [ -n "$got" ] || { printf 'unknown'; return 0; }
  if [ "$want" != "$got" ]; then printf 'stale'; return 0; fi
  # A jq read failure here must not demote a spent stamp to valid — `// "null"` + the x fallback
  # make every unreadable answer land on the SAFE side (spent refuses; valid authorises).
  closed="$(jq -r '.closedAt // "null"' "$stamp" 2>/dev/null || echo x)"
  if [ "$closed" = null ]; then printf 'valid'; else printf 'spent'; fi
}

# ---- oi_origin_class — the CLOSE-CONTRACT consumer's verdict ------------------------------------
# $1=pane $2=cwd [$3=transcript-path] → echoes fired-peer|origin|unknown. Always rc 0.
#
# This is the CONTRACT-polarity mapping (header): every state that does not POSITIVELY prove
# "fired peer" maps to `origin`, because the consumers are bounded/latched Stop-hook arms where a
# false block costs ≤cap turns and a false exemption is a silent, permanent miss. Do NOT reuse this
# mapping for self-close — the gate in handoff-fire keeps its own stricter arms.
#
# The transcript is the PROOF channel (same discriminator as adoption): a fired peer's transcript
# contains the fire MARKER the stamp records, because the marker rode the composed prompt. A Stop
# hook has transcript_path in its payload, so the proof is one grep — no registry, no scan.
#   · valid                                → fired-peer
#   · spent + marker in MY transcript      → fired-peer (same peer, retrying/lingering post-close)
#   · spent otherwise                      → origin     (new tenant of a reused id)
#   · stale                                → origin     (someone else's stamp under my reused id)
#   · absent + open by-cwd record whose marker is in MY transcript
#                                          → fired-peer (id changed under a live peer — orphaned,
#                                            not missing; cwd finds it, the marker proves it)
#   · absent otherwise                     → origin
#   · unreadable pane/cwd both empty       → unknown    (nothing was asked; consumer abstains)
oi_origin_class() {
  local pane="${1:-}" cwd="${2:-}" tp="${3:-}" dir state rec marker idxpane scwd closed
  dir="$(oi_fired_dir)"
  if [ -z "$pane" ] && [ -z "$cwd" ]; then printf 'unknown'; return 0; fi
  state="absent"
  [ -n "$pane" ] && state="$(fired_stamp_tenancy "$dir/$pane.json" "$cwd")"
  case "$state" in
    valid) printf 'fired-peer'; return 0 ;;
    spent)
      marker="$(jq -r '.marker // ""' "$dir/$pane.json" 2>/dev/null || true)"
      if [ -n "$marker" ] && [ -n "$tp" ] && [ -f "$tp" ] && grep -qF -- "$marker" "$tp" 2>/dev/null; then
        printf 'fired-peer'
      else
        printf 'origin'
      fi
      return 0 ;;
    stale) printf 'origin'; return 0 ;;
    unknown) printf 'origin'; return 0 ;;
  esac
  # state=absent — the id may have changed under a live peer. The by-cwd index FINDS the candidate;
  # the marker in THIS session's transcript PROVES it (cwd alone never authorises: an operator pane
  # opened in the peer's worktree matches the cwd too — the load-bearing negative in
  # tests/handoff-fired-cwd-index.bats).
  if [ -n "$cwd" ] && [ -n "$tp" ] && [ -f "$tp" ]; then
    idxpane="$(read_fired_cwd_index "$dir" "$cwd")"
    if [ -n "$idxpane" ] && [ -s "$dir/$idxpane.json" ]; then
      closed="$(jq -r '.closedAt // "null"' "$dir/$idxpane.json" 2>/dev/null || echo x)"
      if [ "$closed" = null ]; then
        scwd="$(jq -r '.cwd // ""' "$dir/$idxpane.json" 2>/dev/null || true)"
        if [ -n "$scwd" ] && scwd="$(cd "$scwd" 2>/dev/null && pwd -P)" \
           && [ "$scwd" = "$(cd "$cwd" 2>/dev/null && pwd -P)" ]; then
          marker="$(jq -r '.marker // ""' "$dir/$idxpane.json" 2>/dev/null || true)"
          if [ -n "$marker" ] && grep -qF -- "$marker" "$tp" 2>/dev/null; then
            printf 'fired-peer'; return 0
          fi
        fi
      fi
    fi
  fi
  printf 'origin'
  return 0
}
