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

# ── FORWARD-WALK COVERAGE, DERIVED FROM install.sh (2026-08-31) ──────────────────────────────────
# install.sh is the map of record and the forward walk RESTATES it. A restatement drifts, and the
# drift is invisible because a class nobody walks produces no output — the absence of a finding and
# the absence of a look are the same bytes on the terminal.
#
# HOW THIS WENT WRONG TWICE, WHICH IS WHY THE ARM IS DERIVED RATHER THAN A LIST. On 2026-08-31 the
# walk globbed bin/cc-* while install.sh globbed three bin/ families; that was repaired, and
# tests/ms365-reply-splice.bats pinned the bin/ families. Hours later the SAME file was measured
# against install.sh's WHOLE glob set and covered 9 of 19 classes: the repair had been per-FAMILY
# while the blindness was per-CLASS. Twenty-nine tracked files across seven per-file classes had
# never once been check_one'd. Fixing one holder of an enumeration is not the same as counting them.
#
# WHY BOTH SIDES ARE EXTRACTED. Neither set is written down here. install.sh's classes come out of
# its own `for ... in` headers and the walk's come out of the walk's, so a class either author adds
# tomorrow is scored without editing this file — which is exactly the property a hand-copied list
# cannot have, and the property whose absence produced both defects above.
#
# THE THIRD SET IS WHAT MAKES THE ARM HONEST. Three of install.sh's classes deploy to a different
# ROOT or by a different MODEL (githooks → .git/hooks, launchd → ~/Library/LaunchAgents, vendor →
# one directory symlink per plugin), so walking them would mint a false finding per member. They are
# DECLARED in deploy-link-parity.sh's NOT-PER-FILE block rather than silently omitted, and this arm
# requires every class to land in exactly one of the two sets. An omission carries no reason; a
# declaration does, and only a declaration can be reviewed when it stops being true.
derive_class_sets() {   # $1 = install.sh to read · writes inst/walk/excl into $BATS_TEST_TMPDIR
  local inst="$1" linkp="$REPO_ROOT/scripts/deploy-link-parity.sh" hdr ftr lh lf
  hdr='# --- the per-file symlink surfaces install.sh deploys'
  ftr='for d in hooks hooks/lib commands scripts scripts/limit-recover bin; do sweep_orphans'
  # Both region anchors must be UNIQUE before anything is read between them. A census that cannot
  # refuse is not a census: a duplicated anchor would silently select the wrong span and every
  # assertion below would be about a region nobody chose.
  [ "$(grep -cF -- "$hdr" "$linkp")" -eq 1 ]
  [ "$(grep -cF -- "$ftr" "$linkp")" -eq 1 ]
  lh="$(grep -nF -- "$hdr" "$linkp" | cut -d: -f1)"
  lf="$(grep -nF -- "$ftr" "$linkp" | cut -d: -f1)"
  sed -n "${lh},${lf}p" "$linkp" >"$BATS_TEST_TMPDIR/region.txt"
  # Tokens are taken WHOLE (everything after the quoted variable, up to whitespace/quote/semicolon)
  # and compared with grep -xF. A substring compare would be wrong in both directions here:
  # /lib/*.sh is a strict substring of /hooks/lib/*.sh and of /scripts/lib/*.sh, so a bare -F match
  # would score lib/ as covered by a line that never mentions it.
  grep -E '^[[:space:]]*for [A-Za-z_]+ in ' "$inst" \
    | grep -oE '\$REPO_DIR"/[^ ";]+' | sed 's/^\$REPO_DIR"//' | sort -u >"$BATS_TEST_TMPDIR/inst.txt"
  grep -E '^[[:space:]]*for [A-Za-z_]+ in ' "$BATS_TEST_TMPDIR/region.txt" \
    | grep -oE '\$REPO"/[^ ";]+' | sed 's/^\$REPO"//' | sort -u >"$BATS_TEST_TMPDIR/walk.txt"
  grep -F '#   NOT-PER-FILE ' "$linkp" | awk '{print $3}' | sort -u >"$BATS_TEST_TMPDIR/excl.txt"
  return 0
}

@test "every deploy class install.sh globs is either forward-walked or declared NOT-PER-FILE" {
  derive_class_sets "$REPO_ROOT/install.sh"

  # NON-VACUITY, all four halves. Each derivation is a pipeline over a real file, and a pipeline
  # that silently reads nothing yields "every member passes" over an empty set. The floors are the
  # populations that existed when this arm was written, so they can only be tripped by a shrink.
  [ "$(grep -c . "$BATS_TEST_TMPDIR/inst.txt")" -ge 15 ]
  [ "$(grep -c . "$BATS_TEST_TMPDIR/walk.txt")" -ge 9 ]
  [ "$(grep -c . "$BATS_TEST_TMPDIR/excl.txt")" -ge 3 ]
  # ...and a known member of each set, so a derivation that produced 15 lines of the WRONG thing
  # still fails. hooks/*.sh predates every fix here; githooks/* is the oldest excluded class.
  [ "$(grep -cxF -- '/hooks/*.sh' "$BATS_TEST_TMPDIR/walk.txt")" -eq 1 ]
  [ "$(grep -cxF -- '/githooks/*' "$BATS_TEST_TMPDIR/excl.txt")" -eq 1 ]

  # THE SUBSTITUTION GOES INSIDE `[ ]`, NEVER INTO A BARE ASSIGNMENT. `grep -c` prints 0 and EXITS 1
  # on a legitimate zero, so `n="$(grep -c ...)"` fails the whole test under bats+errexit — and it
  # fails on the COMMONEST input here, since most classes are absent from the exclusion set. Both
  # loops below were written that way first: this arm then went red on the FIXED tree, and the fire
  # test below went red on the unfixed one for that reason instead of for the defect, which would
  # have shipped a control credited for a failure it did not cause. Inside `[ ]` the rc is discarded.
  UNCLAIMED="$BATS_TEST_TMPDIR/unclaimed.txt"; : >"$UNCLAIMED"
  BOTH="$BATS_TEST_TMPDIR/both.txt"; : >"$BOTH"
  while IFS= read -r cls; do
    if [ "$(grep -cxF -- "$cls" "$BATS_TEST_TMPDIR/walk.txt")" -eq 0 ] \
       && [ "$(grep -cxF -- "$cls" "$BATS_TEST_TMPDIR/excl.txt")" -eq 0 ]; then
      printf '%s\n' "$cls" >>"$UNCLAIMED"
    fi
    if [ "$(grep -cxF -- "$cls" "$BATS_TEST_TMPDIR/walk.txt")" -ge 1 ] \
       && [ "$(grep -cxF -- "$cls" "$BATS_TEST_TMPDIR/excl.txt")" -ge 1 ]; then
      printf '%s\n' "$cls" >>"$BOTH"
    fi
  done <"$BATS_TEST_TMPDIR/inst.txt"

  # A class in NEITHER set is the defect this arm exists for: install.sh deploys it and nothing
  # ever reports it missing.
  [ "$(grep -c . "$UNCLAIMED")" -eq 0 ]
  # A class in BOTH is a contradiction — the file would be simultaneously walking it and declaring
  # that walking it is the wrong question. Asserting it keeps the two sets a real partition rather
  # than two lists that happen to cover everything.
  [ "$(grep -c . "$BOTH")" -eq 0 ]
}

