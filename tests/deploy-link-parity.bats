#!/usr/bin/env bats
# deploy-link-parity.sh — the "landed but not live" reporter.
#
# Guards the failure that motivated it: ~/.claude/{hooks,commands,scripts,bin,skills} are real
# directories of PER-FILE symlinks, so a fast-forward updates every already-linked file and deploys
# NOTHING for a file the checkout gained. `git rev-list HEAD..origin/main` reads 0 while the new
# code does not run at all (scripts/desk-arm-live.sh, 2026-07-20; the lr-reset-poller, 2026-07-21).
#
# And the inverse, which is why the script REPORTS instead of repairing: a settings-wired hook is
# deliberately left unlinked until its staged activation script runs. Auto-linking would erase the
# only signal that the wiring is pending, so PENDING must stay a clean exit and UNLINKED must not.
#
# FULLY HERMETIC: every case builds a fake checkout + config dir + bindir + pending-activation dir
# in BATS_TEST_TMPDIR and drives the script via CC_LINKPARITY_REPO / CC_LINKPARITY_CONFIG /
# CC_LINKPARITY_BINDIR / CC_LINKPARITY_PENDING. No case reads the real ~/.claude or the real
# checkout, so this passes on a fresh clone, in a worktree and in CI. (The live host is asserted by
# running the script itself, not by this suite.)
#
# ASSERTION FORM: non-final `[[ ]]` and bare `!` are silently DEAD under bats+set -e (verified on
# bats 1.13.0). Every assertion here is a `[ ]`, a helper function call, or a pipeline — all three
# are live in any position.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermetic: never touch the live ~/

  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LP="$REPO_ROOT/scripts/deploy-link-parity.sh"

  export CC_LINKPARITY_REPO="$BATS_TEST_TMPDIR/repo"
  export CC_LINKPARITY_CONFIG="$BATS_TEST_TMPDIR/cfg"
  export CC_LINKPARITY_BINDIR="$BATS_TEST_TMPDIR/bin"
  export CC_LINKPARITY_PENDING="$BATS_TEST_TMPDIR/pending"

  mkdir -p "$CC_LINKPARITY_REPO"/{hooks/lib,commands,scripts/limit-recover,bin,skills/demo}
  mkdir -p "$CC_LINKPARITY_CONFIG"/{hooks/lib,commands,scripts/limit-recover,bin,skills/demo}
  mkdir -p "$CC_LINKPARITY_BINDIR" "$CC_LINKPARITY_PENDING"

  # one already-correct link, so a clean run is provably non-vacuous
  printf 'old\n' > "$CC_LINKPARITY_REPO/hooks/established.sh"
  ln -sfn "$CC_LINKPARITY_REPO/hooks/established.sh" "$CC_LINKPARITY_CONFIG/hooks/established.sh"
}

# `printf | grep` and function calls are live assertions in any position; `[[ ]]` is not.
has()   { printf '%s' "$output" | grep -qF -- "$1"; }
lacks() { if printf '%s' "$output" | grep -qF -- "$1"; then return 1; fi; return 0; }

# A file that landed in the checkout and is named by NO staged activation script.
land_new() { printf 'new\n' > "$CC_LINKPARITY_REPO/$1"; }

# A staged activation script that names a repo-relative path, exactly as the real ones do.
stage_activation() {  # $1 = script name · $2 = repo-relative path it will link
  printf '#!/bin/bash\nSRC="$REPO/%s"\nln -sfn "$SRC" "$CFG/%s"\n' "$2" "$2" \
    > "$CC_LINKPARITY_PENDING/$1"
}

@test "everything linked ⇒ clean, exit 0, and the linked count proves it looked" {
  run "$LP"
  [ "$status" -eq 0 ]
  has "1 linked"
  has "every landed file is live"
}

@test "a NEW checkout file with no live link ⇒ UNLINKED, exit 1 (the desk-arm-live regression)" {
  land_new "scripts/desk-arm-live.sh"
  run "$LP"
  [ "$status" -eq 1 ]
  has "UNLINKED"
  has "scripts/desk-arm-live.sh"
  has "silently inert"
}

