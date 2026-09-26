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
  printf '%s\n' 'Owner <owner@example.com> <Secret.Person@corp.example>' > "$CC_PRIVATE_DIR/public-projection/mailmap"
  CONF="$T/conf"
  printf '%s\n' 'path local-only/*' 'email .*@example\.(com|org|net|invalid)' > "$CONF"
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

@test "--tree sees an unlisted address and a local-only path" {
  r="$(mkrepo tree)"
  commit_file "$r" a.md "write to someone@realmail.test"
  commit_file "$r" local-only/x.md "fine"
  run python3 "$LINT" --repo "$r" --tree HEAD --conf "$CONF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"someone@realmail.test"* ]] || false
  [[ "$output" == *"PATH  local-only/x.md"* ]]
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

# ── the cutover (docs/activation/pending-activation/46-public-repo-cutover.sh), end to end, offline:
# github.com is a directory of bare repos (url.insteadOf), gh is a state machine that models the
# rename REDIRECT, visibility and create, and launchctl is a stub. Nothing leaves the box.
cutover_fixture() {
  CUT="$REPO/docs/activation/pending-activation/46-public-repo-cutover.sh"
  GH="$T/gh"; mkdir -p "$GH/state" "$T/bin" "$HOME/Library/LaunchAgents"
  export GIT_CONFIG_GLOBAL="$T/gitconfig"
  git config --global url."$GH/".insteadOf "https://github.com/renchris/"
  git config --global init.defaultBranch main
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
