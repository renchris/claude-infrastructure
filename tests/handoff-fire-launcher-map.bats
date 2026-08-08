#!/usr/bin/env bats
# handoff-fire.sh — the LAUNCHER NAME a fire spawns comes from accounts.json (item 253e4d4254d9).
#
# WHY THIS EXISTS. accounts.json declares a `launcher` per account and its own header calls itself
# the SSOT for "launcher -> config dir -> email -> mailbox -> Dia profile". Every other consumer
# read that field — bin/claude-accounts prints it in the relogin fix line, the generated map keys
# cc_acct_dir_for_name on it, the account-relogin skill quotes it. handoff-fire.sh alone COMPOSED
# it: `claude` + a trailing digit derived from the account name, with account 1 hardcoded as the
# empty-suffix exception. A convention that ships with a counter-example inside it is not a
# convention; it is a second declaration of a field the SSOT already owns, agreeing by coincidence.
#
# THE FAILURE THAT MAKES IT MATTER is silent and lands at spawn: rename a launcher in accounts.json
# (or add a 5th account whose launcher is not `claude5`) and every other consumer follows, while
# this one keeps composing a command the operator's shell does not define. `nocorrect claude5 …`
# reaches a real pane, zsh reports command-not-found into a window nobody is reading, and the fire
# has already printed "→ fired".
#
# THE SAME DEFECT, ONE FIELD OVER, is covered by (5)-(6): ranked_accounts()'s degraded tie-break
# looped over a literal `next next4 next3 next2` while $CC_ACCT_NAMES — generated from accounts[]
# in exactly that order — had ZERO consumers in the whole tree.
#
# PROOF DISCIPLINE. A fixture accounts.json is the only instrument that can tell the two trees
# apart, because the live one's launchers DO follow the convention: `claude3` is what both a correct
# reader and a broken composer print for next3. So every case below runs the real generator over
# names the convention cannot reach (`cc-three`, `ax`), and each assertion is paired with the
# negative control naming what the composed form would have produced there.
#
# RED-PROOF — 6 of 7 RED, measured against a pristine `git archive` of the parent commit (0
# occurrences of cc_acct_launcher_for_name in either script there): (1) prints `launcher: claude3`
# and (2) `launcher: claude`; (3) has no cc_acct_launcher_for_name to call at all; (4) exits 0 and
# prints `launcher: claude3` — the stale map is composed AROUND in silence, which is the sharpest
# statement of the defect this file has; (5) prints `account:  next` from the literal list, naming
# an account the fixture never declared, and (6) `launcher: claude` for it. (7) passes on both trees
# by construction — it asserts the artifact matches its generator, which is true before and after,
# and exists to keep it true after the NEXT accounts.json edit.
#
# Non-final `[[ ]]` / `(( ))` are errexit-EXEMPT in bats and therefore DEAD as assertions; every
# one below is `[ ]` or `… || false`.

