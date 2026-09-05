# ~/.claude/lib/config-mirror.zsh — single source of truth for the knowledge-layer mirror.
# Sourced by ~/.zshrc (interactive) AND by ~/.claude/hooks/config-mirror-assert.sh (zsh -f).
#
# Model (rot-proof): symlink EVERYTHING from ~/.claude into a per-account config dir EXCEPT the
# per-dir isolate-set below. New config dirs that appear in ~/.claude auto-share; only genuine
# per-account state needs an isolate entry. Auth is NOT here — it lives in the macOS Keychain,
# keyed by sha256(CLAUDE_CONFIG_DIR)[:8], so it is isolated automatically by the distinct dir.
#
#   ~/.claude-next      = SAME account 1 (different binary track) → shares transcripts; isolates
#                         only .claude.json (the one state file that races between concurrent CCs).
#   ~/.claude-secondary = DIFFERENT account 2 → ALSO isolates all session/usage/identity state,
#                         or re-syncing would mix the two accounts' transcripts + usage.
#   ~/.claude-tertiary  = DIFFERENT account 3 → same full account isolation as account 2.
#   ~/.claude-quaternary = DIFFERENT account 4 → same full account isolation as account 2.
#
# WHY `tasks` / `tasks-index.json` ARE **NOT** ISOLATED (changed 2026-07-29). They were, having been
# swept into the "all session/usage/identity state" bucket with transcripts and usage counters. That
# was a mis-classification with a real cost: a task board is WORK state, not ACCOUNT state. The four
# accounts here are quota pools for one operator, not four different people, so a board splitting
# four ways along an axis the operator does not think in is pure loss. Measured before the change:
# `claude-infrastructure-main` existed as FOUR divergent boards (15 / 0 / 3 / 23 tasks) whose ids
# collided while carrying different work, 14 boards were populated in an account store while their
# canonical twin sat empty, and an account-3 session launched with the SAME
# CLAUDE_CODE_TASK_LIST_ID wrote into ~/.claude-tertiary/tasks entirely invisibly to account 1.
# The task hooks (hooks/lib/task-helpers.sh, hooks/setup-task-symlinks.sh) had always hardcoded
# ~/.claude/tasks, so for three of four accounts the index, the _current symlink and the desk's
# cross-project rollup were already pointing at boards Claude Code never wrote to.
#
# Sharing is safe under concurrency — proven, not assumed: two sessions creating tasks on one board
# simultaneously both survived with distinct ids (the store is lock-serialised per board).
#
# MIGRATION ORDER IS LOAD-BEARING. Removing these keys makes `--convert` eligible to replace an
# account's real tasks/ dir with a symlink, and --convert resolves a forked real dir with
# `mv -f <dir> <dir>.premirror-bak` — which for 245/251/186 boards means they simply stop being
# reachable. Run `cc-task-store merge` (content) BEFORE any --convert (linkage). cc-task-store is
# additive and never modifies a source, so the order is enforceable and re-runnable.

typeset -gA _CC_ISOLATE
_CC_ISOLATE[$HOME/.claude-next]='.claude.json .claude.json.backup backups-identity daemon jobs'
_CC_ISOLATE[$HOME/.claude-secondary]='.claude.json .claude.json.backup backups-identity daemon jobs .credentials.json projects sessions session-env shell-snapshots history.jsonl session-index.db session-index.db-shm session-index.db-wal session-index.lock session-index.lock.d stats-cache.json statsig telemetry watchdog teams logs file-history run ide state debug plan-history plan-versions drafts mcp-needs-auth-cache.json .last-session .last-interaction .last-search-results.json'
_CC_ISOLATE[$HOME/.claude-tertiary]='.claude.json .claude.json.backup backups-identity daemon jobs .credentials.json projects sessions session-env shell-snapshots history.jsonl session-index.db session-index.db-shm session-index.db-wal session-index.lock session-index.lock.d stats-cache.json statsig telemetry watchdog teams logs file-history run ide state debug plan-history plan-versions drafts mcp-needs-auth-cache.json .last-session .last-interaction .last-search-results.json'
_CC_ISOLATE[$HOME/.claude-quaternary]='.claude.json .claude.json.backup backups-identity daemon jobs .credentials.json projects sessions session-env shell-snapshots history.jsonl session-index.db session-index.db-shm session-index.db-wal session-index.lock session-index.lock.d stats-cache.json statsig telemetry watchdog teams logs file-history run ide state debug plan-history plan-versions drafts mcp-needs-auth-cache.json .last-session .last-interaction .last-search-results.json'