@test "the coverage arm can FIRE — a new install.sh class in neither set is reported unclaimed" {
  # Without this, the arm above is a green nobody has ever seen go red, and a control that has
  # never fired is indistinguishable from one that cannot. The seed is a class install.sh globs
  # and deploy-link-parity neither walks nor declares — the exact shape of both real defects.
  cp "$REPO_ROOT/install.sh" "$BATS_TEST_TMPDIR/install-seeded.sh"
  printf 'for zzz in "$REPO_DIR"/zzzclass-xyzzy/*.zzz; do :; done\n' >>"$BATS_TEST_TMPDIR/install-seeded.sh"

  derive_class_sets "$BATS_TEST_TMPDIR/install-seeded.sh"
  # The seed must actually have entered the derived population, or the run below proves nothing
  # about the arm and only that the seed was invisible.
  [ "$(grep -cxF -- '/zzzclass-xyzzy/*.zzz' "$BATS_TEST_TMPDIR/inst.txt")" -eq 1 ]

  UNCLAIMED="$BATS_TEST_TMPDIR/unclaimed-seeded.txt"; : >"$UNCLAIMED"
  while IFS= read -r cls; do
    if [ "$(grep -cxF -- "$cls" "$BATS_TEST_TMPDIR/walk.txt")" -eq 0 ] \
       && [ "$(grep -cxF -- "$cls" "$BATS_TEST_TMPDIR/excl.txt")" -eq 0 ]; then
      printf '%s\n' "$cls" >>"$UNCLAIMED"
    fi
  done <"$BATS_TEST_TMPDIR/inst.txt"

  # EXACTLY one, and it is the seed: a count alone would also pass if the real tree had drifted
  # under us, crediting this control for a failure it did not cause.
  [ "$(grep -c . "$UNCLAIMED")" -eq 1 ]
  [ "$(grep -cxF -- '/zzzclass-xyzzy/*.zzz' "$UNCLAIMED")" -eq 1 ]
}

# --- UNCONVERGED: the third state, added 2026-08-31 --------------------------------------------
# The two states the stray leg had were "bytes in this checkout" and "bytes nowhere". Both are
# questions about ONE checkout, and the live symlink source is behind origin/main for as long as a
# land goes unconverged — measured six commits behind on 2026-08-31, with a file landed that morning
# reported as "in NO checkout — unversioned". These arms pin the separation and, more importantly,
# pin the two OPPOSITE remedies apart.

# A repo whose INDEX lacks a path that its TRUNK REF still carries — the shared checkout's exact
# state whenever a land has not converged. Returns with $TRUNKREF set for the caller to drive.
behind_checkout() {   # $1 = repo-relative path · $2 = its bytes
  git -C "$CC_LINKPARITY_REPO" init -q
  # `:?` guards the ARGUMENT, not the call: `git -C ""` is a NO-OP, so an unset/empty repo path
  # would write these identities into whatever repo bats is standing in — and ~100 worktrees here
  # share ONE .git/config, so one escape re-authors every session on the box.
  git -C "${CC_LINKPARITY_REPO:?repo path required}" config user.email t@t
  git -C "${CC_LINKPARITY_REPO:?repo path required}" config user.name t
  printf '%s\n' "$2" > "$CC_LINKPARITY_REPO/$1"
  git -C "$CC_LINKPARITY_REPO" add -A
  git -C "$CC_LINKPARITY_REPO" commit -qm landed
  export TRUNKREF="refs/remotes/origin/main"
  git -C "$CC_LINKPARITY_REPO" update-ref "$TRUNKREF" "$(git -C "$CC_LINKPARITY_REPO" rev-parse HEAD)"
  git -C "$CC_LINKPARITY_REPO" rm -q "$CC_LINKPARITY_REPO/$1"
  git -C "$CC_LINKPARITY_REPO" commit -qm "not converged here"
  export CC_LINKPARITY_TRUNK="$TRUNKREF"
}

