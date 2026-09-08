#!/usr/bin/env bats
# The DoD line of a composed brief — MASTER_FIRE_GATE.md § F4, "the stale brief, by construction".
#
# THE DEFECT. `cc-dispatch` composes a worker's brief from the row's title and `dodRef`, and it
# rendered `dodRef` VERBATIM. Every plan-open row in the live store carries an ABSOLUTE path into
# the shared checkout (18 of 18 measured 2026-09-07, all from `bin/cc-discover:273`), and that
# checkout trails trunk — so a worker was told to read its specification from bytes older than the
# fix it was being sent to build on. Re-measured the same day the harm was WORSE than staleness:
# the shared checkout was 1 commit behind trunk with 23 DIRTY files, so a worker that cats the
# absolute path can read a sibling's half-written file (memory:
# peer-worktree-read-midwrite-parses-as-a-code-defect). The worker's OWN worktree is freshness-
# gated by `warm_worktree`; an absolute path routes around that guard entirely.
#
# WHY THE FIX IS HERE AND NOT IN THE PRODUCER. § F4 prescribes "make that the rule for every
# producer" — store `origin/main:<path>`. That is a trap: `cc-eligible._dod_path` and
# `cc-premise._plan_dodref` both resolve a dodRef as a FILESYSTEM path, and the second FAILS OPEN,
# silently deleting the derived plan-open falsifier that those same 18 rows depend on. So the store
# is left alone and the RENDERING is fixed. `tests/cc-venue-dodspec.bats` owns the resolver; this
# suite owns the one property the composer must have.
#
# THE PROPERTY, and it is two-sided on purpose: the brief must be BETTER when the dodRef resolves,
# and BYTE-IDENTICAL to before when it does not. A rendering that "improved" a dodRef it could not
# resolve would be a guess, and a guess in this field sends a worker to a file that does not exist.
# So every non-resolving class — not a path claim, absent from trunk, resolver unavailable — is
# asserted to render the STORED value, and each is paired against the pristine control.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DISP="$REPO/bin/cc-dispatch"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C/stubs" "$C/home" "$C/pristine" "$C/wt"
  export HOME="$C/home"          # hermetic: nothing here may read or write the operator's live ~/

  # THE CONTROL IS A LITERAL SHA, AND THAT IS THE WHOLE POINT. The first version of this suite
  # replayed `origin/main:bin/cc-dispatch`, reasoning that a moving ref keeps the control honest.
  # It is the opposite: origin/main advances PAST this fix the moment it lands, so the control then
  # compares the fix to ITSELF and every case below passes asserting nothing. The land gate's
  # moving-ref ratchet caught it before it landed (memory:
  # control-must-replay-the-real-artifact — a control calibrated to a moving artifact decays
  # silently, and a vacuous green is worse than a red because a red gets fixed).
  #
  # 9b0410823b79c767260da077ea1bd2ee572afff5 is the parent of the dodspec commit: an immutable ancestor of origin/main that carries the
  # verbatim-rendering composer.
  PRE_SHA="${CC_DODSPEC_PRE_SHA:-9b0410823b79c767260da077ea1bd2ee572afff5}"
  git -C "$REPO" show "$PRE_SHA:bin/cc-dispatch" > "$C/pristine/cc-dispatch" 2>/dev/null || true
  PRISTINE="$C/pristine/cc-dispatch"; chmod +x "$PRISTINE" 2>/dev/null || true
  if [ ! -s "$PRISTINE" ]; then
    echo "cc-dispatch-dodspec-brief.bats: cannot recover the pristine control at $PRE_SHA — the RED-proof cannot run." >&2
    return 1
  fi
  # THE MARKER — the second half, and the pin alone is not enough: a re-pointed sha would go
  # vacuous again in silence. `dod_render` is the variable this fix introduces (4 occurrences
  # post-fix, 0 pre-fix, measured), so its ABSENCE proves the replay really is the pre-fix
  # composer and not a copy of the subject.
  if grep -q 'dod_render' "$PRISTINE"; then
    echo "cc-dispatch-dodspec-brief.bats: the 'pristine' control at $PRE_SHA ALREADY CONTAINS dod_render — it is not a pre-fix artifact, so every case here would compare the fix to itself." >&2
    return 1
  fi

  cat > "$C/stubs/backlog" <<EOF
