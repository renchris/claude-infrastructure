#!/usr/bin/env bats
# public-hygiene.bats — the land-gate lint (scripts/public-hygiene-lint.py) and the public history
# projection (scripts/public-publish.sh). Hermetic: a synthetic private store and fixture repos under
# $BATS_TEST_TMPDIR; the operator's real rule set is never read.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/public-hygiene-lint.py"
  PUB="$REPO/scripts/public-publish.sh"
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"; mkdir -p "$HOME"
  export CC_PRIVATE_DIR="$T/private"
  mkdir -p "$CC_PRIVATE_DIR/public-projection"
  printf '%s\n' '# comment lines must not become literals' \
    'Secret.Person@corp.example==>person@example.com' 'secret.person==>person' \
    'TopSecretName==>a name' > "$CC_PRIVATE_DIR/public-projection/replace-text.txt"
  printf '%s\n' 'docs/private-matter.md' > "$CC_PRIVATE_DIR/public-projection/paths-remove.txt"
  printf '%s\n' 'Owner <1+owner@users.noreply.github.com> <Secret.Person@corp.example>' > "$CC_PRIVATE_DIR/public-projection/mailmap"
  CONF="$T/conf"
  printf '%s\n' 'path local-only/*' 'email .*@example\.(com|org|net|invalid)' 'email .*@users\.noreply\.github\.com' > "$CONF"
  G=(-c user.name=Owner -c user.email=Secret.Person@corp.example -c commit.gpgsign=false)
}

mkrepo() {
  local r="$T/${1:?}"; mkdir -p "$r"; git -C "$r" init -q -b main
  git -C "$r" "${G[@]}" commit -q --allow-empty -m base
  echo "$r"
}
commit_file() { # <repo> <path> <content> [message]
  mkdir -p "$(dirname "$1/$2")"; printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add -A; git -C "$1" "${G[@]}" commit -q -m "${4:-add $2}"
}

@test "selftest: every arm flips the verdict on its planted case and stays clean on the control" {
  run python3 "$LINT" --selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"selftest: ok"* ]]
}

@test "MUTATION: disabling the e-mail arm makes the selftest FAIL (the control can see its subject)" {
  sed 's/for m in EMAIL_RE.finditer(data):/for m in []:/' "$LINT" > "$T/mut.py"
  ! cmp -s "$LINT" "$T/mut.py" || false
  run python3 "$T/mut.py" --selftest
  [ "$status" -ne 0 ]
}

@test "MUTATION: disabling the path arm makes the selftest FAIL" {
  sed 's/elif fnmatch.fnmatchcase(path, g) or path == g:/elif False:/' "$LINT" > "$T/mut.py"
  ! cmp -s "$LINT" "$T/mut.py" || false
  run python3 "$T/mut.py" --selftest
  [ "$status" -ne 0 ]
}

@test "own-range blocks only what the range ADDS, and names file and hit" {
  r="$(mkrepo own)"
  commit_file "$r" old.md "TopSecretName was here before"
  base="$(git -C "$r" rev-parse HEAD)"
  commit_file "$r" new.md "clean text, mail person@example.com"
  run python3 "$LINT" --repo "$r" --own-range "$base..HEAD" --conf "$CONF"
  [ "$status" -eq 0 ]
  commit_file "$r" new2.md "call secret.person at (303) 867-53""09"
  run python3 "$LINT" --repo "$r" --own-range "$base..HEAD" --conf "$CONF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"IDENTIFIER new2.md: secret.person"* ]] || false
  [[ "$output" == *"PHONE new2.md: (303) 867-53""09"* ]] || false
  [[ "$output" != *"old.md"* ]]
}

@test "own-range scans EVERY commit: an address added then scrubbed inside the land is a finding" {
  # The 2026-09-29 stall: the NET diff of the land was clean, the projected history was not, and the
  # verifier only found out at publish time. The added line lives in commit 1 alone.
  r="$(mkrepo percommit)"
  base="$(git -C "$r" rev-parse HEAD)"
  commit_file "$r" drafts/pr.md "cc someone@realmail.test on the PR"
  added="$(git -C "$r" rev-parse --short=10 HEAD)"
  commit_file "$r" drafts/pr.md "cc person@example.com on the PR" "scrub"
  run git -C "$r" diff "$base..HEAD"
  [[ "$output" != *realmail* ]] || { echo "the net diff still carries it: vacuous case"; false; }
  run python3 "$LINT" --repo "$r" --own-range "$base..HEAD" --conf "$CONF"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"EMAIL drafts/pr.md: someone@realmail.test  (commit $added)"* ]] || { echo "$output"; false; }
}