@test "UNLINKED emits an exact runnable ln -sfn command, not a description" {
  land_new "hooks/brand-new.sh"
  run "$LP"
  [ "$status" -eq 1 ]
  has "ln -sfn \"$CC_LINKPARITY_REPO/hooks/brand-new.sh\" \"$CC_LINKPARITY_CONFIG/hooks/brand-new.sh\""
}

@test "REPORT-ONLY: a dirty run creates no link and removes nothing" {
  land_new "hooks/brand-new.sh"
  ln -sfn "$CC_LINKPARITY_REPO/hooks/vanished.sh" "$CC_LINKPARITY_CONFIG/hooks/vanished.sh"
  before="$(find "$CC_LINKPARITY_CONFIG" | sort)"
  run "$LP"
  [ "$status" -eq 1 ]
  after="$(find "$CC_LINKPARITY_CONFIG" | sort)"
  [ "$before" = "$after" ]
  [ ! -e "$CC_LINKPARITY_CONFIG/hooks/brand-new.sh" ]
}

@test "unlinked BUT named by a staged activation ⇒ PENDING, exit 0 (by design, not a gap)" {
  land_new "hooks/dispatch-assert.sh"
  stage_activation "11-dispatch-assert-activate.sh" "hooks/dispatch-assert.sh"
  run "$LP"
  [ "$status" -eq 0 ]
  has "PENDING"
  has "11-dispatch-assert-activate.sh"
  has "1 staged-pending"
  lacks "UNLINKED"
}

@test "PENDING never proposes a link — the activation script owns that step" {
  land_new "hooks/dispatch-assert.sh"
  stage_activation "11-dispatch-assert-activate.sh" "hooks/dispatch-assert.sh"
  run "$LP"
  [ "$status" -eq 0 ]
  lacks "ln -sfn"
}

@test "activation already .done ⇒ no longer an excuse, back to UNLINKED exit 1" {
  land_new "hooks/dispatch-assert.sh"
  stage_activation "11-dispatch-assert-activate.sh" "hooks/dispatch-assert.sh"
  touch "$CC_LINKPARITY_PENDING/11-dispatch-assert-activate.sh.done"
  run "$LP"
  [ "$status" -eq 1 ]
  has "UNLINKED"
  lacks "PENDING"
}

@test "PENDING matches the repo-relative PATH, not a bare basename (no false all-clear)" {
  land_new "hooks/watcher.sh"
  # names only the basename, and for a DIFFERENT surface — must not launder hooks/watcher.sh
  printf '#!/bin/bash\n# mentions watcher.sh and scripts/watcher.sh only\n' \
    > "$CC_LINKPARITY_PENDING/99-decoy-activate.sh"
  run "$LP"
  [ "$status" -eq 1 ]
  has "UNLINKED"
  lacks "PENDING"
}

@test "a real file where a symlink belongs ⇒ SHADOW (repo edits never reach it)" {
  printf 'repo\n' > "$CC_LINKPARITY_REPO/scripts/drifted.sh"
  printf 'stale\n' > "$CC_LINKPARITY_CONFIG/scripts/drifted.sh"
  run "$LP"
  [ "$status" -eq 1 ]
  has "SHADOW"
  has "NOT live"
}

@test "a live link pointing outside this checkout ⇒ MISLINKED" {
  printf 'repo\n' > "$CC_LINKPARITY_REPO/scripts/hijacked.sh"
  printf 'other\n' > "$BATS_TEST_TMPDIR/elsewhere.sh"
  ln -sfn "$BATS_TEST_TMPDIR/elsewhere.sh" "$CC_LINKPARITY_CONFIG/scripts/hijacked.sh"
  run "$LP"
  [ "$status" -eq 1 ]
  has "MISLINKED"
}

