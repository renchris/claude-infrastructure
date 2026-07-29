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
_CC_ISOLATE[$HOME/.claude-next]='.claude.json .claude.json.backup'
_CC_ISOLATE[$HOME/.claude-secondary]='.claude.json .claude.json.backup .credentials.json projects sessions session-env shell-snapshots history.jsonl session-index.db session-index.db-shm session-index.db-wal session-index.lock session-index.lock.d stats-cache.json statsig telemetry watchdog teams logs file-history run ide state debug plan-history plan-versions drafts mcp-needs-auth-cache.json .last-session .last-interaction .last-search-results.json'
_CC_ISOLATE[$HOME/.claude-tertiary]='.claude.json .claude.json.backup .credentials.json projects sessions session-env shell-snapshots history.jsonl session-index.db session-index.db-shm session-index.db-wal session-index.lock session-index.lock.d stats-cache.json statsig telemetry watchdog teams logs file-history run ide state debug plan-history plan-versions drafts mcp-needs-auth-cache.json .last-session .last-interaction .last-search-results.json'
_CC_ISOLATE[$HOME/.claude-quaternary]='.claude.json .claude.json.backup .credentials.json projects sessions session-env shell-snapshots history.jsonl session-index.db session-index.db-shm session-index.db-wal session-index.lock session-index.lock.d stats-cache.json statsig telemetry watchdog teams logs file-history run ide state debug plan-history plan-versions drafts mcp-needs-auth-cache.json .last-session .last-interaction .last-search-results.json'

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
  for k in ${(s: :)${_CC_ISOLATE[$dst]:-.claude.json .claude.json.backup}}; do keep[$k]=1; done
  local e name
  for e in "$src"/*(ND); do
    name="${e:t}"
    [[ -n "$keep[$name]" ]] && continue                                   # isolated → leave dst's own
    [[ -L "$dst/$name" && "$(readlink "$dst/$name")" == "$e" ]] && continue  # already the right symlink
    if [[ -e "$dst/$name" && ! -L "$dst/$name" ]]; then                   # a forked real file/dir
      (( convert )) || continue                                           # safe mode: don't touch it
      mv -f "$dst/$name" "$dst/$name.premirror-bak" 2>/dev/null
    fi
    ln -sfn "$e" "$dst/$name"
  done
  # Heal: an isolated entry that got wrongly symlinked to ~/.claude (the account-state leak).
  for k in ${(k)keep}; do
    [[ -L "$dst/$k" ]] && { rm -f "$dst/$k"; print -u2 "config-mirror: un-shared isolated '$k' in ${dst:t}"; }
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
    [[ -L "$d" && "$(readlink "$d")" == "$c" ]] && continue        # already shared
    if [[ -d "$d" && ! -L "$d" ]]; then                            # dst has its own real memory
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

# Combined per-account sync: knowledge-layer config + per-slug project memory.
_cc_sync_account() {
  local dst conv=0
  [[ "$1" == --convert ]] && { conv=1; shift; }
  dst="${1:?}"
  if (( conv )); then
    _cc_sync_config_mirror --convert "$dst" || return 1
    _cc_sync_memory_mirror --convert "$dst"
  else
    _cc_sync_config_mirror "$dst" || return 1
    _cc_sync_memory_mirror "$dst"
  fi
}