@test "own-range scans every commit MESSAGE of the land" {
  r="$(mkrepo permsg)"
  base="$(git -C "$r" rev-parse HEAD)"
  commit_file "$r" a.md "clean" "thanks to someone@realmail.test"
  run python3 "$LINT" --repo "$r" --own-range "$base..HEAD" --conf "$CONF"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"message: someone@realmail.test"* ]] || { echo "$output"; false; }
}

# The land gate's gitleaks arm, run as ship-land.sh defines it (extracted, not re-implemented), with
# gate_red / arm_nonverdict stubbed to record which verdict it raised.
gl_arm() { # <repo> <range> → runs ph_gitleaks_arm in <repo>
  local fn; fn="$(sed -n '/^ph_gitleaks_arm() {/,/^}/p' "$REPO/scripts/ship-land.sh")"
  [ -n "$fn" ] || { echo "ph_gitleaks_arm not defined in ship-land.sh"; return 99; }
  ( cd "$1" && eval "$fn"
    gate_red() { echo "STUB gate_red $1"; }
    arm_nonverdict() { echo "STUB arm_nonverdict $1 rc=${3:-2}"; }
    ph_gitleaks_arm "$2" ) 2>&1
}
fake_token() { printf 'gh''p_%s' "1a2B3c4D5e6F7g8H9i0J1k2L3m4N5o6P7q8R"; }

@test "GITLEAKS ARM: a secret one commit adds and the next removes is RED" {
  command -v gitleaks >/dev/null || skip "gitleaks absent"
  r="$(mkrepo glred)"; base="$(git -C "$r" rev-parse HEAD)"
  commit_file "$r" cfg.txt "github_token = \"$(fake_token)\""
  commit_file "$r" cfg.txt "github_token = \"\"" "scrub"
  run gl_arm "$r" "$base..HEAD"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"STUB gate_red public-hygiene-gitleaks"* ]] || { echo "$output"; false; }
  [[ "$output" != *"$(fake_token)"* ]] || { echo "the finding printed the secret unredacted"; false; }
}

@test "GITLEAKS ARM: a clean range passes (positive control off the same fixture shape)" {
  command -v gitleaks >/dev/null || skip "gitleaks absent"
  r="$(mkrepo glclean)"; base="$(git -C "$r" rev-parse HEAD)"
  commit_file "$r" cfg.txt "github_token = \"\""
  run gl_arm "$r" "$base..HEAD"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *STUB* ]] || { echo "$output"; false; }
}

@test "GITLEAKS ARM: gitleaks missing, or a range git cannot resolve, is a NON-VERDICT, never a pass" {
  r="$(mkrepo glnv)"
  SHIP_LAND_PUBLIC_HYGIENE_GITLEAKS="$T/no-such-gitleaks" run gl_arm "$r" "HEAD~0..HEAD"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"STUB arm_nonverdict public-hygiene-gitleaks rc=127"* ]] || { echo "$output"; false; }
  command -v gitleaks >/dev/null || skip "gitleaks absent"
  run gl_arm "$r" "deadbeef..HEAD"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"STUB arm_nonverdict public-hygiene-gitleaks"* ]] || { echo "$output"; false; }
}

@test "GITLEAKS ARM is WIRED: run_gate calls it inside the public-hygiene block, after the lint" {
  gate="$(sed -n '/^run_gate() {/,/^}/p' "$REPO/scripts/ship-land.sh")"
  block="$(printf '%s\n' "$gate" | sed -n '/PH_LINT=/,/pipefail\/SIGPIPE ratchet/p')"
  [[ "$block" == *'ph_gitleaks_arm "$range" || return 1'* ]] || { echo "run_gate does not call ph_gitleaks_arm"; false; }
}

@test "MUTATION: disabling the per-commit patch scan makes the selftest FAIL" {
  sed 's/for commit, cur, line in _added_lines(patch):/for commit, cur, line in []:/' "$LINT" > "$T/mut.py"
  ! cmp -s "$LINT" "$T/mut.py" || false
  run python3 "$T/mut.py" --selftest
  [ "$status" -ne 0 ]
}