setup() {
  SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$SRC/scripts/handoff-fire.sh"
  GEN="$SRC/scripts/gen-account-map.sh"
  # Hermeticity rule 1: handoff-fire resolves DEFAULT_REPO, $WTROOT, the registry, roles and the
  # projects dirs it counts activity in — all under $HOME. Physical path (see
  # tests/handoff-fire-repo-resolution.bats): $BATS_TEST_TMPDIR is under the /var -> /private/var
  # symlink, and the script's own `pwd -P` returns the resolved form, so resolve once here.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  HOME="$(cd "$HOME" && pwd -P)"    # …then its PHYSICAL form (already exported; a plain re-assign
                                    # keeps it so, and avoids SC2155 on an `export` + `$( )` line)
  mkdir -p "$HOME/.claude/bin"
  # The it2 shim must EXIST — handoff-fire probes it with `sed … | head -1` under pipefail, so an
  # absent file aborts the whole script. A dry run never invokes it.
  printf 'REAL_IT2="/nonexistent/it2"\nPYTHON_BIN="/usr/bin/python3"\n' > "$HOME/.claude/bin/it2"
  chmod +x "$HOME/.claude/bin/it2"
  # Hermeticity rule 2: capacity_gate() reads live `sysctl vm.loadavg` and refuses a net-new fire
  # at >= 2.0/core. This box sits above that, so an unpinned suite reads ambient load, not its
  # subject. The account sweep is pinned off for the same reason plus the network.
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off
  # …and the three seams that do NOT resolve under $HOME, so fixturing it does not reach them: two
  # absolute /tmp defaults and one BARE NAME the subject executes off the operator's PATH. An absent
  # path is the right fixture — each sensor fails open on one (test-hermeticity-lint rules 5a/5b).
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"
  # ranked_accounts() resolves `claude-accounts` off PATH, not through a CC_* seam. The operator's
  # real one is on this box's PATH and would hit the usage endpoint, making the ranking depend on
  # live quota. rc=3 is that function's own documented "live limits unreadable" degrade, which is
  # exactly the branch (5)-(6) are about.
  STUBBIN="$BATS_TEST_TMPDIR/stubbin"; mkdir -p "$STUBBIN"
  printf '#!/bin/bash\nexit 3\n' > "$STUBBIN/claude-accounts"
  chmod +x "$STUBBIN/claude-accounts"
  export PATH="$STUBBIN:$PATH"
  REPO="$HOME/Development/reso-management-app"     # the script's own default, restated
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  echo x > "$REPO/f"; git -C "$REPO" add f
  # TRANSIENT identity (`-c`, not `config`): it cannot persist, so there is no shape here for an
  # empty `-C` to leak into a caller's shared .git/config — scripts/git-identity-lint.sh rule 1.
  git -C "$REPO" -c user.email=f@x -c user.name=f commit -qm init
  git -C "$REPO" update-ref refs/remotes/origin/main HEAD
  PAYLOAD="$BATS_TEST_TMPDIR/p.txt"
  echo "TASK — launcher-map fixture payload." > "$PAYLOAD"
}

# genmap <name:launcher> … — run the REAL generator over a fixture accounts.json and echo the path
# of the map it produced. Both the generator and the json are copied into a temp REPO_DIR so the
# generator's own `$REPO_DIR/lib/…` output path lands in the fixture, never in the checkout.
genmap() {
  local d="$BATS_TEST_TMPDIR/gen$RANDOM" pair rows=""
  mkdir -p "$d/scripts" "$d/lib"
  cp "$GEN" "$d/scripts/gen-account-map.sh"
  for pair in "$@"; do
    rows="${rows:+$rows,}{\"name\":\"${pair%%:*}\",\"config_dir\":\"~/.claude-${pair%%:*}\",\"launcher\":\"${pair##*:}\"}"
  done
  printf '{"accounts":[%s]}\n' "$rows" > "$d/accounts.json"
  bash "$d/scripts/gen-account-map.sh" >/dev/null 2>&1 || return 1
  echo "$d/lib/account-map.generated.sh"
}

# fire [args…] — the real script, dry, from the fixture repo.
fire() {
  run env -u ITERM_SESSION_ID \
      bash -c "cd '$REPO' && bash '$HF' --prompt-file '$PAYLOAD' --dry-run --session-id 'w0t0p0:FIX' \"\$@\"" _ "$@"
}

# ── 1-2: an EXPLICIT account composes its launch line from accounts.json ─────────────────────────

@test "1 --account uses the launcher accounts.json declares, not \`claude\`+digit" {
  CC_ACCOUNT_MAP="$(genmap next:ccx next3:cc-three)"; export CC_ACCOUNT_MAP
  fire --account next3
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^launcher: cc-three$" || false
  echo "$output" | grep -q "nocorrect cc-three " || false
  # the control: `claude` + the trailing digit of next3 is what the composed form produced here,
  # and it must appear NOWHERE — not in the readout, not in the command that would be spawned.
  ! echo "$output" | grep -q "claude3" || false
}

