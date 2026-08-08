#!/usr/bin/env bash
# cloud-websetup-drive.sh — link an account's CLI to GitHub for cloud sessions, with ZERO human input.
#
#   cloud-websetup-drive.sh --account <name>...   drive /web-setup for each named account
#   cloud-websetup-drive.sh --all                 every account in accounts.json
#   cloud-websetup-drive.sh --status              report per-account link state, drive nothing
#   cloud-websetup-drive.sh --resolve <name>      print the resolved binary + config dir, drive nothing
#   cloud-websetup-drive.sh --verify <name>       spend ONE cloud session to prove the link end-to-end
#   cloud-websetup-drive.sh --force …             re-drive an account already recorded as linked
#
# ── why this exists as a script and not a runbook ────────────────────────────────────────────────
# `/web-setup` is a TUI-only slash command: no `claude web-setup` subcommand exists (checked against
# 2.1.220 `--help`), and the CLI cannot mint the link any other way. So the only automatable path is
# to drive a real terminal — which is exactly what this does, via kitty remote control. A runbook
# telling a human to type `/web-setup` four times is the thing this replaces.
#
# ── three traps this encodes, each one already paid for ──────────────────────────────────────────
# T1  LOGIN SHELL IS MANDATORY. `kitten @ launch <binary>` skips the login shell, so /opt/homebrew/bin
#     is off PATH, `gh` is not found, and /web-setup reports "GitHub CLI not found" — a FALSE finding
#     about the machine. Always launch via `/bin/zsh -l -i -c`. (Cost one wrong diagnosis 2026-08-08.)
# T2  ENTER IS \r, NEVER \n. The Ink TUI ignores \n outright.
# T3  ABSENCE OF AN ERROR IS NOT SUCCESS. The consent dialog clears leaving no verdict line, so this
#     script never infers success from a clean pane — see verify_account(), which reads the only
#     un-fakeable signal: whether `claude --cloud` still falls back to bundle mode.
#
#     T3 AMENDED (2026-08-08), never deleted — the sentence above is still the law, and what changed
#     is that a SECOND un-fakeable signal was found, one that costs no cloud session. Live on
#     account next3 the TUI printed, verbatim:
#         Connected as renchris. Opened https://claude.ai/code
#     `Connected as ` is a POSITIVE verdict line. So the drive no longer stops at "the consent prompt
#     appeared and no error followed" — which is the absence-of-an-error shape T3 names, and which
#     the first draft of this file shipped as its success condition. Matching that literal is the
#     success test; NOT matching it inside the window is its own third state (see EXIT STATES), never
#     folded into either success or failure. verify_account() remains the strongest proof and remains
#     opt-in, because it draws real subscription quota.
#
# ── EXIT STATES: THREE, NOT TWO ──────────────────────────────────────────────────────────────────
# The whole point of the T3 amendment is that "it worked", "it broke", and "I could not tell" are
# three different answers, and collapsing the third into either of the others is how a link that was
# never made gets recorded as made (fold into success) or how a healthy-but-slow pane gets a caller
# to tear down a working account (fold into failure).
#
#   0  LINKED       — the pane printed `Connected as `, or the account was already recorded linked.
#   1  FAILED       — an ERROR was OBSERVED: no config dir, the launch produced no window id, or the
#                     TUI printed a named failure such as "GitHub CLI not found".
#   2  PRECONDITION — this box cannot run the drive at all (no kitten, remote control refused, no
#                     repo, unresolvable binary) or the argv was bad. Nothing was attempted.
#   3  NOT-SUCCESS  — the drive ran, nothing errored, and `Connected as ` never appeared within the
#                     window. INDETERMINATE. No state file is written; the correct caller response is
#                     to look, or to re-run with a longer CC_WEBSETUP_POLL_MAX — NOT to record a link.
#
# Across several accounts the run reports the worst outcome, with an OBSERVED error outranking an
# indeterminate one: any FAILED ⇒ 1, else any NOT-SUCCESS ⇒ 3, else 0. (An observed error names a
# cause; an indeterminate says only that nothing was named. The one that carries information wins.)
#
# ── two resolution rules, and WHY each is a rule rather than a convenience ────────────────────────
# R1  CLAUDE_CONFIG_DIR COMES FROM accounts.json, NEVER A HARDCODED PATH. accounts.json is the SSOT
#     identity map (launcher → config dir → email → mailbox → Dia profile) that /accounts,
#     handoff-fire.sh and account-relogin all read. A path spelled out here is a second source of
#     truth that cannot learn it changed — an account added, renamed, or re-homed silently drives the
#     wrong config dir, i.e. links the wrong subscription. There are four accounts and each has its
#     own dir; being off by one is not a visible error, it is a silently wrong link.
# R2  THE claude BINARY COMES FROM THE RUNNING PROCESS, NEVER A LAUNCHER WRAPPER. `claude` and `cc`
#     are shell FUNCTIONS, not binaries. Their `--version` reports whichever launcher the NAME points
#     at right now, which is not the binary the calling session is running: this box has run two CC
#     tracks at once, and reading the launcher measured 114 while the live session was 220 — an
#     upgrade filed against a version nobody was on (memory
#     `version-identity-is-the-running-process-not-the-launcher`). So resolution walks `ps -o
#     command= -p <pid>` up from $PPID and takes the REAL argv-0 path of the running process. When no
#     ancestor is a claude process (a cron/launchd/headless caller), it falls back to accounts.json's
#     recorded `claude_bin` — still a recorded absolute path, still not a wrapper. `command -v claude`
#     is never consulted, on any path.
#
# ── state (correction 4) ─────────────────────────────────────────────────────────────────────────
# Per-account progress lives at $STATE_DIR/<acct>.linked and <acct>.verified — the convention already
# on disk. `.linked` is written ONLY on the `Connected as ` match, so the file means "a verdict line
# was read", not "a keystroke was sent". An existing `.linked` makes the account a NO-OP (no pane is
# opened at all); `--force` re-drives it.
#
# ── env seams ────────────────────────────────────────────────────────────────────────────────────
# Every seam below is honored SET-INCLUDING-EMPTY (`${VAR+set}`, never `${VAR:-}`) — a seam that
# cannot express "off" is not a seam, and `${VAR:-}` cannot tell unset from set-to-empty.
#   CC_ACCOUNTS_JSON      the SSOT map                    (empty ⇒ no map ⇒ nothing resolves ⇒ rc 2)
#   CC_WEBSETUP_REPO      cwd the driven pane opens in    (empty ⇒ rc 2, a pane needs a real cwd)
#   CC_CLAUDE_BIN         override for R2                 (empty ⇒ no override; resolve as normal)
#   CC_WEBSETUP_STATE     state dir                       (empty ⇒ STATELESS: no reads, no writes)
#   CC_WEBSETUP_POLL_MAX  seconds to wait for a verdict   (empty ⇒ 0 ⇒ do not wait at all)
#   CC_WEBSETUP_SLEEP     the sleep command               (empty ⇒ never sleep — this is what makes
#                                                          the bats suite cost no wall-clock time)
set -euo pipefail