@test "--tree sees an unlisted address and a local-only path" {
  r="$(mkrepo tree)"
  commit_file "$r" a.md "write to someone@realmail.test"
  commit_file "$r" local-only/x.md "fine"
  run python3 "$LINT" --repo "$r" --tree HEAD --conf "$CONF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"someone@realmail.test"* ]] || false
  [[ "$output" == *"PATH  local-only/x.md"* ]]
}

@test "the REAL conf refuses a nested .fire/ brief and the tracked truememory-2-0 link (DR-17)" {
  r="$(mkrepo dr17)"
  commit_file "$r" .fire/sub/brief.txt "fine"
  mkdir -p "$r/docs/research"; ln -s /nowhere "$r/docs/research/truememory-2-0"
  git -C "$r" add -A; git -C "$r" "${G[@]}" commit -q -m link
  run python3 "$LINT" --repo "$r" --tree HEAD --conf "$REPO/config/public-hygiene.conf"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PATH  .fire/sub/brief.txt"* ]] || false
  [[ "$output" == *"PATH  docs/research/truememory-2-0"* ]]
}

@test "--history sees content deleted long ago, commit messages and author idents" {
  r="$(mkrepo hist)"
  commit_file "$r" gone.md "TopSecretName"
  git -C "$r" rm -q gone.md; git -C "$r" "${G[@]}" commit -q -m "remove it"
  run python3 "$LINT" --repo "$r" --history HEAD --conf "$CONF" --max-findings 100
  [ "$status" -eq 1 ]
  [[ "$output" == *"gone.md: TopSecretName"* ]] || false
  [[ "$output" == *"author: Secret.Person@corp.example"* ]]
}

@test "a missing private map is a NON-VERDICT (rc 2), never a pass" {
  r="$(mkrepo nomap)"
  rm "$CC_PRIVATE_DIR/public-projection/replace-text.txt"
  run python3 "$LINT" --repo "$r" --tree HEAD --conf "$CONF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"NON-VERDICT"* ]]
}

@test "publish: projection removes, replaces and remaps — and its verifier reads 0 hits" {
  command -v git-filter-repo >/dev/null || skip "git-filter-repo absent"
  command -v gitleaks >/dev/null || skip "gitleaks absent"
  r="$(mkrepo pub)"; mkdir -p "$r/config"; cp "$CONF" "$r/config/public-hygiene.conf"
  git -C "$r" add -A; git -C "$r" "${G[@]}" commit -q -m conf
  commit_file "$r" docs/private-matter.md "entirely personal"
  commit_file "$r" local-only/x.md "licensed"
  commit_file "$r" notes.md "ask TopSecretName or Secret.Person@corp.example" "note for TopSecretName"
  run bash "$PUB" --src "$r" --out "$T/out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"projection-verifier: 0 identifier hit(s), 0 gitleaks finding(s)"* ]] || false
  tip="$(printf '%s\n' "$output" | sed -n 's/^verdict=projected tip=\([0-9a-f]*\).*/\1/p')"
  p="$T/out/proj.git"
  [ "$(git -C "$p" show "$tip:notes.md")" = "ask a name or person@example.com" ]
  ! git -C "$p" log --all --name-only --format= | grep -qE 'private-matter|local-only' || false
  ! git -C "$p" log --format='%ae%n%ce%n%B' | grep -qiE 'secret|topsecret' || false
  [ -s "$CC_PRIVATE_DIR/public-projection/commit-map" ]
}

@test "publish is DETERMINISTIC: a longer history re-projects to a fast-forward of the shorter" {
  command -v git-filter-repo >/dev/null || skip "git-filter-repo absent"
  command -v gitleaks >/dev/null || skip "gitleaks absent"
  r="$(mkrepo det)"; mkdir -p "$r/config"; cp "$CONF" "$r/config/public-hygiene.conf"
  git -C "$r" add -A; git -C "$r" "${G[@]}" commit -q -m conf
  commit_file "$r" a.md "TopSecretName one"
  commit_file "$r" local-only/y.md "licensed"
  run bash "$PUB" --src "$r" --out "$T/o1"; [ "$status" -eq 0 ]
  t1="$(printf '%s\n' "$output" | sed -n 's/^verdict=projected tip=\([0-9a-f]*\).*/\1/p')"
  commit_file "$r" b.md "TopSecretName two"
  # publish the SHORTER projection to a bare "public" remote, then re-project the longer history
  git init -q --bare "$T/public.git"
  git -C "$T/o1/proj.git" push -q "$T/public.git" "$t1:refs/heads/main"
  run bash "$PUB" --src "$r" --out "$T/o2" --public-url "$T/public.git"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ff=yes published=$t1"* ]]
}

