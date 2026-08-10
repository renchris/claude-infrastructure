#!/bin/bash
# PreToolUse hook for Bash command validation
#
# Complements settings.json deny/ask permissions with pattern-matching that
# permission prefixes can't catch (DDL inside commands, compound command
# escape hatches, bypass-flag detection aware of quoted message bodies).
#
# Exit 0 with JSON to stdout for decisions. Exit 2 for blocking errors.
#
# Rollback knobs (env):
#   VALIDATE_BASH_LEGACY=1       Use regex-only flag detection (skips shlex).
#   VALIDATE_BASH_DISABLED=1     No-op the hook entirely (emergency only).

# Kill switch
if [[ "${VALIDATE_BASH_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

# Builtin read, NOT `$(cat)`: command substitution forks AND execs /bin/cat on the hottest path
# in the system (this hook fires on EVERY Bash tool call). Measured 2026-07-31: ~6 ms per hook,
# ~18% of the 163 ms PreToolUse/Bash chain across the five hooks that did this. `read -d ''`
# returns non-zero at EOF -- the normal case here -- hence `|| true`; it also PRESERVES the
# trailing newline that `$(cat)` strips, so strip it back off for byte-parity with the old value.
IFS= read -r -d '' INPUT || true
while [ "${INPUT%$'\n'}" != "${INPUT}" ]; do INPUT="${INPUT%$'\n'}"; done

# === JQ / PAYLOAD GUARD — fail OPEN, but never SILENTLY (audit 09 D-4) ===
# Every other PreToolUse hook guards jq (backup-before-write.sh:17, git-worktree-guard.sh,
# check-edit-boundary.sh, agent-teams-enforce.sh, frontier-spawn-gate.sh,
# cc-unattended-ask-guard.sh, plan-agent-teams-default.sh). This one did not: with jq absent or
# the payload unparseable, CMD went empty, EVERY danger pattern missed, and the hook exited 0 —
# the bash validator silently disabled itself. Fail-open is the right availability posture for a
# gate that can block a tool call; failing open with ZERO signal is the defect. So: still exit 0,
# but leave one loud line behind (the keychain-guard.sh:19-21 documented-fail-open posture).
# Sink + TSV shape (ts \t kind \t detail) are shared with lib/is-true-flag.sh:200-205, which
# already logs its own "could not decide" case there — one file, one shape, one meaning:
# "the bash validator did not actually validate this".
abstain_unclear() { # <reason>
  mkdir -p "$HOME/.claude/logs" 2>/dev/null || true
  printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ 2>/dev/null || echo '?')" \
    'validate-bash-ABSTAIN' "fail-open, command NOT validated: $1" \
    >> "$HOME/.claude/logs/validate-bash-unclear.log" 2>/dev/null || true
  exit 0
}
command -v jq >/dev/null 2>&1 || abstain_unclear "jq unavailable on PATH"
if ! CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  abstain_unclear "unparseable PreToolUse payload on stdin"
fi

# Source the argv-aware flag detector. If unavailable, caller can force
# legacy mode; otherwise fall back silently on a per-call basis below.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
if [[ -f "$LIB_DIR/is-true-flag.sh" && "${VALIDATE_BASH_LEGACY:-0}" != "1" ]]; then
  # shellcheck source=lib/is-true-flag.sh
  # shellcheck disable=SC1091  # resolved at RUNTIME from BASH_SOURCE; the static path is only
  #                              valid when shellcheck is run from hooks/ (the land gate is not)
  source "$LIB_DIR/is-true-flag.sh"
  HAVE_IS_TRUE_FLAG=1
else
  HAVE_IS_TRUE_FLAG=0
fi

# json_escape — a decision is only enforced if the harness can PARSE it. Every reason below used
# to be interpolated raw into the JSON body, so the first message to contain a `"` (or a quote
# echoed back from the user's own command, as the pkill clause does) emitted malformed JSON and the
# deny silently became a no-op — a guard that reports blocking while not blocking. Escape order is
# load-bearing: backslashes BEFORE quotes, else the added backslashes get re-escaped. Control
# characters are stripped: a literal newline is not legal inside a JSON string.
json_escape() {  # <string> → a safe JSON string BODY (no surrounding quotes)
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\000-\037'
}

deny() {
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$(json_escape "$1")"
  }
}
EOF
  exit 0
}

warn() {
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "$(json_escape "$1")"
  }
}
EOF
  exit 0
}

