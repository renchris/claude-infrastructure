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
#
# MULTI-RANGE: the changed-file sets of every range are UNIONED before the rules run, so a
# CAS-stale re-gate can pass the sibling trunk delta as a second range and see the novelty
# of the COMPOSED tree. A path that is D/R in any range still fails the whole run closed.
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
# Clause (e) — stems measured to match half the corpus as ordinary English/shell words.
STOPLIST = ("run", "common", "main", "test", "commit")
SCRIPTY = (".sh", ".bash", ".zsh", ".py")

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

    def reachable(root):               # to FIXPOINT — depth-2 drops real 3-hop couplings
        seen, stack = set(), list(refs.get(root, ()))
        while stack:
            node = stack.pop()
            if node in seen:
                continue
            seen.add(node)
            stack.extend(refs.get(node, ()))
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

    # UNION of every range's changed-file set, deduped on (status, path) so a file touched by
    # two ranges is judged once. `-M` asks for rename detection explicitly: git must REPORT
    # an R status for the R-⇒-FULL rule to fire on it.
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
                rec = (status, raw[i + 1] if i + 1 < len(raw) else "")
                i += 2
            else:
                rec = (status, raw[i] if i < len(raw) else "")
                i += 1
            if rec not in seen:
                seen.add(rec)
                changes.append(rec)

    picked, direct_picked = set(), set()

    for status, path in changes:
        if not path:
            emit_full("unparseable-diff-record:%s" % status)
        code = status[0]
        if code == "D":
            emit_full("deleted:%s" % path)
        if code in ("R", "C"):
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
        elif is_prose(path):           # no suite builds a doc path dynamically — literal or inert
            take(set(s for s in suites if path in text.get(s, "")), "prose-literal", direct=True)
        else:
            if code == "A":
                emit_full("added-unmapped:%s" % path)
            if path not in tset:
                emit_full("absent-at-head:%s" % path)
            stem = os.path.splitext(os.path.basename(path))[0]
            take(set(s for s in suites if path in text.get(s, "")), "literal", direct=True)  # (a)
            take(naming(stem), "naming", direct=True)                                        # (b)
            take(set(s for s in suites if path in closure[s]), "closure")                    # (c)
            parent = os.path.dirname(path)                                                   # (d)
            if "/" in parent:
                take(set(s for s in suites if (parent + "/") in text.get(s, "")), "pkgdir")
            if stem not in STOPLIST and len(stem) > 2:                                       # (e)
                word = re.compile(r'(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])' % re.escape(stem))
                take(set(s for s in suites if word.search(text.get(s, ""))), "stem")
            if INSTALL_SUITE in tset and INSTALL_RE.match(path) and in_base(path):            # (f)
                take(set([INSTALL_SUITE]), "install-glob")
            if not hits:
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