if [ -n "${CC_ACCOUNTS_JSON+set}" ]; then ACCOUNTS_JSON="$CC_ACCOUNTS_JSON"; else ACCOUNTS_JSON="${HOME:-}/.claude/accounts.json"; fi
if [ -n "${CC_WEBSETUP_REPO+set}" ]; then REPO="$CC_WEBSETUP_REPO"; else REPO="${HOME:-}/Development/claude-infrastructure"; fi
if [ -n "${CC_CLAUDE_BIN+set}" ]; then CLAUDE_BIN="$CC_CLAUDE_BIN"; else CLAUDE_BIN=""; fi
if [ -n "${CC_WEBSETUP_STATE+set}" ]; then STATE_DIR="$CC_WEBSETUP_STATE"; else STATE_DIR="${HOME:-}/.claude/autonomy/websetup"; fi
if [ -n "${CC_WEBSETUP_POLL_MAX+set}" ]; then POLL_MAX="${CC_WEBSETUP_POLL_MAX:-0}"; else POLL_MAX=90; fi
if [ -n "${CC_WEBSETUP_SLEEP+set}" ]; then SLEEP_CMD="$CC_WEBSETUP_SLEEP"; else SLEEP_CMD="sleep"; fi

RC_OK=0; RC_FAILED=1; RC_PRECOND=2; RC_NOTSUCCESS=3

# The pane-spawn census (scripts/lib/pane-spawn-log.sh): every in-tree site that CREATES a terminal
# surface writes one row, which is what makes "a pane with no row came from outside this tree" a
# sound inference. Sourced by direct child path — never by `..` traversal off $0, which resolves to
# ~/.claude for a symlink-deployed invocation (scripts/self-path-lint.sh).
for _psl in "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")/lib/pane-spawn-log.sh" \
            "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/scripts/lib/pane-spawn-log.sh" \
            "${HOME:-}/.claude/scripts/lib/pane-spawn-log.sh"; do
  # shellcheck source=/dev/null
  if [ -r "$_psl" ]; then . "$_psl"; break; fi