# check_real_flag <flag> — returns 0 if CMD contains <flag> as a real argv
# token (in a non-inert head, outside message bodies). Returns 1 otherwise.
# Falls back to word-boundary regex when the shlex helper is unavailable.
check_real_flag() {
  local flag="$1"
  if [[ "$HAVE_IS_TRUE_FLAG" == "1" ]]; then
    is_true_flag "$flag" "$CMD"
    local rc=$?
    # rc=0 → real flag; rc=1 → substring only; rc=2 → unclear (fail safe = block)
    [[ "$rc" == "0" || "$rc" == "2" ]] && return 0
    return 1
  else
    # Legacy fallback: word-boundary regex (still false-positives on message
    # bodies that contain the literal bracketed by spaces).
    local pattern="(^|[[:space:]])${flag//./\\.}([[:space:]]|\$)"
    echo "$CMD" | grep -qE "$pattern"
  fi
}

# ── LIVE-/goal guard: a PARKED background watcher disables an armed /goal ─────────────────────────
# CC's Stop handler deletes the /goal Stop hook at any Stop where the task registry holds a
# non-terminal local_bash task, then restores it in a `finally` — the registry always LOOKS healthy
# while the goal is silently skipped (measured on 2.1.220; docs/research/goal-in-handoff-2026-08-08.md
# § RESOLVED). `cc-await-ping` armed via Bash(run_in_background) is exactly such a task, parked for
# hours by design — and CLAUDE.md § Agent Teams instructs that arm, so a goal-armed session
# sabotages its own goal unless the act's own tool call is gated
# (MEMORY.md enforcement-must-live-at-the-chokepoint). Scope, deliberately narrow: ONLY
# cc-await-ping + run_in_background:true + a LIVE goal. A foreground cc-await-ping (cc-wait's use)
# is terminal by the time any Stop happens; an ordinary background build/subagent settles and its
# completion re-invokes the model — both are correct deferrals, untouched. Fail OPEN on any read
# failure: a false deny would strand a goal-less session's only wake path.
# COMMAND-POSITION, not substring: a background `rg 'cc-await-ping' …` is a search that settles in
# seconds, not a parked watcher — substring matching would deny it and teach a falsehood. The two
# real arm spellings every instruction site uses are the bare name in first position and a path
# ending in bin/cc-await-ping; a compound-command evasion merely falls open, which is this guard's
# declared fail direction. (MEMORY.md denylist-enumerates-spellings: match what GOVERNS, here the
# executed token, never the byte-string.)
_gg_hit=0
_gg_first="${CMD%%[[:space:]]*}"
case "$_gg_first" in *cc-await-ping) _gg_hit=1 ;; esac
[[ "$CMD" == *bin/cc-await-ping* ]] && _gg_hit=1
if [[ "$_gg_hit" == 1 ]]; then
  _gg_bg="$(printf '%s' "$INPUT" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)"
  if [[ "$_gg_bg" == "true" ]]; then
    _gg_tp="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)"
    _gg_lib="$LIB_DIR/goal-state.sh"
    [[ -f "$_gg_lib" ]] || _gg_lib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/goal-state.sh"
    [[ -f "$_gg_lib" ]] || _gg_lib="$HOME/.claude/hooks/lib/goal-state.sh"
    if [[ -f "$_gg_lib" ]]; then
      # shellcheck source=lib/goal-state.sh
      # shellcheck disable=SC1091  # runtime-resolved fallback chain
      source "$_gg_lib" 2>/dev/null || true
    fi
    if command -v goal_live_condition >/dev/null 2>&1; then
      _gg_cond="$(goal_live_condition "$_gg_tp" 2>/dev/null)" || _gg_cond=""
      if [[ -n "$_gg_cond" ]]; then
      deny "A /goal is LIVE in this session (\"${_gg_cond:0:120}\"), and a PARKED background watcher would silently disable it: Claude Code skips /goal evaluation at every Stop while a non-terminal background Bash exists (the registry is restored afterwards, so nothing ever looks wrong). Do not arm cc-await-ping here. You are not deaf without it — the goal blocks your stops, so you keep taking turns and mailbox-drain delivers peer mail at every turn boundary; the birth watcher (mailbox-wake-arm, asyncRewake) also wakes a genuinely idle session WITHOUT entering the task registry. If you need a cross-turn continuation lever, use: ~/.claude/hooks/session-continue.sh set \"<next step>\" — it is goal-safe. Detail: docs/research/goal-in-handoff-2026-08-08.md"
      fi
    fi
  fi
fi

# ── Hard deny: catastrophic or rule-violating patterns ────────────────