#!/bin/bash
case "\$1" in
  list) jq -c . "$C/items.json" ;;
  claim|reopen|block) printf '%s %s\n' "\$1" "\$2" >> "$C/backlog.log"; echo "\$2" ;;
esac
exit 0
EOF
  # The wave planner hands back the fire line, and the --prompt-file path in it is the artifact
  # this suite reads. An EMPTY file is what makes the composer run at all (`[ ! -s "$pfile" ]`).
  cat > "$C/stubs/waveplan" <<EOF
#!/bin/bash
items='[]'
while [ \$# -gt 0 ]; do case "\$1" in --items) items="\$2"; shift 2 ;; *) shift ;; esac; done
printf '%s' "\$items" | jq -c --arg d "$C" \\
  '[ .[] | {id, account:"next3", fire_line:["--prompt-file",(\$d+"/brief-"+.id+".txt"),"--cwd",(\$d+"/wt/wt-"+.id)] } ]'
EOF
  cat > "$C/stubs/spawn" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$C/spawn.log"
exit 0
EOF
  chmod +x "$C/stubs/backlog" "$C/stubs/waveplan" "$C/stubs/spawn"

  CONF="$C/dispatch-projects.conf"
  printf 'proj  repo=%s\n' "$C/repos/proj" > "$CONF"
  export CC_DISPATCH_BACKLOG_BIN="$C/stubs/backlog" \
         CC_DISPATCH_WAVEPLAN_BIN="$C/stubs/waveplan" \
         CC_DISPATCH_SPAWN_BIN="$C/stubs/spawn" \
         CC_DISPATCH_PAGES_DIR="$C/pages" \
         CC_DISPATCH_IDL="$C/idl.jsonl" \
         CC_DISPATCH_LOCK_DIR="$C/dispatch.lock" \
         CC_DISPATCH_PROJECTS_CONF="$CONF" \
         CC_DISPATCH_PROJECT="proj" \
         CC_DISPATCH_MAX_SPAWN=9 \
         CC_DISPATCH_SID="bats" \
         CC_DISPATCH_VENUE_BIN="$REPO/bin/cc-venue" \
         CC_VENUE_BACKLOG_BIN="$C/stubs/backlog"
  echo '[]' > "$C/items.json"
}

items() { printf '%s' "$1" > "$C/items.json"; }
fresh()  { : > "$C/idl.jsonl"; : > "$C/spawn.log"; : > "$C/backlog.log"
           rm -rf "$C/pages" "$C/dispatch.lock" "$C"/brief-*.txt; }

# mk_repo <dir> — a real repo whose origin/main CARRIES docs/plans/PLAN.md. The subject is
# `git cat-file -e origin/main:<path>`, so the ref must really exist; a stub would test the stub.
mk_repo() {
  local d="$1" o="$1.origin"
  rm -rf "$d" "$o"; mkdir -p "$d/docs/plans" "$o"
  git -C "$o" init -q --bare -b main
  git -C "$d" init -q -b main
  echo one > "$d/f"; printf 'the spec\n' > "$d/docs/plans/PLAN.md"
  git -C "${d:?repo path required}" add -A
  git -C "${d:?repo path required}" -c user.email=t@t -c user.name=t commit -qm one
  git -C "$d" remote add origin "$o"; git -C "$d" push -q origin main
  git -C "$d" fetch -q origin
  git -C "$d" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}

# The composed brief's DoD clause — the one line this suite is about.
dodline() { sed -n 's/^DoD ref: \(.*\)\. Scope (frozen).*$/\1/p' "$C/brief-$1.txt" | head -1; }