done
unset _psl

log() { printf '%s\n' "$*" >&2; }
die() { log "cloud-websetup-drive: $*"; exit "$RC_PRECOND"; }

# nap — the ONLY wall-clock in this file, and it is seam-controlled so the suite can zero it out.
# An empty CC_WEBSETUP_SLEEP means "do not sleep"; a test that had to really wait 90s for a
# NOT-SUCCESS verdict would be a test nobody runs.
nap() { [ -n "$SLEEP_CMD" ] || return 0; "$SLEEP_CMD" "$1" >/dev/null 2>&1 || true; }

state_file() { [ -n "$STATE_DIR" ] || return 1; printf '%s/%s.%s' "$STATE_DIR" "$1" "$2"; }
state_has()  { local f; f="$(state_file "$1" "$2")" || return 1; [ -f "$f" ]; }
state_put()  {
  local f; f="$(state_file "$1" "$2")" || return 0
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$3" > "$f" 2>/dev/null || true
}

# ── accounts.json queries (R1) ───────────────────────────────────────────────────────────────────
# One reader, three verbs. Shape-tolerant on purpose: accounts.json has carried both an `accounts`
# array of rows and a bare name→row object, and a resolver that understands only today's shape is a
# resolver that silently returns "" the day it changes — and "" here means "skip this account",
# which reads as a clean run.
accounts_query() {
  python3 - "$ACCOUNTS_JSON" "$1" "${2:-}" <<'PY'
import json, os, sys
path, verb, arg = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    j = json.load(open(path))
except Exception:
    raise SystemExit(0)
if verb == "claude_bin":
    print(os.path.expanduser(j.get("claude_bin", "") or "") if isinstance(j, dict) else "")
    raise SystemExit(0)
accts = j.get("accounts", j) if isinstance(j, dict) else j
if isinstance(accts, dict):
    rows = [dict(v, **{"name": k}) for k, v in accts.items() if isinstance(v, dict)]
elif isinstance(accts, list):
    rows = [r for r in accts if isinstance(r, dict)]
else:
    rows = []
if verb == "names":
    print("\n".join(r.get("name") for r in rows if r.get("name")))
    raise SystemExit(0)
if verb == "config_dir":
    for r in rows:
        if arg in (r.get("name"), r.get("launcher")) or arg in (r.get("aliases") or []):
            print(os.path.expanduser(r.get("config_dir") or r.get("configDir") or ""))
            raise SystemExit(0)
print("")
PY
}
config_dir_for() { accounts_query config_dir "$1"; }
all_accounts()   { accounts_query names; }