@test "a live link whose checkout target was renamed away ⇒ ORPHAN + an rm command" {
  ln -sfn "$CC_LINKPARITY_REPO/scripts/renamed-away.sh" "$CC_LINKPARITY_CONFIG/scripts/renamed-away.sh"
  run "$LP"
  [ "$status" -eq 1 ]
  has "ORPHAN"
  has "rm \"$CC_LINKPARITY_CONFIG/scripts/renamed-away.sh\""
}

@test "a link into a FOREIGN repo is not ours to judge — never reported as an orphan" {
  # ~/.claude/bin carries live links into other checkouts (claude-session-search); a dangling one
  # there is that repo's business, and flagging it would train the operator to ignore this report.
  ln -sfn "$BATS_TEST_TMPDIR/other-repo/bin/tool" "$CC_LINKPARITY_CONFIG/bin/cc-foreign"
  run "$LP"
  [ "$status" -eq 0 ]
  lacks "ORPHAN"
}

@test "--quiet is silent when clean but still speaks up when actionable" {
  run "$LP" --quiet
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  land_new "hooks/brand-new.sh"
  run "$LP" --quiet
  [ "$status" -eq 1 ]
  has "UNLINKED"
}

@test "--all lists correctly-linked files too" {
  run "$LP" --all
  [ "$status" -eq 0 ]
  has "LINKED"
  has "hooks/established.sh"
}

@test "every per-file symlink surface install.sh deploys is actually covered" {
  land_new "hooks/s1.sh"
  land_new "hooks/lib/s2.sh"
  land_new "commands/s3.md"
  land_new "scripts/s4.sh"
  land_new "scripts/limit-recover/s5.sh"
  land_new "bin/cc-s6"
  land_new "skills/demo/SKILL.md"
  land_new "accounts.json"
  land_new "bin/claude-accounts"
  run "$LP"
  [ "$status" -eq 1 ]
  for f in hooks/s1.sh hooks/lib/s2.sh commands/s3.md scripts/s4.sh \
           scripts/limit-recover/s5.sh bin/cc-s6 skills/demo/SKILL.md accounts.json; do
    has "$f"
  done
  # claude-accounts is the one link that lands in BINDIR, not the config dir
  has "$CC_LINKPARITY_BINDIR/claude-accounts"
}

@test "non-symlink surfaces stay out of scope (deploy-parity-assert.sh owns COPY drift)" {
  land_new "statusline.sh"
  land_new "CLAUDE.md"
  mkdir -p "$CC_LINKPARITY_REPO/launchd"; land_new "launchd/com.example.plist"
  run "$LP"
  [ "$status" -eq 0 ]
  lacks "statusline.sh"
  lacks "CLAUDE.md"
  lacks "com.example.plist"
}

@test "invoked VIA ITS OWN LIVE SYMLINK it still resolves a real checkout, never ~/.claude" {
  # The deploy-parity-assert.sh defect class: BASH_SOURCE is the symlink path, so an unresolved
  # dirname puts the repo root at ~/.claude — not a checkout — and every leg exits 0 vacuously.
  ln -sfn "$LP" "$BATS_TEST_TMPDIR/live-link.sh"
  land_new "hooks/brand-new.sh"
  run "$BATS_TEST_TMPDIR/live-link.sh"
  [ "$status" -eq 1 ]
  has "UNLINKED"
}

@test "a missing config dir is a prerequisite failure (3), never a vacuous pass" {
  export CC_LINKPARITY_CONFIG="$BATS_TEST_TMPDIR/no-such-dir"
  run "$LP"
  [ "$status" -eq 3 ]
}

@test "a missing checkout is a prerequisite failure (3), never a vacuous pass" {
  export CC_LINKPARITY_REPO="$BATS_TEST_TMPDIR/no-such-repo"
  run "$LP"
  [ "$status" -eq 3 ]
}