run_once() { fresh; CC_DISPATCH_CEILING=9 "$1" --once >/dev/null 2>&1 || true; }

# path_without <name> — $PATH minus every directory that carries an executable <name>. The ABSENCE
# of a binary is not expressible by unsetting one variable; it has to be built, and this is one of
# the three fallbacks that has to be closed to build it (see the fail-open arm below).
path_without() {
  local out='' d; local IFS=:
  for d in $PATH; do [ -x "$d/$1" ] || out="${out:+$out:}$d"; done
  printf '%s' "$out"
}

@test "an ABSOLUTE dodRef into the shared checkout is briefed as a TRUNK PATHSPEC" {
  mk_repo "$C/repos/proj"
  items "$(jq -nc --arg d "$C/repos/proj/docs/plans/PLAN.md" \
    '[{id:"a1",project:"proj",status:"open",title:"t",dodRef:$d}]')"

  run_once "$DISP"
  [ -s "$C/brief-a1.txt" ] || { echo "no brief composed"; false; }
  [ "$(dodline a1)" = "origin/main:docs/plans/PLAN.md" ] || { echo "got: $(dodline a1)"; false; }

  # RED: the pristine composer renders the shared-checkout path the worker must not read.
  run_once "$PRISTINE"
  [ "$(dodline a1)" = "$C/repos/proj/docs/plans/PLAN.md" ] || { echo "control got: $(dodline a1)"; false; }
}

@test "a dodRef that is NOT a path claim is briefed VERBATIM, not guessed at" {
  mk_repo "$C/repos/proj"
  items '[{"id":"a2","project":"proj","status":"open","title":"t","dodRef":"decision:5f0a1b2c"}]'

  run_once "$DISP"
  [ "$(dodline a2)" = "decision:5f0a1b2c" ] || { echo "got: $(dodline a2)"; false; }

  # The control renders it identically — this arm proves the change did not WIDEN. An inverted
  # verdict here means the resolver started answering questions it was not asked.
  run_once "$PRISTINE"
  [ "$(dodline a2)" = "decision:5f0a1b2c" ] || { echo "control got: $(dodline a2)"; false; }
}

@test "a dodRef ABSENT from trunk is briefed VERBATIM — a non-resolution is never a rendered guess" {
  mk_repo "$C/repos/proj"
  items "$(jq -nc --arg d "$C/repos/proj/docs/plans/NEVER_LANDED.md" \
    '[{id:"a3",project:"proj",status:"open",title:"t",dodRef:$d}]')"

  run_once "$DISP"
  [ "$(dodline a3)" = "$C/repos/proj/docs/plans/NEVER_LANDED.md" ] || { echo "got: $(dodline a3)"; false; }
  run_once "$PRISTINE"
  [ "$(dodline a3)" = "$C/repos/proj/docs/plans/NEVER_LANDED.md" ] || { echo "control got: $(dodline a3)"; false; }
}