@test "publish REFUSES a non-fast-forward push and an unconfirmed target" {
  command -v git-filter-repo >/dev/null || skip "git-filter-repo absent"
  command -v gitleaks >/dev/null || skip "gitleaks absent"
  r="$(mkrepo nff)"; mkdir -p "$r/config"; cp "$CONF" "$r/config/public-hygiene.conf"
  git -C "$r" add -A; git -C "$r" "${G[@]}" commit -q -m conf
  commit_file "$r" a.md "TopSecretName"
  git init -q --bare "$T/owner/pubrepo.git"
  run bash "$PUB" --src "$r" --out "$T/o1" --public-url "$T/owner/pubrepo.git" --push --confirm owner/wrong
  [ "$status" -eq 3 ]
  run bash "$PUB" --src "$r" --out "$T/o1" --public-url "$T/owner/pubrepo.git" --push --confirm owner/pubrepo
  [ "$status" -eq 0 ]
  [[ "$output" == *"pushed="* ]] || false
  # change the rule set so it rewrites the ROOT commit's message: every old commit re-projects
  # differently, so the new tip is NOT a descendant of the published one
  printf '%s\n' 'base==>root' >> "$CC_PRIVATE_DIR/public-projection/replace-text.txt"
  commit_file "$r" b.md "one more"
  run bash "$PUB" --src "$r" --out "$T/o2" --public-url "$T/owner/pubrepo.git" --push --confirm owner/pubrepo
  [ "$status" -eq 3 ]
  [[ "$output" == *"ff=no"* ]] || false
  [[ "$output" == *"FORCE-PUSH"* ]]
}

@test "publish LOCK: a live holder makes --push step aside; a reused pid is reclaimed; the lock is released" {
  command -v git-filter-repo >/dev/null || skip "git-filter-repo absent"
  command -v gitleaks >/dev/null || skip "gitleaks absent"
  r="$(mkrepo lk)"; mkdir -p "$r/config"; cp "$CONF" "$r/config/public-hygiene.conf"
  git -C "$r" add -A; git -C "$r" "${G[@]}" commit -q -m conf
  git init -q --bare "$T/owner/pubrepo.git"
  L="$CC_PRIVATE_DIR/public-projection/.publish.lock"; mkdir "$L"
  # a LIVE holder: this bats process, with its real start time
  printf '%s\n%s\n%s\n' "$$" "$(ps -o lstart= -p $$ | sed 's/^ *//; s/ *$//')" "2026-09-29T00:00:00Z" > "$L/owner"
  run bash "$PUB" --src "$r" --out "$T/o1" --public-url "$T/owner/pubrepo.git" --push --confirm owner/pubrepo
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=locked"* ]] || { echo "$output"; false; }
  [ -z "$(git -C "$T/owner/pubrepo.git" for-each-ref)" ]          # nothing was pushed
  [ -d "$L" ]                                                        # and the holder's lock is intact
  # the same pid with a DIFFERENT start time is a reused pid, not the holder: reclaimed
  printf '%s\n%s\n%s\n' "$$" "Thu Jan  1 00:00:00 1970" "1970-01-01T00:00:00Z" > "$L/owner"
  run bash "$PUB" --src "$r" --out "$T/o2" --public-url "$T/owner/pubrepo.git" --push --confirm owner/pubrepo
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"reclaimed a stale lock"* ]] || { echo "$output"; false; }
  [[ "$output" == *"pushed="* ]] || { echo "$output"; false; }
  [ ! -e "$L" ] || { ls -la "$L"; false; }                          # released on exit
}