# System damage, part 1 — the two shapes that are NOT an rm argv question. A fork bomb is syntax,
# not a command with flags; `sudo rm` is a two-token shape whose breadth (any rm at all under
# sudo) is deliberate. Both keep their text matching, unchanged.
if echo "$CMD" | grep -qE '(sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then
  deny "Dangerous command pattern blocked: potential system damage (sudo rm, or fork bomb)."
fi

# ── System damage, part 2 — catastrophic rm, decided on ARGV ──────────
# The regex this replaces hardcoded ONE spelling of the flags, `-rf`, so every equivalent spelling
# walked past it. Measured against the shipped hook (codex-security scan dc12c8db, finding 1):
#     rm -rf /*                 deny          ← the only spelling it knew
#     rm -fr /*                 ask           ← downgraded
#     rm -r -f /*               ask           ← downgraded
#     rm -Rf /                  NO DECISION   ← -R is the same flag
#     rm -f -r /                NO DECISION
#     rm --recursive --force /* NO DECISION   ← the long form is not a flag bundle at all
#     rm -rf /                  ask           ← the slash branch ended in `[^a-zA-Z]`, which must
#                                               CONSUME a character, so bare `/` at end-of-input
#                                               could not match — while the tilde branch beside it
#                                               was written `~(/|$|…)` and did accept it. That
#                                               internal disagreement is what proves oversight
#                                               rather than intent.
# The equivalence class is not enumerable by regex — flag order, bundling, case, long form and
# `--` separation multiply — so the spelling question is answered by tokenizing instead:
# rm_argv_scan reports (recursive, force, target) per real invocation, and the rule reads exactly
# as it is written in CLAUDE.md. That also fixes the mirror-image defect, since text is not
# execution: `git commit -m "fix: guard rm -rf / properly"` used to be DENIED, so the guard
# blocked its own fix from being committed.
#
# ONE scan, TWO consumers (this deny and the non-build-target warn below): a second parse would be
# a second place for the spelling rule to rot out of sync.
RM_SCAN=""
RM_SCAN_OK=0
RM_PRESENT=0
if printf '%s' "$CMD" | grep -qE '(^|[^a-zA-Z0-9_-])rm([[:space:]]|$)'; then
  RM_PRESENT=1
  # `declare -F` is not ceremony: hooks/ deploys as per-file symlinks, so a live layer can briefly
  # hold a NEW validate-bash.sh beside an OLD lib. Absent function → legacy path, never a crash.
  if [[ "$HAVE_IS_TRUE_FLAG" == "1" ]] && declare -F rm_argv_scan >/dev/null 2>&1; then
    if RM_SCAN=$(rm_argv_scan "$CMD"); then
      RM_SCAN_OK=1
    fi
  fi
fi

# is_catastrophic_rm_target <argv-token> — the TARGET half of the predicate. Deliberately the same
# REACH as the regex it replaces, so this change moves only the flag and quoting spellings and
# never which targets count:
#   /  //  /*  /.        root itself or a root-level glob — but NOT /usr, /etc, which stay `ask`
#   ~  ~/  ~/anything    the tilde branch's existing prefix reach
#   $HOME…  ${HOME}…     the $HOME branch's existing prefix reach; ${HOME} is the same variable,
#                        spelled differently, which is the very defect class being fixed here
is_catastrophic_rm_target() {
  local t="$1"
  local re_root='^/([^a-zA-Z].*)?$'
  local re_tilde='^~(/.*)?$'
  local re_home='^\$\{?HOME\}?'
  [[ "$t" =~ $re_root || "$t" =~ $re_tilde || "$t" =~ $re_home ]]
}

deny_catastrophic_rm() {  # <target> — one message, so both paths below cannot drift apart
  deny "Dangerous command pattern blocked: potential system damage — recursive+force rm targeting '$1' (root or home). Flag spelling is irrelevant: -rf, -fr, -Rf, -r -f, --recursive --force and every bundle containing r/R and f are the same command. If you meant a path INSIDE the tree, name it relatively."
}

if [[ "$RM_PRESENT" == "1" && "$RM_SCAN_OK" == "1" ]]; then
  while IFS=$'\t' read -r rm_rec rm_force rm_target; do
    [[ "$rm_rec" == "1" && "$rm_force" == "1" ]] || continue
    is_catastrophic_rm_target "$rm_target" && deny_catastrophic_rm "$rm_target"
  done <<<"$RM_SCAN"
