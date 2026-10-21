#!/usr/bin/env bats
# G1 — "no recovery decision reads load" — as a lint over the limit-recover rail.
# Plan: docs/plans/LR_SUSTAINED_LOAD_IMPL.md W1 lever 5 and red control C3. Design:
# docs/research/lr-sustained-load-2026-10-20/impl/B1-load-harness.md §9.10-§9.11, review F2/F10/F11/F12/C7.
#
# Every load read in the scanned files must sit in a function that tests/rig/g1-allow.tsv lists, as
# telemetry, capped-bound-stretch, env-off:<builder> or debt:<owner>.
#   Rule 1: an unlisted load read fails.
#   Rule 2: a stale telemetry / capped-bound-stretch / env-off row fails; a stale debt row prints
#           `RESOLVED (remove row)` and passes, so a wave that pays a debt is never blocked by a file
#           it may not write. Debt rows that still match are printed, with `G1 debt <n>` (F11).
#   Rule 3: a cc_capacity_admit / cc_capacity_probe call outside the library must carry
#           CC_ADMIT_LOAD_TERM=off, or `${X:-off}` where no rail environment (launchd plists,
#           lr_recon act.py, the rig's env.sh writer) names X, or sit in a debt / env-off row (C7).
# A load read is: os.getloadavg (any attribute, `from os import getloadavg [as x]`, module-level
# aliases, F2), the strings vm.loadavg / uptime / getloadavg, the names load1 / load5, `sysctl …
# vm.loadavg`, an `uptime` command, a *LOAD_PER_CORE threshold or seam, and in shell one level more:
# a call of a value accessor (a function named *load1, *load5 or *load_per_core that reads load).
# A capped-bound-stretch function must show its cap: python `return min(`, shell min( or an awk
# clamp `if (x > m) x = m` (F12). bin/claude-accounts is scanned only along --place/--rank: the
# call closure of cmd_place, get_data and ranked.
#
# G1_LINT_ROOT (default: this repo) and G1_ALLOW (default: tests/rig/g1-allow.tsv) point the lint
# elsewhere; the red-proofs below copy the scan set into $BATS_TEST_TMPDIR and never edit the repo.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home" TMPDIR="$BATS_TEST_TMPDIR/tmp"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr" LR_RECON_ROOT="$BATS_TEST_TMPDIR/recon"
  # the lint only READS handoff-fire.sh and capacity-admit.sh as text, but the hermeticity gate
  # closes both against ambient load for every suite that names them
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  mkdir -p "$HOME" "$TMPDIR"
  ROOT="$BATS_TEST_TMPDIR/root"
  ALLOW="$BATS_TEST_TMPDIR/allow.tsv"
}

