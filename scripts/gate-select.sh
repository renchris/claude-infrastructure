#!/bin/bash
# gate-select.sh — changed-file → test-suite selector for the landing gate.
#
#   gate-select.sh [--explain] [--direct] <base..head> [<base2..head2> ...]
#     stdout: `FULL` (run everything) | newline list of tests/*.bats | EMPTY (provably inert)
#     exit:   always 0 on completion.
#   gate-select.sh lint      — anti-rot guard, see below. exit 0 clean / 1 + orphan list.
#
# THE LAW: any doubt fails CLOSED. An unrecognised status, an unmapped file, a missing
# python3, an unparseable range, an internal error — every one of them prints FULL. A
# false FULL costs wall-clock; a false narrow selection ships an untested regression.
#
#   --explain  one stderr line per decision (`tests/X.bats <- literal:scripts/foo.sh`).
#   --direct   print only the DIRECT clauses (literal-path + naming-convention) — the land
#              gate uses this to tell a real RED from a flake in a merely-adjacent suite.
#              A DIRECT edge needs evidence in the suite's EXECUTABLE text; a path a suite only
#              CITES in a comment selects it but never makes it un-exonerable (see `cited_only`).
#
# MULTI-RANGE: the changed-file sets of every range are UNIONED before the rules run, so a
# CAS-stale re-gate can pass the sibling trunk delta as a second range and see the novelty
# of the COMPOSED tree. A path that is D/R in any range fails the whole run closed — EXCEPT a
# prose path, which has a removal rung of its own (see `prose removal` in the selector).
#
# LINT: asserts every tests/*.bats is reachable from >=1 non-test tracked file through some
# clause. An unreachable suite is one the selector can NEVER pick — it would silently stop
# running. ship-land falls back to FULL whenever this lint fails.
#
# Map is rebuilt per invocation (git ls-files pass, ~2s) — never cached, so it cannot rot.
# bash 3.2-safe (no declare -A / mapfile, no empty-array expansion under set -u); the
# selection itself runs in the python heredoc.
set -uo pipefail

EXPLAIN=0
DIRECT=0
MODE=select
RANGES=()

usage() { sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; }

fail_closed() {  # $1=reason — the single exit used by every uncertainty in this wrapper
  [ "$EXPLAIN" -eq 1 ] && printf 'FULL <- %s\n' "$1" >&2
  printf 'FULL\n'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --explain) EXPLAIN=1 ;;
    --direct)  DIRECT=1 ;;
    -h|--help) usage; exit 0 ;;
    lint)      MODE=lint ;;
    --)        shift; while [ $# -gt 0 ]; do RANGES+=("$1"); shift; done; break ;;
    -*)        fail_closed "unknown-option:$1" ;;
    *)         RANGES+=("$1") ;;
  esac
  shift
done

command -v git >/dev/null 2>&1 || fail_closed "no-git"
command -v python3 >/dev/null 2>&1 || fail_closed "no-python3"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$ROOT" ] || fail_closed "not-a-git-checkout"

if [ "$MODE" = select ]; then
  [ "${#RANGES[@]}" -gt 0 ] || fail_closed "no-range"
  for r in "${RANGES[@]}"; do
    case "$r" in *..*) ;; *) fail_closed "bad-range:$r" ;; esac
  done
fi

