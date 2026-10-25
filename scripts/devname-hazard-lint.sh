#!/bin/bash
# devname-hazard-lint.sh — refuse shell forms that walk /dev (devname/ttyname) on a watchdog path.
#
# WHY. On 2026-10-25 one poisoned devfs node (ttys063) turned every `/dev` name lookup into a
# permanent kernel sleep: 17 `login`, 23 `ps` and every new zsh hung in
# `ttyname_r → devname_r → lstat → devfs_lookup → … → msleep` (incident DESIGN.md I4, R1/R2;
# rca/diag-reports.md §2a). A watchdog that runs one of those forms becomes a casualty of the
# thing it watches. Apple `ps` calls devname() for the `tt`/`tty` columns, for -t/-T/-M, and for
# every ctty process when -x is absent; a multi-pid -p without -x is KERN_PROC_ALL plus that same
# ctty filter (adv_cmds ps.c:568-571, 681-690; print.c:619-623,649). `lsof` lstat-scans /dev
# (lsof lib/rdev.c:107-121). `tty` calls ttyname(0). Single-pid `ps -p N -o <no tt>` is safe.
#
# TIERS. "hazard" rules (a hang path) apply to the whole scope. "strict" rules apply to the
# lockwatch/forensics/break-glass dirs only, where new code is written against I4 from the start:
# `pgrep` without -a (silently drops the caller's ancestors, so it cannot find kitty from a pane),
# and any `zsh` / `login` invocation (both run ttyname at startup).
#
# Suppress one line with a trailing `# devname-hazard-lint:allow <reason>`.
#
# Usage: devname-hazard-lint.sh [--file F]... [--diff <git-range>] · --selftest · --print-scope
#   no --file  → the default scope, every line
#   --diff R   → only lines ADDED by `git diff R` are judged, so a land is refused for a hazard it
#                introduces and never for a sibling's legacy line it did not touch
# Exit: 0 clean · 1 findings · 2 no verdict (python3 missing, unreadable file, bad range)
set -uo pipefail