# One python process per run.
g1_lint() {
  G1_LINT_ROOT="${G1_LINT_ROOT:-$REPO}" G1_ALLOW="${G1_ALLOW:-$REPO/tests/rig/g1-allow.tsv}" \
    /usr/bin/python3 -I - <<'PY'
import ast, glob, os, re, sys

ROOT, ALLOW = os.environ["G1_LINT_ROOT"], os.environ["G1_ALLOW"]
TOP = "<top>"
CLASSES = ("telemetry", "capped-bound-stretch")
SHELL = ["scripts/handoff-fire.sh", "scripts/boot-resume-launch.sh", "bin/reso-resume-one", "bin/cc-lr",
         "scripts/lib/capacity-admit.sh", "bin/cc-wave-plan", "bin/cc-dispatch"]
LIB = "scripts/lib/capacity-admit.sh"  # defines the Rule 3 functions; its delegation inherits the caller's env
ACCOUNTS = "bin/claude-accounts"
ACCOUNTS_ROOTS = ("cmd_place", "get_data", "ranked")  # --place → cmd_place; --rank → get_data, ranked
ENV_SOURCES = ("launchd", "tests/rig/lr-recon-rig.sh", "scripts/limit-recover/lr_recon/act.py")
LOADNAMES = {"load1", "load5"}
LOADCONST = {"vm.loadavg", "uptime", "getloadavg"}
SH_READ = re.compile(r"vm\.loadavg|getloadavg|(?<![\w.-])uptime(?![\w-])|(?<![\w$.-])\$?\{?load[15](?![\w-])"
                     r"|[A-Z_]*LOAD_PER_CORE(?!\w)")
ACCESSOR = re.compile(r"load(?:1|5|_per_core)$")
ADMIT = re.compile(r"(?<![\w-])cc_capacity_(?:admit|probe)(?![\w-])")
NOTCALL = re.compile(r"(?:command\s+-v|type|declare\s+-[fF]|unset\s+-f)\s+$")
TERM_OFF = re.compile(r"CC_ADMIT_LOAD_TERM=(?:off|\"off\"|'off')(?![\w-])")
TERM_DEFAULT = re.compile(r"CC_ADMIT_LOAD_TERM=\"?\$\{(\w+):?-off\}\"?")
SH_FUNC = re.compile(r"^(\s*)(?:function\s+)?([A-Za-z_][\w:.-]*)\s*\(\)\s*\{")
HEREDOC = re.compile(r"<<(-?)\s*(['\"]?)([A-Za-z_]\w*)\2")
CLAMP = re.compile(r"if\s*\(\s*(\w+)\s*>=?\s*([^()]+?)\s*\)\s*\1\s*=\s*\2")
fails, out = [], []


def rel(p):
    return os.path.relpath(p, ROOT)


def read(p):
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read()


def scan_set():
    lr = os.path.join(ROOT, "scripts/limit-recover")
    files = [("py", rel(p)) for p in sorted(glob.glob(os.path.join(lr, "lr_recon/**/*.py"), recursive=True))
             if "tests" not in rel(p).split(os.sep)]
    files += [("sh", rel(p)) for p in sorted(glob.glob(os.path.join(lr, "*.sh")))]
    return files + [("sh", p) for p in SHELL] + [("py", ACCOUNTS)]


def strip_sh_comment(line):
    s = line.lstrip()
    if s.startswith("#") and not s.startswith("#!"):
        return ""
    sq = dq = False
    for i, ch in enumerate(line):
        if ch == "'" and not dq:
            sq = not sq
        elif ch == '"' and not sq and (i == 0 or line[i - 1] != "\\"):
            dq = not dq
        elif ch == "#" and not sq and not dq and i > 0 and line[i - 1] in " \t;":
            return line[:i]
    return line


def parse_sh(path):
    """→ ({function: body lines}, [(lineno, function, logical line)]). A function ends at a `}` at its
    header's indentation; heredoc bodies (tcl, awk, python) belong to the enclosing bash function."""
    funcs, stack, logical = {}, [], []
    hd, buf, buf_start, buf_fn = None, "", 0, TOP
    for n, raw in enumerate(read(os.path.join(ROOT, path)).split("\n"), 1):
        cur = stack[-1][1] if stack else TOP
        code = strip_sh_comment(raw)
        if hd is not None:
            if (raw.lstrip("\t") if hd[1] else raw) == hd[0]:
                hd = None
            else:
                for _, f in stack:
                    funcs[f].append(code)
                logical.append((n, cur, code))
            continue
        m = SH_FUNC.match(code)
        if m and not buf:
            name = m.group(2)
            funcs.setdefault(name, [])
            if code[m.end():].strip().endswith("}"):  # one-liner
                for f in [s[1] for s in stack] + [name]:
                    funcs[f].append(code)
                logical.append((n, name, code))
                continue
            stack.append((m.group(1), name))
            cur = name
        elif stack and not buf and re.match(re.escape(stack[-1][0]) + r"\}", code):
            stack.pop()
            continue
        for _, f in stack:
            funcs[f].append(code)
        h = HEREDOC.search(code) if "<<<" not in code else None
        if h:
            hd = (h.group(3), h.group(1) == "-")
        if not buf:
            buf_start, buf_fn = n, cur
        if code.rstrip().endswith("\\"):
            buf += code.rstrip()[:-1] + " "
            continue
        logical.append((buf_start, buf_fn, buf + code))
        buf = ""
    return funcs, logical


class PyScan(ast.NodeVisitor):
    def __init__(self, src):
        self.src, self.qual, self.reads, self.calls, self.funcs = src, [], [], [], {}
        self.aliases, self.docs, self.callgraph = set(), set(), {}

    def scope(self):
        return ".".join(self.qual) or TOP

    def collect(self, tree):
        for node in ast.walk(tree):
            if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
                b = node.body
                if b and isinstance(b[0], ast.Expr) and isinstance(b[0].value, ast.Constant):
                    self.docs.add(id(b[0].value))
            if isinstance(node, ast.ImportFrom) and node.module == "os":  # G1-ALIAS
                self.aliases |= {a.asname or a.name for a in node.names if a.name == "getloadavg"}
        for _ in range(3):  # module-level aliases, including aliases of aliases
            for node in tree.body:
                if isinstance(node, (ast.Assign, ast.AnnAssign)) and node.value is not None \
                        and any(self.is_read(x) for x in ast.walk(node.value)):
                    for t in (node.targets if isinstance(node, ast.Assign) else [node.target]):
                        self.aliases |= {x.id for x in ast.walk(t) if isinstance(x, ast.Name)}

    def is_read(self, x):
        if isinstance(x, ast.Attribute):
            return "getloadavg" in x.attr
        if isinstance(x, ast.Name):
            return "getloadavg" in x.id or x.id in LOADNAMES or x.id in self.aliases  # G1-ALIAS
        if isinstance(x, ast.arg):
            return "getloadavg" in x.arg or x.arg in LOADNAMES
        if isinstance(x, ast.alias):
            return x.name == "getloadavg"
        return isinstance(x, ast.Constant) and isinstance(x.value, str) and x.value in LOADCONST

    def visit_FunctionDef(self, node):
        self.qual.append(node.name)
        self.funcs[self.scope()] = node
        self.generic_visit(node)
        self.qual.pop()

    visit_AsyncFunctionDef = visit_FunctionDef

    def visit_ClassDef(self, node):
        self.qual.append(node.name)
        self.generic_visit(node)
        self.qual.pop()

    def generic_visit(self, node):
        for child in ast.iter_child_nodes(node):
            if self.is_read(child):
                self.reads.append((getattr(child, "lineno", getattr(node, "lineno", 0)), self.scope(),
                                   ast.get_source_segment(self.src, child) or getattr(child, "name", "")))
            if isinstance(child, ast.Constant) and isinstance(child.value, str) and id(child) not in self.docs:
                for m in ADMIT.finditer(child.value):
                    if not NOTCALL.search(child.value[:m.start()]):
                        self.calls.append((child.lineno, self.scope(), child.value, child.value[:m.start()]))
            if isinstance(child, ast.Call) and isinstance(child.func, ast.Name) and self.qual:
                self.callgraph.setdefault(self.qual[0], set()).add(child.func.id)
            self.visit(child)


def capped(body):
    """A bound-stretch shows its cap: python `return min(`; shell min( or an awk clamp."""
    if isinstance(body, str):
        return re.search(r"\breturn\s+min\(", body) is not None
    code = "\n".join(body)
    return "min(" in code or CLAMP.search(code) is not None


def env_sets(var):
    """→ the rail env source naming var, or None. A missing source fails closed."""
    for s in ENV_SOURCES:
        p = os.path.join(ROOT, s)
        paths = glob.glob(os.path.join(p, "**/*.plist"), recursive=True) if os.path.isdir(p) else [p]
        if not paths or not all(os.path.isfile(q) for q in paths):
            return "%s (missing: cannot prove it does not set %s)" % (s, var)
        for q in paths:
            if re.search(r"(?<![\w-])%s(?![\w-])" % re.escape(var), read(q)):
                return rel(q)
    return None


def term_ok(pre):
    """pre = the call's own line up to the call (env assignments included, continuations joined)."""
    if TERM_OFF.search(pre):
        return True, ""
    m = TERM_DEFAULT.search(pre)
    if m:
        who = env_sets(m.group(1))
        return who is None, "${%s:-off}, but %s sets %s" % (m.group(1), who, m.group(1))
    return False, "no CC_ADMIT_LOAD_TERM=off on the call"


def env_off_proved(target):
    """env-off:<module>.<function>: '' when that lr_recon builder sets the term off and a test says so."""
    mod, _, fn = target.rpartition(".")
    p = os.path.join(ROOT, "scripts/limit-recover/lr_recon", mod + ".py")
    if not os.path.isfile(p):
        return "env builder module %s missing" % rel(p)
    src = read(p)
    node = next((x for x in ast.walk(ast.parse(src)) if isinstance(x, ast.FunctionDef) and x.name == fn), None)
    if node is None:
        return "env builder %s not defined" % target
    if not re.search(r"[\"']CC_ADMIT_LOAD_TERM[\"']\s*:\s*[\"']off[\"']", ast.get_source_segment(src, node) or ""):
        return "env builder %s does not set CC_ADMIT_LOAD_TERM to off" % target
    for t in glob.glob(os.path.join(ROOT, "tests/*.bats")) + \
            glob.glob(os.path.join(ROOT, "scripts/limit-recover/lr_recon/tests/*.py")):
        body = read(t)
        if fn in body and "CC_ADMIT_LOAD_TERM" in body:
            return ""
    return "no test names %s and CC_ADMIT_LOAD_TERM" % fn


def load_rows():
    if not os.path.isfile(ALLOW):
        fails.append("G1 FAIL allowlist missing: %s" % ALLOW)
        return []
    rows = []
    for n, line in enumerate(read(ALLOW).split("\n"), 1):
        if not line.strip() or line.startswith("#"):
            continue
        cols = line.split("\t")
        if len(cols) != 4 or not all(c.strip() for c in cols) \
                or not (cols[2] in CLASSES or re.match(r"(env-off|debt):[\w.-]+$", cols[2])):
            fails.append("G1 BAD ROW %d (want path<TAB>function<TAB>class<TAB>reason): %s" % (n, line))
            continue
        rows.append(tuple(cols))
    return rows


def main():
    rows = load_rows()
    allow = {(r[0], r[1]): r for r in rows}
    reads, calls, bodies, sh = [], [], {}, {}
    defined = set()
    for kind, path in scan_set():
        full = os.path.join(ROOT, path)
        if not os.path.isfile(full):
            fails.append("G1 FAIL scan file missing: %s" % path)
            continue
        defined.add((path, TOP))
        if kind == "sh":
            funcs, logical = parse_sh(path)
            sh[path] = logical
            for name, body in funcs.items():
                defined.add((path, name))
                bodies[(path, name)] = body
            continue
        src = read(full)
        tree = ast.parse(src)
        v = PyScan(src)
        v.collect(tree)
        v.visit(tree)
        keep = None
        if path == ACCOUNTS:  # only the --place/--rank path: the call closure of its roots
            keep, todo = set(), list(ACCOUNTS_ROOTS)
            while todo:
                f = todo.pop()
                if f not in keep and f in v.funcs:
                    keep.add(f)
                    todo += sorted(v.callgraph.get(f, ()))
            fails.extend("G1 FAIL %s: --place/--rank root %s() not found" % (path, r)
                         for r in ACCOUNTS_ROOTS if r not in v.funcs)
        for q, node in v.funcs.items():
            defined.add((path, q))
            bodies[(path, q)] = (src, node)
        def inscope(q):
            return keep is None or q.split(".")[0] in keep
        reads += [(path, n, q, c) for n, q, c in v.reads if inscope(q)]
        calls += [(path, n, q, c, pre) for n, q, c, pre in v.calls if inscope(q)]
    # Shell: raw reads, plus one level through value accessors. Callers of a gate are not followed:
    # they consume a verdict, and the gate carries the row.
    accessors = {fn for logical in sh.values() for _, fn, code in logical
                 if ACCESSOR.search(fn) and SH_READ.search(code)}
    pat = SH_READ
    if accessors:
        alt = "|".join(re.escape(a) for a in sorted(accessors, key=len, reverse=True))
        pat = re.compile(r"%s|(?<![\w$.-])(?:%s)(?![\w-])" % (SH_READ.pattern, alt))
    for path, logical in sh.items():
        for n, fn, code in logical:
            if any(m.group(0) != fn and not NOTCALL.search(code[:m.start()]) for m in pat.finditer(code)):
                reads.append((path, n, fn, code.strip()))
            if path != LIB:  # G1-RULE3
                calls += [(path, n, fn, code.strip(), code[:m.start()]) for m in ADMIT.finditer(code)
                          if not NOTCALL.search(code[:m.start()])]
    used, debt = set(), {}
    for path, n, fn, code in sorted(reads, key=lambda r: (r[0], r[1])):
        row = allow.get((path, fn))
        if row is None:
            fails.append("G1 VIOLATION %s:%d in %s(): unlisted load read: %s" % (path, n, fn, code[:160]))
            continue
        used.add((path, fn))
        if row[2].startswith("debt:"):
            debt[(path, fn)] = row
    for path, n, fn, code, pre in calls:
        ok, why = term_ok(pre)
        row = allow.get((path, fn))
        if ok:
            continue
        if row and row[2].startswith(("debt:", "env-off:")):
            used.add((path, fn))
            if row[2].startswith("debt:"):
                debt[(path, fn)] = row
            continue
        fails.append("G1 VIOLATION %s:%d in %s(): bare capacity call (Rule 3: %s): %s"
                     % (path, n, fn, why, code[:160]))
    for r in rows:
        key, cls = (r[0], r[1]), r[2]
        if cls.startswith("env-off:"):
            bad = env_off_proved(cls.split(":", 1)[1])
            if bad:
                fails.append("G1 FAIL env-off row unproved (%s): %s" % (bad, "\t".join(r)))
        if cls == "capped-bound-stretch" and key in defined:
            body = bodies.get(key, [])
            if isinstance(body, tuple):
                body = ast.get_source_segment(*body) or ""
            if not capped(body):
                fails.append("G1 FAIL capped-bound-stretch row has no min(MAX, ...) cap in %s(): %s"
                             % (r[1], "\t".join(r)))
        if key in used:
            continue
        if cls.startswith("debt:"):  # G1-STALE-DEBT
            out.append("RESOLVED (remove row): %s" % "\t".join(r))
        else:
            fails.append("G1 STALE row (%s): %s"
                         % ("no such function" if key not in defined else "no load read in it", "\t".join(r)))
    out.extend("G1 DEBT %s %s() %s: %s" % debt[k] for k in sorted(debt))
    out.append("G1 debt %d" % len(debt))
    print("\n".join(out + fails))
    print("G1 %s (%d reads, %d capacity calls, %d rows)"
          % ("FAIL" if fails else "PASS", len(reads), len(calls), len(rows)))
    return 1 if fails else 0


sys.exit(main())
PY
}