# ── STRAY: the live→checkout direction (2026-08-08) ──────────────────────────────────────────────
#
# Every case above walks checkout→live and so is blind to a file that entered the live layer without
# ever being in the repo. bin/cc-mail sat live and unversioned for 5 days — hand-placed into
# ~/.claude/bin (which is on PATH) by a peer session working in another repo — while this script read
# "0 actionable"; bin/cc-thread was the same failure a day earlier.
#
# The hard half is NOT detection, it is not convicting the copy-deploy state: ~/.claude/bin/it2 is a
# real file by design, cp'd from the tracked bin/it2-wrapper under a DIFFERENT NAME. The it2 case
# below is therefore a CONTROL, not a courtesy — it is the assertion that fails if the leg ever
# regresses to a path-keyed diff, which is the sibling-auditors-disagree failure this repo has paid
# for once already.

# A tool hand-placed straight into the live layer, exactly as a peer session does it: a real file,
# never `git add`ed, in no checkout.
hand_place() { printf '%s\n' "${2:-#!/bin/bash}" > "$CC_LINKPARITY_CONFIG/$1"; }

# A manifest row. Written to a fixture path so no case reads the repo's real config/live-only.manifest.
declare_row() {  # $1 = live path (basename may lead with *) · $2 = kind · $3 = witness · $4 = why
  export CC_LINKPARITY_MANIFEST="$BATS_TEST_TMPDIR/live-only.manifest"
  printf '# fixture\n%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$CC_LINKPARITY_MANIFEST"
}

# A witness landed AND linked. The link matters: a witness dropped into scripts/ is itself a new
# checkout file, so the forward walk would report it UNLINKED and the case would go red for a reason
# that has nothing to do with the row under test (memory assertion-span-must-equal-its-subject).
witness() {  # $1 = repo-relative path · $2 = the line that must name the artifact
  printf '%s\n' "$2" > "$CC_LINKPARITY_REPO/$1"
  ln -sfn "$CC_LINKPARITY_REPO/$1" "$CC_LINKPARITY_CONFIG/$1"
}

@test "a hand-placed live tool in NO checkout ⇒ STRAY, exit 1 (the cc-mail/cc-thread regression)" {
  hand_place "bin/cc-mail"
  run "$LP"
  [ "$status" -eq 1 ]
  has "STRAY"
  has "bin/cc-mail"
  has "unversioned, invisible to review"
}

@test "CONTROL: a copy under a DIFFERENT NAME is matched by CONTENT, never convicted (the it2 trap)" {
  # install.sh:593 cp's the tracked bin/it2-wrapper to ~/.claude/bin/it2. A path-keyed live→checkout
  # diff reports it as a stray on every single run. This case is the mutant-proof for that: it is red
  # the moment the leg stops comparing bytes.
  printf 'wrapper\n' > "$CC_LINKPARITY_REPO/bin/it2-wrapper"
  printf 'wrapper\n' > "$CC_LINKPARITY_CONFIG/bin/it2"
  run "$LP"
  [ "$status" -eq 0 ]
  lacks "STRAY"
  has "1 live-extra"
}

@test "CONTROL: the same file with ONE byte changed IS a stray — the match is exact, not fuzzy" {
  # Without this, the case above could pass because the leg exempts everything named it2, or
  # everything in bin, rather than because it compared content.
  printf 'wrapper\n' > "$CC_LINKPARITY_REPO/bin/it2-wrapper"
  printf 'wrapperX\n' > "$CC_LINKPARITY_CONFIG/bin/it2"
  run "$LP"
  [ "$status" -eq 1 ]
  has "STRAY"
  has "bin/it2"
}

