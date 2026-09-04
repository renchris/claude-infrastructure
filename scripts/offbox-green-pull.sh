#!/bin/bash
# offbox-green-pull.sh — bring the off-box hermetic verdict ONTO the box, into a store of its own.
#
#   offbox-green-pull.sh [--limit N] [--dry-run] [--quiet]
#   offbox-green-pull.sh status
#   offbox-green-pull.sh --selftest
#
# WHY A PULLER AT ALL. `.github/workflows/hermetic.yml` runs on GitHub and cannot write to this
# machine. A verdict nobody transports is a verdict nobody enforces — the exact shape this repo has
# paid for eight times over (memory: conclusion-must-reach-the-enforcing-store; eight correct
# analyses landed and changed nothing). So the last mile is a pull, run from `deploy-live.sh` at the
# top of every evaluation, and it is the whole reason this producer is real rather than advisory.
#
# ── IT WRITES TO offbox/, NEVER TO stamps/ — THE LOAD-BEARING DECISION ───────────────────────────
# THE DECISION STANDS; THE CENSUS UNDER IT WAS WRONG, AND IT WAS WRONG IN A WAY WORTH KEEPING.
# What still holds the decision up needs only ONE consumer: `deploy-live.sh`'s is_green()/is_red()
# read `.verdict` and nothing else, and `tests/deploy-live.bats:33` proves a two-field
# `{"verdict":"green","tree":…}` stamp is accepted and deployed. A subset green in `stamps/` would
# therefore become a T1 deploy target with no code change and nothing to review. That is sufficient,
# and it is why the separate directory and `deploy-live.sh`'s T1H tier are the right shape.
#
# What was NOT true is the sentence this block used to open with — "Measured before this was written:
# NO consumer of `~/.claude/autonomy/postland/stamps/` reads any field but `.verdict`
# (deploy-live.sh:172-181), `.commit` and file mtime; there is NO producer attribution field anywhere
# in the record; and although the record carries `suites`, NOTHING checks it." Re-measured
# 2026-09-04 (recycle #297), clause by clause:
#   · FALSE — `scripts/cycle-time-census.sh:112-121` reads `ts`, `run_s`, `suites` AND `env.cc`.
#   · FALSE — `env.cc` IS the producer-attribution field. `cycle-time-census.sh:136-137` partitions
#     the store on it (cc=="unknown" ⇒ the launchd lane; anything else ⇒ session-invoked) and its
#     whole verdict is computed over the launchd arm alone. Live: 415/142/0 of 557 records.
#   · TRUE, but only as stated: `suites` is READ by that one consumer and CHECKED by none. Read is
#     not checked. (48 of 557 records do not carry it at all; `int(d.get('suites') or 0)` reads 0.)
#   · `.commit` is named here as a field consumers read. NOTHING reads it: the only occurrence in
#     the tree is write_stamp()'s own emit line, postland-verify.sh:2217.
#
# HOW A CAREFUL CENSUS MISSED FIVE OF SEVEN CONSUMERS, which is the transferable part: it was keyed
# on the store's PATH. A path is spelled ONCE, at the assignment, and every read after it is a
# VARIABLE. `git grep -l postland/stamps -- bin scripts hooks` returns 3 files; the assignment-keyed
# census returns 7; the overlap is 2 — and the five it cannot see include every consumer that reads
# a FIELD, this store's own producer, and the one consumer that refutes the claim above.
# Census a store's consumers by the variable that RESOLVES it, never by its path.
#
# ── ONLY GREEN IS EVER WRITTEN *HERE* — AND "NOT GREEN" IS NO LONGER WRITTEN NOWHERE ─────────────
# A subset that cannot see the machine-coupled suites can acquit what it ran and nothing else. It has
# no standing to convict, so a non-green off-box run still writes NOTHING into `offbox/` — it does
# not produce a `red`, and no consumer can ever read one there. The workflow's binary conclusion is
# the same rule stated on the other side of the wire. That half is unchanged and is load-bearing.
#
# WHAT CHANGED, AND WHY (cc-backlog `01ab05685857`, 2026-09-04). The rule above was written as "may
# acquit, may not convict" and IMPLEMENTED as "on a non-green, do nothing at all" — a `*) : ;;` arm
# with no store behind it. Those are different rules, and the gap between them is the whole of the
# row this change closes. Measured on trunk `11f50d3408f0` the same day, workflow run 431:
#
#     {"verdict":"red","suites":537,"expected":537,"green":527,"red":9,"nonverdict":1,
#      "unreported":0,"run_s":6475,"failing":[…nine suites…]}
#
# A COMPLETE re-proof of trunk — 537 of 537 suites, zero unreported — finding nine suites red, and
# NOTHING on this box could learn it. The run's own conclusion is `success` (the fold reports and
# never convicts, deliberately); the `verdict` job is `skipped`; the puller wrote nothing. Meanwhile
# `nightly-regression.sh`'s starvation page printed `off-box acquittal: none — nothing anywhere has
# proven this span` over a span that HAD been proven, four hours earlier, and found red by name.
# The row was filed as "postland-verify is INERT … this is how red suites went unnoticed"; the
# on-box verifier's starvation is the famous half, and this is the half nobody was looking at — the
# lane that is NOT starving, reporting completely, into a store with no room for the answer.
#
# So: a non-green now writes a record into `offbox/notgreen/`, a SIBLING directory, and the
# not-convicting property is preserved STRUCTURALLY rather than by silence. Every consumer of the
# acquittal store is path-keyed on `offbox/<tree>.json` — `deploy-live.sh:1746` and
# `nightly-regression.sh:449` are the only two, verified by census — so a record one directory down
# is unreachable to all of them and cannot become a deploy input by accident. It carries
# `verdict:"not-green"`, a token no green predicate matches, and the same `scope:"offbox-hermetic"`
# two-field discipline the acquittal record uses, so a bare file drop is not a claim here either.
# REPORTING IS NOT CONVICTING: the deploy lane's behaviour is byte-identical, and the only thing
# that changes is that the nightly can now say WHICH of three states the span is in.
#
# A NOT-GREEN TREE IS STILL RE-QUERIED EVERY TICK, and that is deliberate. Only `offbox/<tree>.json`
# short-circuits the scan; the notgreen record never does. A run that is re-run and goes green must
# still be able to acquit its tree — the property the `case` arm below already documents — and
# suppressing the query to save an API call would silently trade it away. The cost is unchanged from
# before this block existed, when a non-green tree was re-queried every tick and simply forgotten.
#
# ── FAIL-OPEN, ALWAYS ────────────────────────────────────────────────────────────────────────────
# Every failure mode — no `gh`, no network, no auth, a locked keychain under launchd, a rate limit,
# an unparseable response — exits 0 having written nothing. This runs inside the 144x/day deploy lane,
# where the ONLY thing worse than missing an acquittal is turning a network hiccup into a deploy
# refusal. The lane's behaviour without this script is exactly today's behaviour, which is the
# definition of a safe degradation for an ADDITIVE producer (memory: addon-failure-exceeds-its-blast-radius).
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
REPO_DIR="${CC_OFFBOX_REPO:-$(cd "$(dirname "$SELF")/.." && pwd)}"
POSTLAND_DIR="${CC_POSTLAND_DIR:-$HOME/.claude/autonomy/postland}"
OFFBOX_DIR="${CC_OFFBOX_STAMPS:-$POSTLAND_DIR/offbox}"
# A SUBDIRECTORY, never a suffix in the same directory. `offbox/<tree>.notgreen.json` would sit in
# the same glob as the acquittals, and the one consumer that enumerates rather than path-resolves
# (cmd_status's `find`) would have counted them as greens — which is how a "reporting" store becomes
# an "acquitting" one without anybody editing a predicate.
NOTGREEN_DIR="${CC_OFFBOX_NOTGREEN:-$OFFBOX_DIR/notgreen}"
GH_BIN="${CC_OFFBOX_GH:-gh}"
JOB_NAME="${CC_OFFBOX_JOB:-verdict}"
# The ref to walk. `origin/main` is the only ref the deploy lane can ever deploy FROM, so it is the
# only one that matters in production — but the seam exists because the alternative is a script whose
# single most important path (does a real green actually make it into the store?) can be exercised
# for the first time only after it has landed. That is the bootstrap circle this repo has paid for
# elsewhere (memory: deployed-layer-bootstrap-circle), and one variable breaks it.
REF="${CC_OFFBOX_REF:-origin/main}"
LIMIT="${CC_OFFBOX_PULL_LIMIT:-40}"
# Two bounds, because one does not cover the other: CALL_BOUND_S caps a single hung API call, and
# TOTAL_BOUND_S caps the loop that makes many of them. A per-call bound multiplied across a loop is
# not a bound (memory: bounding-external-calls).
CALL_BOUND_S="${CC_OFFBOX_CALL_BOUND_S:-10}"
TOTAL_BOUND_S="${CC_OFFBOX_TOTAL_BOUND_S:-45}"
DRY=0; QUIET=0