# Copy the scan set, the rail env sources and the allowlist under $BATS_TEST_TMPDIR.
g1_copy_root() {
  local f files
  files="$(cd "$REPO" && find scripts/limit-recover/lr_recon -name '*.py' -not -path '*/tests/*'
           printf '%s\n' scripts/limit-recover/*.sh)"
  for f in $files scripts/handoff-fire.sh scripts/boot-resume-launch.sh \
    scripts/lib/capacity-admit.sh bin/reso-resume-one bin/cc-lr bin/cc-wave-plan bin/cc-dispatch \
    bin/claude-accounts tests/rig/lr-recon-rig.sh; do
    mkdir -p "$ROOT/$(dirname "$f")"
    cp "$REPO/$f" "$ROOT/$f"
  done
  cp -R "$REPO/launchd" "$ROOT/launchd"
  cp "$REPO/tests/rig/g1-allow.tsv" "$ALLOW"
  export G1_LINT_ROOT="$ROOT" G1_ALLOW="$ALLOW"
}

@test "G1 lint is green at HEAD with the seeded allowlist, and prints every debt row" {
  run g1_lint
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; false; }
  [[ "$output" =~ G1\ PASS\ \(([1-9][0-9]*)\ reads ]] || false
  [[ "$output" =~ G1\ debt\ ([0-9]+) ]] || false
  n="${BASH_REMATCH[1]}"
  [ "$n" -gt 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^G1 DEBT ')" -eq "$n" ]
  printf '%s\n' "$output" | grep -q '^G1 DEBT scripts/handoff-fire.sh hf_lr_admit() debt:W12'
  printf '%s\n' "$output" | grep -q '^G1 DEBT scripts/handoff-fire.sh hf_recycle_load_gate() debt:typed-relaunch'
  printf '%s\n' "$output" | grep -q '^G1 DEBT scripts/limit-recover/lr_recon/clock.py Clock.load_multiplier() debt:W8'
}

@test "C3: a new function holding a bare os.getloadavg() is red, and named" {
  g1_copy_root
  printf '\n\ndef g1_planted():\n    return os.getloadavg()[0]\n' >> "$ROOT/scripts/limit-recover/lr_recon/plan.py"
  run g1_lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"lr_recon/plan.py:"*" in g1_planted(): unlisted load read"* ]] || false
}

@test "C3: a 'from os import getloadavg as gl' alias is red at its use (F2)" {
  g1_copy_root
  printf '\nfrom os import getloadavg as gl\n\n\ndef g1_alias():\n    return gl()[0]\n' \
    >> "$ROOT/scripts/limit-recover/lr_recon/plan.py"
  run g1_lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"in g1_alias(): unlisted load read: gl"* ]] || false
}

@test "C3: an emptied allowlist is red" {
  g1_copy_root
  grep '^#' "$REPO/tests/rig/g1-allow.tsv" > "$ALLOW"
  run g1_lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"G1 VIOLATION "* ]] || false
  [[ "$output" == *"G1 FAIL ("* ]] || false
}

@test "C3: a stale telemetry row (its function no longer exists) is red" {
  g1_copy_root
  printf 'scripts/limit-recover/lr_recon/admit.py\tAdmission.g1_gone\ttelemetry\tplanted stale row\n' >> "$ALLOW"
  run g1_lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"G1 STALE row (no such function): scripts/limit-recover/lr_recon/admit.py"*"Admission.g1_gone"* ]] || false
}

@test "C3: a stale debt row passes and prints RESOLVED (remove row)" {
  g1_copy_root
  printf 'scripts/limit-recover/lr_recon/admit.py\tAdmission.g1_gone\tdebt:W99\tplanted resolved debt\n' >> "$ALLOW"
  run g1_lint
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; false; }
  [[ "$output" == *"RESOLVED (remove row): scripts/limit-recover/lr_recon/admit.py"*"Admission.g1_gone"* ]] || false
}

@test "C3: a bare cc_capacity_admit planted in a rail script is red (Rule 3)" {
  g1_copy_root
  printf '\ng1_bare() {\n  cc_capacity_admit g1 "planted"\n}\n' >> "$ROOT/scripts/limit-recover/lr-fleet.sh"
  run g1_lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"lr-fleet.sh:"*" in g1_bare(): bare capacity call (Rule 3"* ]] || false
}

@test "C3: \${X:-off} is red once a rail environment sets X (Rule 3, F10)" {
  g1_copy_root
  printf '<plist><dict><key>LR_LOAD_TERM</key><string>on</string></dict></plist>\n' \
    > "$ROOT/launchd/com.example.g1-planted.plist"
  run g1_lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"lr-fire-resume.sh:"*"\${LR_LOAD_TERM:-off}, but launchd/com.example.g1-planted.plist sets LR_LOAD_TERM"* ]] || false
}

@test "C3: a capped-bound-stretch row whose function shows no min( cap is red (F12)" {
  g1_copy_root
  awk -F'\t' 'BEGIN { OFS = FS } $2 == "Clock.load_multiplier" { $3 = "capped-bound-stretch" } { print }' \
    "$REPO/tests/rig/g1-allow.tsv" > "$ALLOW"
  run g1_lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"G1 FAIL capped-bound-stretch row has no min(MAX, ...) cap in Clock.load_multiplier()"* ]] || false
}