@test "publish STALE SNAPSHOT: a projection OLDER than the published tip exits 0, not rc=3" {
  command -v git-filter-repo >/dev/null || skip "git-filter-repo absent"
  command -v gitleaks >/dev/null || skip "gitleaks absent"
  r="$(mkrepo st)"; mkdir -p "$r/config"; cp "$CONF" "$r/config/public-hygiene.conf"
  git -C "$r" add -A; git -C "$r" "${G[@]}" commit -q -m conf
  commit_file "$r" a.md "TopSecretName one"
  old="$(git -C "$r" rev-parse HEAD)"
  commit_file "$r" b.md "two"
  git init -q --bare "$T/owner/pubrepo.git"
  run bash "$PUB" --src "$r" --out "$T/o1" --public-url "$T/owner/pubrepo.git" --push --confirm owner/pubrepo
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  published="$(git -C "$T/owner/pubrepo.git" rev-parse refs/heads/main)"
  last="$(cat "$CC_PRIVATE_DIR/public-projection/last-projection")"
  # a second checkout still at the OLDER main — the snapshot a racing tick would have taken
  git clone -q "$r" "$T/stale"; git -C "$T/stale" reset -q --hard "$old"
  run bash "$PUB" --src "$T/stale" --out "$T/o2" --public-url "$T/owner/pubrepo.git" --push --confirm owner/pubrepo
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"ff=stale published=$published"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict=stale-snapshot"* ]] || { echo "$output"; false; }
  [[ "$output" != *"rule set changed"* ]] || { echo "$output"; false; }
  [ "$(git -C "$T/owner/pubrepo.git" rev-parse refs/heads/main)" = "$published" ]
  [ "$(cat "$CC_PRIVATE_DIR/public-projection/last-projection")" = "$last" ]   # newer map kept
}

@test "TICK: a TERM to the tick reaches the whole publisher group — no orphaned filter-repo" {
  r="$(mkrepo tickterm)"; mkdir -p "$r/scripts"
  cp "$REPO/scripts/public-publish-tick.sh" "$r/scripts/"
  git -C "$r" config cc.publicRepo owner/public-fixture
  # stub publisher: a long-running child stands in for git-filter-repo
  printf '#!/bin/bash\nsleep 300 &\necho $! > "%s/child.pid"\nwait\n' "$T" > "$r/scripts/public-publish.sh"
  touch "$CC_PRIVATE_DIR/public-projection/publish-enabled"
  /bin/bash "$r/scripts/public-publish-tick.sh" > "$T/tick.out" 2>&1 3>&- &
  tick=$!
  for _ in $(seq 1 100); do [ -s "$T/child.pid" ] && break; sleep 0.1; done
  child="$(cat "$T/child.pid")"; [ -n "$child" ]
  kill -TERM "$tick"
  for _ in $(seq 1 50); do kill -0 "$tick" 2>/dev/null || break; sleep 0.1; done
  for _ in $(seq 1 20); do kill -0 "$child" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$child" 2>/dev/null; then kill "$child"; echo "filter-repo stand-in ORPHANED"; cat "$T/tick.out"; false; fi
  ! kill -0 "$tick" 2>/dev/null || { kill "$tick"; echo "tick did not exit"; false; }
}

@test "publish REFUSES to push an identity GitHub would not credit to the confirmed owner" {
  command -v git-filter-repo >/dev/null || skip "git-filter-repo absent"
  command -v gitleaks >/dev/null || skip "gitleaks absent"
  r="$(mkrepo attr)"; mkdir -p "$r/config"; cp "$CONF" "$r/config/public-hygiene.conf"
  git -C "$r" add -A; git -C "$r" "${G[@]}" commit -q -m conf
  printf '%s\n' 'Owner <owner@example.com> <Secret.Person@corp.example>' > "$CC_PRIVATE_DIR/public-projection/mailmap"
  git init -q --bare "$T/owner/pubrepo.git"
  run bash "$PUB" --src "$r" --out "$T/o1" --public-url "$T/owner/pubrepo.git" --push --confirm owner/pubrepo
  [ "$status" -eq 1 ]
  [[ "$output" == *"would not credit to @owner"* ]] || false
  [[ "$output" == *"owner@example.com"* ]] || false
  [ -z "$(git -C "$T/owner/pubrepo.git" for-each-ref)" ]
}