@test "CONTROL: content-matching still holds under a REAL git checkout, not just the fixtures" {
  # The leg has two hash paths — `git hash-object` + `git ls-files -s` for a real checkout, shasum for
  # a bare directory. A git blob hash carries a header and can NEVER equal a bare content digest, so
  # mixing them would convict every legitimate copy — and the fixtures alone would never show it,
  # because they are the branch that does not use git. Production is the git branch; test it.
  git -C "$CC_LINKPARITY_REPO" init -q
  # `:?` guards the ARGUMENT, not the call: `git -C ""` is a NO-OP, so an unset/empty repo path
  # would write these identities into whatever repo bats is standing in — and ~100 worktrees here
  # share ONE .git/config, so one escape re-authors every session on the box.
  git -C "${CC_LINKPARITY_REPO:?repo path required}" config user.email t@t
  git -C "${CC_LINKPARITY_REPO:?repo path required}" config user.name t
  printf 'wrapper\n' > "$CC_LINKPARITY_REPO/bin/it2-wrapper"
  git -C "$CC_LINKPARITY_REPO" add -A; git -C "$CC_LINKPARITY_REPO" commit -qm f
  printf 'wrapper\n' > "$CC_LINKPARITY_CONFIG/bin/it2"
  run "$LP"
  [ "$status" -eq 0 ]
  lacks "STRAY"
  has "1 live-extra"
}

@test "an UNTRACKED file in the checkout never launders a live file into a clean exit" {
  # The whole defect is unversionedness, so the exemption set is `git ls-files` — not the working
  # tree. An untracked twin sitting beside the checkout is exactly as lost as no twin at all.
  #
  # WHICH LEG reports it is deliberately NOT pinned here. The forward walk's globs are FILESYSTEM
  # globs, so it claims $REPO/bin/cc-* whether or not git tracks it, and calls this SHADOW; the stray
  # leg then defers (one file, one verdict). Asserting the class would pin an incidental ordering and
  # go red the day either glob changes, while the property worth guarding — an unversioned live file
  # is never silently exempt — would still hold. So assert the property.
  git -C "$CC_LINKPARITY_REPO" init -q
  # `:?` guards the ARGUMENT, not the call: `git -C ""` is a NO-OP, so an unset/empty repo path
  # would write these identities into whatever repo bats is standing in — and ~100 worktrees here
  # share ONE .git/config, so one escape re-authors every session on the box.
  git -C "${CC_LINKPARITY_REPO:?repo path required}" config user.email t@t
  git -C "${CC_LINKPARITY_REPO:?repo path required}" config user.name t
  git -C "$CC_LINKPARITY_REPO" commit -q --allow-empty -m empty
  printf 'ghost\n' > "$CC_LINKPARITY_REPO/bin/cc-ghost"     # present on disk, never added
  printf 'ghost\n' > "$CC_LINKPARITY_CONFIG/bin/cc-ghost"
  run "$LP"
  [ "$status" -eq 1 ]
  has "bin/cc-ghost"
  has "0 live-extra"          # never counted as an accounted-for live file
}

@test "a live file with NO checkout twin at all is a STRAY even under git mode" {
  # The complement of the case above, and the shape the defect actually took: nothing in the checkout
  # claims the path, so no forward glob reaches it and the stray leg is the ONLY thing that can see it.
  git -C "$CC_LINKPARITY_REPO" init -q
  # `:?` guards the ARGUMENT, not the call: `git -C ""` is a NO-OP, so an unset/empty repo path
  # would write these identities into whatever repo bats is standing in — and ~100 worktrees here
  # share ONE .git/config, so one escape re-authors every session on the box.
  git -C "${CC_LINKPARITY_REPO:?repo path required}" config user.email t@t
  git -C "${CC_LINKPARITY_REPO:?repo path required}" config user.name t
  git -C "$CC_LINKPARITY_REPO" commit -q --allow-empty -m empty
  hand_place "bin/cc-thread"
  run "$LP"
  [ "$status" -eq 1 ]
  has "STRAY"
  has "bin/cc-thread"
}

@test "a DECLARED live-only file is exempt, and its reason is printed under --all" {
  hand_place "bin/kitty-pane-menu-native"
  declare_row "bin/kitty-pane-menu-native" build "scripts/kitty-setup.sh" "compiled from the tracked .swift"
  witness "scripts/kitty-setup.sh" "swiftc -o kitty-pane-menu-native"
  run "$LP"
  [ "$status" -eq 0 ]
  lacks "STRAY"
  run "$LP" --all
  has "DECLARED"
  has "compiled from the tracked .swift"
}