elif [[ "$RM_PRESENT" == "1" ]]; then
  # UNCLEAR (python3 absent / unbalanced quotes) or VALIDATE_BASH_LEGACY=1. No argv, so decide on
  # text — over-blocking a message body exactly as this clause always did. Still spelling-aware,
  # so the rollback knob is a rollback of the PARSER, never a re-opening of the bypass.
  RM_TEXT_OCC=$(printf '%s' "$CMD" | grep -oE '(^|[^a-zA-Z0-9_-])rm([[:space:]]+[^;&|]*)?' || true)
  while IFS= read -r rm_occ; do
    [[ -z "$rm_occ" ]] && continue
    printf '%s' "$rm_occ" | grep -qE '(^|[[:space:]])-[a-zA-Z]*[rR][a-zA-Z]*([[:space:]]|$)|--recursive([[:space:]=]|$)' || continue
    printf '%s' "$rm_occ" | grep -qE '(^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$)|--force([[:space:]=]|$)' || continue
    # `read -a`, never `for tok in $rm_occ`: word splitting there would also GLOB, and the first
    # target it expanded would be `/*` — the guard would list the root directory and then match
    # nothing. Quotes are stripped by hand because this path never tokenized.
    RM_TOKS=()
    read -r -a RM_TOKS <<<"$rm_occ"
    for rm_tok in "${RM_TOKS[@]}"; do
      rm_tok="${rm_tok//\"/}"
      rm_tok="${rm_tok//\'/}"
      [[ "$rm_tok" == -* ]] && continue
      is_catastrophic_rm_target "$rm_tok" && deny_catastrophic_rm "$rm_tok"
    done
  done <<<"$RM_TEXT_OCC"
fi

# ── Worktree-UNSCOPED pkill/killall of gate processes ─────────────────
# ROOT CAUSE of the 2026-07-26 false-RED epidemic (backlog a0718a5d78b3). Peer sessions were
# SIGKILLing each other's landing gates:
#     pkill -9 -f bats-core/bats                  ← every bats cmdline on this box contains that
#     pkill -f "ship-land.sh --trunk main"
# The desk tied victim gates to actor commands with a 3-5s lag twice over; >=8 broad-pkill events
# across 5 sessions in 24h. Victims mis-read their own SIGKILL as OOM/jetsam (REFUTED: 68% memory
# free, zero memorystatus kills) and propagated that wrong theory into their block reasons.
# These patterns are machine-wide BY CONSTRUCTION, not by accident, so this is a deny and not an
# ask: a correct scoped form exists, and a helper implements it — both are named in the message.
# Scoped forms pass untouched. Kill switch: the whole hook's VALIDATE_BASH_DISABLED=1.
# COMMAND POSITION, not substring: `git commit -m "fix: do not pkill bats"` merely MENTIONS the
# thing. Deciding on raw text is the exact defect this clause exists to stop, one level down (a
# `pkill -f bats` pattern matches peers because it matches TEXT). So the position test runs on a
# quote-STRIPPED copy — killing message bodies — while the target/scope tests below still read the
# ORIGINAL, because that is where the real pattern lives (`pkill -f "bats tests/"`).
CMD_NOQ=$(printf '%s' "$CMD" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g')
if printf '%s' "$CMD_NOQ" | sed 's/[&|()]/;/g' | tr ';' '\n' | sed 's/^[[:space:]]*//' \
     | grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then
  PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)
  while IFS= read -r pk; do
    [[ -z "$pk" ]] && continue
    # Does this occurrence target a GATE program at all? Otherwise it is none of our business.
    echo "$pk" | grep -qE '(bats|ship-land|postland-verify)' || continue
    # Is it scoped to ONE worktree? Any of: a $PWD-derived expression, a -P (parent-pid) scope,
    # or an explicitly named worktree (a .worktrees/ path or a wt-* directory name).
    # shellcheck disable=SC2016  # $PWD / $(pwd) are LITERALS to match in the command TEXT, by design
    if echo "$pk" | grep -qE '\$PWD|\$\{PWD|\$\(pwd|`pwd|\$\(basename|(^|[[:space:]])-P[[:space:]]|\.worktrees/|(^|[^a-zA-Z0-9])wt-[a-zA-Z0-9]'; then
      continue
    fi
    # …or it names THIS session's own worktree directory literally.
    if [[ -n "${PWD##*/}" ]] && echo "$pk" | grep -qF -- "${PWD##*/}"; then
      continue
    fi
    deny "Worktree-UNSCOPED kill of gate processes blocked: '$(echo "$pk" | cut -c1-60)'. Every bats command line on this box contains '/libexec/bats-core/bats', so this pattern SIGKILLs EVERY concurrent session's landing gate machine-wide, not just yours — the measured root cause of the 2026-07-26 false-RED epidemic (backlog a0718a5d78b3): the victim reports the kill as a gate RED, its item re-blocks, the dispatcher retries, load climbs, more gates die. Use the scoped helper: 'scripts/gate-cleanup.sh --dry-run' to see the selection, then the same without --dry-run. It signals only processes whose cwd is inside THIS worktree, plus their descendants. To scope a pattern by hand, name the worktree in it: pkill -f \"bats.*\${PWD##*/}\"."
  done <<<"$PK_OCCURRENCES"