@test "an UNAVAILABLE resolver costs nothing — the brief is byte-identical to the control's" {
  # THE FAIL-OPEN ARM. cc-venue reaches the composer through a resolved path and a subprocess, and
  # both can be absent on a box mid-deploy. This must degrade to today's behaviour silently, never
  # to an empty DoD line or a refused fire — the brief is on the hot path of every dispatch.
  #
  # THE FIXTURE HAS TO BUILD THE ABSENCE, and pointing CC_DISPATCH_VENUE_BIN at a file that does not
  # exist does not build it. That was this arm's first form and it was a post-land RED within the
  # hour (backlog 0fc69d08957c, 2026-09-08): `resolve_bin` deliberately DROPS a non-executable
  # override and falls through to PATH, then $HOME/.claude/bin, then the SIBLING of the running
  # script — and the subject runs out of $REPO/bin, where cc-venue always sits. Measured: the
  # sibling arm rescued it even at PATH=/usr/bin:/bin with HOME stubbed, so the arm ran against a
  # fully LIVE resolver and compared the fixed rendering to the pre-fix one on every box, always.
  #
  # THE FALLBACKS ARE CLOSED HERE AND NOT IN cc-dispatch. Honouring a set-but-broken override would
  # change production behaviour at all three of its call sites (`ready_paths`, `ready_relabel`, this
  # composer) and make a live dispatch LESS resilient to a mid-deploy gap, to make one fixture
  # convenient — the resolution chain IS the documented contract (§ CC_DISPATCH_VENUE_BIN: "default:
  # co-versioned sibling cc-venue, else PATH / ~/.claude/bin"). So the test reaches the regime it
  # names instead (memory: control-fixture-must-reach-the-bugs-regime).
  mk_repo "$C/repos/proj"
  items "$(jq -nc --arg d "$C/repos/proj/docs/plans/PLAN.md" \
    '[{id:"a4",project:"proj",status:"open",title:"t",dodRef:$d}]')"

  # The control is taken FIRST and held: `fresh` deletes the briefs, so a control read after the
  # degraded run reads whichever run happened to write last.
  run_once "$PRISTINE"
  local control; control="$(dodline a4)"
  [ -n "$control" ] || { echo "the control composed no DoD line at all"; false; }

  # (1) THE BINARY CANNOT BE FOUND. Override absent + no cc-venue on PATH + HOME already stubbed +
  #     the subject copied somewhere with no cc-venue beside it, which is what closes the arm that
  #     actually fired.
  mkdir -p "$C/isolated"; cp "$DISP" "$C/isolated/cc-dispatch"; chmod +x "$C/isolated/cc-dispatch"
  local saved_path="$PATH" blind_path
  blind_path="$(path_without cc-venue)"
  export CC_DISPATCH_VENUE_BIN="$C/stubs/absent-venue" PATH="$blind_path"
  run_once "$C/isolated/cc-dispatch"
  export PATH="$saved_path" CC_DISPATCH_VENUE_BIN="$REPO/bin/cc-venue"
  [ -s "$C/brief-a4.txt" ] || { echo "the fire was lost when the resolver was missing"; false; }
  [ "$(dodline a4)" = "$control" ] || { echo "missing: got=$(dodline a4) control=$control"; false; }

  # (2) THE SUBPROCESS FAILS. The other half of "a resolved path AND a subprocess": the binary is
  #     right there, `[ -x ]` passes so no fallback runs, and it answers non-zero. This reaches the
  #     same fail-open branch from the side no amount of PATH surgery can reach.
  #     The stub PRINTS a plausible answer and THEN exits 4, deliberately: a stub that exited
  #     silently would also be caught by the composer's `[ -n "$dspec" ]` guard, so it could not
  #     tell a dropped exit code from a dropped empty string. Only a talkative failure pins the
  #     rc check, which is the half that decides whether "could not ask" (exit 4) is honoured.
  cat > "$C/stubs/broken-venue" <<'STUB'
#!/bin/bash
echo origin/main:NOT_THE_ANSWER.md
exit 4
STUB
  chmod +x "$C/stubs/broken-venue"
  export CC_DISPATCH_VENUE_BIN="$C/stubs/broken-venue"
  run_once "$DISP"
  export CC_DISPATCH_VENUE_BIN="$REPO/bin/cc-venue"
  [ -s "$C/brief-a4.txt" ] || { echo "the fire was lost when the resolver failed"; false; }
  [ "$(dodline a4)" = "$control" ] || { echo "failing: got=$(dodline a4) control=$control"; false; }
}

@test "a row with NO dodRef still briefs 'none' — the resolver never empties the clause" {
  mk_repo "$C/repos/proj"
  items '[{"id":"a5","project":"proj","status":"open","title":"t"}]'

  run_once "$DISP"
  [ "$(dodline a5)" = "none" ] || { echo "got: $(dodline a5)"; false; }
  run_once "$PRISTINE"
  [ "$(dodline a5)" = "none" ] || { echo "control got: $(dodline a5)"; false; }
}