@test "a live file whose bytes are on TRUNK but not in this INDEX is UNCONVERGED, never STRAY" {
  # The defect: "in NO checkout — unversioned, invisible to review" is a claim about the world, and
  # `git ls-files -s` is evidence about one reader. A file landed and not yet converged satisfies
  # the evidence and contradicts the claim.
  behind_checkout "skills/demo/SKILL.md" "landed-this-morning"
  printf 'landed-this-morning\n' > "$CC_LINKPARITY_CONFIG/skills/demo/SKILL.md"
  run "$LP"
  [ "$status" -eq 1 ]
  has "UNCONVERGED"
  has "skills/demo/SKILL.md"
  lacks "in NO checkout"
  has "1 actionable"        # still a finding: bytes reaching the live layer unlinked IS drift
}

@test "UNCONVERGED prints the CONVERGER, never a cp/add into a checkout that already has the file" {
  # The half that bites hardest. A remedy computed from an incomplete classification does not just
  # mislabel — it prescribes, and here it prescribed staging an already-landed file into the shared
  # checkout this repo's own .claude/CLAUDE.md opens by forbidding anyone to commit in.
  behind_checkout "skills/demo/SKILL.md" "landed-this-morning"
  printf 'landed-this-morning\n' > "$CC_LINKPARITY_CONFIG/skills/demo/SKILL.md"
  run "$LP"
  [ "$status" -eq 1 ]
  has "deploy-live.sh"
  has "do NOT cp/add it into the checkout"
  # The wrong remedy must be gone for THIS path. Anchored on the add verb plus the path, because a
  # bare "git add" would also match a sibling finding's fix and the assertion would pass vacuously.
  [ "$(printf '%s' "$output" | grep -cF -- 'add "skills/demo/SKILL.md"')" -eq 0 ]
}

@test "CONTROL: a live file on NEITHER index nor trunk stays STRAY, with the cp/add remedy intact" {
  # The FIRE control for the old class. A re-labelling that swallowed the real strays would be a
  # weaker gate wearing a fix's clothes, and a count alone cannot tell the two apart.
  behind_checkout "skills/demo/SKILL.md" "landed-this-morning"
  hand_place "bin/cc-thread"
  run "$LP"
  [ "$status" -eq 1 ]
  has "STRAY"
  has "bin/cc-thread"
  has "in NO checkout"
  [ "$(printf '%s' "$output" | grep -cF -- 'add "bin/cc-thread"')" -eq 1 ]
}

@test "CONTROL: an unresolvable trunk ref falls back to STRAY — the clause fails toward the finding" {
  # The new question needs a ref, and a ref can be missing (a fresh clone with no remote, the
  # hermetic no-git branch). Failing closed here would mean laundering a real stray into silence on
  # exactly the machines least able to notice. It must degrade to the old, louder answer.
  behind_checkout "skills/demo/SKILL.md" "landed-this-morning"
  printf 'landed-this-morning\n' > "$CC_LINKPARITY_CONFIG/skills/demo/SKILL.md"
  export CC_LINKPARITY_TRUNK="refs/remotes/origin/no-such-branch"
  run "$LP"
  [ "$status" -eq 1 ]
  has "STRAY"
  lacks "UNCONVERGED"
}

# --- REFERENCE PROVENANCE: the reference states its own currency, added 2026-08-31 ---------------
# The clause above asks the trunk ref before convicting ONE file. These arms pin the sentence that
# covers every absence verdict at once: how far behind the trunk ref is the index all of them were
# computed against. The measurement that forced it is that the clause above landed on trunk and the
# real destination went on printing the pre-fix verdict for a whole link, because the script is
# reached by a per-file symlink into the very checkout whose staleness produces the false verdict —
# 8 commits behind, with ZERO occurrences of content_is_on_trunk in the copy that executed.
#
# A checkout GENUINELY BEHIND its trunk ref. behind_checkout() above is not that, by measurement:
# it produces the index/trunk disagreement the stray leg needs by REMOVING the path in a LATER
# commit, so its HEAD is one commit AHEAD of the ref and `rev-list --count HEAD..<ref>` reads 0.
# Correct for a question about blob membership, useless for a question about LAG. This one lands the
# file on a side branch, points the ref there, and leaves HEAD on the branch that never got it —
# which is the shared checkout's actual shape, and needs no destructive git to build.
behind_by() {   # $1 = repo-relative path · $2 = its bytes → checkout sits 1 commit behind the ref
  local base_branch
  git -C "$CC_LINKPARITY_REPO" init -q
  # `:?` guards the ARGUMENT, not the call — see behind_checkout above for why that matters here.
  git -C "${CC_LINKPARITY_REPO:?repo path required}" config user.email t@t
  git -C "${CC_LINKPARITY_REPO:?repo path required}" config user.name t
  git -C "$CC_LINKPARITY_REPO" add -A
  git -C "$CC_LINKPARITY_REPO" commit -qm base
  base_branch="$(git -C "$CC_LINKPARITY_REPO" rev-parse --abbrev-ref HEAD)"
  git -C "$CC_LINKPARITY_REPO" checkout -q -b landed-elsewhere
  printf '%s\n' "$2" > "$CC_LINKPARITY_REPO/$1"
  git -C "$CC_LINKPARITY_REPO" add -A
  git -C "$CC_LINKPARITY_REPO" commit -qm landed
  export TRUNKREF="refs/remotes/origin/main"
  git -C "$CC_LINKPARITY_REPO" update-ref "$TRUNKREF" "$(git -C "$CC_LINKPARITY_REPO" rev-parse HEAD)"
  git -C "$CC_LINKPARITY_REPO" checkout -q "$base_branch"
  export CC_LINKPARITY_TRUNK="$TRUNKREF"
}