fi

# DDL via any mechanism (turso shell, sqlite3, echo|pipe, etc.) — only
# blocked when in DATABASE-COMMAND context. This avoids false positives on
# commit messages that discuss DDL ("fix: block DROP TABLE in migration").
# A command like `echo "DROP TABLE x" | turso db shell` still matches because
# BOTH conditions are true.
if echo "$CMD" | grep -qiE '\b(turso|sqlite3?|psql|mysql|mariadb|libsql|drizzle-kit[[:space:]]+(push|drop|migrate))\b' \
   && echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then
  deny "DDL blocked — all schema changes must go through Drizzle migrations (pnpm generate). See CLAUDE.md critical rule #1."
fi

# drizzle-kit push bypasses migration history
if echo "$CMD" | grep -qE 'drizzle-kit[[:space:]]+push'; then
  deny "drizzle-kit push bypasses migration history and causes schema drift. Use pnpm generate instead."
fi

# git add -f / --force (argv-aware)
if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
  deny "git add --force blocked — gitignored files are intentionally excluded. Force-adding bypasses .gitignore protection."
fi
if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
  deny "git add -f blocked — gitignored files are intentionally excluded. Force-adding bypasses .gitignore protection."
fi

# --no-verify bypasses pre-commit hooks (CLAUDE.md critical rule)
# argv-aware: recognises that `--no-verify` inside a quoted -m / -F message
# body is not a real flag to git.
if check_real_flag "--no-verify"; then
  deny "--no-verify blocked — bypasses pre-commit hooks. Fix the underlying hook failure instead. See CLAUDE.md critical rule #2."
fi

# --no-gpg-sign also bypasses signing policy
if check_real_flag "--no-gpg-sign"; then
  deny "--no-gpg-sign blocked — bypasses commit signing policy. See CLAUDE.md git-safety rules."
fi

# git commit -n short form of --no-verify (head-aware regex). `-n` is meaningful
# only when preceded by `git commit` (or git commit --amend, etc.). Cannot use
# is_true_flag since `-n` is common on many tools (cat -n, sed -n, head -n).
if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then
  deny "git commit -n blocked — short form of --no-verify, bypasses pre-commit hooks. See CLAUDE.md critical rule #2."
fi

# ── the identity GATE's own escape hatches (2026-08-08) ───────────────
# The rules above refuse `--no-verify` and `git commit -n` — the escape an agent reaches for FIRST
# when githooks/pre-commit refuses it. A red-team found that the two which actually WORK were both
# unblocked and documented as supported overrides three lines from the refusal message, so an
# agent under "🔧 never yields" was being steered straight at them:
#
#   CC_GIT_IDENTITY_OWNER=x git commit …        takes the repo OUT OF SCOPE, so the gate exits 0
#                                               without ever reading the identity. Silent.
#   git config --local cc.identity.exempt "…"   exempts the repo — and from a linked worktree that
#                                               writes the SHARED config, exempting ~200 at once.
#
# The vars are now sealed behind CC_GIT_IDENTITY_TEST=1 (the suite sets it, production does not),
# so the single-var form is already inert. This blocks the two-var form and the exemption: a
# bypass that merely also has to disable the seal is still a bypass, and an exemption is a
# DECISION about how the operator's commits are attributed, which is theirs to make.
if printf '%s' "$CMD" | grep -qE '\bCC_GIT_IDENTITY_(TEST|EMAIL|OWNER|HOOK)='; then
  deny "CC_GIT_IDENTITY_* assignment blocked — these are the identity gate's TEST seams, not a route past it. Setting OWNER takes the repo out of scope so the gate never reads the identity at all; setting EMAIL widens the allowlist. If a commit is being refused, the identity is genuinely wrong — run the cure the hook printed. To run the suite, invoke bats (it sets the sentinel itself); never set these by hand."
