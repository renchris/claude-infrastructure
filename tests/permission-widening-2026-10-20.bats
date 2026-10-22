#!/usr/bin/env bats
# The 2026-10-20 permission widening (operator ruling on decision 29d62f1ad390: "permission prompts
# is virtually always a yes … our past usage of commands [should be] pattern recognized and
# allowed"). Census, replay and the evidence count behind every arm:
# docs/research/permission-prompt-reduction-2026-10-20/REPORT.md.
#
# Subjects: hooks/validate-bash.sh (AGENT SCRATCH, GIT-OWNERSHIP's cd/-C tracking and PUSH arm, the
# rm SCRATCH-TEMP category) and hooks/lib/smart-bash-allowlist.py (write scope, local git, scoped
# write verbs, wrappers, inert builtins).
#
# THE CLAIM IS TWO-SIDED (MEMORY.md guard-proxy-fails-in-both-directions): every PERMIT is paired
# with the REFUSAL one lever away — a reserved name, a socket, a `..`, a symlink out, a cd that may
# have failed, a remote that is someone else's — so a hook that merely said yes more often fails
# this file. Agent scratch is LOCATION-based (/private/tmp), so the fixtures live there, under a
# mktemp dir this suite removes in teardown.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  VB="$REPO/hooks/validate-bash.sh"
  SBA="$REPO/hooks/smart-bash-allowlist.sh"
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  export CC_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/shared"; mkdir -p "$CC_SHARED_CHECKOUT"
  export CC_SCRATCHPAD_ROOT="$BATS_TEST_TMPDIR/spads"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  # The fixture fence: the operator's ask rules AFTER migrations/0075 (no `git push`).
  cat > "$HOME/.claude/settings.json" <<'JSON'
{"permissions": {"allow": [], "ask": ["Bash(fly deploy:*)", "Bash(git stash clear:*)"],
 "deny": ["Bash(git push --force:*)", "Bash(git push -f:*)", "Bash(wget:*)"]}}
JSON
  S="$(mktemp -d /private/tmp/pw-bats.XXXXXX)"           # agent scratch
  P="$BATS_TEST_TMPDIR/proj"; mkdir -p "$P/src"            # a project (not scratch)
  mkdir -p "$S/sub" "$S/repo"
  git -C "$S/repo" init -q -b main .
  git -C "$S/repo" commit -q --allow-empty -m A
  printf 'x\n' > "$S/repo/f"; git -C "$S/repo" add f; git -C "$S/repo" commit -q -m B
  printf 'dirty\n' >> "$S/repo/f"                          # uncommitted: a reset here loses it
  git -C "$P" init -q -b main .
  git -C "$P" commit -q --allow-empty -m A
}

teardown() {
  [[ -n "${S:-}" && "$S" == /private/tmp/pw-bats.* ]] && /bin/rm -rf "$S"
  return 0
}

vb() {  # <command> [cwd] → DENY | ASK | PASS  (validate-bash)
  local out
  out="$(jq -nc --arg c "$1" --arg d "${2:-$P}" \
          '{session_id:"7bacff59-dcaa-472c-8600-cca1baaa4ae4", cwd:$d, tool_input:{command:$c}}' \
        | bash "$VB" 2>/dev/null)"
  [ -z "$out" ] && { printf 'PASS'; return 0; }
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision | ascii_upcase'
}
sba() {  # <command> [cwd] → ALLOW | DEFER  (smart-bash-allowlist; the hook judges in its own cwd)
  local out
  out="$(cd "${2:-$P}" && jq -nc --arg c "$1" \
          '{session_id:"7bacff59-dcaa-472c-8600-cca1baaa4ae4", tool_input:{command:$c}}' \
        | bash "$SBA" 2>/dev/null)"
  [ -n "$out" ] && printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "allow"' >/dev/null \
    && { printf 'ALLOW'; return 0; }
  printf 'DEFER'
}

# ── validate-bash: rm -r in agent scratch ─────────────────────────────────────────────────────