# ── R2: resolve the RUNNING binary, never a launcher wrapper ─────────────────────────────────────
resolve_claude_bin() {
  [ -z "$CLAUDE_BIN" ] || { printf '%s' "$CLAUDE_BIN"; return 0; }
  local p c hit=""
  p="${PPID:-0}"
  for _ in 1 2 3 4 5 6 7 8; do
    [ -n "$p" ] && [ "$p" != 0 ] || break
    c="$(ps -o command= -p "$p" 2>/dev/null | head -1 || true)"
    hit="$(printf '%s' "$c" | tr ' ' '\n' | grep -m1 -E '(^|/)(node_modules/\.bin/claude|claude)$' || true)"
    case "$hit" in
      /*) if [ -x "$hit" ]; then printf '%s' "$hit"; return 0; fi ;;
    esac
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ' || true)"
  done
  # No claude ancestor — a launchd/cron/headless caller. accounts.json's recorded absolute path is
  # the fallback. `command -v claude` is NOT consulted here or anywhere: it resolves the shell
  # FUNCTION's target, which is a launcher wrapper (R2).
  accounts_query claude_bin || true
}

pane_text() { kitten @ get-text --match "id:$1" 2>/dev/null | tr -d '\000' || true; }

# ── the drive ────────────────────────────────────────────────────────────────────────────────────
# Returns RC_OK / RC_FAILED / RC_NOTSUCCESS — the three states, kept apart end to end.
drive_account() {
  local acct="$1" cfg wid txt i verdict consent_sent=0

  cfg="$(config_dir_for "$acct")"
  if [ -z "$cfg" ] || [ ! -d "$cfg" ]; then
    log "  $acct: FAILED — no config dir resolved from $ACCOUNTS_JSON (R1: the map is the only source)"
    return "$RC_FAILED"
  fi

  # T1: login shell, or gh is invisible and /web-setup lies about it.
  wid="$(kitten @ launch --type=window --title "websetup-$acct" --cwd "$REPO" \
         --env "CLAUDE_CONFIG_DIR=$cfg" \
         /bin/zsh -l -i -c "$CLAUDE_BIN --permission-mode auto" 2>/dev/null || true)"
  wid="$(printf '%s' "$wid" | tr -d ' \n')"
  case "$wid" in
    ''|*[!0-9]*)
      log "  $acct: FAILED — kitten @ launch produced no window id"
      return "$RC_FAILED" ;;
  esac
  command -v cc_log_pane_spawn >/dev/null 2>&1 && \
    cc_log_pane_spawn window kitty "$wid" "$REPO" "cloud-websetup-drive $acct" || true
  kitten @ resize-window --match "id:$wid" --axis horizontal --increment 60 >/dev/null 2>&1 || true

  # Wait for the TUI to reach its composer before typing into it.
  for ((i=0; i<POLL_MAX; i++)); do
    txt="$(pane_text "$wid")"
    case "$txt" in *"? for shortcuts"*|*"Describe a task"*|*"auto mode on"*) break ;; esac
    nap 1
  done

  kitten @ send-text --match "id:$wid" "/web-setup" >/dev/null 2>&1 || true
  nap 1
  kitten @ send-text --match "id:$wid" "\r" >/dev/null 2>&1 || true   # T2: \r, never \n

  # ONE loop, and it exits on a VERDICT — not on the consent prompt. Consenting is a step along the
  # way, so it dismisses the dialog (once) and keeps reading. This is the shape correction: the
  # earlier version returned success here, which is precisely "the error did not happen yet".
  verdict=""
  for ((i=0; i<POLL_MAX; i++)); do
    txt="$(pane_text "$wid")"
    case "$txt" in
      *"Connected as "*)          verdict=linked;  break ;;
      *"GitHub CLI not found"*)   verdict=nogh;    break ;;
      *"Connect Claude on the web to GitHub"*)
        # Defaults to "1. Continue". Wait for it explicitly rather than blind-sending — a blind \r
        # survives on first-word luck only. Send once; a second \r would answer the NEXT prompt.
        if [ "$consent_sent" = 0 ]; then
          kitten @ send-text --match "id:$wid" "\r" >/dev/null 2>&1 || true
          consent_sent=1
        fi ;;
    esac
    nap 1
  done

  # One last read: the verdict line can land in the same second the loop expires.
  if [ -z "$verdict" ]; then
    txt="$(pane_text "$wid")"
    case "$txt" in *"Connected as "*) verdict=linked ;; esac
  fi

  kitten @ close-window --match "id:$wid" >/dev/null 2>&1 || true

  case "$verdict" in
    linked)
      state_put "$acct" linked "connected-as-observed"
      log "  $acct: LINKED — pane printed 'Connected as '"
      return "$RC_OK" ;;
    nogh)
      log "  $acct: FAILED — 'GitHub CLI not found' (T1: launched without a login shell?)"
      return "$RC_FAILED" ;;
    *)
      # T3. Nothing errored and nothing confirmed. No state file — a link this script cannot see is
      # a link it must not record.
      log "  $acct: NOT-SUCCESS — 'Connected as ' never appeared within ${POLL_MAX}s (consent_sent=$consent_sent)."
      log "         INDETERMINATE, not a failure: look at the account, or raise CC_WEBSETUP_POLL_MAX."
      return "$RC_NOTSUCCESS" ;;
  esac
}

# ── the strongest proof, opt-in: does a create still fall back to bundle mode? ────────────────────
# COSTS one real cloud session and draws subscription quota. Deliberately NOT part of drive_account.
verify_account() {
  local acct="$1" cfg out sid
  cfg="$(config_dir_for "$acct")"
  [ -n "$cfg" ] || { log "  $acct: no config dir"; return "$RC_FAILED"; }
  out="$(cd "$REPO" && CLAUDE_CONFIG_DIR="$cfg" script -q /dev/null "$CLAUDE_BIN" --cloud \
        "Reply with the single word OK and stop. Make no edits and open no PR." </dev/null 2>&1 \
        | tr -d '\000' | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' || true)"
  case "$out" in
    *"Created cloud session"*)
      sid="$(printf '%s' "$out" | grep -oE 'session_[A-Za-z0-9]+' | head -1 || true)"
      state_put "$acct" verified "$sid"
      log "  $acct: VERIFIED — created $sid"
      command -v cc-cloud >/dev/null 2>&1 && cc-cloud declare --id "$sid" --branch main \
        --url "https://claude.ai/code/$sid" >/dev/null 2>&1 || true
      return "$RC_OK" ;;
    *"Bundle upload failed"*)
      log "  $acct: NOT LINKED — still falling back to bundle mode"; return "$RC_FAILED" ;;
    *)
      log "  $acct: NOT-SUCCESS — $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
      return "$RC_NOTSUCCESS" ;;
  esac
}

status_report() {
  local a
  printf '%-10s %-12s %s\n' ACCOUNT LINK VERIFIED
  while read -r a; do
    [ -n "$a" ] || continue
    printf '%-10s %-12s %s\n' "$a" \
      "$(state_has "$a" linked && echo linked || echo none)" \
      "$(state_has "$a" verified && cat "$(state_file "$a" verified)" || echo '-')"
  done < <(all_accounts)
}

# ── argv ─────────────────────────────────────────────────────────────────────────────────────────
targets=(); mode=drive; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --account) shift; [ $# -gt 0 ] || die "--account needs a name"; targets+=("$1") ;;
    --all)     while read -r a; do [ -n "$a" ] || continue; targets+=("$a"); done < <(all_accounts) ;;
    --status)  mode=status ;;
    --resolve) mode=resolve; shift; [ $# -gt 0 ] || die "--resolve needs a name"; targets+=("$1") ;;
    --verify)  mode=verify;  shift; [ $# -gt 0 ] || die "--verify needs a name";  targets+=("$1") ;;
    --force)   FORCE=1 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

# --status is a pure read of the state dir and must not need a terminal, a repo, or a binary — it is
# the verb a caller reaches for precisely when the machine is in a bad state.
if [ "$mode" = status ]; then status_report; exit "$RC_OK"; fi

CLAUDE_BIN="$(resolve_claude_bin)"
[ -n "$CLAUDE_BIN" ] || die "could not resolve the running claude binary (R2) — set CC_CLAUDE_BIN"

if [ "$mode" = resolve ]; then
  rc=$RC_OK
  for a in "${targets[@]}"; do
    printf 'account=%s bin=%s config=%s\n' "$a" "$CLAUDE_BIN" "$(config_dir_for "$a")"
  done
  exit "$rc"
fi

# Preconditions for anything that opens a pane. Each fail-closed, each naming its reason: this box
# not being able to drive is a DIFFERENT answer from an account failing to link (rc 2, not rc 1).
[ -x "$CLAUDE_BIN" ] || die "resolved claude binary is not executable: $CLAUDE_BIN"
[ -n "$REPO" ] && [ -d "$REPO" ] || die "repo not found: $REPO (set CC_WEBSETUP_REPO)"
if [ "$mode" = drive ]; then
  command -v kitten >/dev/null 2>&1 || die "kitty's 'kitten' is not on PATH — this drive needs kitty remote control"
  kitten @ ls >/dev/null 2>&1 || die "kitty remote control is refused (allow_remote_control). Cannot drive a TUI without it."
fi

[ ${#targets[@]} -gt 0 ] || die "nothing to do — pass --account <name>, --all, --status, or --resolve <name>"

if [ "$mode" = verify ]; then
  rc=$RC_OK
  for a in "${targets[@]}"; do
    verify_account "$a" || case "$?" in
      "$RC_FAILED") rc=$RC_FAILED ;;
      *) [ "$rc" = "$RC_FAILED" ] || rc=$RC_NOTSUCCESS ;;
    esac
  done
  exit "$rc"
fi

log "cloud-websetup-drive: binary=$CLAUDE_BIN repo=$REPO state=${STATE_DIR:-<stateless>}"
rc=$RC_OK
for a in "${targets[@]}"; do
  if [ "$FORCE" = 0 ] && state_has "$a" linked; then
    log "  $a: already linked — no-op (--force to re-drive)"
    continue
  fi
  drive_account "$a" || case "$?" in
    "$RC_FAILED") rc=$RC_FAILED ;;
    *) [ "$rc" = "$RC_FAILED" ] || rc=$RC_NOTSUCCESS ;;
  esac
done
exit "$rc"