fi
# WRITES only. The first cut matched the key anywhere after `config`, so `--get cc.identity.exempt`
# — the way you INSPECT an exemption, and what the sweep itself does — was denied. A guard that
# blocks reading the thing it guards makes the state unauditable, which is the opposite of the
# point. Same read-form exclusion the identity-write clause below uses, and a write is recognised
# the same way: the key must be FOLLOWED BY A VALUE.
if printf '%s' "$CMD" | grep -qE '\bconfig\b' \
   && ! printf '%s' "$CMD" | grep -qE '\-\-(get|get-all|get-regexp|list|unset|unset-all|remove-section)\b' \
   && printf '%s' "$CMD" | grep -qE '\bcc\.identity\.exempt[[:space:]]+[^[:space:]]'; then
  deny "cc.identity.exempt write blocked — an exemption declares that a repo's commits SHOULD carry a non-default address. That is the operator's call, not a way to clear a refusal. From a linked worktree 'git config --local' writes the SHARED .git/config, so it exempts every worktree of the repo at once (~200 here). If the identity is simply wrong, fix the identity; if the repo genuinely needs a project address, ask."
fi

# ── git identity write that can collapse into the CURRENT repo ────────
# 2026-08-05 incident: `git -C "" config user.email t@t` is a DOCUMENTED NO-OP on the -C — it
# does NOT change directory (verified live on git 2.54.0), so the write lands in whatever repo
# is cwd. claude-infrastructure is one bare repo with ~100 linked worktrees that SHARE a single
# .git/config, so one such line re-authors every session on the box: 9 mis-attributed commits
# here, 214 on reso. Local scope beats global and `t@t` matches no GitHub account, so the only
# true repair is rewrite+force-push across 213 live worktrees — i.e. unrepairable after the fact.
# Prevention is the whole game. Evidence: docs/research/git-identity-leak-2026-08-05.md §D.
#
# Why THIS hook: the corpus half of the leak is a tree-wide lint over source. Reso has no leaky
# source at all — it was poisoned by an agent hand-typing the same line in an adversarial repro
# (the advV/advJ rows approved into its settings.local.json:470-476). A source lint is
# structurally blind to that. A PreToolUse hook is the only thing that sees it.
#
# Why the SHAPE and not the spelling: this hook reads the command BEFORE expansion, so
# `-C "$SOMEDIR"` is statically undecidable — it is empty exactly when the accident happens, and
# never when you test it. Matching a literal `-C ""` would be a denylist of one spelling that
# misses every real occurrence (memory: denylist-enumerates-spellings-not-the-class). So the rule
# is the research doc's lint rule 2 applied to argv: an identity WRITE must name its target with
# something that CANNOT expand to nothing. `-C /tmp/x`, `-C "$tmp/repo"` and `-C "${r:?}"` pass;
# `-C "$1"`, `-C "$REPO"`, `-C ""`, `-C "$(mktemp -d)"` and a bare no-`-C` write do not.
#
# `cd <target> &&` counts as naming the target, but is held to the SAME test — and that is a
# correction to the research doc's own §Fixes table, measured here: **`cd "" ` SUCCEEDS** (rc 0,
# cwd unchanged). So the prescribed `cd "$repo" || exit 1` idiom guards a *nonexistent* path and
# not an *empty* one — against the empty variable it is inert, and `&&` short-circuiting never
# fires. Both collapse paths therefore need the identical literal-remainder test.
#
# NOT matched, by construction: reads (`--get*`, `--list`, `-l`), the `--unset*` repair this
# incident actually needed (a guard that denies its own fix is the -rf lesson), explicitly-scoped
# writes (`--global`/`--system`/`--file`/`--blob` name their own target — no cwd to collapse
# into), and the transient `git -c user.email=… commit` form, which is lowercase `-c`, is not a
# `config` subcommand, and cannot persist at all — it is the recommended shape.

# Every `$…` below is a LITERAL to be matched, never an expansion to be performed — that is the
# whole point of a guard that reads commands before the shell does. Single quotes are load-bearing.
# shellcheck disable=SC2016
# _gid_literal_survives <token> — 0 when the token cannot expand to nothing.
# Delete-then-match, never widen: strip quotes, delete every expansion, and ask whether any
# LITERAL text is left. `"$tmp/repo"` leaves `/repo` (safe); `"$1"` and `""` leave nothing.
_gid_literal_survives() {
  local t="$1"
  # `${v:?}` / `${v:?msg}` aborts on empty rather than expanding to it — the doc's own
  # prescribed helper guard. Treat it as naming a target even though it is all-expansion.
  case "$t" in *':?'*) return 0 ;; esac
  t="$(printf '%s' "$t" | tr -d "\"'")"
  # A command substitution containing whitespace is TORN APART by the positional walk, so the
  # target arrives as the fragment `$(mktemp` and the balanced-form deletion below can never
  # match it — it would survive as literal text and pass. Any substitution marker at all means
  # the value is computed at runtime and can come back empty: `$(mktemp -d)` on a full disk is
  # precisely the unchecked-mktemp leak site the research doc lists.
  case "$t" in *'$('*|*'`'*) return 1 ;; esac
  t="$(printf '%s' "$t" | sed -E 's/\$\([^)]*\)//g; s/`[^`]*`//g; s/\$\{[^}]*\}//g; s/\$[A-Za-z_][A-Za-z0-9_]*//g; s/\$[0-9@*#?-]//g')"
  [ -n "$t" ]
}