@test "a reference BEHIND its trunk ref says so, above the findings it qualifies" {
  # The whole defect in one arm: the verdicts are evidence about an index, the index has a lag, and
  # the lag was never printed. Position is load-bearing — a caveat underneath the list it qualifies
  # has already been skipped by the reader it exists for.
  behind_by "skills/demo/SKILL.md" "landed-this-morning"
  printf 'landed-this-morning\n' > "$CC_LINKPARITY_CONFIG/skills/demo/SKILL.md"
  run "$LP"
  has "commit(s) BEHIND"
  has "1 commit(s) BEHIND"
  has "computed against THIS index"
  # ABOVE the findings, not below: the reference line must precede the first verdict line. Ordering
  # is decided in ONE awk pass rather than a grep|head|cut chain, so a missing side cannot arrive as
  # an empty string that a numeric comparison then reads as a position.
  [ "$(printf '%s\n' "$output" | awk '
       /commit\(s\) BEHIND/ { if (r == 0) r = NR }
       /UNCONVERGED/        { if (f == 0) f = NR }
       END { print (r > 0 && f > 0 && r < f) ? "above" : "NOT-above(r=" r " f=" f ")" }')" = "above" ]
}

@test "CONTROL: at a lag of 0 the reference line is SILENT — a caveat on every clean run is noise" {
  # A deliberate zero. An advisory that fires on every run carries the same information as one that
  # cannot fire, so lag 0 must add nothing to the bare report. behind_checkout's own lag IS 0
  # (measured: HEAD one AHEAD of the ref), which is what makes it the right fixture for this arm.
  behind_checkout "skills/demo/SKILL.md" "landed-this-morning"
  printf 'landed-this-morning\n' > "$CC_LINKPARITY_CONFIG/skills/demo/SKILL.md"
  run "$LP"
  lacks "commit(s) BEHIND"
  lacks "is CURRENT with"
  lacks "lag is UNKNOWN"
  has "UNCONVERGED"          # the run still did its real work; only the caveat is absent
}

@test "--all makes a CURRENT reference say so, so a missing line cannot mean both current and unchecked" {
  # The other half of the silence above. Without a reachable positive reading, "no reference line"
  # means both "checked, current" and "never asked" — the shape that let this go unnoticed for a
  # whole link (memory: lookup-miss-is-not-absence).
  behind_checkout "skills/demo/SKILL.md" "landed-this-morning"
  printf 'landed-this-morning\n' > "$CC_LINKPARITY_CONFIG/skills/demo/SKILL.md"
  run "$LP" --all
  has "is CURRENT with"
  has "refs/remotes/origin/main"
  lacks "commit(s) BEHIND"
}

@test "CONTROL: a git reference whose trunk ref will not resolve reads UNKNOWN, never 0" {
  # 0 is the HEALTHY answer here, so a failed read that rendered as 0 would be indistinguishable
  # from a converged reference — the fail-safe-mimics-healthy shape. It has to say it cannot tell.
  behind_by "skills/demo/SKILL.md" "landed-this-morning"
  printf 'landed-this-morning\n' > "$CC_LINKPARITY_CONFIG/skills/demo/SKILL.md"
  export CC_LINKPARITY_TRUNK="refs/remotes/origin/no-such-branch"
  run "$LP"
  has "lag is UNKNOWN"
  lacks "commit(s) BEHIND"
  lacks "is CURRENT with"
}

@test "CONTROL: a NON-git reference prints no provenance line at all — the question is n-a, not 0" {
  # The hermetic fixture every other arm in this file runs on has no git at all, so "how far behind
  # its trunk ref" does not exist as a question. Reporting UNKNOWN there would put a permanent
  # warning on every hermetic run; reporting 0 would assert currency nobody measured. It says
  # nothing, and this arm is predicted GREEN before the fix as well as after — it PINS the silence
  # rather than creating it, which is what stops the table below reading as complete.
  hand_place "bin/cc-thread"
  run "$LP"
  lacks "commit(s) BEHIND"
  lacks "is CURRENT with"
  lacks "lag is UNKNOWN"
  has "STRAY"
}

# ── THE REVERSE DIRECTION: does the MAP cover the TERRITORY? (2026-08-31) ────────────────────────
# Every other arm in this file drives the script through its map — the forward walk's globs, or one
# of the two hand-written sweep directory lists. The arm at :623 asks the coverage question already,
# and it is green, because its population is `grep -E '^[[:space:]]*for [A-Za-z_]+ in ' install.sh`:
# loop headers only. install.sh's SEVEN single-file `link_file "$REPO_DIR/<x>"` sites have no loop
# header, and scripts/kitty-setup.sh — the second installer — is never read at all, so neither is a
# member of that arm's question rather than an uncovered member of it.
#
# MEASURED against the live layer 2026-08-31T23:56:23Z: 512 distinct checkout paths carry a per-file
# live symlink and the forward walk claimed 458. The 54 it never visits are not a hypothesis; they
# are already deployed and executing, which is what makes the blind region demonstrably real rather
# than merely possible. These arms drive the new leg through the fixture instead, so they pass on a
# fresh clone, in a worktree and in CI.
#
# A NESTED SKILL FILE IS THE FIXTURE ON PURPOSE: it is the largest of the five real classes (39 of
# the 54) and it is the one whose two enumerations are provably the same class at two depths —
# install.sh:745-754 links every file under a skill RECURSIVELY, the forward walk visits depth 1.

@test "the reverse walk names a live-linked file no forward-walk glob visits (UNMAPPED)" {
  mkdir -p "$CC_LINKPARITY_REPO/skills/demo/references" "$CC_LINKPARITY_CONFIG/skills/demo/references"
  printf 'nested\n' > "$CC_LINKPARITY_REPO/skills/demo/references/buried.md"
  ln -sfn "$CC_LINKPARITY_REPO/skills/demo/references/buried.md" \
          "$CC_LINKPARITY_CONFIG/skills/demo/references/buried.md"
  run "$LP" --all
  [ "$status" -eq 0 ]
  has "UNMAPPED"
  has "skills/demo/references/buried.md"
  # the COUNT as well as the line: a leg that named the file but tallied 0 would still let the
  # summary say the map covers the territory, which is the sentence this whole class exists to stop.
  has "1 unmapped"
}

@test "CONTROL: a forward-walked file is CLAIMED, so a clean layer reads 0 unmapped" {
  # setup() links hooks/established.sh, which hooks/*.sh DOES glob. If _claimed() failed to match —
  # the fail-OPEN direction, and the one a pipeline membership test would produce — this reads 1.
  # Without this arm the leg could pass the case above by reporting EVERY live link as unmapped.
  run "$LP"
  [ "$status" -eq 0 ]
  has "1 linked"
  has "0 unmapped"
  lacks "UNMAPPED"
}

@test "CONTROL: with no live link into the checkout the field is ?, never 0" {
  # 0 unmapped is the HEALTHY value — "the map covers the territory" — so a failed or empty
  # enumeration rendering as 0 would be indistinguishable from a fully-mapped layer, and it is the
  # most reassuring sentence this report can print. The denominator decides, not the numerator.
  rm "$CC_LINKPARITY_CONFIG/hooks/established.sh"
  run "$LP"
  [ "$status" -eq 1 ]
  has "? unmapped"
  lacks "0 unmapped"
}

@test "a SHADOW is still classified ONCE once SEEN passes the pipe buffer (SEEN's own PIPE arm)" {
  # THE SECOND READER OF SEEN, found by the first. Writing sweep_unmapped's membership test made the
  # question "what else reads SEEN" unavoidable, and the answer was the stray leg's deferral, which
  # until 2026-08-31 read `printf '%s' "$SEEN" | grep -qxF -- "$rel" && continue`.
  #
  # Under the script's own `set -uo pipefail` that pipeline's rc IS the deferral, and it inverts on
  # the MATCH: grep -q exits the instant it finds the path, printf takes SIGPIPE, pipefail promotes
  # the rc to 141, `&& continue` never fires, and a file the forward walk already reported SHADOW is
  # classified a SECOND time — the exact double-classification SEEN was introduced to prevent.
  #
  # THE FIXTURE MUST OVERFLOW THE 64 KiB PIPE BUFFER OR THIS CASE IS VACUOUS, for the same reason
  # the PIPE1 arm above states it, and the once-only arm above THAT is why it matters: that arm pins
  # this very contract and was green over this defect for its whole life, because its SEEN is a few
  # hundred bytes. The real layer measured 12,113 B at 458 claimed paths — latent, at ~33% of floor,
  # on a feed that only grows.
  #
  # 400 x ~255 B is chosen from the MEASURED regime rather than picked: the two-stage builtin
  # pipeline is SAFE to 37,121 B, racy from 55,721 and ALWAYS inverted past 87,122. Sizing past the
  # always-inverted floor makes a re-introduced pipeline fail EVERY run, not one in twenty.
  # 🚨 THE NEEDLE MUST SIT NEAR THE START OF THE FEED, WHICH IS WHY THE PADDING IS NAMED `zz`.
  # SIZE ALONE IS NOT ENOUGH and this arm was written the other way first: with the padding sorted
  # BEFORE the needle, the forward walk appends `hooks/shadowed.sh` near the END of SEEN, grep
  # matches only after printf has already written all 102 KB, nothing is ever signalled, and the arm
  # passed against the UNFIXED script. That is #241's measured protocol restated as a fixture
  # constraint — every band in the table was measured with the needle on LINE 1 — and it is the
  # difference between a behavioural arm and a green nobody can attribute. The forward walk's glob
  # is lexicographic, so `shadowed.sh` precedes every `zz…` pad.
  PAD=""
  while [ "${#PAD}" -lt 240 ]; do PAD="${PAD}padding"; done
  PAD="${PAD:0:240}"
  i=0
  while [ "$i" -lt 400 ]; do
    printf 'pad\n' > "$CC_LINKPARITY_REPO/hooks/zz${i}-${PAD}.sh"
    ln -sfn "$CC_LINKPARITY_REPO/hooks/zz${i}-${PAD}.sh" "$CC_LINKPARITY_CONFIG/hooks/zz${i}-${PAD}.sh"
    i=$((i + 1))
  done
  # NON-VACUITY, asserted rather than assumed: the claimed-path bytes must actually clear the
  # always-inverted floor, or this arm passes against the UNFIXED script and credits itself.
  [ "$(cd "$CC_LINKPARITY_REPO" && find hooks -name 'zz*.sh' -type f | wc -c)" -gt 87122 ]

  land_new "hooks/shadowed.sh"
  printf 'new\n' > "$CC_LINKPARITY_CONFIG/hooks/shadowed.sh"     # identical bytes ⇒ matches COPY

  # 🚨 ASSERT THE COLUMN THAT ACTUALLY DIFFERS. Written first as `[ grep -c == 2 ]` + `1 actionable`
  # and it passed against the UNFIXED subject, because BOTH of those hold in BOTH states: the second
  # classification here is COPY, whose note is gated behind $ALL, and COPY neither adds a finding nor
  # a fix line. Measured on ONE fixture with BOTH subjects (probe272-shadow.sh) —
  #     PRE   400 linked · 0 staged-pending · 1 live-extra · 1 actionable   (--all: 3 mentions)
  #     POST  400 linked · 0 staged-pending · 0 live-extra · 0 unmapped · 1 actionable   (--all: 2)
  # — so live-extra is the discriminating column and --all is what makes the duplicate line visible.
  # The idiom itself was confirmed to invert 20/20 at this feed with the needle on line 1, and 0/20
  # with it last, so a green here is a statement about the ASSERTION, never about the pipeline.
  run "$LP" --all
  [ "$status" -eq 1 ]
  has "SHADOW"
  has "0 live-extra"
  # the note + its fix line, not 3: the duplicate is a COPY line for a path already reported SHADOW
  [ "$(printf '%s' "$output" | grep -c "hooks/shadowed.sh")" -eq 2 ]
}

@test "CONTROL: UNMAPPED never changes the verdict — predicted GREEN before the fix too" {
  # A DELIBERATE ZERO. This arm is green on the unfixed script as well as the fixed one, and saying
  # so is the point: it pins that the new class adds no finding and moves no exit status, which is
  # exactly the claim the other three arms CANNOT make. A uniform prediction across a table says
  # nothing about attribution; a varying one is a claim about what the design can and cannot catch.
  mkdir -p "$CC_LINKPARITY_REPO/skills/demo/references" "$CC_LINKPARITY_CONFIG/skills/demo/references"
  printf 'nested\n' > "$CC_LINKPARITY_REPO/skills/demo/references/buried.md"
  ln -sfn "$CC_LINKPARITY_REPO/skills/demo/references/buried.md" \
          "$CC_LINKPARITY_CONFIG/skills/demo/references/buried.md"
  run "$LP"
  [ "$status" -eq 0 ]
  has "0 actionable"
  has "every landed file is live"
}

# ── THE DANGLING CLASS BEYOND sweep_orphans's HAND-WRITTEN SCOPE (2026-09-01) ────────────────────
#
# sweep_strays skips every symlink, deferring in a comment to "the forward walk / sweep_orphans".
# That is a PARTITION CLAIM over the live symlink population naming two owners, and the forward walk
# cannot own the rename/delete case at all: check_one returns at `[ -f "$src" ]`, since a
# renamed-away target IS a repo file that no longer exists. So the whole class rested on
# sweep_orphans's directory list — six names plus skills/*/, one level deep — which is the fourth
# restated enumeration of the live layer in that file and the only one no arm quantified over.
#
# MEASURED 2026-09-01T01:18Z on the live layer: 514 symlinks resolve into the checkout, the ORPHAN
# leg's scope reaches 446, and it misses 68. A hermetic run with one broken link planted per scope
# class reported ONE of five and printed "0 unmapped" over the other four — the `[ -f "$tgt" ]` test
# in sweep_unmapped dropped them before the non-vacuity denominator ever counted them.
#
# The arms below plant the broken link in the classes the list cannot reach. The last two predict
# GREEN on purpose: one pins that the in-scope case is still reported exactly ONCE (the new deferral
# ledger), the other that a resolving directory symlink is still not a finding (the -f test kept its
# real job when it stopped doubling as the dangling filter).

@test "a dangling link in scripts/lib — swept for STRAYS, never for ORPHANS — is reported" {
  mkdir -p "$CC_LINKPARITY_CONFIG/scripts/lib"
  ln -sfn "$CC_LINKPARITY_REPO/scripts/lib/renamed-away.sh" \
          "$CC_LINKPARITY_CONFIG/scripts/lib/renamed-away.sh"
  run "$LP"
  [ "$status" -eq 1 ]
  has "ORPHAN"
  has "scripts/lib/renamed-away.sh"
  has "rm \"$CC_LINKPARITY_CONFIG/scripts/lib/renamed-away.sh\""
}

@test "a dangling link at the CONFIG ROOT is reported — model-config.yaml lives there" {
  # Not a hypothetical directory: model-config.yaml, providers.json and accounts.json are all
  # root-level live links into the checkout today, and the root is in NEITHER sweep list.
  ln -sfn "$CC_LINKPARITY_REPO/model-config.yaml" "$CC_LINKPARITY_CONFIG/model-config.yaml"
  run "$LP"
  [ "$status" -eq 1 ]
  has "ORPHAN"
  has "model-config.yaml"
}

@test "a dangling link in a skills SUBdirectory is reported — sweep_orphans is one level deep" {
  # sweep_orphans iterates "$CFG"/skills/*/ and then "$d"/*, so skills/<n>/<file> is swept and
  # skills/<n>/<sub>/<file> is not. 37 of the 68 uncovered live links are this shape.
  mkdir -p "$CC_LINKPARITY_CONFIG/skills/demo/references"
  ln -sfn "$CC_LINKPARITY_REPO/skills/demo/references/gone.md" \
          "$CC_LINKPARITY_CONFIG/skills/demo/references/gone.md"
  run "$LP"
  [ "$status" -eq 1 ]
  has "ORPHAN"
  has "skills/demo/references/gone.md"
}

@test "MECHANISM: every dir swept for strays but NOT for orphans has its dangling case reported" {
  # Both lists are DERIVED from the subject, never transcribed, so this arm survives any rewording
  # of the fix and scores a directory added to either loop tomorrow without editing this file. It
  # names no directory: today the set difference is {lib, scripts/lib}, and that is a fact about the
  # source, not about this test. A spelling arm dies the day someone rewords; this one does not.
  local linkp="$REPO_ROOT/scripts/deploy-link-parity.sh"
  [ "$(grep -cE '^for d in .*; do sweep_orphans' "$linkp")" -eq 1 ]
  [ "$(grep -cE '^for d in .*; do sweep_strays' "$linkp")" -eq 1 ]
  grep -E '^for d in .*; do sweep_orphans' "$linkp" | sed 's/^for d in //; s/; do.*//' \
    | tr ' ' '\n' | sort -u > "$BATS_TEST_TMPDIR/orph.txt"
  grep -E '^for d in .*; do sweep_strays' "$linkp" | sed 's/^for d in //; s/; do.*//' \
    | tr ' ' '\n' | sort -u > "$BATS_TEST_TMPDIR/stray.txt"
  comm -13 "$BATS_TEST_TMPDIR/orph.txt" "$BATS_TEST_TMPDIR/stray.txt" > "$BATS_TEST_TMPDIR/gap.txt"
  # NON-VACUITY: if the two lists ever coincide this arm would pass without asserting anything.
  [ "$(wc -l < "$BATS_TEST_TMPDIR/gap.txt")" -ge 1 ]
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    mkdir -p "$CC_LINKPARITY_CONFIG/$d"
    ln -sfn "$CC_LINKPARITY_REPO/$d/vanished.sh" "$CC_LINKPARITY_CONFIG/$d/vanished.sh"
    run "$LP"
    [ "$status" -eq 1 ]
    has "$d/vanished.sh"
    rm -f "$CC_LINKPARITY_CONFIG/$d/vanished.sh"
  done < "$BATS_TEST_TMPDIR/gap.txt"
}

@test "CONTROL: an IN-scope dangling link is still reported exactly ONCE, not twice" {
  # A DELIBERATE ZERO — green before the fix and after it. Two legs now sweep the same class, so
  # without the ORPHANED ledger one broken link would be classified twice with one remedy: the exact
  # double-classification the SEEN ledger was introduced to prevent, one leg over. Counting the
  # ORPHAN lines is what discriminates; a `has "ORPHAN"` would hold in both states and assert nothing.
  ln -sfn "$CC_LINKPARITY_REPO/scripts/renamed-away.sh" "$CC_LINKPARITY_CONFIG/scripts/renamed-away.sh"
  run "$LP" --all
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '^  ORPHAN ')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c 'renamed-away.sh')" -eq 2 ]
}