@test "2 the digit-less account is read too — its launcher is a FIELD, not an empty-suffix rule" {
  # Account 1 having no trailing digit was the composed form's hardcoded exception. Give it a name
  # the rule cannot reach and the rule's answer (bare `claude`) becomes the negative control.
  CC_ACCOUNT_MAP="$(genmap next:ax next3:cc-three)"; export CC_ACCOUNT_MAP
  fire --account next
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^launcher: ax$" || false
  echo "$output" | grep -q "nocorrect ax " || false
  ! echo "$output" | grep -q "nocorrect claude " || false
}

# ── 3-4: the map function itself, and what happens when it is missing ────────────────────────────

@test "3 the generator emits name -> launcher, and returns 1 on an account it never saw" {
  local map; map="$(genmap next:ax next3:cc-three)"
  # shellcheck source=/dev/null
  source "$map"
  [ "$(cc_acct_launcher_for_name next)" = "ax" ]
  [ "$(cc_acct_launcher_for_name next3)" = "cc-three" ]
  run cc_acct_launcher_for_name next9
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "4 a STALE map with no launcher function is NAMED, never composed around" {
  # The state a deployed-but-not-regenerated map is in: the dir lookup resolves, the launcher one
  # does not exist. Composing a name here is precisely the defect, so the fire must die saying so.
  local map="$BATS_TEST_TMPDIR/stale-map.sh"
  cat > "$map" <<'STALE'
cc_acct_dir_for_name() { CC_ACCT_IS_FABLE=0; case "$1" in next3) CC_ACCT_DIR="$HOME/.claude-tertiary" ;; *) return 1 ;; esac; }
cc_acct_name_for_dir_basename() { echo ""; }
CC_ACCT_NAMES="next3"
STALE
  CC_ACCOUNT_MAP="$map"; export CC_ACCOUNT_MAP
  fire --account next3
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "cc_acct_launcher_for_name" || false
  echo "$output" | grep -q "gen-account-map.sh" || false
  ! echo "$output" | grep -q "^launcher: claude3$" || false
}

# ── 5-6: the same field one over — the DEGRADED ranking's account list ───────────────────────────

@test "5 the degraded tie-break ranks the accounts accounts.json declares, in its order" {
  # claude-accounts exits 3 (setup), so ranked_accounts falls to the activity proxy. Every fixture
  # account has zero transcripts under the fixtured $HOME, so declaration order IS the ranking.
  CC_ACCOUNT_MAP="$(genmap alpha:ax beta:bx)"; export CC_ACCOUNT_MAP
  fire --account auto
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^account:  alpha" || false
  # the literal list's answer, which cannot be right for a tree that declares neither name
  ! echo "$output" | grep -q "^account:  next" || false
}

@test "6 …and that ranked pick composes ITS launcher from the same source" {
  CC_ACCOUNT_MAP="$(genmap alpha:ax beta:bx)"; export CC_ACCOUNT_MAP
  fire --account auto
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^launcher: ax$" || false
  echo "$output" | grep -q "nocorrect ax " || false
}

# ── 7: the committed artifact is what the committed accounts.json produces ───────────────────────

@test "7 lib/account-map.generated.sh is in sync with accounts.json (drift guard)" {
  # The fix above makes handoff-fire DEPEND on this file being current, so a hand-edited or
  # not-regenerated map re-introduces the defect in a new form: a stale literal instead of a
  # composed one. install.sh regenerates on install; this is the check that binds on every land.
  # Copied into a temp REPO_DIR with no argument, so the generator takes its default-path branch
  # and stamps the repo-relative header line — the byte-identical form of the committed file.
  local d="$BATS_TEST_TMPDIR/sync"
  mkdir -p "$d/scripts" "$d/lib"
  cp "$GEN" "$d/scripts/gen-account-map.sh"
  cp "$SRC/accounts.json" "$d/accounts.json"
  run bash "$d/scripts/gen-account-map.sh"
  [ "$status" -eq 0 ]
  run diff -u "$SRC/lib/account-map.generated.sh" "$d/lib/account-map.generated.sh"
  [ "$status" -eq 0 ]
}