# _gid_target_of <clause> — prints the token that NAMES the write target, empty if none.
# Positional walk, not a regex: only argv position can tell a real `-C` from the same two
# characters inside a quoted value. `-C` wins over `--git-dir=`, which wins over a governing `cd`.
_gid_target_of() {
  local tok prev="" c="" g="" d=""
  set -f  # a command containing `*` must not glob against the cwd during the walk
  for tok in $1; do
    case "$prev" in
      -C) [ -n "$c" ] || c="$tok" ;;
      cd) [ -n "$d" ] || d="$tok" ;;
    esac
    case "$tok" in --git-dir=*) [ -n "$g" ] || g="${tok#--git-dir=}" ;; esac
    prev="$tok"
  done
  set +f
  printf '%s' "${c:-${g:-$d}}"
}

# Fast pass-through, BUILTIN and fork-free. This hook runs on every Bash tool call in the fleet
# and the clause scan below costs one fork per clause, so the common case (no identity key
# anywhere in the command) must not reach it at all — the same measured concern that replaced
# `$(cat)` with `read -d ''` at the top of this file (~6 ms per fork, ~18% of a 163 ms chain).
if [[ "$CMD" == *user.email* || "$CMD" == *user.name* ]]; then
# Split on `;` and `|` so a compound command cannot be exonerated by a sibling clause (the
# per-target lesson the rm scan below already learned) — but NEVER on `&&`, which is what
# GOVERNS the fragment: splitting there would hide the `cd … &&` and convict a guarded write.
# `tr` pads the replacement set with its last char, so one `\n` maps BOTH delimiters — spelling it
# '\n\n' is the same operation with a duplicate shellcheck rightly flags (SC2020).
GID_CLAUSES="$(printf '%s' "$CMD" | tr ';|' '\n')"
while IFS= read -r gid_clause; do
  printf '%s' "$gid_clause" | grep -qE 'git\b.*\bconfig\b.*\buser\.(email|name)\b' || continue
  # Reads, the repair, and explicitly-scoped writes are never blocked.
  printf '%s' "$gid_clause" | grep -qE '\-\-(get|get-all|get-regexp|get-urlmatch|list|unset|unset-all|remove-section|rename-section|global|system|file|blob)\b' && continue
  printf '%s' "$gid_clause" | grep -qE '[[:space:]]-(l|e)([[:space:]]|$)' && continue
  # A bare `git config user.email` READS. Only a key FOLLOWED BY A VALUE writes.
  printf '%s' "$gid_clause" | grep -qE '\buser\.(email|name)[[:space:]]+[^[:space:]]' || continue

  gid_target="$(_gid_target_of "$gid_clause")"
  if [ -z "$gid_target" ]; then
    deny "git identity write with no target blocked — 'git config user.email/name <value>' writes to whatever repo is CURRENT. claude-infrastructure is one bare repo whose ~100 linked worktrees SHARE a single .git/config, so this re-authors every session on the machine (2026-08-05: 9 mis-attributed commits here, 214 on reso; unrepairable without a rewrite+force-push across 213 live worktrees). Use the transient form, which cannot persist: git -c user.email=you@example.com -c user.name='Your Name' commit … — or name the repo with a literal path: git -C /tmp/your-fixture config user.email … . To read, --get; to clean up, --unset-all; to set your real global identity, --global."
  fi
  if ! _gid_literal_survives "$gid_target"; then
    deny "git identity write to an all-expansion target blocked: -C '$gid_target'. That argument is entirely a variable/substitution, so it is EMPTY exactly when the accident happens — and 'git -C \"\"' is a documented NO-OP that does not change directory, dropping the write into the CURRENT repo instead (verified live, git 2.54.0). That is the 2026-08-05 leak: ~100 linked worktrees share one .git/config, so one such line re-authored 9 commits here and 214 on reso. 'cd \"\"' does NOT save you either — it exits 0 and stays put, so '&&' never short-circuits. Give the target a literal segment that cannot vanish (git -C \"\$tmp/repo\" config … ), assert it first (git -C \"\${dir:?repo path required}\" config … ), or best, use the transient form that cannot persist at all: git -c user.email=… -c user.name=… commit … ."
  fi