@test "CONTROL: a RESOLVING directory symlink is still never a finding (the vendor/ leg)" {
  # The -f test used to double as the dangling filter. Splitting the two jobs must not cost it its
  # real one: vendor/ deploys ONE directory symlink per plugin, declared NOT-PER-FILE, and a
  # per-file verdict on it would mint a false finding per member.
  mkdir -p "$CC_LINKPARITY_REPO/vendor/plugin"
  printf 'v\n' > "$CC_LINKPARITY_REPO/vendor/plugin/file.sh"
  mkdir -p "$CC_LINKPARITY_CONFIG/vendor"
  ln -sfn "$CC_LINKPARITY_REPO/vendor/plugin" "$CC_LINKPARITY_CONFIG/vendor/plugin"
  run "$LP"
  [ "$status" -eq 0 ]
  lacks "ORPHAN"
  has "0 unmapped"
}

# ── THE STRAY DIRECTION'S OWN COVERAGE ARM (2026-09-01) ─────────────────────────────────────────
# The arm above pins install.sh's classes against the FORWARD walk. Nothing pinned the forward walk
# against the LIVE-SIDE sweep, so on 2026-08-31 the walk gained seven classes and sweep_strays's
# hand-written list did not follow — measured behaviourally: an unversioned real file planted in
# scripts/backlog-consolidation/ produced no verdict at all, which is the bin/cc-mail defect class
# in a directory the walk had just declared part of the deployed surface. A scope sentence is not
# falsified by anything it says; it is falsified by a sibling enumeration growing, and no reader of
# either one can see the other move. This is that reader.
derive_stray_sets() {  # $1 = the deploy-link-parity.sh to read (a seeded COPY in the fire test)
  local linkp="$1" hdr ftr lh lf
  hdr='# --- the per-file symlink surfaces install.sh deploys'
  ftr='for d in hooks hooks/lib commands scripts scripts/limit-recover bin; do sweep_orphans'
  # Region anchors unique BEFORE anything between them is read — a census that cannot refuse is not
  # a census, and a duplicated anchor would silently select a span nobody chose.
  [ "$(grep -cF -- "$hdr" "$linkp")" -eq 1 ]
  [ "$(grep -cF -- "$ftr" "$linkp")" -eq 1 ]
  lh="$(grep -nF -- "$hdr" "$linkp" | cut -d: -f1)"
  lf="$(grep -nF -- "$ftr" "$linkp" | cut -d: -f1)"
  sed -n "${lh},${lf}p" "$linkp" >"$BATS_TEST_TMPDIR/sregion.txt"
  # The walk's LIVE-SIDE directory is the dirname of each class token: /skills/*/ → skills,
  # /scripts/backlog-consolidation/*.py → scripts/backlog-consolidation. The trailing slash is
  # stripped FIRST, or dirname of /skills/*/ is /skills/* and the two sides never join.
  grep -E '^[[:space:]]*for [A-Za-z_]+ in ' "$BATS_TEST_TMPDIR/sregion.txt" \
    | grep -oE '\$REPO"/[^ ";]+' | sed -e 's/^\$REPO"//' -e 's#/$##' -e 's#/[^/]*$##' -e 's#^/##' \
    | sort -u >"$BATS_TEST_TMPDIR/walkdirs.txt"
  # sweep_strays's scope is TWO things: a flat loop list, and the call sites that pass a literal.
  # Reading only the loop would score skills/ and agents/ as unswept and mint a false finding.
  { grep -F -- '; do sweep_strays "$d"; done' "$linkp" | sed -e 's/^for d in //' -e 's/;.*$//' | tr ' ' '\n'
    grep -oE 'sweep_strays "[^"$]+' "$linkp" | sed -e 's/^sweep_strays "//' -e 's#/$##'
  } | grep -v '^$' | sort -u >"$BATS_TEST_TMPDIR/straydirs.txt"
  grep -F '#   NOT-STRAY-SWEPT ' "$linkp" | awk '{print $3}' | sort -u >"$BATS_TEST_TMPDIR/sexcl.txt"
  return 0
}

