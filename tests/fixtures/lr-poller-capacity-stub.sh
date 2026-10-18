# shellcheck shell=bash
# A stand-in for scripts/lib/capacity-admit.sh, sourced by lr-reset-poller.sh through its
# LR_POLLER_CAPACITY_LIB seam (lr-wake 2026-10-18, Wave B step 5).
#
# WHY A STUB. Since the poller probes before every pane it opens (contract K5), the real library
# would read THIS box — its memory headroom and its live claude census — and a suite's verdict would
# then depend on how busy the machine running it is. The probe's own behaviour is pinned by
# tests/capacity-probe.bats and tests/capacity-admit-actor-queue.bats; poller suites only need to
# choose the verdict.
#
#   LR_FAKE_PROBE=admit (default) | refuse     what cc_capacity_probe answers (0 / 9)
#   LR_FAKE_CA_LOG=<file>                      one line per probe and per mint, with the env they saw
#   LR_FAKE_LAUNCH=typed (default) | none | rc:<n>
#       The spawn stubs in these suites never execute the launcher, so the token mint — the one call
#       that learns the run dir the launcher would report into — plays that report: `typed` writes
#       the `relaunch-typed` state lr-fire-resume.sh writes when it hands over to claude, `rc:<n>`
#       writes `relaunch.rc`, `none` writes nothing (the launcher has not reported yet).

_fake_ca_log() { [ -n "${LR_FAKE_CA_LOG:-}" ] && printf '%s\n' "$*" >> "$LR_FAKE_CA_LOG"; return 0; }

CC_ADMIT_REASON=""
cc_capacity_admit_reason() { printf '%s' "$CC_ADMIT_REASON"; }

cc_capacity_probe() { # $1=caller $2=what → 0 / 9
  _fake_ca_log "probe caller=$1 what=$2 queued_since=${CC_ADMIT_QUEUED_SINCE:-}"
  if [ "${LR_FAKE_PROBE:-admit}" = refuse ]; then
    CC_ADMIT_REASON="capacity-admit: PROBE would REFUSE $2 — fake: 8 sessions mid-turn + 1 > active ceiling 8"
    return 9
  fi
  CC_ADMIT_REASON="capacity-admit: ADMIT — fake"
  return 0
}

cc_capacity_token_mint() { # $1=sid → prints a token path
  local d="${HOME:?}/.claude/autonomy/capacity-admit/tokens" p run="${CC_ADMIT_TOKEN_RUN:-}"
  mkdir -p "$d" || return 1
  p="$d/$1.fake$$"
  printf '%s\t%s\t%s\t\nkind=%s\n' "$(date +%s)" "$1" "$(id -u)" "${CC_ADMIT_TOKEN_KIND:-turn}" > "$p" || return 1
  _fake_ca_log "mint sid=$1 kind=${CC_ADMIT_TOKEN_KIND:-} run=$run"
  if [ -n "$run" ]; then
    mkdir -p "$run"
    case "${LR_FAKE_LAUNCH:-typed}" in
      typed) printf '{"state":"relaunch-typed","stage":"expect"}\n' >> "$run/events.jsonl" ;;
      rc:*)  printf '%s\n' "${LR_FAKE_LAUNCH#rc:}" > "$run/relaunch.rc" ;;
    esac
  fi
  printf '%s' "$p"
}