# ── fork-free symlink-target read ──────────────────────────────────────────────────────────────
# `$(readlink X)` costs a FORK PLUS A SUBSHELL per call, and the mirror calls it once per mirrored
# entry. Measured 2026-08-10 on this box: _cc_sync_config_mirror took 1554 ms on ~/.claude-next
# (186 symlinks / 400 entries) and 1473 ms on ~/.claude-secondary (192 / 437) — against 1.8 ms for
# the same 314-iteration loop via zsh/stat. The launcher runs this on EVERY start and SessionStart's
# config-mirror-assert.sh runs the whole thing AGAIN, so an interactive launch paid the fork storm
# at least twice (three times on claude2/3/4, which also walk the memory mirror).
#
# 🚨 The saving is in deleting the COMMAND SUBSTITUTION, not merely the readlink binary: `$( )`
# forks a subshell whatever is inside it. So this helper SETS a variable and prints nothing — a
# `$(_cc_linktarget …)` call site would re-introduce the entire cost it exists to remove.
#
# zstat +link yields the RAW link target, byte-identical to readlink (verified over every symlink
# in ~/.claude, 0 mismatches). It is deliberately NOT ${f:A}/${f:P}, which fully RESOLVE the path —
# every comparison below wants the literal target, and resolution would silently change the verdict
# for a link that points at another link. Falls back to readlink when the module is unavailable, so
# correctness never depends on zsh/stat being present.
typeset -g _CC_LINK=''
typeset -g _CC_HAVE_ZSTAT=0
zmodload -F zsh/stat b:zstat 2>/dev/null && _CC_HAVE_ZSTAT=1
_cc_linktarget() {   # <path> → sets $_CC_LINK to the raw symlink target ('' if not a symlink)
  _CC_LINK=''
  if (( _CC_HAVE_ZSTAT )); then
    local -a _z
    zstat -L -A _z +link -- "$1" 2>/dev/null && _CC_LINK="${_z[1]}"
  else
    _CC_LINK="$(readlink "$1" 2>/dev/null)"
  fi
}