# ── the cutover (docs/activation/pending-activation/46-public-repo-cutover.sh), end to end, offline:
# github.com is a directory of bare repos (url.insteadOf), gh is a state machine that models the
# rename REDIRECT, visibility and create, and launchctl is a stub. Nothing leaves the box.
cutover_fixture() {
  CUT="$REPO/docs/activation/pending-activation/46-public-repo-cutover.sh"
  # the bare repos sit under a path ENDING github.com/renchris: git hands pre-push the insteadOf-
  # REWRITTEN url, and the identity gate scopes on that string, so a bare "$T/gh" put it out of scope
  GH="$T/github.com/renchris"; mkdir -p "$GH/state" "$T/bin" "$HOME/Library/LaunchAgents"
  export GIT_CONFIG_GLOBAL="$T/gitconfig"
  git config --global url."$GH/".insteadOf "https://github.com/renchris/"
  git config --global init.defaultBranch main
  # production parity: init.templatedir puts the REAL identity gate (githooks/pre-push) into every
  # new repo, the publisher's projection clone included, and the gate accepts only the private
  # address. Without this the suite ran with no gate at all and the 2026-09-27 cutover refused
  # 5814 of 5814 projected commits on the first real push.
  mkdir -p "$T/tmpl/hooks" "$HOME/.claude"; cp "$REPO/githooks/pre-push" "$T/tmpl/hooks/pre-push"
  git config --global init.templatedir "$T/tmpl"
  printf '{"git_identity":{"email":"Secret.Person@corp.example"}}\n' > "$HOME/.claude/identity.local.json"
  printf '%s\n' 'Owner <1+renchris@users.noreply.github.com> <Secret.Person@corp.example>' > "$CC_PRIVATE_DIR/public-projection/mailmap"
  git init -q --bare "$GH/claude-infrastructure.git"
  printf 'renchris/claude-infrastructure public\n' > "$GH/state/repos"
  cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
S="$GH_STATE"; R="$S/repos"
lookup() { local n="$1" row; row="$(grep -i "^$n " "$R")" && { echo "$row"; return; }
           row="$(grep -i "^$n " "$S/redirects" 2>/dev/null)" || return 1; lookup "$(echo "$row" | cut -d' ' -f2)"; }
case "$1 $2" in
  "auth status") exit 0 ;;
  "repo rename") new="$3"; old="$5"; o="${old%/*}"
    sed -i '' "s#^$old #$o/$new #" "$R"; echo "$old $o/$new" >> "$S/redirects"
    mv "$GH_DIR/${old#*/}.git" "$GH_DIR/$new.git" ;;
  "repo edit")   sed -i '' "s#^$3 .*#$3 private#" "$R" ;;
  "repo create") echo "$3 public" >> "$R"; git init -q --bare "$GH_DIR/${3#*/}.git" ;;
  "api -X") exit 0 ;;
  api*) name="${2#repos/}"; row="$(lookup "$name")" || exit 1
    case "$*" in *full_name*) echo "$row" | cut -d' ' -f1 ;; *visibility*) echo "$row" | cut -d' ' -f2 ;; esac ;;
  *) echo "gh stub: unhandled $*" >&2; exit 9 ;;
esac
STUB
  printf '#!/bin/sh\nexit 0\n' > "$T/bin/launchctl"; chmod +x "$T/bin/gh" "$T/bin/launchctl"
  export GH_STATE="$GH/state" GH_DIR="$GH" PATH="$T/bin:$PATH"
  # the working repo: the real publisher + lint + conf, one commit carrying an identifier
  W="$T/work"; git clone -q "https://github.com/renchris/claude-infrastructure.git" "$W" 2>/dev/null
  # clone stores the insteadOf-REWRITTEN path; the real checkout's origin is the github URL
  git -C "$W" remote set-url origin "https://github.com/renchris/claude-infrastructure.git"
  mkdir -p "$W/scripts" "$W/config" "$W/launchd"
  cp "$PUB" "$LINT" "$W/scripts/"; cp "$REPO/config/public-hygiene.conf" "$W/config/public-hygiene.conf"
  printf '<plist/>\n' > "$W/launchd/com.claude.public-publish.plist"
  printf 'ask TopSecretName\n' > "$W/notes.md"
  git -C "$W" add -A; git -C "$W" "${G[@]}" commit -q -m base; git -C "$W" push -q origin HEAD:main
  export CC_CUTOVER_REPO="$W" CC_CUTOVER_BACKUP_DIR="$T/backup"
}

@test "cutover DRY RUN: backup verified, projection verified, NOTHING on GitHub changes" {
  command -v git-filter-repo >/dev/null && command -v gitleaks >/dev/null || skip "tools absent"
  cutover_fixture
  run bash "$CUT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"DRY RUN"* ]] || false
  [[ "$output" == *"projection-verifier: 0 identifier hit(s)"* ]] || false
  ls "$T"/backup/all-refs-*.bundle >/dev/null
  [ "$(cat "$GH/state/repos")" = "renchris/claude-infrastructure public" ]
  [ "$(git -C "$W" config --get remote.origin.url)" = "https://github.com/renchris/claude-infrastructure.git" ]
}