@test "a declared row whose witness is GONE fails loud — an exemption is never permanent" {
  # The row outliving its producer is how a dissolved reason keeps laundering a real defect. It must
  # become a finding, not silently keep exempting.
  hand_place "bin/kitty-pane-menu-native"
  declare_row "bin/kitty-pane-menu-native" build "scripts/kitty-setup.sh" "compiled from the tracked .swift"
  run "$LP"
  [ "$status" -eq 1 ]
  has "STALE-DECL"
}

@test "a declared row whose witness no longer NAMES it fails loud too (renamed away, not deleted)" {
  # The likelier rot: the producer survives a rename of what it builds. Existence alone would pass.
  hand_place "bin/kitty-pane-menu-native"
  declare_row "bin/kitty-pane-menu-native" build "scripts/kitty-setup.sh" "compiled from the tracked .swift"
  witness "scripts/kitty-setup.sh" "swiftc -o something-else-entirely"
  run "$LP"
  [ "$status" -eq 1 ]
  has "STALE-DECL"
  has "1 actionable"        # STALE-DECL is the ONLY finding — not exit 1 borrowed from the forward walk
}

@test "a wildcard row matches by suffix and stays scoped to its own directory" {
  mkdir -p "$CC_LINKPARITY_CONFIG/lib"
  hand_place "lib/config-mirror.zsh.prelink-bak"
  hand_place "bin/impostor.prelink-bak"
  declare_row "lib/*.prelink-bak" residue "docs/act.sh" "kept by the activation script"
  mkdir -p "$CC_LINKPARITY_REPO/docs"; printf 'cp x x.prelink-bak\n' > "$CC_LINKPARITY_REPO/docs/act.sh"
  run "$LP"
  [ "$status" -eq 1 ]
  has "STRAY"
  has "bin/impostor.prelink-bak"                    # same suffix, WRONG directory ⇒ still a finding
  lacks "lib/config-mirror.zsh.prelink-bak"         # matched the row ⇒ exempt, and silent without --all
}

@test "SYMLINKS are never judged by the stray leg — that contract is inherited, not re-decided" {
  # A live link into another checkout is that repo's business (see the FOREIGN case above). The stray
  # leg must not quietly reverse a decision another case already made, which is how two auditors over
  # one population end up disagreeing.
  # The link must RESOLVE. A dangling one is skipped by the earlier "does it exist" guard, so it
  # exercises nothing here and the case passes even with the symlink rule deleted — measured, and it
  # is what this assertion originally did. ~/.claude/bin carries 5 resolving links into
  # claude-session-search today, so the resolving case is also the real population.
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
  printf 'not ours\n' > "$BATS_TEST_TMPDIR/elsewhere/tool"
  ln -sfn "$BATS_TEST_TMPDIR/elsewhere/tool" "$CC_LINKPARITY_CONFIG/bin/cc-linked-away"
  run "$LP"
  [ "$status" -eq 0 ]
  lacks "STRAY"
}

@test "commands/ stays out of the stray leg's scope — the boundary that did NOT move" {
  # skills/ and agents/ were brought in scope on 2026-08-19; commands/ was not, and that asymmetry
  # is deliberate. Pinning it here stops the widening from being read as "sweep every document
  # surface" by the next editor.
  hand_place "commands/personal.md"
  run "$LP"
  [ "$status" -eq 0 ]
  lacks "STRAY"
}

@test "an undeclared live skill IS swept ⇒ STRAY (skills/ is in scope as of 2026-08-19)" {
  # The gap this closes: a hand-placed skill directory was in no checkout, had no git history, no
  # /ship path, and NO auditor looked at it from the live side (backlog bb2495b098b8).
  mkdir -p "$CC_LINKPARITY_CONFIG/skills/hand-placed"
  hand_place "skills/hand-placed/SKILL.md"
  run "$LP"
  [ "$status" -eq 1 ]
  has "STRAY"
  has "skills/hand-placed/SKILL.md"
}