# One heredoc, two call sites: `lint` needs its exit code to PROPAGATE (a failed lint is how
# ship-land learns to fall back to FULL), while `select` captures stdout whole — a python
# crash mid-stream must never leak a PARTIAL suite list, which would read as a narrow
# selection = silently open.
run_selector() {  # $1=mode; rest=ranges
  local mode="$1"
  shift
  GS_ROOT="$ROOT" GS_MODE="$mode" GS_EXPLAIN="$EXPLAIN" GS_DIRECT="$DIRECT" python3 - "$@" <<'PY'
import os, re, subprocess, sys

ROOT = os.environ["GS_ROOT"]
MODE = os.environ.get("GS_MODE", "select")
RANGES = sys.argv[1:]
EXPLAIN = os.environ.get("GS_EXPLAIN") == "1"
DIRECT = os.environ.get("GS_DIRECT") == "1"

# Top-level dirs a repo-relative path can start with, for the closure edge regex.
PATH_RE = re.compile(r'(?:scripts|bin|hooks|lib|commands|docs|templates|skills|agents'
                     r'|settings-templates|launchd|usage|evolve-fixtures)/[A-Za-z0-9._/-]+')
# Rule 2 — shared surfaces with no single owning suite.
FULL_FILES = ("install.sh", "sync.sh", "accounts.json", "statusline.sh", "statusline-debug.sh")
# Clause (f) — what install.sh wires; a pre-existing member changing re-checks the wiring.
INSTALL_RE = re.compile(r'^(hooks/[^/]+\.sh|hooks/lib/[^/]+\.sh|commands/[^/]+\.md'
                        r'|scripts/[^/]+\.sh|scripts/limit-recover/.+|skills/.+'
                        r'|bin/cc-[^/]+|launchd/[^/]+\.plist)$')
INSTALL_SUITE = "tests/install-wire-hooks.bats"
# Clause (g) — the dead-assertion ratchet. A changed suite selects only ITSELF, so a
# reintroduced dead assertion would land green: the edited file's own tests still pass
# (that is precisely the failure mode — the assertion is discarded, not failed). Only the
# liveness analyzer sees it, so any .bats edit must also run its ratchet.
LIVENESS_SUITE = "tests/bats-assert-liveness.bats"
# Clause (e) — stems measured to match half the corpus as ordinary English/shell words.
STOPLIST = ("run", "common", "main", "test", "commit")
SCRIPTY = (".sh", ".bash", ".zsh", ".py")
# Clause (c) — how far the closure walk composes, and through what. BOTH bounds exist because
# `refs` is a MENTION graph, not a dependency graph, and clause (c) reads a chain of mentions as
# "this suite exercises code that depends on that path". That inference is only sound while every
# edge means USES. An index node — a doc, a manifest, a repo-wide lint or regression runner — emits
# edges meaning COVERS, the inverse relation, so composing through one yields a non-dependency.
# Measured on this repo before these bounds: docs/ alone carried 59% of all edges at mean
# out-degree 9.3 (real code: 0.8-2.0), and the median changed file dragged in 48 suites via
# clause (c) — 283 of 721 non-test files pulled >=20. Chains like
#   suite -> ship-land.sh -> host-suites.manifest -> nightly-regression.sh -> never-stuck-gate.sh
#           -> hooks/session-continue.sh
# are five hops through four inventories and describe no dependency at all. Median fan-in with
# both bounds: 4 suites (>=20: 37 of 721); the map lint stays at 0 orphans either way.
#
# DEPTH is 3 because 3 is exactly what this selector's contract asks for: the suite's own fixpoint
# proof is a 3-hop chain that a depth-2 walk drops (tests/gate-select.bats). Nothing documented
# needs hop 4, and an unbounded walk over a mention graph this dense reaches most of the repo from
# most roots. The bound is also what keeps this fix SYSTEMIC rather than a hub blacklist: a new
# inventory file added later can still contribute its own refs, but it can no longer cascade.
# An out-degree cap was measured and REJECTED — the distribution is a smooth power-law tail
# (p90=9, p95=16, max=63) with no gap to place a threshold in, so any cap would be arbitrary and
# would silently reclassify ordinary code as the repo grows.
CLOSURE_DEPTH = 3

def git(*args):
    return subprocess.run(("git", "-C", ROOT) + args, stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL, check=True).stdout.decode("utf-8", "replace")

def note(sel, reason):
    if EXPLAIN:
        sys.stderr.write("%s <- %s\n" % (sel, reason))

def emit_full(reason):
    note("FULL", reason)
    sys.stdout.write("FULL\n")
    sys.exit(0)

def read_text(path):
    try:
        with open(os.path.join(ROOT, path), "rb") as fh:
            blob = fh.read(1 << 20)
    except (OSError, IOError):
        return ""
    if b"\0" in blob[:8192]:          # binary — no refs to harvest
        return ""
    return blob.decode("utf-8", "replace")

def is_document(path):
    """Non-executable by construction — nothing can depend on it AT RUNTIME.

    The single premise two different rungs below both rest on, named once so they cannot drift
    apart. `is_index` turns it into "never a closure RELAY"; the `unmapped` rung turns it into
    "no clause fired ⇒ INERT, not undecidable". Keyed on the extension, never on a path prefix:
    a prefix list only ever describes the trees that existed when it was written.
    """
    return path.endswith(".md")


def is_index(path):
    """A node whose out-edges mean COVERS, not USES ⇒ reachable, but never a RELAY.

    Markdown is the airtight case and the dominant one: a document cannot execute, so a path it
    names can never be a runtime dependency OF it. Deliberately keyed on the extension rather
    than on `is_prose` (which is a SELECTION rule about docs/ and answers a different question) —
    commands/*.md and skills/**/*.md index just as hard and live outside docs/.
    """
    return is_document(path)


def is_prose(path):
    if path in ("README.md", "CLAUDE.md"):
        return True
    if path.startswith("docs/research/") or path.startswith("docs/plans/"):
        return True
    return path.startswith("docs/") and path.endswith(".md")

def full_trigger(path):
    if path in FULL_FILES:
        return "full-trigger"
    if path.startswith("settings-templates/"):
        return "settings-template"
    # `/lib/` anywhere, not just `^lib/`: hooks/lib/*.sh are sourced helpers with no suite
    # naming them (measured — a `^lib/`-only test misses two thirds of these).
    if path.startswith("lib/") or "/lib/" in path:
        return "shared-lib"
    return None

def lint(tracked, suites, text, closure, naming):
    """Anti-rot: a suite no clause can ever reach is a suite that silently stops running.

    Clause (f) is deliberately EXCLUDED — install-glob only ever yields the install suite,
    so counting it would let that one suite vouch for itself. Cheap clauses go first and a
    resolved suite short-circuits, so the O(files x suites) scans stay rare in practice.
    """
    nontest = [p for p in tracked if not p.startswith("tests/")]
    ntset = set(nontest)
    stems = set(os.path.splitext(os.path.basename(p))[0] for p in nontest)
    named = set()
    for stem in stems:
        named |= naming(stem)
    dirs = sorted(set(os.path.dirname(p) for p in nontest if "/" in os.path.dirname(p)))
    tokens = [re.compile(r'(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])' % re.escape(t))
              for t in sorted(stems) if t not in STOPLIST and len(t) > 2]
    orphans = []
    for suite in suites:
        body = text.get(suite, "")
        if closure[suite] & ntset:                       # (a) refs + (c) transitive closure
            continue
        if suite in named:                               # (b) naming convention
            continue
        if any(p in body for p in nontest):              # (a) raw literal substring
            continue
        if any((d + "/") in body for d in dirs):         # (d) package dir
            continue
        if any(rx.search(body) for rx in tokens):        # (e) basename token
            continue
        orphans.append(suite)
    for suite in orphans:
        sys.stdout.write("%s\n" % suite)
    if orphans:
        sys.stderr.write("gate-select lint: %d suite(s) NOTHING selects — name the file each "
                         "one covers inside it (a comment counts)\n" % len(orphans))
        return 1
    return 0


def main():
    bases = [r.split("...", 1)[0] if "..." in r else r.split("..", 1)[0] for r in RANGES]

    tracked = [p for p in git("ls-files", "-z").split("\0") if p]
    tset = set(tracked)
    suites = sorted(p for p in tracked if p.startswith("tests/") and p.endswith(".bats"))
    text = dict((p, read_text(p)) for p in tracked)

    bin_names = dict((os.path.basename(p), p) for p in tracked if p.startswith("bin/"))
    bin_re = None
    if bin_names:                      # empty alternation would match the empty string everywhere
        bin_re = re.compile(r'(?<![A-Za-z0-9._-])(%s)(?![A-Za-z0-9._-])'
                            % "|".join(re.escape(n) for n in
                                       sorted(bin_names, key=len, reverse=True)))

    def ref_body(path):
        body = text.get(path, "")
        # Comments are load-bearing EVIDENCE in suites (clause a) but noise in source files,
        # where a mentioned path is usually prose, not a dependency.
        if path.endswith(".bats"):
            return body
        if path.endswith(SCRIPTY) or "." not in os.path.basename(path):
            return "\n".join(ln for ln in body.splitlines() if not ln.lstrip().startswith("#"))
        return body

    def refs_of(path):
        body = ref_body(path)
        out = set()
        for hit in PATH_RE.findall(body):
            cand = hit.rstrip("./-")
            if cand in tset and cand != path:
                out.add(cand)
        if bin_re is not None:
            for hit in bin_re.findall(body):
                if bin_names[hit] != path:
                    out.add(bin_names[hit])
        return out

    refs = dict((p, refs_of(p)) for p in tracked)

    # The suite's EXECUTABLE text — same line rule `ref_body` already applies to source files.
    code_text = dict((s, "\n".join(ln for ln in text.get(s, "").splitlines()
                                   if not ln.lstrip().startswith("#"))) for s in suites)

    def stem_word(path):               # clause (e)'s token test, reused as DIRECT corroboration
        stem = os.path.splitext(os.path.basename(path))[0]
        if stem in STOPLIST or len(stem) <= 2:
            return None
        return re.compile(r'(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])' % re.escape(stem))

    def cited_only(path, suite):
        """The suite's ONLY trace of `path` is prose ⇒ a CITATION, not a dependency.

        `ref_body` already draws exactly this line for source files ("a mentioned path is usually
        prose, not a dependency"); .bats kept its comments because they ARE evidence — of coverage,
        which is what the map lint asserts and what makes a suite worth RUNNING. That was never
        evidence of a functional dependency, and conflating the two is what let a citation veto a
        land: a DIRECT edge is the claim "a failure here is caused by your diff", so its evidence
        has to live in the text that actually executes.

        Measured over this corpus (2026-07-30): 90 of 542 clause-(a) edges were comment-only and
        exactly ONE was a real dependency — tests/lead-supervisor.bats, which drives
        scripts/supervisor-e2e.sh through `lead-supervisor.sh --selftest` and therefore never names
        the path in code. The second disjunct is what keeps it: the comment says WHICH file, the
        code shows the suite really exercises something by that name. The rule demotes 80 of 88 and
        loses no functional edge; because it can only ever demote an edge whose ENTIRE evidence is
        non-executable, and retains anything the suite's own code corroborates, it is conservative
        by construction — the fail-closed direction is preserved.

        The motivating case is self-inflicted and was GROWING: the $HOME-fixture remediation writes
        a boilerplate comment naming scripts/test-hermeticity-lint.sh into every suite it fixes, so
        each hermeticity fix MANUFACTURED another false DIRECT edge — 7 suites on 2026-07-26, 20
        four days later, of which 2 have any functional dependency. The better this repo got at
        hermeticity, the more unrelated suites could veto a land on an unrelated flake (the one
        observed: cc-authbrowser's frozen machine-wide CDP ports 9341-9344). Same class as the
        detector that matched its own skill description: text is never evidence.
        """
        body = code_text.get(suite, "")
        if path in body:                       # the path itself is resolvable from executable text
            return False
        rx = stem_word(path)                   # …or the suite names a file it builds at runtime
        return not (rx and rx.search(body))

    def reachable(root):               # BFS so the hop count is meaningful — see CLOSURE_DEPTH
        seen = set()
        frontier, hop = list(refs.get(root, ())), 1
        while frontier:
            nxt = []
            for node in frontier:
                if node in seen:
                    continue
                seen.add(node)         # an index node is still REACHED (a suite may cover it)…
                if is_index(node):     # …it just does not pass the walk along.
                    continue
                nxt.extend(refs.get(node, ()))
            if hop >= CLOSURE_DEPTH:
                break
            frontier, hop = nxt, hop + 1
        return seen

    closure = dict((s, reachable(s)) for s in suites)

    def naming(stem):
        got = set()
        if "tests/%s.bats" % stem in tset:
            got.add("tests/%s.bats" % stem)
        got |= set(s for s in suites if s.startswith("tests/%s-" % stem))
        parts = stem.split("-")        # reverse: longest prefix that owns a suite
        for i in range(len(parts) - 1, 0, -1):
            cand = "tests/%s.bats" % "-".join(parts[:i])
            if cand in tset:
                got.add(cand)
                break
        return got

    def in_base(path):                 # pre-existing in ANY range's base ⇒ already installed
        for base in bases:
            if subprocess.run(("git", "-C", ROOT, "cat-file", "-e", "%s:%s" % (base, path)),
                              stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL).returncode == 0:
                return True
        return False

    if MODE == "lint":
        sys.exit(lint(tracked, suites, text, closure, naming))

    # UNION of every range's changed-file set, deduped on (status, path, src) so a file touched
    # by two ranges is judged once. `-M` asks for rename detection explicitly: git must REPORT
    # an R status for the R-⇒-FULL rule to fire on it. The SRC half of an R/C record is kept, not
    # discarded: the prose-removal rung below has to judge the path that went AWAY, and a rename
    # whose two ends land in different classes (prose ⇄ code) must still fail closed.
    changes, seen = [], set()
    for rng in RANGES:
        raw = git("diff", "--name-status", "-z", "-M", rng).split("\0")
        i = 0
        while i < len(raw):
            status = raw[i]
            i += 1
            if not status:
                continue
            if status[0] in ("R", "C"):        # src \0 dst
                rec = (status, raw[i + 1] if i + 1 < len(raw) else "",
                       raw[i] if i < len(raw) else "")
                i += 2
            else:
                rec = (status, raw[i] if i < len(raw) else "", "")
                i += 1
            if rec not in seen:
                seen.add(rec)
                changes.append(rec)

    picked, direct_picked = set(), set()

    def prose_refs(p):
        """The ONE coupling a prose path has to the corpus: a suite that NAMES it literally.

        Measured over the whole corpus: every suite that touches this repo's own docs tree does
        so through an explicit literal path (`$REPO/docs/activation/.../08-…-activate.sh`,
        `$REPO/docs/templates/desk-boot-brief.md`, …). Not one globs it, and the suites that DO
        enumerate a docs/plans tree (plan-index, validate-plan-structure, find-plan-list-open)
        build a FIXTURE one under $BATS_TEST_TMPDIR, so no real doc path reaches them. That is
        why the prose rung is literal-only, and it is what makes the removal rung below sound.
        `text` is read from the WORKING TREE — the POST-change side — so "still names it" is
        exactly the breakage set: a land that drops the doc AND its references selects nothing,
        while a land that drops the doc and leaves a suite naming it runs that suite.
        """
        return set(s for s in suites if p in text.get(s, ""))

    for status, path, src in changes:
        if not path:
            emit_full("unparseable-diff-record:%s" % status)
        code = status[0]

        # PROSE REMOVAL — the one rung above the blanket D/R fail-closed.
        #
        # WHY THIS IS NOT A WEAKENING, AND WHY IT NOW BUYS PROOF RATHER THAN SPENDING IT: FULL is
        # this selector's "I cannot decide", and in the v2 land lane its consumer INVERTED. It used
        # to mean "run the ~1630-test corpus"; ship-land.sh now reads it as "this selection is
        # untrustworthy ⇒ NO direct-suite smoke" ("no direct-suite smoke this land"), and the
        # stale-gate re-round (`direct = FULL` ⇒ `direct=""`) reads it as "exonerate nothing" —
        # both cited by line number until 2026-07-31, by which point both had drifted ~25 lines.
        # So a docs-only land that renamed or archived one research
        # doc ran ZERO suites and could exonerate nothing — a fail-closed rung that fails OPEN at
        # its consumer (the class of docs/research/land-pipeline-v2-research-2026-07-28). Deciding
        # the removal narrowly runs the suites that can actually break; FULL runs none of them.
        #
        # The blanket rule stays for CODE because a removed script takes its whole clause ladder
        # with it (closure edges, stems, install wiring) and the map cannot describe a path that
        # moved out from under it. Prose has no ladder — only the literal ref above.
        if code in ("D", "R", "C"):
            gone = src if code in ("R", "C") else path
            # BOTH ends must be prose. A rename across the classes (docs/x.md → scripts/x.sh, or
            # back) hands the code end a path whose clauses were never run, which is precisely the
            # `unmapped` fail-closed case; judging it as prose would skip that rung.
            if gone and is_prose(gone) and (code == "D" or is_prose(path)):
                hits, dhits = set(), set()
                for suite in sorted(prose_refs(gone)):
                    note(suite, "prose-removed:%s" % gone)
                    hits.add(suite)
                    if not cited_only(gone, suite):
                        dhits.add(suite)
                if code in ("R", "C"):         # the dst end is an ADD — same rung as A/M prose
                    for suite in sorted(prose_refs(path)):
                        note(suite, "prose-literal:%s" % path)
                        hits.add(suite)
                        if not cited_only(path, suite):
                            dhits.add(suite)
                picked |= hits
                # Prose you are landing is never exonerated — but only where a suite actually READS
                # it. A doc cannot execute, so a suite that merely cites one in a comment cannot
                # break when it moves; it still RUNS, it just may not veto the land on its own flake.
                direct_picked |= dhits
                continue
            if code == "D":
                emit_full("deleted:%s" % path)
            emit_full("%s:%s" % ("renamed" if code == "R" else "copied", path))
        if code not in ("A", "M", "T"):
            emit_full("status-%s:%s" % (status, path))

        trigger = full_trigger(path)
        if trigger:
            emit_full("%s:%s" % (trigger, path))

        # Per-FILE hit sets: "did any clause fire" must be answered for THIS file alone —
        # probing the global set instead makes two files sharing one suite look unmapped.
        hits, dhits = set(), set()

        def take(found, tag, direct=False, _h=hits, _d=dhits, _p=path):
            for suite in sorted(found):
                note(suite, "%s:%s" % (tag, _p))
                _h.add(suite)
                if direct:
                    _d.add(suite)

        if path.startswith("tests/") and path.endswith(".bats"):
            take(set([path]), "suite", direct=True)
            if LIVENESS_SUITE in tset and path != LIVENESS_SUITE:                        # (g)
                take(set([LIVENESS_SUITE]), "assert-liveness")
        elif is_prose(path):           # no suite builds a doc path dynamically — literal or inert
            pr = prose_refs(path)
            take(set(s for s in pr if not cited_only(path, s)), "prose-literal", direct=True)
            take(set(s for s in pr if cited_only(path, s)), "prose-cited")
        else:
            # An ADDED file gets NO special rung: it runs the same clauses as a modified one,
            # and the `unmapped` rung below still fails it closed if nothing maps it. The old
            # `code == "A" ⇒ FULL` fired BEFORE the clauses, so it was "added ⇒ FULL", not the
            # "added-unmapped" its label claimed — and since this fleet's dominant change shape
            # is `bin/cc-foo` + `tests/cc-foo.bats` added together, nearly every land widened to
            # the full 1,749-test suite. That cost is also pure: no pre-existing test can cover
            # a path that did not exist, so FULL bought no coverage the clauses do not already
            # buy. (Measured 2026-07-26: 33 of 39 scoped-era gate failures ran with
            # selected_n=-1 — i.e. widened to FULL — while every land that stayed narrow landed.)
            if path not in tset:
                emit_full("absent-at-head:%s" % path)
            stem = os.path.splitext(os.path.basename(path))[0]
            lit = set(s for s in suites if path in text.get(s, ""))                          # (a)
            take(set(s for s in lit if not cited_only(path, s)), "literal", direct=True)
            take(set(s for s in lit if cited_only(path, s)), "cited")                        # (a')
            take(naming(stem), "naming", direct=True)                                        # (b)
            take(set(s for s in suites if path in closure[s]), "closure")                    # (c)
            parent = os.path.dirname(path)                                                   # (d)
            if "/" in parent:
                take(set(s for s in suites if (parent + "/") in text.get(s, "")), "pkgdir")
            word = stem_word(path)                                                           # (e)
            if word is not None:
                take(set(s for s in suites if word.search(text.get(s, ""))), "stem")
            if INSTALL_SUITE in tset and INSTALL_RE.match(path) and in_base(path):            # (f)
                take(set([INSTALL_SUITE]), "install-glob")
            if not hits:
                # A DOCUMENT reaching here is INERT, not undecidable — the one rung where "nothing
                # mapped it" is a PROOF. Clauses (a)/(a') just asked every suite in the corpus
                # whether it names this path, (d) whether it names its directory, (e) whether it
                # names its stem; a file that cannot execute has no other way to reach a suite.
                # (Verified over this corpus 2026-07-31: no suite mentions vendor/ or
                # evolve-fixtures/ at all; the one naming agents/ builds a fixture tree; the two
                # that walk a tree wholesale walk $CC_PARITY_REPO and $CC_PAGES_DIR, not the repo;
                # and nothing drives the repo-wide markdown walkers.)
                #
                # `is_prose` cannot carry this — it is a path-PREFIX allowlist (README/CLAUDE,
                # docs/), which only ever describes the trees that existed when it was written, so
                # prose living anywhere else falls through to the code clauses and lands here.
                # Measured: 30 of 278 tracked .md did (vendor/codex-security 23,
                # evolve-fixtures/pyramid-principle/cases 4, agents/ 3 — the last only because
                # clause (d) skips a TOP-LEVEL parent, `"/" in "agents"` being false).
                #
                # This was never confined to docs-only lands, because emit_full ABORTS THE WHOLE
                # SELECTION: a land touching commands/ship.md selects 82 suites including
                # tests/ship-land.bats — add one vendored NOTICE.md and it collapses to FULL,
                # which ship-land.sh reads as "no direct-suite smoke this land" and, in the
                # stale-gate re-round, as `direct=""` ⇒ exonerate nothing. A fail-closed rung
                # failing OPEN at its consumer — the same inversion the prose-removal rung above
                # was written for. Deciding it restores the smoke.
                if is_document(path):
                    note("(inert)", "document-unmapped:%s" % path)
                else:
                    emit_full("unmapped:%s" % path)

        picked |= hits
        direct_picked |= dhits

    for suite in sorted(direct_picked if DIRECT else picked):
        sys.stdout.write("%s\n" % suite)

try:
    main()
except SystemExit:
    raise
except Exception as exc:               # noqa: BLE001 — every internal error fails CLOSED
    if MODE == "lint":                 # a lint that cannot run has NOT proved the map sound
        sys.stderr.write("gate-select lint: %s\n" % exc)
        sys.exit(1)
    if EXPLAIN:
        sys.stderr.write("FULL <- selector-error:%s\n" % exc)
    sys.stdout.write("FULL\n")
PY
}

if [ "$MODE" = lint ]; then
  # An arg to `lint` means the caller expected selection semantics; refusing beats linting
  # the wrong thing and reporting green. (No FULL here — lint speaks in exit codes.)
  [ "${#RANGES[@]}" -eq 0 ] || { printf 'gate-select: lint takes no range\n' >&2; exit 1; }
  run_selector lint || exit 1
  exit 0
fi

OUT="$(run_selector select "${RANGES[@]}")"
RC=$?
[ "$RC" -eq 0 ] || fail_closed "selector-error:rc=$RC"
[ -n "$OUT" ] && printf '%s\n' "$OUT"
exit 0