@test "rm -r: PERMITS a literal or same-command-variable target in agent scratch" {
  [ "$(vb "rm -rf $S/sub")" = "PASS" ]
  [ "$(vb "D=$S/sub; rm -rf \"\$D\"")" = "PASS" ]
  [ "$(vb "rm -rf ${S/#\/private/}/sub")" = "PASS" ]                 # the /tmp spelling
}

@test "rm -r: REFUSES the reserved names, a socket, a .. escape and a symlink out of scratch" {
  [ "$(vb 'rm -rf /tmp/cc-pw-bats-x')" = "ASK" ]
  [ "$(vb 'rm -rf /tmp/.pw-bats-x')" = "ASK" ]
  [ "$(vb 'rm -rf /tmp/claude-pw-bats/x')" = "ASK" ]
  [ "$(vb 'rm -rf /tmp/land-lock-pw')" = "ASK" ]
  python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$S/sub/live.sock"
  [ "$(vb "rm -rf $S/sub")" = "ASK" ]
  [ "$(vb "rm -rf $S/../../etc")" = "ASK" ]
  ln -s "$P/src" "$S/link-out"
  [ "$(vb "rm -rf $S/link-out")" = "ASK" ]
  [ "$(vb 'rm -rf /private/tmp')" = "ASK" ]
  CC_VB_SCRATCH_TEMP=off run vb "rm -rf $S/repo"
  [ "$output" = "ASK" ]                                                # the kill switch
}

@test "rm -r: a RELATIVE target resolves against every dir its statement may run in" {
  [ "$(vb "cd $S && rm -rf sub")" = "PASS" ]                           # && replaces the cwd
  [ "$(vb "cd $S; rm -rf sub")" = "ASK" ]                              # the cd may have failed → $P/sub
  [ "$(vb 'cd /etc && rm -rf sub')" = "ASK" ]
  [ "$(vb 'cd "$X" && rm -rf sub')" = "ASK" ]                          # undecidable cd
  [ "$(vb 'rm -rf sub' "$S")" = "PASS" ]                               # payload cwd IS scratch
  [ "$(vb 'rm -rf src')" = "ASK" ]                                     # payload cwd is the project
}

@test "rm -r: never-source artifact names PERMIT at any depth; ambiguous names stay top-only" {
  [ "$(vb 'rm -rf bin/__pycache__')" = "PASS" ]
  [ "$(vb 'rm -rf docs/research/x/__pycache__')" = "PASS" ]
  [ "$(vb 'rm -rf scripts/build')" = "ASK" ]
  [ "$(vb 'rm -rf src/__pycache__/../../src')" = "ASK" ]
}

# ── validate-bash: GIT-OWNERSHIP with cd / -C / scratch ───────────────────────────────────────

@test "reset --hard: PERMITS in a scratch repo even when dirty; the same in a project still ASKS" {
  [ "$(vb "git -C $S/repo reset --hard HEAD~1")" = "PASS" ]
  [ "$(vb "cd $S/repo && git reset --hard HEAD")" = "PASS" ]
  printf 'y\n' > "$P/g"; git -C "$P" add g
  [ "$(vb "cd $S/repo; git reset --hard HEAD")" = "ASK" ]             # may run in $P, which is dirty
  [ "$(vb "git -C $P reset --hard HEAD")" = "ASK" ]                    # staged change in a project
  git -C "$P" reset -q
  [ "$(vb "git -C $P reset --hard HEAD")" = "PASS" ]                   # clean project: lossless
  [ "$(vb "git -C \$R reset --hard HEAD")" = "ASK" ]
}

@test "reset --hard: a MENTION inside a data heredoc is not an invocation; an executed one still asks" {
  [ "$(vb $'cat > /tmp/brief.md <<\'EOF\'\nNever run git reset --hard here.\nEOF')" = "PASS" ]
  [ "$(vb $'bash <<\'EOF\'\ngit reset --hard HEAD~1\nEOF')" = "ASK" ]
}

@test "restore / stash drop: scratch PERMITS; a project or a scratch WORKTREE of a real repo ASKS" {
  [ "$(vb "git -C $S/repo restore f")" = "PASS" ]
  [ "$(vb "git -C $P restore f")" = "ASK" ]
  git -C "$S/repo" stash -q
  [ "$(vb "git -C $S/repo stash drop")" = "PASS" ]
  git -C "$P" worktree add -q "$S/wt" -b wt
  [ "$(vb "git -C $S/wt stash drop")" = "ASK" ]                        # shares $P's stash stack
  [ "$(vb "git -C $S/nope stash drop")" = "ASK" ]                      # cannot tell
}

@test "push: PERMITS the operator's own remote; ASKS for a third party, a delete, a variable remote" {
  git -C "$P" remote add origin https://github.com/renchris/pw-bats.git
  git -C "$P" remote add up https://github.com/someone-else/pw-bats.git
  git -C "$P" remote add loc "$S/bare.git"
  [ "$(vb "git -C $P push origin HEAD:main")" = "PASS" ]
  [ "$(vb "cd $P && git push -q origin HEAD:main 2>&1 | tail -3")" = "PASS" ]
  [ "$(vb "git -C $P push loc main")" = "PASS" ]
  [ "$(vb "git -C $P push up HEAD:main")" = "ASK" ]
  [ "$(vb "git -C $P push")" = "ASK" ]                                 # bare: every remote must be own
  [ "$(vb "git -C $P push origin --delete x")" = "ASK" ]
  [ "$(vb "git -C $P push origin +HEAD:main")" = "ASK" ]
  [ "$(vb "git -C $P push \$R HEAD:main")" = "ASK" ]
  [ "$(vb 'git commit -m "then git push origin main"')" = "PASS" ]   # a mention
  # a $( ) elsewhere in the command does not make the cd undecidable; a cd INSIDE a subshell does
  [ "$(vb "cd $P && sha=\$(git rev-parse HEAD) && git push -q origin HEAD:main")" = "PASS" ]
  [ "$(vb "(cd /tmp && git push origin HEAD:main)")" = "ASK" ]
  CC_VB_PUSH_OWNERS=nobody run vb "git -C $P push origin HEAD:main"
  [ "$output" = "ASK" ]
}

@test "push: a sibling remote that is a relative local path is the operator's own disk" {
  git -C "$P" remote add origin https://github.com/renchris/pw-bats.git
  git -C "$P" remote add sib ../sibling
  [ "$(vb "git -C $P push")" = "PASS" ]                                 # bare: every remote is own
  git -C "$P" remote add up git@github.com:someone-else/x.git
  [ "$(vb "git -C $P push")" = "ASK" ]
}

# ── smart-bash-allowlist: write scope ─────────────────────────────────────────────────────────

@test "writes: a redirect, tee, cp, mv, touch into the project or scratch ALLOW; elsewhere DEFER" {
  [ "$(sba $'cat > notes.md <<\'EOF\'\nx\nEOF')" = "ALLOW" ]
  [ "$(sba "echo hi >> $S/log.txt 2>&1")" = "ALLOW" ]
  [ "$(sba "cp src/a $S/b && mv $S/b $S/c && touch $S/d")" = "ALLOW" ]
  [ "$(sba "printf x | tee -a $S/t")" = "ALLOW" ]
  [ "$(sba 'echo x > /etc/hosts')" = "DEFER" ]
  [ "$(sba 'echo x > ~/.zshrc')" = "DEFER" ]
  [ "$(sba 'echo x > /tmp/cc-pw-bats')" = "DEFER" ]
  [ "$(sba 'echo x > /tmp/.desk-land-lock')" = "DEFER" ]
  [ "$(sba 'echo x > .git/config')" = "DEFER" ]
  [ "$(sba 'cp ~/.ssh/id_rsa src/k')" = "DEFER" ]
  [ "$(sba "mv /etc/a $S/a")" = "DEFER" ]                             # mv removes its source
  [ "$(sba 'tee >(sh) f')" = "DEFER" ]
  [ "$(sba "awk '{print > \"f\"}' in")" = "DEFER" ]
}

@test "rm in a compound: a resolved scratch target or a mktemp dir ALLOWS; reserved or unresolved DEFERS" {
  [ "$(sba "T=\$(mktemp -d $S/t.XXXX) && echo hi > \$T/f && rm -rf \"\$T\"")" = "ALLOW" ]
  [ "$(sba "D=$S/sub; ls \$D && rm -rf \"\$D\"")" = "ALLOW" ]
  # A relative target must be scratch under EVERY dir the command may run in, the hook's own cwd
  # included; $P sits under $BATS_TEST_TMPDIR, which is scratch only when $TMPDIR is under
  # /private/tmp (the default /var/folders is not), so judge from $S to keep this line deterministic.
  [ "$(sba "cd $S && rm -rf sub && echo done" "$S")" = "ALLOW" ]
  [ "$(sba 'D=/tmp/cc-pw-bats; ls $D && rm -rf "$D"')" = "DEFER" ]
  [ "$(sba "D=$S/a; D=/etc; ls && rm -rf \"\$D\"")" = "DEFER" ]       # bound twice
  [ "$(sba 'ls && rm -rf "$UNSET"')" = "DEFER" ]
  python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$S/sub/l.sock"
  [ "$(sba "D=$S/sub; ls && rm -rf \"\$D\"")" = "DEFER" ]           # a live listener below it
  # (a LITERAL /tmp target is rm-safe-allowlist.sh's allow; validate-bash's ask overrides it for the
  # reserved names and sockets — pinned in the rm -r REFUSES case above)
}

@test "writes: a variable target resolves from this command's own binding; archives are scoped" {
  [ "$(sba "D=$S/o; mkdir -p \$D && echo x > \"\$D/f\"")" = "ALLOW" ]
  [ "$(sba "T=\$(mktemp -d) && cp src/a \"\$T/\" && echo y >> \$T/log")" = "ALLOW" ]
  [ "$(sba 'D=/etc; echo x > "$D/f"')" = "DEFER" ]
  [ "$(sba 'echo x > "$UNBOUND/f"')" = "DEFER" ]
  [ "$(sba "tar -czf $S/a.tgz src && tar -xzf $S/a.tgz -C $S/u && unzip -q $S/a.zip -d $S/z")" = "ALLOW" ]
  [ "$(sba 'tar -xzf a.tgz -C /etc')" = "DEFER" ]
  [ "$(sba "tar -xf $S/a.tar --to-command=sh")" = "DEFER" ]
  mkdir -p "$HOME/Development/exists"
  [ "$(sba "git clone https://github.com/a/b ~/Development/pw-new-clone")" = "ALLOW" ]   # a NEW dir
  [ "$(sba "git clone https://github.com/a/b $HOME/Development/exists")" = "DEFER" ]
  [ "$(sba 'git -C "$W" add x && git -C "$W" commit -m y')" = "ALLOW" ]
}

@test "writes: a relative target follows the cd; a cd it cannot read makes it DEFER" {
  [ "$(sba "cd $S && echo x > hosts")" = "ALLOW" ]
  [ "$(sba 'cd /etc && echo x > hosts')" = "DEFER" ]
  [ "$(sba 'cd "$D" && echo x > f')" = "DEFER" ]
}

# ── smart-bash-allowlist: local git, wrappers, builtins ───────────────────────────────────────

@test "git: local history operations ALLOW; the forms that execute or discard DEFER" {
  [ "$(sba 'git add a && git commit -m "x y" && git status')" = "ALLOW" ]
  [ "$(sba "git -C $S/repo rebase main")" = "ALLOW" ]
  [ "$(sba 'git checkout -b feat/x && git branch -D old')" = "ALLOW" ]
  [ "$(sba 'git -c user.name=t commit -m y')" = "ALLOW" ]
  [ "$(sba 'git push -q origin HEAD:main')" = "ALLOW" ]
  [ "$(sba "git rebase -x 'touch M' main")" = "DEFER" ]
  [ "$(sba 'git -c core.pager=evil log')" = "DEFER" ]
  [ "$(sba 'git checkout -- src/a')" = "DEFER" ]
  [ "$(sba 'git clone ext::sh /tmp/x')" = "DEFER" ]
  [ "$(sba 'git stash pop')" = "DEFER" ]
  [ "$(sba 'git push --force origin main')" = "DEFER" ]
  [ "$(sba 'git push origin --delete x')" = "DEFER" ]
  [ "$(sba 'git config core.hooksPath /tmp/h')" = "DEFER" ]
}

@test "git push meets the operator's fence: while Bash(git push:*) is an ask, even -C forms DEFER" {
  printf '{"permissions":{"ask":["Bash(git push:*)"],"deny":[]}}' > "$HOME/.claude/settings.json"
  [ "$(sba 'git push origin HEAD:main')" = "DEFER" ]
  [ "$(sba "git -C $P push origin HEAD:main")" = "DEFER" ]
}

@test "wrappers and builtins: judged by what they run" {
  [ "$(sba 'timeout 30 git status')" = "ALLOW" ]
  [ "$(sba 'timeout 30 python3 x.py')" = "DEFER" ]
  [ "$(sba 'while read -r l; do echo "$l"; done < f')" = "ALLOW" ]
  [ "$(sba "T=\$(mktemp -d $S/t.XXXX) && echo \$T")" = "ALLOW" ]
  [ "$(sba 'for i in 1 2; do [ $i = 2 ] && break; continue; done')" = "ALLOW" ]
}

@test "the reserved-name lists in the two hooks agree" {
  vb_list=$(sed -n "s/^_SCRATCH_TEMP_RESERVED='\(.*\)'$/\1/p" "$VB")
  py_list=$(grep -A1 '^_SCRATCH_RESERVED = re.compile' "$REPO/hooks/lib/smart-bash-allowlist.py" \
            | sed -n 's/^ *r"\(.*\)|\\\.sock\$"$/\1/p')
  [ -n "$vb_list" ] && [ "$vb_list" = "$py_list" ]
}