@test "the live agents/ directory is swept too — its one real file is the same class" {
  # setup() does not build agents/, on purpose: a MISSING surface must be a silent no-op (the guard
  # in sweep_strays), so the directory is created here by the case that actually needs it.
  mkdir -p "$CC_LINKPARITY_CONFIG/agents"
  hand_place "agents/hand-placed.md"
  run "$LP"
  [ "$status" -eq 1 ]
  has "STRAY"
  has "agents/hand-placed.md"
}

@test "a WHOLE-DIRECTORY row exempts a vendored skill, and prints its reason under --all" {
  # The form the 5 live third-party skills use: skills/<name>/*, witnessed by skills/LOCAL_ONLY.md.
  mkdir -p "$CC_LINKPARITY_CONFIG/skills/vendored"
  hand_place "skills/vendored/SKILL.md"
  hand_place "skills/vendored/REFERENCE.md"
  declare_row "skills/vendored/*" vendored "skills/LOCAL_ONLY.md" "upstream owns the text"
  witness "skills/LOCAL_ONLY.md" "| \`vendored\` | replaced wholesale on re-vendor |"
  run "$LP"
  [ "$status" -eq 0 ]
  lacks "STRAY"
  run "$LP" --all
  has "DECLARED"
  has "upstream owns the text"
}

@test "a whole-directory row whose witness stops naming the DIRECTORY goes STALE, not silently OK" {
  # THE VACUITY THIS GUARDS. A row's witness stem is the literal remainder after the '*', and for a
  # bare `skills/<name>/*` that remainder is the EMPTY STRING — `grep -F ''` matches every line, so
  # the witness check would degrade to "the file exists" and the anti-rot device would be dead while
  # still looking alive. The stem falls back to the row's own directory name so this case can fail.
  mkdir -p "$CC_LINKPARITY_CONFIG/skills/vendored"
  hand_place "skills/vendored/SKILL.md"
  declare_row "skills/vendored/*" vendored "skills/LOCAL_ONLY.md" "upstream owns the text"
  witness "skills/LOCAL_ONLY.md" "this file no longer mentions the directory it exempts"
  run "$LP"
  [ "$status" -eq 1 ]
  has "STALE-DECL"
  has "1 actionable"        # the STALE row is the only finding — nothing borrowed from another leg
}

@test "the sweep reaches INTO each skill dir — passing the nested parent would visit nothing" {
  # sweep_strays lists ONE directory and skips subdirectories, so a single sweep of "skills" would
  # look at 5 directory entries, skip all 5, and report a clean pass over a surface it never read.
  # Driving it one level down is what makes the leg non-vacuous on a nested surface.
  mkdir -p "$CC_LINKPARITY_CONFIG/skills/alpha" "$CC_LINKPARITY_CONFIG/skills/beta"
  hand_place "skills/alpha/SKILL.md"
  hand_place "skills/beta/SKILL.md"
  run "$LP"
  [ "$status" -eq 1 ]
  has "skills/alpha/SKILL.md"
  has "skills/beta/SKILL.md"
}

@test "coverage is DEPTH 1 by construction — nested skill content is not audited, and that is stated" {
  # Honest scope, pinned so it is not mistaken for full coverage later. A skill IS its top-level
  # SKILL.md, so a newly hand-placed unversioned skill is always caught; content nested inside an
  # already-declared skill is deliberately out of scope (it is what made the wall read as 82 files
  # when the sweep only ever visits 5).
  mkdir -p "$CC_LINKPARITY_CONFIG/skills/deep/references"
  hand_place "skills/deep/references/buried.md"
  run "$LP"
  [ "$status" -eq 0 ]
  lacks "buried.md"
}

@test "directories in a swept surface are not tools — __pycache__ never reads as a stray" {
  mkdir -p "$CC_LINKPARITY_CONFIG/bin/__pycache__"
  run "$LP"
  [ "$status" -eq 0 ]
  lacks "STRAY"
}

