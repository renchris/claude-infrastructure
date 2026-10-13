# stop-hook-forks-helpers.bash — shared by the four Stop-hook process-budget suites
# (operator-readout-forks, session-continue-forks, completion-assert-forks, boundary-handoff-forks).
#
# Two instruments, both hermetic:
#
#   shf_build_stubs  counts every external command a hook starts. Each name on the real PATH gets a
#                    wrapper that logs its name and execs the real tool, so behavior is unchanged and
#                    an unstubbed call cannot slip past the count (the tests/memory-nudge-forks.bats
#                    pattern). A hook is then run as `PATH="$STUB" /bin/bash <hook>`: /bin/bash is
#                    the interpreter the harness gives a Stop hook, not the one on a developer PATH.
#
#   shf_old_tree     rebuilds the hook as it was on trunk before this work, from git, so a parity
#                    test replays the real pre-change bytes instead of a remembered expectation.
#                    The named files hold their SHF_BASE content; everything else in hooks/, bin/
#                    and scripts/ is a symlink to the checkout, so both arms share one set of libs.

# Trunk just before the Stop-hook fork work (docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md, Wave 4).
SHF_BASE=e1fbd8a5a5b3c3835109c9a7d2a2a0f1caf0bac5

shf_build_stubs() { # <dir>
  local stub="$1" d f name
  local IFS=:
  mkdir -p "$stub"
  # First occurrence wins, exactly as PATH lookup resolves it.
  for d in $PATH; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      name="${f##*/}"
      [ -x "$f" ] && [ ! -d "$f" ] || continue
      case "$name" in *\'*|'') continue ;; esac
      [ -e "$stub/$name" ] && continue
      # shellcheck disable=SC2016  # $SHF_FORK_LOG and $@ belong to the generated wrapper
      printf '#!/bin/bash\nprintf %%s\\\\n %s >> "$SHF_FORK_LOG"\nexec %s "$@"\n' \
        "'$name'" "'$f'" > "$stub/$name"
    done
  done
  chmod +x "$stub"/*
}

# _shf_real_dir <tree> <repo> <rel dir> — make <tree>/<rel dir> a REAL directory whose entries are
# symlinks into the checkout, so one of them can be replaced without touching the checkout.
_shf_real_dir() {
  local tree="$1" repo="$2" rel="$3" e
  [ -d "$tree/$rel" ] && [ ! -L "$tree/$rel" ] && return 0
  case "$rel" in */*) _shf_real_dir "$tree" "$repo" "${rel%/*}" ;; esac
  rm -f "$tree/$rel"
  mkdir -p "$tree/$rel"
  for e in "$repo/$rel"/*; do
    [ -e "$e" ] || continue
    ln -s "$e" "$tree/$rel/${e##*/}"
  done
}

shf_old_tree() { # <tree> <repo> <repo-relative path>… → rc 1 when SHF_BASE is not in this clone
  local tree="$1" repo="$2" p
  shift 2
  git -C "$repo" cat-file -e "$SHF_BASE^{commit}" 2>/dev/null || return 1
  mkdir -p "$tree"
  for p in hooks bin scripts; do _shf_real_dir "$tree" "$repo" "$p"; done
  for p in "$@"; do
    case "$p" in */*/*) _shf_real_dir "$tree" "$repo" "${p%/*}" ;; esac
    rm -f "$tree/$p"
    git -C "$repo" show "$SHF_BASE:$p" > "$tree/$p" || return 1
    chmod +x "$tree/$p"
  done
}

# shf_run <label> <hook> [args…] — stdin is the hook's stdin. Runs under /bin/bash with the stub
# PATH; stdout lands in $SHF_OUT_DIR/<label>.out and the call log in $SHF_OUT_DIR/<label>.forks.
shf_run() {
  local label="$1" hook="$2" rc=0
  shift 2
  export SHF_FORK_LOG="$SHF_OUT_DIR/$label.forks"
  : > "$SHF_FORK_LOG"
  # shellcheck disable=SC2153  # STUB is exported by each suite's setup_file
  PATH="$STUB" /bin/bash "$hook" "$@" > "$SHF_OUT_DIR/$label.out" 2> "$SHF_OUT_DIR/$label.err" || rc=$?
  return "$rc"
}
# shf_mkrepo <dir> [unlanded] — a clone of a bare origin with `main` pushed (the ✅ shape once the
# gate marker names HEAD); `unlanded` adds one commit that is not on origin (the 📦 shape).
shf_mkrepo() {
  local w="$1"
  git init -q --bare "$w.origin.git"
  git -c init.defaultBranch=main clone -q "$w.origin.git" "$w" 2>/dev/null
  ( cd "$w" || exit 1
    git symbolic-ref HEAD refs/heads/main
    git config user.email t@e.com; git config user.name t
    echo seed > f.txt; git add -A; git commit -qm init; git push -q -u origin main
    git rev-parse HEAD > .git/gate-green
    if [ "${2:-}" = unlanded ]; then echo x > x.txt; git add x.txt; git commit -qm "unlanded work"; fi
  ) >/dev/null 2>&1
}

# shf_keep <label> <idl file> <state dir> — file an arm's side effects beside its stdout, so two
# arms that ran one after the other over the SAME paths can be compared afterwards.
shf_keep() {
  shf_idl "$2" > "$SHF_OUT_DIR/$1.idl"
  if [ -d "$3" ]; then ( cd "$3" && find . -type f | LC_ALL=C sort ) > "$SHF_OUT_DIR/$1.state"
  else : > "$SHF_OUT_DIR/$1.state"; fi
}
# shf_same <old label> <new label> — stdout, stderr, IDL rows and state file names all equal.
shf_same() {
  local k
  for k in out err idl state; do
    cmp "$SHF_OUT_DIR/$1.$k" "$SHF_OUT_DIR/$2.$k" || { echo "--- $1.$k"; cat "$SHF_OUT_DIR/$1.$k"; echo "--- $2.$k"; cat "$SHF_OUT_DIR/$2.$k"; return 1; }
  done
}

shf_total() { grep -c . "$SHF_OUT_DIR/$1.forks" || true; }                 # <label> → external calls
shf_calls() { grep -cx -- "$2" "$SHF_OUT_DIR/$1.forks" || true; }          # <label> <name> → count
shf_census() { sort "$SHF_OUT_DIR/$1.forks" | uniq -c | sort -rn | awk '{printf "%s×%s ", $2, $1}'; }
# IDL rows without their wall-clock fields: two runs a second apart must still compare equal. A suite
# whose hook logs an age names it in SHF_IDL_DEL (a jq path list; the default is .ts).
shf_idl() { jq -c "del(${SHF_IDL_DEL:-.ts})" "$1" 2>/dev/null || true; }