say() { [ "$QUIET" -eq 1 ] || printf 'offbox-pull: %s\n' "$1"; }
usage() { sed -n '2,/^set -uo/p' "$SELF" | sed 's/^# \{0,1\}//; /^set -uo/d'; }

# Fail-open exit. Named so every early return reads as a deliberate policy, not an oversight.
bail_open() { say "$1 — nothing pulled (the lane proceeds exactly as it would without this script)"; exit 0; }

resolve_timeout() {
  local c
  for c in timeout gtimeout; do command -v "$c" >/dev/null 2>&1 && { printf '%s\n' "$c"; return 0; }; done
  return 1
}

g() { git -C "$REPO_DIR" "$@"; }

# owner/repo from the origin URL. Both spellings, because a box may use either.
nwo() {
  local url; url="$(g remote get-url origin 2>/dev/null)" || return 1
  case "$url" in
    *github.com/*)  printf '%s\n' "${url#*github.com/}" ;;
    *github.com:*)  printf '%s\n' "${url#*github.com:}" ;;
    *) return 1 ;;
  esac | sed 's/\.git$//'
}

# The verdict for ONE commit: prints `success` / `failure` / `pending` / nothing.
# Reads the check-run whose name is $JOB_NAME. A run that is still in flight is `pending` and is
# deliberately NOT cached — the next tick asks again.
check_conclusion() {
  local sha="$1" nwo="$2" tmo="$3" out
  out="$("$tmo" -k 2 "$CALL_BOUND_S" "$GH_BIN" api \
        "repos/$nwo/commits/$sha/check-runs?per_page=100" \
        --jq ".check_runs[] | select(.name == \"$JOB_NAME\") | .status + \":\" + (.conclusion // \"none\")" \
        2>/dev/null)" || return 1
  [ -n "$out" ] || return 1
  # Newest first is not guaranteed; a success anywhere in the list is the answer we want, since a
  # re-run that goes green is still a green for that tree.
  case "$out" in
    *completed:success*) printf 'success\n' ;;
    *completed:*)
      # NOT-GREEN, and WHICH not-green is the entire diagnostic value, so it is carried out of here
      # rather than collapsed to one word as it was. `skipped` is the fold saying the partition was
      # not clean — the common, informative case, since the `verdict` job's own
      # `if: needs.fold.outputs.verdict == 'green'` simply did not fire. `failure`/`cancelled`/
      # `timed_out` say the publisher itself broke and the tree was never judged at all. One is a
      # code problem and the other is a lane problem, they take opposite repairs, and the old
      # `failure` token could not tell them apart.
      # Sanitised to the GitHub conclusion alphabet before it reaches a JSON record: this string is
      # remote input, and it is about to be interpolated into a file a later reader parses.
      local c
      c="$(printf '%s\n' "$out" | sed -n 's/^completed:\(.*\)$/\1/p' | head -1 | tr -cd 'a-z_' | cut -c1-32)"
      printf 'notgreen:%s\n' "${c:-unknown}" ;;
    *)                   printf 'pending\n' ;;
  esac
}

write_stamp() {
  local tree="$1" sha="$2" nwo="$3"
  mkdir -p "$OFFBOX_DIR" 2>/dev/null || return 1
  # Attribution is present from the first record, unlike the on-box store which has none and cannot
  # tell one producer from another. `scope` is the field that stops this ever being mistaken for a
  # full-corpus claim by a future reader who only greps for "verdict".
  local tmp="$OFFBOX_DIR/.$tree.$$.tmp"
  printf '{"tree":"%s","commit":"%s","verdict":"green","scope":"offbox-hermetic","producer":"github-actions","workflow":"hermetic","job":"%s","repo":"%s","ts":"%s"}\n' \
    "$tree" "$sha" "$JOB_NAME" "$nwo" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$tmp" 2>/dev/null || return 1
  # temp+rename, so a reader can never see a half-written record. The on-box store writes with a
  # bare `>` truncate; this one does not inherit that.
  mv -f "$tmp" "$OFFBOX_DIR/$tree.json" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

# The REPORTING record. Everything about it is chosen so that no existing consumer can read it as a
# claim about deployability, and so that a reader who finds it can tell what it is without knowing
# this file: a directory none of them resolve, a `verdict` token none of their predicates match, and
# the same both-fields-or-neither discipline the acquittal carries (`tests/deploy-live.bats`'s
# "a bare file drop under offbox/ is NOT an acquittal" pins that rule on the green side; the
# starvation reader applies it here too, so a stray file cannot mint a not-green either).
write_notgreen() {
  local tree="$1" sha="$2" nwo="$3" conclusion="$4"
  mkdir -p "$NOTGREEN_DIR" 2>/dev/null || return 1
  local tmp="$NOTGREEN_DIR/.$tree.$$.tmp"
  printf '{"tree":"%s","commit":"%s","verdict":"not-green","scope":"offbox-hermetic","conclusion":"%s","producer":"github-actions","workflow":"hermetic","job":"%s","repo":"%s","ts":"%s"}\n' \
    "$tree" "$sha" "$conclusion" "$JOB_NAME" "$nwo" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$tmp" 2>/dev/null || return 1
  mv -f "$tmp" "$NOTGREEN_DIR/$tree.json" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

cmd_pull() {
  local tmo; tmo="$(resolve_timeout)" || bail_open "no timeout(1) on PATH"
  command -v "$GH_BIN" >/dev/null 2>&1 || bail_open "no '$GH_BIN' on PATH"
  local NWO; NWO="$(nwo)" || bail_open "origin is not a github.com remote"

  g fetch -q origin "${REF#origin/}" 2>/dev/null || true

  local deadline=$(( $(date +%s) + TOTAL_BOUND_S ))
  local n_new=0 n_seen=0 n_pending=0 n_notgreen=0 sha tree verdict

  while IFS=' ' read -r sha tree; do
    [ -n "$sha" ] || continue
    [ "$(date +%s)" -lt "$deadline" ] || { say "total bound ${TOTAL_BOUND_S}s reached after $n_seen commit(s)"; break; }
    n_seen=$((n_seen + 1))
    # Already have it: the store is keyed by TREE, so a rebase that preserves the tree keeps its
    # acquittal — the same keying choice the on-box store documents, and the reason a Revert can
    # inherit one there. Here it is safe for the same reason it is there: the claim is about a tree.
    [ -f "$OFFBOX_DIR/$tree.json" ] && continue

    verdict="$(check_conclusion "$sha" "$NWO" "$tmo")" || continue
    case "$verdict" in
      success)
        if [ "$DRY" -eq 1 ]; then
          say "WOULD write offbox green for ${sha:0:12} (tree ${tree:0:12})"
        elif write_stamp "$tree" "$sha" "$NWO"; then
          say "offbox GREEN ${sha:0:12} (tree ${tree:0:12})"
        fi
        n_new=$((n_new + 1))
        ;;
      notgreen:*)
        # NOT an acquittal and NOT a conviction — a record that the lane RAN this tree and did not
        # certify it. It goes to a store no deploy consumer resolves (see NOTGREEN_DIR), so the
        # "may acquit, may not convict" contract is now enforced by where the record lives rather
        # than by there being no record at all. Written once per tree; the tree itself keeps being
        # re-queried above, so a later re-run that goes green still acquits it.
        if [ -f "$NOTGREEN_DIR/$tree.json" ]; then
          :
        elif [ "$DRY" -eq 1 ]; then
          say "WOULD record offbox not-green for ${sha:0:12} (tree ${tree:0:12}) — ${verdict#notgreen:}"
          n_notgreen=$((n_notgreen + 1))
        elif write_notgreen "$tree" "$sha" "$NWO" "${verdict#notgreen:}"; then
          say "offbox NOT-GREEN ${sha:0:12} (tree ${tree:0:12}) — ${verdict#notgreen:}"
          n_notgreen=$((n_notgreen + 1))
        fi
        ;;
      pending) n_pending=$((n_pending + 1)) ;;
      *) : ;;   # unreachable today; still writes NOTHING rather than guessing a verdict.
    esac
  done <<EOF
$(g log --format='%H %T' -n "$LIMIT" "$REF" 2>/dev/null)
EOF

  say "scanned $n_seen commit(s): $n_new new green(s), $n_notgreen new not-green(s), $n_pending still running"
  return 0
}

cmd_status() {
  local n=0 ng=0
  # `-maxdepth 1` IS THE CORRECTNESS CLAUSE, not a tidy-up. Without it this walk descends into
  # notgreen/ and reports records that are explicitly NOT acquittals under the heading "greens held"
  # — the store's own status command laundering the weaker claim into the stronger one, which is the
  # single failure this whole separation exists to prevent.
  [ -d "$OFFBOX_DIR" ] && n="$(find "$OFFBOX_DIR" -maxdepth 1 -name '*.json' -type f 2>/dev/null | grep -c . || true)"
  [ -d "$NOTGREEN_DIR" ] && ng="$(find "$NOTGREEN_DIR" -maxdepth 1 -name '*.json' -type f 2>/dev/null | grep -c . || true)"
  printf 'offbox store:   %s\n' "$OFFBOX_DIR"
  printf 'greens held:    %s\n' "$n"
  printf 'not-greens:     %s   (%s — reported, never read by the deploy lane)\n' "$ng" "$NOTGREEN_DIR"
  if [ "$n" -gt 0 ]; then
    printf 'newest green:   %s\n' "$(find "$OFFBOX_DIR" -maxdepth 1 -name '*.json' -type f -exec ls -t {} + 2>/dev/null | head -1)"
  fi
}

# ── SELFTEST ─────────────────────────────────────────────────────────────────────────────────────
st_fail=0
chk() { if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s — wanted [%s] got [%s]\n' "$1" "$2" "$3" >&2; st_fail=1; fi; }

cmd_selftest() {
  ST_TMP="$(mktemp -d)" || { printf 'selftest: mktemp failed\n' >&2; return 1; }
  trap 'rm -rf "${ST_TMP:-}"' EXIT
  local tmp="$ST_TMP"

  # A fixture repo with a real origin URL and two commits, plus a stub `gh` whose answer we control.
  mkdir -p "$tmp/repo" "$tmp/bin" "$tmp/store"
  ( cd "$tmp/repo" || exit 1
    git init -q .
    git config user.email t@e.com; git config user.name t
    git remote add origin https://github.com/acme/widgets.git
    echo one > f; git add f; git commit -qm one
    git branch -f main >/dev/null 2>&1 || true
    git update-ref refs/remotes/origin/main HEAD
  ) >/dev/null 2>&1

  mk_gh() { printf '#!/bin/bash\nprintf "%%s\\n" "%s"\n' "$1" > "$tmp/bin/gh"; chmod +x "$tmp/bin/gh"; }
  pull() { CC_OFFBOX_REPO="$tmp/repo" CC_OFFBOX_STAMPS="$tmp/store" CC_OFFBOX_GH="$tmp/bin/gh" \
           PATH="$tmp/bin:$PATH" bash "$SELF" "$@"; }
  # `-maxdepth 1`, for the reason cmd_status carries it: this counter is the oracle for every
  # "writes NOTHING" control below, and a recursive walk would count a notgreen record as a green
  # and turn each of those controls from an assertion into a tautology-in-the-wrong-direction.
  n_stamps()   { find "$tmp/store" -maxdepth 1 -name '*.json' -type f 2>/dev/null | grep -c . || true; }
  n_notgreen() { find "$tmp/store/notgreen" -maxdepth 1 -name '*.json' -type f 2>/dev/null | grep -c . || true; }
  reset_store() { rm -rf "$tmp/store"; mkdir -p "$tmp/store"; }

  # P1 a completed:success writes exactly one green.
  mk_gh 'completed:success'
  pull --quiet >/dev/null 2>&1
  chk "P1 a success writes one offbox green" 1 "$(n_stamps)"

  # P1b the record carries its SCOPE and PRODUCER — the two fields that stop a future reader
  # mistaking it for a full-corpus claim.
  local rec; rec="$(cat "$tmp"/store/*.json 2>/dev/null)"
  case "$rec" in *'"scope":"offbox-hermetic"'*) printf 'ok   P1b the record names its scope\n' ;;
                 *) printf 'FAIL P1b scope missing: %s\n' "$rec" >&2; st_fail=1 ;; esac
  case "$rec" in *'"producer":"github-actions"'*) printf 'ok   P1c the record names its producer\n' ;;
                 *) printf 'FAIL P1c producer missing: %s\n' "$rec" >&2; st_fail=1 ;; esac

  # P2 A NON-GREEN WRITES NOTHING INTO THE ACQUITTAL STORE. The control for the whole "may acquit,
  # may not convict" contract — without it the puller could quietly mint a `red` this store has no
  # vocabulary for. The claim under test is UNCHANGED by the notgreen store below; what changed is
  # that "writes nothing anywhere" is no longer how it is satisfied, so the assertion now names the
  # store it is about instead of counting every file the script can produce.
  reset_store
  mk_gh 'completed:failure'
  pull --quiet >/dev/null 2>&1
  chk "P2 a non-green writes NOTHING into the acquittal store" 0 "$(n_stamps)"

  # P2b …AND IT IS NO LONGER SILENT. The row this closes (cc-backlog 01ab05685857) is a complete
  # off-box re-proof of trunk that nothing on the box could read; the old `*) : ;;` arm is what made
  # it unreadable, and an arm that does nothing leaves no trace to assert on. This is the positive
  # control for the whole change: without a record here, the nightly cannot tell "nothing has proven
  # this span" from "something proved it and the answer was not green".
  chk "P2b a non-green IS recorded in the notgreen store" 1 "$(n_notgreen)"

  local ngrec; ngrec="$(cat "$tmp"/store/notgreen/*.json 2>/dev/null)"
  case "$ngrec" in *'"verdict":"not-green"'*) printf 'ok   P2c the record says not-green\n' ;;
                   *) printf 'FAIL P2c verdict token missing: %s\n' "$ngrec" >&2; st_fail=1 ;; esac
  # The scope field is what stops a future reader treating this as a full-corpus judgment, exactly
  # as on the green side. Both fields or neither — the starvation reader demands both.
  case "$ngrec" in *'"scope":"offbox-hermetic"'*) printf 'ok   P2d the record names its scope\n' ;;
                   *) printf 'FAIL P2d scope missing: %s\n' "$ngrec" >&2; st_fail=1 ;; esac
  # P2e THE DISCRIMINATOR SURVIVES THE WIRE. `skipped` (the fold was not clean — a code problem) and
  # `failure` (the publisher broke — a lane problem) take opposite repairs, and the pre-change code
  # collapsed both to one token. Asserting the word here is what keeps that bit from being dropped
  # again by a future simplification of check_conclusion.
  case "$ngrec" in *'"conclusion":"failure"'*) printf 'ok   P2e the record carries WHICH not-green\n' ;;
                   *) printf 'FAIL P2e conclusion missing/wrong: %s\n' "$ngrec" >&2; st_fail=1 ;; esac

  # P2f ANTI-LAUNDERING, STRUCTURAL. Every consumer of the acquittal store is path-keyed on
  # `offbox/<tree>.json` (deploy-live.sh:1746, nightly-regression.sh:449). So the property that
  # matters is not "the predicate rejects it" — it is that the record is NOT AT THAT PATH and no
  # predicate is ever asked. Asserted by name rather than by count, so a future record whose tree
  # happens to differ cannot pass this by accident.
  local ngtree; ngtree="$(basename "$(find "$tmp/store/notgreen" -name '*.json' -type f | head -1)")"
  if [ -n "$ngtree" ] && [ ! -e "$tmp/store/$ngtree" ]; then
    printf 'ok   P2f the record is NOT at the acquittal path the deploy lane resolves\n'
  else
    printf 'FAIL P2f a not-green record is readable as an acquittal (%s)\n' "$ngtree" >&2; st_fail=1
  fi

  # P2g A NOT-GREEN TREE IS STILL RE-QUERIED — the property the skip guard could silently trade away
  # for one saved API call. P7 proves a GREEN tree short-circuits; this proves a not-green one does
  # not, so a re-run that goes green can still acquit the tree it already failed on.
  mk_gh 'completed:success'
  pull --quiet >/dev/null 2>&1
  chk "P2g a not-green tree re-queries, and a later green acquits it" 1 "$(n_stamps)"

  # P3 an in-flight run writes nothing and is not cached — in EITHER store. Pending is not a
  # verdict, so it must not leave a not-green record behind that a re-query would then skip.
  reset_store
  mk_gh 'in_progress:none'
  pull --quiet >/dev/null 2>&1
  chk "P3 a pending run writes nothing" 0 "$(n_stamps)"
  chk "P3b a pending run records no not-green either" 0 "$(n_notgreen)"

  # P4 FAIL-OPEN: a `gh` that does not exist exits 0 and writes nothing.
  local rc
  CC_OFFBOX_REPO="$tmp/repo" CC_OFFBOX_STAMPS="$tmp/store" CC_OFFBOX_GH="$tmp/bin/nope" \
    bash "$SELF" --quiet >/dev/null 2>&1; rc=$?
  chk "P4 a missing gh exits 0 (fail-open)" 0 "$rc"
  chk "P4b and writes nothing" 0 "$(n_stamps)"

  # P5 FAIL-OPEN: a `gh` that errors exits 0 and writes nothing.
  printf '#!/bin/bash\nexit 4\n' > "$tmp/bin/gh"; chmod +x "$tmp/bin/gh"
  pull --quiet >/dev/null 2>&1; rc=$?
  chk "P5 an erroring gh exits 0" 0 "$rc"
  chk "P5b and writes nothing" 0 "$(n_stamps)"

  # P6 a non-github remote is fail-open, not a crash.
  ( cd "$tmp/repo" && git remote set-url origin /some/local/path ) >/dev/null 2>&1
  mk_gh 'completed:success'
  pull --quiet >/dev/null 2>&1; rc=$?
  chk "P6 a non-github origin exits 0" 0 "$rc"
  chk "P6b and writes nothing" 0 "$(n_stamps)"
  ( cd "$tmp/repo" && git remote set-url origin https://github.com/acme/widgets.git ) >/dev/null 2>&1

  # P7 IDEMPOTENT — a second pull over an already-stamped tree adds nothing and re-queries nothing.
  mk_gh 'completed:success'
  pull --quiet >/dev/null 2>&1
  local first; first="$(n_stamps)"
  printf '#!/bin/bash\nexit 9\n' > "$tmp/bin/gh"; chmod +x "$tmp/bin/gh"   # any query now fails
  pull --quiet >/dev/null 2>&1
  chk "P7 a stamped tree is not re-queried" "$first" "$(n_stamps)"

  # P8 THE STATUS COMMAND DOES NOT LAUNDER. `status` is the one reader in this file that ENUMERATES
  # the store instead of resolving a path, so it is the one place a not-green can be counted as a
  # green — and it would be, silently, under the recursive walk this command used to do. The store
  # here holds exactly one of each, so a `greens held: 2` is the laundering and nothing else.
  reset_store
  mk_gh 'completed:success'; pull --quiet >/dev/null 2>&1          # one real acquittal
  mkdir -p "$tmp/store/notgreen"
  printf '{"verdict":"not-green","scope":"offbox-hermetic","tree":"deadbeef"}\n' \
    > "$tmp/store/notgreen/deadbeef.json"                          # one not-green beside it
  local stat_out
  stat_out="$(CC_OFFBOX_REPO="$tmp/repo" CC_OFFBOX_STAMPS="$tmp/store" CC_OFFBOX_GH="$tmp/bin/gh" \
              bash "$SELF" status 2>/dev/null)"
  chk "P8 status counts ONE green, not the not-green beside it" \
      1 "$(printf '%s\n' "$stat_out" | sed -n 's/^greens held: *\([0-9]*\).*/\1/p')"
  chk "P8b status reports the not-green separately" \
      1 "$(printf '%s\n' "$stat_out" | sed -n 's/^not-greens: *\([0-9]*\).*/\1/p')"

  [ "$st_fail" -eq 0 ] || { printf '\noffbox-green-pull --selftest: FAILED\n' >&2; return 1; }
  printf '\noffbox-green-pull --selftest: all controls green\n'
  return 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --limit)    LIMIT="${2:?--limit needs a number}"; shift ;;
    --dry-run)  DRY=1 ;;
    --quiet)    QUIET=1 ;;
    status)     cmd_status; exit 0 ;;
    --selftest) cmd_selftest; exit $? ;;
    -h|--help)  usage; exit 0 ;;
    *)          printf 'offbox-pull: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

cmd_pull