done <<<"$GID_CLAUSES"
fi

# ── Warn (ask): destructive but sometimes intentional ────────────────

# git reset --hard — can destroy uncommitted work
if echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard\b'; then
  warn "git reset --hard can destroy uncommitted work. Verify intentional."
fi

# git clean -x / -X removes gitignored files (may include paid assets).
# Match any flag bundle containing x or X after `git clean -`.
if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then
  warn "git clean -x/-X removes gitignored files which may include paid assets (AI-generated images, API outputs). Confirm intentional — safer alternative is git clean -fd (no -x)."
fi

# Recursive rm on non-safe targets. Per-target evaluation avoids the compound-command escape
# hatch (e.g., `rm -rf src && rm -rf node_modules` used to silently pass because one clause
# matched a safe target).
SAFE_RM_TARGETS='(node_modules|\.next|dist|__pycache__|\.cache|build|\.turbo|coverage|test-results|out|\.vercel|artifacts|\.pytest_cache|target|\.tox|htmlcov|\.ruff_cache|\.mypy_cache)'

# is_safe_rm_target <argv-token> — shared by both paths below, for the same no-drift reason.
is_safe_rm_target() {
  # Strip leading `./` or `/` (but NOT a leading `.` — `.next` must match `\.next`).
  # Two separate subs to avoid `|` collision with sed's delimiter.
  local stripped
  stripped=$(printf '%s' "$1" | sed -E 's|^\./||; s|^/||')
  printf '%s' "$stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"
}

if [[ "$RM_PRESENT" == "1" && "$RM_SCAN_OK" == "1" ]]; then
  # Same spelling blindness as the deny above lived here too, one flag-bundle enumeration further
  # on: `-(r|rf|fr)` knew neither `-R` nor `--recursive`, so `rm -Rf /etc` and
  # `rm --recursive --force src` emitted no decision at all. Recursive in ANY spelling, with or
  # without force, is the trigger — unchanged in meaning, only in reach.
  while IFS=$'\t' read -r rm_rec rm_force rm_target; do
    [[ "$rm_rec" == "1" ]] || continue
    if ! is_safe_rm_target "$rm_target"; then
      warn "rm -r on non-build-artifact target: '$rm_target'. Verify intentional."
    fi
  done <<<"$RM_SCAN"
elif [[ "$RM_PRESENT" == "1" ]]; then
  RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+(-[a-zA-Z-]+[[:space:]]+)*[^[:space:];&|-][^[:space:];&|]*' || true)
  if [[ -n "$RM_OCCURRENCES" ]]; then
    while IFS= read -r occurrence; do
      printf '%s' "$occurrence" | grep -qE '(^|[[:space:]])-[a-zA-Z]*[rR][a-zA-Z]*([[:space:]]|$)|--recursive([[:space:]=]|$)' || continue
      target=$(printf '%s' "$occurrence" | sed -E 's/^rm[[:space:]]+(-[a-zA-Z-]+[[:space:]]+)*//')
      if ! is_safe_rm_target "$target"; then
        warn "rm -r on non-build-artifact target: '$target'. Verify intentional."
        # shellcheck disable=SC2317  # reachable: warn() exits, so this only runs if warn is stubbed
        break
      fi
    done <<<"$RM_OCCURRENCES"
  fi
fi

# (Layer-3 #9 writer-lock guard removed 2026-06-03 — always-worktree isolation makes it a
# no-op; the reso-writer-lock.py + concurrent-writer-guard.sh stack was deleted. See the
# parallel-sessions-simple plan / memory parallel-sessions-simple-2026-06-03.)

# Log command for audit — ISO timestamp + session id prefix (D-3). The bare `echo "$CMD"` left a
# 13 MB log with no attribution and no line anchor: nothing was greppable by session, and a
# multi-line command shredded the line structure with no way to tell a continuation line from a
# new entry. `.session_id` comes from stdin (never CLAUDE_SESSION_ID — CC does not export it, D-9).
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "-"' 2>/dev/null)
[ -n "$SID" ] || SID="-"
mkdir -p ~/.claude/logs
echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log
exit 0