_p="${BASH_SOURCE[0]}"   # resolve the ~/.claude/scripts symlink first, or `..` is ~/.claude
while [ -L "$_p" ]; do _d="$(cd "$(dirname "$_p")" && pwd)"; _p="$(readlink "$_p")"
  case "$_p" in /*) ;; *) _p="$_d/$_p" ;; esac; done
ROOT="$(cd "$(dirname "$_p")/.." && pwd)"
PY="$(command -v python3 2>/dev/null || true)"
[ -n "$PY" ] || { echo "devname-hazard-lint: python3 not on PATH — no verdict" >&2; exit 2; }

default_scope() {
  local f
  for f in "$ROOT"/scripts/lockwatch/* "$ROOT"/scripts/forensics/* "$ROOT"/scripts/break-glass/* \
           "$ROOT"/scripts/compressor-sentinel.sh "$ROOT"/scripts/capacity-alarm.sh \
           "$ROOT"/hooks/*.sh "$ROOT"/hooks/lib/*.sh; do
    [ -f "$f" ] && printf '%s\n' "${f#"$ROOT"/}"
  done
}

# in_scope <relpath> → 0 iff the path belongs to the lint's population (used to filter --file lists)
in_scope() {
  case "$1" in
    scripts/lockwatch/*|scripts/forensics/*|scripts/break-glass/*) return 0 ;;
    scripts/compressor-sentinel.sh|scripts/capacity-alarm.sh) return 0 ;;
    hooks/*.sh) return 0 ;;   # a case `*` crosses "/", so this covers hooks/lib/*.sh too
  esac
  return 1
}

read -r -d '' LINT_PY <<'PY'
import re, shlex, sys

STRICT_DIRS = ("scripts/lockwatch/", "scripts/forensics/", "scripts/break-glass/")
ALLOW = "devname-hazard-lint:allow"
CMDPOS = r"(?:(?<=^)|(?<=[\s;|&(`$]))"
SEP = re.compile(r"""(?<!\\)(?:\|\||&&|[|;&)`<>]|\$\(|\b[0-9]?>)""")
PS = re.compile(CMDPOS + r"(?:/bin/)?ps(?=\s+-)")
# a COMMAND start: line start, after ; | & $( ` or a shell keyword — never mid-argument, so a path
# test (`[ -x /usr/sbin/lsof ]`), an assignment or a variable named tty is not an invocation
CMDSTART = r"(?:^\s*|[;|&]\s*|\$\(\s*|`\s*|\b(?:if|then|do|else|exec|command|!)\s+)"
WORD = lambda w: re.compile(CMDSTART + r"(?:/usr/s?bin/|/bin/)?" + w + r"(?=$|[\s;|&)])")
LSOF, ZSH, LOGIN, PGREP, LS = (WORD("lsof"), WORD("zsh"), WORD("login"), WORD("pgrep"), WORD("ls"))
TTY = WORD("tty")

def strip_comment(line):
    q, prev = None, " "
    for i, ch in enumerate(line):
        if q:
            if ch == q and (q == "'" or prev != "\\"): q = None
        elif ch in "'\"": q = ch
        elif ch == "#" and prev.isspace(): return line[:i]
        prev = ch
    return line
ARGF = set("GgOoptUu")

def args_after(line, end):
    rest = line[end:]
    m = SEP.search(rest)
    seg = rest[: m.start()] if m else rest
    try:
        return shlex.split(seg, posix=True)
    except ValueError:
        return seg.split()

def ps_findings(toks):
    flags, ovals, pvals = set(), [], []
    i = 0
    while i < len(toks):
        t = toks[i]
        if t.startswith("-") and len(t) > 1 and not t.startswith("--"):
            j = 1
            while j < len(t):
                c = t[j]
                flags.add(c)
                if c in ARGF:
                    v = t[j + 1:]
                    if not v and i + 1 < len(toks):
                        i += 1; v = toks[i]
                    if c in "oO": ovals.append(v)
                    if c == "p": pvals.append(v)
                    break
                j += 1
        i += 1
    out = []
    for c, why in (("t", "-t stats /dev/<tty>"), ("T", "-T reads the caller's tty"),
                   ("M", "-M forces a TT column"), ("O", "-O adds to the default format, which has TT"),
                   ("j", "-j prints tt"), ("l", "-l prints tt"), ("f", "-f prints tty")):
        if c in flags: out.append("ps " + why)
    if "o" not in flags and "O" not in flags:
        out.append("ps without -o prints the default TT column")
    for v in ovals:
        if "$" in v: continue
        for kw in re.split(r"[,\s]+", v):
            if kw.split("=", 1)[0] in ("tt", "tty"):
                out.append("ps -o %s calls devname() per row (use tdev: 16/N = ttys%%03d)" % kw)
    xkeep = bool(flags & set("xAe"))
    multi = len(pvals) > 1 or any("," in v or re.search(r"(?i)\$\{?\w*(csv|pids|list)", v) for v in pvals)
    if not xkeep:
        if multi:
            out.append("multi-pid ps -p without -x walks every ctty process through devname()")
        elif not pvals:
            out.append("ps without -x/-A runs devname() for every ctty process (add -x)")
    return out

def lint_line(path, line):
    s = line.lstrip()
    if not s or s.startswith("#") or ALLOW in line:
        return []
    line = strip_comment(line)
    out = []
    for m in PS.finditer(line):
        out += ps_findings(args_after(line, m.end()))
    if LSOF.search(line): out.append("lsof lstat-scans /dev for device names")
    if TTY.search(line): out.append("tty calls ttyname(0)")
    for m in LS.finditer(line):
        if any(a.startswith("/dev") and a not in ("/dev/null",) for a in args_after(line, m.end())):
            out.append("ls /dev walks devfs")
    if path.startswith(STRICT_DIRS):
        if ZSH.search(line): out.append("zsh runs ttyname() at startup (init_io)")
        if LOGIN.search(line): out.append("login hangs in ttyname()")
        for m in PGREP.finditer(line):
            if not any(t.startswith("-") and "a" in t[1:] for t in args_after(line, m.end())):
                out.append("pgrep without -a drops the caller's ancestors")
    return out

def main(argv):
    mode, files, added = argv[0], [], {}
    if mode == "selftest":
        return selftest()
    i = 1
    while i < len(argv):
        files.append(argv[i]); i += 1
    if mode == "diff":
        cur = None
        for l in sys.stdin:
            if l.startswith("+++ "):
                cur = l[6:].rstrip("\n") if l.startswith("+++ b/") else None
                added.setdefault(cur, set())
            elif l.startswith("@@") and cur:
                m = re.search(r"\+(\d+)(?:,(\d+))?", l)
                a, n = int(m.group(1)), int(m.group(2) or "1")
                added[cur].update(range(a, a + n))
    bad = 0
    for f in files:
        try:
            text = open(f, encoding="utf-8", errors="replace").read().split("\n")
        except OSError as e:
            print("devname-hazard-lint: cannot read %s: %s" % (f, e), file=sys.stderr); return 2
        want = added.get(f) if mode == "diff" else None
        for n, line in enumerate(text, 1):
            if want is not None and n not in want: continue
            for why in lint_line(f, line):
                print("%s:%d: %s\n    %s" % (f, n, why, line.strip()[:160])); bad += 1
    return 1 if bad else 0

def selftest():
    hz = "hooks/x.sh"; st = "scripts/lockwatch/x.sh"
    must = [
        (hz, 't="$(ps -o tty= -p "$p" 2>/dev/null)"'),
        (hz, "ps -t ttys001 -o stat=,command="),
        (hz, "/bin/ps -axM"),
        (hz, "ps -o pid=,comm= -p 1,2"),
        (hz, 'ps -o pid= -p "$csv"'),
        (hz, "ps -o pid,comm"),
        (hz, "ps -p 123"),
        (hz, "ps -axo pid,tt"),
        (hz, "x=$(lsof -p 12)"),
        (hz, "ls -la /dev/ttys0*"),
        (hz, "t=$(tty)"),
        (hz, "if tty -s; then :; fi"),
        (hz, "ps -O tdev -p 1"),
        (st, "pgrep -x kitty"),
        (st, "/bin/zsh -fc true"),
        (st, "exec login -f me"),
    ]
    clean = [
        (hz, 't="$(ps -o tdev= -p "$p" 2>/dev/null)"'),
        (hz, "ps -axo pid=,tdev=,stat=,command="),
        (hz, "ps -x -o pid=,ppid= -p 1,2"),
        (hz, "ps -o ppid= -p $PPID"),
        (hz, "ls -1 /tmp 2>/dev/null"),
        (hz, "echo x >/dev/null"),
        (hz, "# ps -t ttys001 in a comment"),
        (hz, "ps -o tty= -p 1  # devname-hazard-lint:allow fixture"),
        (hz, "pgrep -x kitty"),
        (st, "pgrep -a -x kitty"),
        (hz, "cps -o x"),
        (hz, 'local pid="$1" tty'),
        (hz, 'elif [ -x /usr/sbin/lsof ]; then LSOF=/usr/sbin/lsof'),
        (hz, 'log "pane closed ($tty is gone)"'),
        (hz, 'X="${A:-}"   # from `ps -o tty= -p <lead>`'),
    ]
    fails = 0
    for p, l in must:
        if not lint_line(p, l): print("selftest: MISSED %s" % l); fails += 1
    for p, l in clean:
        r = lint_line(p, l)
        if r: print("selftest: FALSE POSITIVE %s -> %s" % (l, r)); fails += 1
    print("devname-hazard-lint selftest: %d/%d %s" % (len(must) + len(clean) - fails,
          len(must) + len(clean), "pass" if not fails else "FAIL"))
    return 1 if fails else 0

sys.exit(main(sys.argv[1:]))
PY

run_py() { "$PY" -I -c "$LINT_PY" "$@"; }

case "${1:-}" in
  --selftest) run_py selftest; exit $? ;;
  --print-scope) default_scope; exit 0 ;;
esac

FILES=() RANGE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file) [ $# -ge 2 ] || { echo "devname-hazard-lint: --file needs a path" >&2; exit 2; }; FILES+=("$2"); shift 2 ;;
    --diff) [ $# -ge 2 ] || { echo "devname-hazard-lint: --diff needs a range" >&2; exit 2; }; RANGE="$2"; shift 2 ;;
    *) echo "devname-hazard-lint: unknown argument $1" >&2; exit 2 ;;
  esac
done

cd "$ROOT" || exit 2
if [ "${#FILES[@]}" -eq 0 ]; then
  while IFS= read -r f; do FILES+=("$f"); done < <(
    if [ -n "$RANGE" ]; then git diff --name-only --diff-filter=AM "$RANGE" 2>/dev/null; else default_scope; fi)
fi
SCOPED=()
for f in "${FILES[@]+"${FILES[@]}"}"; do
  f="${f#"$ROOT"/}"
  in_scope "$f" && [ -f "$f" ] && SCOPED+=("$f")
done
[ "${#SCOPED[@]}" -gt 0 ] || { echo "devname-hazard-lint: 0 file(s) in scope — clean"; exit 0; }

if [ -n "$RANGE" ]; then
  _diff="$(git diff -U0 --diff-filter=AM "$RANGE" -- "${SCOPED[@]}")" || {
    echo "devname-hazard-lint: git diff $RANGE failed — no verdict" >&2; exit 2; }
  printf '%s\n' "$_diff" | run_py diff "${SCOPED[@]}"; rc=$?
else
  run_py all "${SCOPED[@]}"; rc=$?
fi
case "$rc" in
  0) echo "devname-hazard-lint: ${#SCOPED[@]} file(s) clean" ;;
  1) echo "devname-hazard-lint: RED — fix the form (ps -x, tdev instead of tty, no lsof) or annotate '# devname-hazard-lint:allow <reason>'" >&2 ;;
esac
exit "$rc"