# _cc_sync_config_mirror [--convert] <dst-config-dir>
#   Default (no --convert): RACE-SAFE. Creates MISSING symlinks + HEALS isolated entries that were
#   wrongly symlinked to ~/.claude (e.g. the .last-session leak). It NEVER mv's a forked real dir,
#   so it is safe to run while other sessions on the same dir are live (launcher + SessionStart use this).
#   --convert: ALSO mv forked real dirs → *.premirror-bak then symlink. Heavy; run only with all that
#   account's panes closed (the lsof-guarded claude-next-convert-secondary one-shot uses this).
_cc_sync_config_mirror() {
  emulate -L zsh
  local convert=0; [[ "$1" == --convert ]] && { convert=1; shift; }
  local src="$HOME/.claude" dst="${1:?}"
  [[ "$dst" == "$HOME/.claude-"* && "$dst" != "$src" ]] || { print -u2 "config-mirror: refusing target $dst"; return 1; }
  mkdir -p "$dst" || return 1
  local -A keep; local k
  for k in ${(s: :)${_CC_ISOLATE[$dst]:-.claude.json .claude.json.backup backups-identity daemon jobs}}; do keep[$k]=1; done
  local e name
  for e in "$src"/*(ND); do
    name="${e:t}"
    # A DERIVATIVE OF AN ISOLATED NAME IS ISOLATED (backlog fa475126f710). The isolate lists are
    # SPELLINGS, and the identity family has many: measured on this box, ~/.claude-quaternary holds
    # 28 `.claude.json*` entries (25 of them `.claude.json.tmp.<pid>.<hash>`, full identity
    # snapshots) and ~/.claude-next holds 8 including `.claude.json.bak-ms365-restore` — against
    # exactly two listed spellings. This is the same failure the transient arm below already
    # records in its own comment: "the per-dir isolate lists already carried session-index.lock and
    # STILL missed .oauth_refresh.lock when the vendor added it."
    #
    # It is latent rather than live only because the share loop walks $src, and ~/.claude currently
    # holds just the two listed names. The moment it acquires one — an ms365 restore, or CC's own
    # `.claude.json.tmp.<pid>.<hash>` caught mid-write — the loop shares it into all four accounts;
    # under --convert that means `mv -f` an account's real identity file to .premirror-bak and
    # symlink another account's in its place, and for the .tmp spelling it means a DANGLING link
    # the instant the vendor renames it.
    #
    # DERIVED FROM THE DECLARED POLICY, NOT A NEW ONE: a name is isolated when stripping dot-suffixes
    # reaches a name this dir already isolates. So `.claude.json.bak-ms365-restore` and
    # `.claude.json.tmp.9.a` follow `.claude.json` in EVERY dir, `.credentials.json.*` follows
    # `.credentials.json` only in the dirs that isolate it (accounts 2-4, never .claude-next, which
    # shares account 1's credentials by design), and `settings.json.bak-*` stays SHARED because
    # `settings.json` is not isolated anywhere. Adding a spelling to a list is no longer required.
    if [[ -z "$keep[$name]" ]]; then
      local _b="$name"
      while [[ "$_b" == ?*.* ]]; do
        _b="${_b%.*}"
        [[ -n "$keep[$_b]" ]] && { keep[$name]=1; break; }
      done
    fi
    [[ -n "$keep[$name]" ]] && continue                                   # isolated → leave dst's own
    # NEVER share a runtime lock/pid/socket. These are TRANSIENT: the mirror can catch one during
    # the instant it exists in ~/.claude, and once the real file is released every account dir is
    # left holding a DANGLING symlink. A dangling lock is not inert — proper-lockfile reads
    # mkdir=EEXIST + stat=ENOENT as ELOCKED, i.e. "held, forever", so the operation it guards can
    # never run again. That is exactly what disabled the in-session OAuth token refresh on all four
    # accounts: symlinks born 2026-07-31 14:58-16:36, first forced /login 70 minutes later, then an
    # 8-hourly logout-while-working for two days (heal() kept the fleet alive only because it
    # bypasses the lock — and only fires when an account has ZERO live sessions).
    # Pattern-matched, not enumerated: the per-dir isolate lists already carried session-index.lock
    # and STILL missed .oauth_refresh.lock when the vendor added it. The next new lock must be safe
    # without anyone editing this file.
    if [[ "$name" == *.lock || "$name" == *.lock.d || "$name" == *.pid || "$name" == *.sock ]]; then
      [[ -L "$dst/$name" ]] && { rm -f "$dst/$name"; print -u2 "config-mirror: un-shared transient '$name' in ${dst:t}"; }
      continue
    fi
    if [[ -L "$dst/$name" ]]; then
      _cc_linktarget "$dst/$name"
      [[ "$_CC_LINK" == "$e" ]] && continue                               # already the right symlink
    fi
    if [[ -e "$dst/$name" && ! -L "$dst/$name" ]]; then                   # a forked real file/dir
      # SAFE MODE SKIPS A FORK, BUT IT MUST NOT DO SO SILENTLY. Every other outcome in this loop
      # announces itself on stderr — un-shared transient, un-shared isolated, reaped dangling — and
      # the fork was the only one that did not, while being the ONLY one that persists indefinitely:
      # the three noisy cases are all self-healing on the next run, and this one is by construction
      # unreachable without --convert. So the mirror ran at every session start, correctly, and was
      # structurally incapable of reporting the single condition it could not fix.
      # MEASURED 2026-09-04: ~/.claude-next carried forked real `commands` (frozen 2026-07-18),
      # `hooks` (53 entries vs 82) and `scripts` (55 vs 193) for SEVEN WEEKS. The operator found it
      # by typing a slash command that had landed, been converged to the live layer, and verified in
      # ~/.claude — and getting "No commands match". Nothing on the box had said a word.
      # The ACTUATOR reports, deliberately: a separate detector would have to re-implement the
      # isolate list, the transient-name skip and the already-correct-symlink test, and would drift
      # from them silently. This line cannot disagree with the decision it is reporting.
      (( convert )) || { print -u2 "config-mirror: FORKED real '$name' in ${dst:t} — shadows ~/.claude/$name; safe mode cannot fix it, run with --convert (all that account's panes closed)"; continue; }
      mv -f "$dst/$name" "$dst/$name.premirror-bak" 2>/dev/null
    fi
    ln -sfn "$e" "$dst/$name"
  done
  # Heal: an isolated entry that got wrongly symlinked to ~/.claude (the account-state leak).
  for k in ${(k)keep}; do
    [[ -L "$dst/$k" ]] && { rm -f "$dst/$k"; print -u2 "config-mirror: un-shared isolated '$k' in ${dst:t}"; }
  done
  # Reap symlinks into ~/.claude whose target has since DISAPPEARED. The share loop above walks
  # `$src/*`, so it can only ever see names that still exist there — a link whose source was
  # deleted is unreachable by it, and the transient-name skip cannot fire either. Without this,
  # a captured-then-released file leaves a permanent dangling link. Scoped to targets under $src
  # so an operator's own symlink in a config dir is never touched, and it only removes links that
  # already resolve to nothing, so it can destroy no data.
  # (N@D): N=no-match-ok, @=symlinks only, D=INCLUDE DOTFILES. The D is load-bearing and its
  # absence is silent — every name this reaper exists for (.oauth_refresh.lock, .credentials.json)
  # begins with a dot, so without D the loop is a no-op that still looks correct.
  local l
  for l in "$dst"/*(N@D); do
    _cc_linktarget "$l"
    [[ "$_CC_LINK" == "$src"/* ]] || continue            # not ours — leave it alone
    [[ -e "$l" ]] && continue                            # target still resolves — healthy
    rm -f "$l"; print -u2 "config-mirror: reaped dangling '${l:t}' in ${dst:t}"
  done
  # Seed .claude.json ONLY for SAME-account dirs (e.g. ~/.claude-next — intentionally shares
  # account 1's identity). CROSS-account dirs (isolate-set keeps .credentials.json) must start
  # logged OUT: copying account 1's .claude.json makes them silently resume account 1 via the
  # bare-Keychain fallback, since their dir-keyed slot sha256(dir)[:8] is empty until first
  # /login (the 2026-06-10 account-3 bug). Absent .claude.json → CC first-runs; the user /logs-in
  # once, which writes the new token to the dir-keyed Keychain slot (account 1's slot untouched).
  if [[ ! -f "$dst/.claude.json" && -z "$keep[.credentials.json]" ]]; then
    cp "$src/.claude.json" "$dst/.claude.json" 2>/dev/null
  fi
  # Guard: the SHARED settings.json must never carry an account-pinning auth key (it would override
  # the per-dir Keychain token for BOTH accounts). Such keys belong in a per-dir settings.local.json.
  grep -qE '"(ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN|CLAUDE_CODE_OAUTH_TOKEN|apiKeyHelper|forceLoginMethod|forceLoginOrgUUID)"' "$src/settings.json" 2>/dev/null \
    && print -u2 "⚠️  config-mirror: shared settings.json has an account-pinning auth key — move it to a per-dir settings.local.json"
  return 0
}

# Per-slug project-memory sharing (cross-account dirs only — those whose isolate-set keeps projects/
# REAL). Shares each project's memory/ subdir by symlinking it to account 1's canonical
# ~/.claude/projects/<slug>/memory, so BOTH accounts share a project's memory while the transcripts
# (*.jsonl, alongside it) stay isolated per account — this is the per-project-separation model.
# Same-account dirs (~/.claude-next: projects/ fully symlinked) already share memory → skipped.
#   default (safe): only create symlinks where dst's slug memory is absent (pure additive, race-safe).
#   --convert: also MERGE a real dst memory dir into canonical (rsync --ignore-existing keeps
#              canonical's copies + adds dst-only files; MEMORY.md indexes are line-unioned), back it
#              up → *.premirror-bak, then symlink. No data loss: canonical kept, dst preserved in .bak.
_cc_sync_memory_mirror() {
  emulate -L zsh
  local convert=0; [[ "$1" == --convert ]] && { convert=1; shift; }
  local dst="${1:?}" cano="$HOME/.claude/projects"
  [[ "$dst" == "$HOME/.claude-"* && "$dst" != "$HOME/.claude" ]] || { print -u2 "memory-mirror: refusing $dst"; return 1; }
  [[ " ${_CC_ISOLATE[$dst]} " == *" projects "* ]] || return 0   # same-account already shares memory
  local -A slugs; local sp slug c d
  for sp in "$cano"/*(N/);         do slugs[${sp:t}]=1; done
  for sp in "$dst/projects"/*(N/); do slugs[${sp:t}]=1; done
  for slug in ${(k)slugs}; do
    c="$cano/$slug/memory"; d="$dst/projects/$slug/memory"
    if [[ -L "$d" ]]; then
      _cc_linktarget "$d"
      [[ "$_CC_LINK" == "$c" ]] && continue                        # already shared
    fi
    if [[ -d "$d" && ! -L "$d" ]]; then                            # dst has its own real memory
      if [[ ! -d "$c" ]]; then
        # ADOPT — safe in DEFAULT mode, because there is NOTHING TO MERGE. Canonical does not
        # exist, so no union has to be computed and no copy of anything can be lost: the move is
        # a rename and the symlink hands it straight back, so the writing session keeps reading
        # its own memory live (proven by hand on `sevenrooms-bridge`, 2026-08-22).
        #
        # This case used to fall into the `continue` below, which is why a project first touched
        # on a NON-PRIMARY account stranded FOREVER: no automation ever passes --convert
        # (config-mirror-assert.sh runs the mirror in default mode at SessionStart), so the skip
        # that is correct for the merge was also skipping the case that needs no merge. 13 slugs
        # were invisible to every other account when this was measured on 2026-08-22 — and since
        # the router picks an account by live quota headroom, that is silent knowledge loss.
        #
        # `mkdir "$c"` is an ATOMIC CLAIM, not a convenience. Between the -d test above and the
        # move, canonical can come into existence: the SAME slug can be stranded on two accounts
        # at once (`agent-workstation` was, on tertiary and quaternary), and an account-1 session
        # can start writing memory at any moment. A plain `mv "$d" "$c"` in that window does not
        # fail — POSIX mv moves the source INSIDE an existing directory, silently producing
        # "$c/memory" that no reader ever looks at. mkdir fails instead, this run leaves the slug
        # alone, and the next one sees both sides populated and routes to the merge branch, which
        # is the correct handling once canonical is real.
        local -a _ents
        mkdir -p "${c:h}" 2>/dev/null
        if command mkdir "$c" 2>/dev/null; then
          _ents=( "$d"/*(ND) )
          (( $#_ents )) && command mv -- $_ents "$c"/ 2>/dev/null
          # rmdir REFUSES a non-empty directory, so a partially-moved slug can never reach the
          # symlink: `ln -sfn "$c" "$d"` onto a surviving real dir would create "$d/memory"
          # rather than replace "$d", stranding the remainder one level deeper than it started.
          command rmdir "$d" 2>/dev/null && ln -sfn "$c" "$d"
        fi
        continue
      fi
      (( convert )) || continue                                    # safe mode: don't merge under a live session
      mkdir -p "$c"; command rsync -a --ignore-existing "$d"/ "$c"/ 2>/dev/null
      if [[ -f "$d/MEMORY.md" && -f "$c/MEMORY.md" ]] && ! cmp -s "$d/MEMORY.md" "$c/MEMORY.md"; then
        command python3 - "$c/MEMORY.md" "$d/MEMORY.md" <<'PY'
import sys
cano, dst = sys.argv[1], sys.argv[2]
have = {l.strip() for l in open(cano, errors="replace")}
add = [l for l in open(dst, errors="replace") if l.strip() and l.strip() not in have]
if add: open(cano, "a").write("\n<!-- merged from account 2 -->\n" + "".join(add))
PY
      fi
      mv -f "$d" "$d.premirror-bak"; ln -sfn "$c" "$d"
    elif [[ -d "$c" ]]; then                                       # acct1 has memory → share it to dst (additive)
      [[ -L "$d" ]] && rm -f "$d"                                  # heal a stale/wrong symlink
      mkdir -p "${d:h}"; ln -sfn "$c" "$d"
    fi
    # else (no canonical memory to share): leave dst untouched. A brand-new account-2-only project's
    # memory is folded into canonical on the next --convert run — no empty-dir litter for transient slugs.
  done
}

# ── Per-account long-lived OAuth token (`claude setup-token`, 1 year) ───────────────────────────
# CLAUDE_CODE_OAUTH_TOKEN is read from the environment by every Claude Code binary, and it is a
# GLOBAL: one export aims every LATER launch in that shell at whichever account minted it. The
# launchers are shell FUNCTIONS, not subshells, so `claude3` then `claude-prev2` runs both in one
# long-lived interactive shell — an export left behind by the first silently bearers account 3's
# token for account 2's session. So this is SET-OR-UNSET on every launch, never set-only: the
# unset arm is the entire mechanism, and the set arm alone would be worse than not doing this.
#
# Deliberately NOT the one-liner `[[ -r $f ]] && export X="$(<$f)" || unset X`: under
# `A && B || C` the C arm fires when B fails too, so the two branches stop being exclusive.
# Explicit if/else, so each branch is reachable only for its own reason.
#
# Fail-CLOSED on anything unexpected — config dir not one of the four accounts, file missing,
# unreadable, or empty/whitespace-only ⇒ UNSET. A truncated token file must never become a bogus
# bearer token: absent falls back to the Keychain credential, which is the working default.
#
# This does NOT touch, and cannot blind, the quota spine. The Keychain credential is a SEPARATE
# store — bin/claude-accounts bearers creds['accessToken'] read from the Keychain, never this env
# var — so minting year tokens leaves /accounts, cc-wave-plan, cc-value and cc-board intact.
typeset -gA _CC_OAUTH_TOKEN_ACCT
_CC_OAUTH_TOKEN_ACCT[$HOME/.claude-next]='next'
_CC_OAUTH_TOKEN_ACCT[$HOME/.claude-secondary]='next2'
_CC_OAUTH_TOKEN_ACCT[$HOME/.claude-tertiary]='next3'
_CC_OAUTH_TOKEN_ACCT[$HOME/.claude-quaternary]='next4'

_cc_oauth_token_env() {
  local acct tokf tok
  acct="${_CC_OAUTH_TOKEN_ACCT[${1:-}]:-}"
  if [[ -n "$acct" ]]; then
    tokf="$HOME/.claude/oauth-tokens/$acct.token"
    if [[ -r "$tokf" ]]; then
      tok="$(<"$tokf")"
      # Trim only leading/trailing whitespace — a hand-pasted secret often carries a stray space
      # or a wrapped newline. Plain ${..%%..}/${..##..} form, so this stays correct under `zsh -f`
      # (the assert hook's shell) without depending on extendedglob being set.
      tok="${tok#"${tok%%[![:space:]]*}"}"
      tok="${tok%"${tok##*[![:space:]]}"}"
      if [[ -n "$tok" ]]; then
        export CLAUDE_CODE_OAUTH_TOKEN="$tok"
        return 0
      fi
    fi
  fi
  unset CLAUDE_CODE_OAUTH_TOKEN
  return 0
}

# Combined per-account sync: knowledge-layer config + per-slug project memory.
_cc_sync_account() {
  local dst conv=0
  [[ "$1" == --convert ]] && { conv=1; shift; }
  dst="${1:?}"
  # FIRST, and unconditionally — before the early `return 1` below. The token has to be re-aimed
  # on EVERY launch, including the ones where the mirror fails: a sync failure that skipped this
  # would leave the PREVIOUS launcher's token exported, which is the cross-account misfire this
  # exists to prevent. Always returns 0, so _cc_sync_account's own exit status is unchanged (the
  # `claude` launcher branches on it to print its "config may be stale" warning).
  _cc_oauth_token_env "$dst"
  if (( conv )); then
    _cc_sync_config_mirror --convert "$dst" || return 1
    _cc_sync_memory_mirror --convert "$dst"
  else
    _cc_sync_config_mirror "$dst" || return 1
    _cc_sync_memory_mirror "$dst"
  fi
}