@test "every forward-walked directory is either stray-swept or declared NOT-STRAY-SWEPT" {
  derive_stray_sets "$REPO_ROOT/scripts/deploy-link-parity.sh"

  # NON-VACUITY on all three derivations plus a known member of each, so a pipeline that read the
  # wrong thing cannot pass by producing an empty set that every member trivially satisfies.
  [ "$(grep -c . "$BATS_TEST_TMPDIR/walkdirs.txt")" -ge 11 ]
  [ "$(grep -c . "$BATS_TEST_TMPDIR/straydirs.txt")" -ge 10 ]
  [ "$(grep -c . "$BATS_TEST_TMPDIR/sexcl.txt")" -ge 1 ]
  [ "$(grep -cxF -- 'scripts/backlog-consolidation' "$BATS_TEST_TMPDIR/walkdirs.txt")" -eq 1 ]
  [ "$(grep -cxF -- 'hooks' "$BATS_TEST_TMPDIR/straydirs.txt")" -eq 1 ]
  [ "$(grep -cxF -- 'commands' "$BATS_TEST_TMPDIR/sexcl.txt")" -eq 1 ]

  # Every substitution goes INSIDE `[ ]`: grep -c prints 0 and EXITS 1 on a legitimate zero, which
  # is the commonest input here, and a bare assignment would fail the test under bats+errexit.
  UNCLAIMED="$BATS_TEST_TMPDIR/sunclaimed.txt"; : >"$UNCLAIMED"
  BOTH="$BATS_TEST_TMPDIR/sboth.txt"; : >"$BOTH"
  while IFS= read -r d; do
    if [ "$(grep -cxF -- "$d" "$BATS_TEST_TMPDIR/straydirs.txt")" -eq 0 ] \
       && [ "$(grep -cxF -- "$d" "$BATS_TEST_TMPDIR/sexcl.txt")" -eq 0 ]; then
      printf '%s\n' "$d" >>"$UNCLAIMED"
    fi
    if [ "$(grep -cxF -- "$d" "$BATS_TEST_TMPDIR/straydirs.txt")" -ge 1 ] \
       && [ "$(grep -cxF -- "$d" "$BATS_TEST_TMPDIR/sexcl.txt")" -ge 1 ]; then
      printf '%s\n' "$d" >>"$BOTH"
    fi
  done <"$BATS_TEST_TMPDIR/walkdirs.txt"

  # In NEITHER set is the defect: the walk deploys there and no leg would ever report a hand-placed
  # unversioned file in it. In BOTH is a contradiction that would let the two lists stop being a
  # partition and start being two lists that happen to cover everything.
  [ "$(grep -c . "$UNCLAIMED")" -eq 0 ]
  [ "$(grep -c . "$BOTH")" -eq 0 ]
}