@test "a SHADOW is classified ONCE — the stray leg defers to the forward walk, never doubles it" {
  # Both legs sweep the same live directories. A live real file that shadows a tracked one is the
  # overlap: without a claim it is SHADOW here and COPY/STRAY there — two lines, one file, one remedy,
  # and an inflated tally. One population, one state model.
  land_new "hooks/shadowed.sh"
  printf 'new\n' > "$CC_LINKPARITY_CONFIG/hooks/shadowed.sh"     # identical bytes ⇒ would match COPY
  run "$LP"
  [ "$status" -eq 1 ]
  has "SHADOW"
  has "1 actionable"
  has "0 live-extra"
  [ "$(printf '%s' "$output" | grep -c "hooks/shadowed.sh")" -eq 2 ]   # the note + its fix line, not 4
}

@test "a clean live layer still proves the stray leg LOOKED (live-extra is counted, not hidden)" {
  # A leg that can only ever print nothing is indistinguishable from one that never ran.
  printf 'wrapper\n' > "$CC_LINKPARITY_REPO/bin/it2-wrapper"
  printf 'wrapper\n' > "$CC_LINKPARITY_CONFIG/bin/it2"
  run "$LP"
  [ "$status" -eq 0 ]
  has "1 live-extra"
  has "every landed file is live"
}

# ── the STRAY leg's content-match, and why its SIZE is the whole test (2026-08-19) ───────────────
# content_is_tracked() ended in a bare `printf '%s\n' "$TRACKED_SET" | grep -qxF -- "$h"`. Under the
# file's own `set -uo pipefail` that pipeline's rc is the FUNCTION'S RETURN VALUE, and `grep -q`
# exits the moment it matches — killing the producer with SIGPIPE and yielding rc 141. So a file
# whose bytes ARE tracked answered "not tracked" and was convicted STRAY.
#
# 🚨 THE FIXTURE MUST OVERFLOW THE 64 KiB PIPE BUFFER OR THIS CASE IS VACUOUS. Below it the producer
# completes before the consumer is even scheduled, nothing is signalled, and the case passes against
# the UNFIXED script. That is asserted explicitly below rather than left to the file count.
@test "a content-matched copy is not convicted STRAY once the tracked set passes the pipe buffer (PIPE1)" {
  git init -q "$CC_LINKPARITY_REPO"
  printf 'the-copied-bytes\n' > "$CC_LINKPARITY_REPO/bin/aaa-source"
  ln -sfn "$CC_LINKPARITY_REPO/bin/aaa-source" "$CC_LINKPARITY_CONFIG/bin/aaa-source"
  # Filler lives in docs/, which no surface walk visits, so it inflates TRACKED_SET without minting
  # 1,800 UNLINKED findings. Empty files share one blob, but ls-files prints one ROW PER PATH.
  mkdir -p "$CC_LINKPARITY_REPO/docs"
  local i=0
  while [ "$i" -lt 1800 ]; do : > "$CC_LINKPARITY_REPO/docs/f$i"; i=$((i + 1)); done
  git -C "$CC_LINKPARITY_REPO" add -A >/dev/null 2>&1
  # the live REAL file: same bytes as bin/aaa-source, different name — the copy-deploy shape
  printf 'the-copied-bytes\n' > "$CC_LINKPARITY_CONFIG/bin/zz-copy"
  chmod +x "$CC_LINKPARITY_CONFIG/bin/zz-copy"

  # ANTI-VACUITY, both halves: the set must be git-backed AND past 64 KiB (40-char sha + newline).
  run git -C "$CC_LINKPARITY_REPO" ls-files
  [ "${#lines[@]}" -ge 1700 ] || false
  [ "$(( ${#lines[@]} * 41 ))" -gt 65536 ] || false
  # ...and the match must sort EARLY, or grep never exits before the producer finishes.
  run bash -c "git -C '$CC_LINKPARITY_REPO' ls-files | head -1"
  [ "$output" = "bin/aaa-source" ] || false

  run bash "$LP" --all
  lacks "STRAY"
  lacks "zz-copy                                      live and executable, in NO checkout"
  has "COPY"
}