@test "cutover --confirm: private working origin, public projection, identity kept — and a re-run is a no-op" {
  command -v git-filter-repo >/dev/null && command -v gitleaks >/dev/null || skip "tools absent"
  cutover_fixture
  run bash "$CUT" --confirm renchris/wrong
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"DRY RUN"* ]] || false # a wrong target never executes
  run bash "$CUT" --confirm renchris/claude-infrastructure
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=CUTOVER-OK"* ]] || false
  grep -qx 'renchris/claude-infrastructure-private private' "$GH/state/repos"
  grep -qx 'renchris/claude-infrastructure public' "$GH/state/repos"
  [ "$(git -C "$W" config --get remote.origin.url)" = "https://github.com/renchris/claude-infrastructure-private.git" ]
  [ "$(git -C "$W" config cc.canonicalUrl)" = "https://github.com/renchris/claude-infrastructure.git" ]
  [ "$(git -C "$W" config cc.publicRepo)" = "renchris/claude-infrastructure" ]
  # the public repo holds the projection, the private one the untouched working history
  git clone -q "$GH/claude-infrastructure.git" "$T/pubcheck"
  [ "$(cat "$T/pubcheck/notes.md")" = "ask a name" ]
  [ "$(git -C "$GH/claude-infrastructure-private.git" rev-parse main)" = "$(git -C "$W" rev-parse HEAD)" ]
  [ -f "$CC_PRIVATE_DIR/public-projection/publish-enabled" ]
  run bash "$CUT" --confirm renchris/claude-infrastructure
  [ "$status" -eq 0 ]
  [[ "$output" == *"rename already done"* ]] || false
  [[ "$output" == *"ff=yes"* ]]
}

@test "PARITY: the ripgrep fast path and the Python path return the SAME findings (>200 blobs)" {
  command -v rg >/dev/null || skip "rg absent — only the Python path exists here"
  r="$(mkrepo parity)"
  for i in $(seq 1 230); do printf 'file %s clean person@example.com +1 555-010-0123\n' "$i" > "$r/f$i.txt"; done
  printf 'ask TopSecretName, mail someone@realmail.test, call (303) 867-53''09\n' > "$r/hits.txt"
  git -C "$r" add -A; git -C "$r" "${G[@]}" commit -q -m many
  run python3 "$LINT" --repo "$r" --tree HEAD --conf "$CONF" --max-findings 1000
  fast="$(printf '%s\n' "$output" | grep -E '^(IDENTIFIER|EMAIL|PHONE)' | sed 's/  */ /g' | sort)"
  PUBLIC_HYGIENE_NO_RG=1 run python3 "$LINT" --repo "$r" --tree HEAD --conf "$CONF" --max-findings 1000
  slow="$(printf '%s\n' "$output" | grep -E '^(IDENTIFIER|EMAIL|PHONE)' | sed 's/  */ /g' | sort)"
  [ "$(printf '%s\n' "$fast" | grep -c .)" -eq 3 ] || { echo "fast: $fast"; false; }
  [ "$fast" = "$slow" ] || { diff <(echo "$fast") <(echo "$slow"); false; }
}

@test "TICK: run through a symlinked scripts/ dir (launchd's path) it reads cc.publicRepo from the REAL checkout" {
  # A copy of the tick in a fixture checkout, with a stub publisher that only records its args —
  # the real public-publish.sh (which pushes) is never reached.
  r="$(mkrepo tickrepo)"; mkdir -p "$r/scripts" "$T/live/scripts"
  cp "$REPO/scripts/public-publish-tick.sh" "$r/scripts/"
  printf '#!/bin/bash\necho "STUB-PUBLISH $*"\n' > "$r/scripts/public-publish.sh"
  git -C "$r" config cc.publicRepo owner/public-fixture
  ln -s "$r/scripts/public-publish-tick.sh" "$T/live/scripts/public-publish-tick.sh"
  touch "$CC_PRIVATE_DIR/public-projection/publish-enabled"
  TMPDIR="$T" run bash "$T/live/scripts/public-publish-tick.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *REFUSED* ]] || { echo "$output"; false; }
  [[ "$output" == *"STUB-PUBLISH --src $r --ref main --public-url https://github.com/owner/public-fixture.git"* ]] || { echo "$output"; false; }
}