@test "the stray-coverage arm can FIRE — a new forward-walk class in neither set is unclaimed" {
  # Without this the arm above is a green nobody has watched go red, and a control that has never
  # fired is indistinguishable from one that cannot. The seed is a class the walk visits and the
  # sweep neither visits nor declares — the exact shape of the scripts/backlog-consolidation defect.
  cp "$REPO_ROOT/scripts/deploy-link-parity.sh" "$BATS_TEST_TMPDIR/lp-seeded.sh"
  awk '/^for d in hooks hooks\/lib commands scripts scripts\/limit-recover bin; do sweep_orphans/ \
         { print "for f in \"$REPO\"/zzzstray-xyzzy/*.zzz; do :; done" } { print }' \
    "$BATS_TEST_TMPDIR/lp-seeded.sh" >"$BATS_TEST_TMPDIR/lp-seeded2.sh"
  mv "$BATS_TEST_TMPDIR/lp-seeded2.sh" "$BATS_TEST_TMPDIR/lp-seeded.sh"

  derive_stray_sets "$BATS_TEST_TMPDIR/lp-seeded.sh"
  # The seed must have entered the derived population, or the loop below proves nothing about the
  # arm and only that the seed was invisible to the extractor.
  [ "$(grep -cxF -- 'zzzstray-xyzzy' "$BATS_TEST_TMPDIR/walkdirs.txt")" -eq 1 ]

  UNCLAIMED="$BATS_TEST_TMPDIR/sunclaimed-seeded.txt"; : >"$UNCLAIMED"
  while IFS= read -r d; do
    if [ "$(grep -cxF -- "$d" "$BATS_TEST_TMPDIR/straydirs.txt")" -eq 0 ] \
       && [ "$(grep -cxF -- "$d" "$BATS_TEST_TMPDIR/sexcl.txt")" -eq 0 ]; then
      printf '%s\n' "$d" >>"$UNCLAIMED"
    fi
  done <"$BATS_TEST_TMPDIR/walkdirs.txt"
  [ "$(grep -cxF -- 'zzzstray-xyzzy' "$UNCLAIMED")" -eq 1 ]
}

@test "a hand-placed unversioned file under scripts/backlog-consolidation is reported STRAY" {
  # BEHAVIOURAL, and it survives any rewording of the fix: it plants the defect class rather than
  # pinning the text of a list. The commands/ plant is the discriminating control — it is DECLARED
  # not-stray-swept, so a green here cannot come from the sweep having simply become indiscriminate.
  export CC_LINKPARITY_MANIFEST="$BATS_TEST_TMPDIR/manifest"; : >"$CC_LINKPARITY_MANIFEST"
  mkdir -p "$CC_LINKPARITY_CONFIG/scripts/backlog-consolidation"
  printf 'hand placed by a peer session\n' > "$CC_LINKPARITY_CONFIG/scripts/backlog-consolidation/handplaced.py"
  printf 'hand placed by a peer session\n' > "$CC_LINKPARITY_CONFIG/commands/handplaced.md"
  run "$LP"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '^  STRAY .*scripts/backlog-consolidation/handplaced.py')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c 'commands/handplaced.md')" -eq 0 ]
}
