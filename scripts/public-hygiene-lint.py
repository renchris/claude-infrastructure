#!/usr/bin/env python3
"""public-hygiene-lint.py — refuse personal identifiers and local-only content in this PUBLIC repo.

WHY A GATE. This repo is public (docs/plans/PUBLIC_REPO_HYGIENE.md). The tree was cleaned once; a
convention that says "never commit an address" is executed by nothing, and the append rate here is
dozens of commits a day. So the refusal sits at the land (scripts/ship-land.sh), where the act is.

THREE ARMS, each a finding on its own:
  1. PRIVATE MAP — every left-hand side of the operator's redaction map
     ($CC_PRIVATE_DIR/public-projection/replace-text.txt, git filter-repo --replace-text format).
     The same file drives the public history projection, so "what the gate refuses" and "what the
     publish rewrites" cannot drift apart. It names the identifiers, so it is private by necessity.
  2. E-MAIL — any address not allowed by config/public-hygiene.conf `email` rows. This is the arm
     that catches an address nobody listed yet.
  3. PHONE — NANP-shaped numbers in their written forms (+1…, (…) …-…, tel:), except 555-01xx.
  Plus LOCAL-ONLY PATHS — a tracked path matching a `path` row, or the private path list
  ($CC_PRIVATE_DIR/public-projection/paths-remove.txt).

MODES
  --own-range <range>   the ship gate: scan only lines and paths the range ADDS (own-scope — a
                        sibling's pre-existing text is not this land's to answer for)
  --tree <ref>          every blob of one tree (the "0 hits on origin/main" proof)
  --history <ref>       every blob, commit message and author/committer ident reachable from <ref>
                        (the projection verifier)
  --selftest            plant each finding class in a scratch repo and require the verdict to flip

Options: --repo DIR (default: cwd's toplevel) · --map FILE · --paths FILE · --conf FILE ·
         --max-findings N (default 50 printed)
Exit: 0 clean · 1 findings · 2 NON-VERDICT (map unreadable, git failed, bad args). A 2 is never a
pass: without the private map on this machine the gate cannot know what it is looking for.
"""

from __future__ import annotations

import argparse
import fnmatch
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
DEFAULT_PRIVATE = os.environ.get("CC_PRIVATE_DIR") or os.path.expanduser(
    "~/Development/claude-private"
)

PHONE_RE = re.compile(
    rb"(?:tel:\+?1?\d{10}\b"
    rb"|\+1[ .-]?\(?\d{3}\)?[ .-]?\d{3}[ .-]?\d{4}\b"
    rb"|\(\d{3}\) ?\d{3}-\d{4}\b"
    rb"|\b\d{3}[.-]\d{3}[.-]\d{4}\b(?=[^\d.-]|$))"
)
def phone_allowed(m: bytes) -> bool:
    """Fictional numbers never count: area code 555, or exchange 555 with line 01xx (the range
    reserved for fiction). ONE rule for both scan paths — they disagreed once, and the lint then
    convicted its own clean control on the ripgrep path only."""
    d = re.sub(rb"\D", b"", m)
    if len(d) == 11 and d.startswith(b"1"):
        d = d[1:]
    if len(d) == 7:
        return d.startswith(b"55501")
    return len(d) == 10 and (d[:3] == b"555" or (d[3:6] == b"555" and d[6:8] == b"01"))


EMAIL_RE = re.compile(
    rb"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}"
)


class NonVerdict(Exception):
    pass


def git(repo: str, *args: str, input_bytes: bytes | None = None) -> bytes:
    p = subprocess.run(
        ["git", "-C", repo, *args], input=input_bytes, capture_output=True
    )
    if p.returncode != 0:
        raise NonVerdict(
            f"git {' '.join(args[:3])} failed: {p.stderr.decode(errors='replace').strip()[:200]}"
        )
    return p.stdout


# ── rule loading ──────────────────────────────────────────────────────────────────────────────
def _scoped(pat: str) -> str:
    """A leading global inline flag (?i) becomes a scoped group, so patterns can be alternated."""
    m = re.match(r"^\(\?([aiLmsux]+)\)", pat)
    return f"(?{m.group(1)}:{pat[m.end() :]})" if m else f"(?:{pat})"


def load_map(path: str) -> tuple[re.Pattern[bytes] | None, list[str], list[str]]:
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError as e:
        raise NonVerdict(f"private redaction map unreadable: {path} ({e.strerror})")
    parts, literals, regexes = [], [], []
    for ln in lines:
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        lhs = ln.split("==>", 1)[0]
        if lhs.startswith("regex:"):
            parts.append(_scoped(lhs[len("regex:") :]))
            regexes.append(parts[-1])
        elif lhs.startswith("glob:"):
            parts.append(
                _scoped(fnmatch.translate(lhs[len("glob:") :]).replace(r"\Z", ""))
            )
            regexes.append(parts[-1])
        else:
            if lhs.startswith("literal:"):
                lhs = lhs[len("literal:") :]
            parts.append(re.escape(lhs))
            literals.append(lhs)
    if not parts:
        return None, [], []
    try:
        return re.compile("|".join(parts).encode()), literals, regexes
    except re.error as e:
        raise NonVerdict(f"private redaction map does not compile: {e}")


def load_conf(path: str) -> tuple[list[str], re.Pattern[bytes]]:
    globs, emails = [], []
    try:
        for ln in open(path, encoding="utf-8"):
            ln = ln.strip()
            if not ln or ln.startswith("#"):
                continue
            kind, _, val = ln.partition(" ")
            val = val.strip()
            if kind == "path":
                globs.append(val)
            elif kind == "email":
                emails.append(val)
            else:
                raise NonVerdict(f"{path}: unknown directive {kind!r}")
    except OSError as e:
        raise NonVerdict(f"conf unreadable: {path} ({e.strerror})")
    allow = (
        re.compile(("(?i)^(?:" + "|".join(emails) + ")$").encode())
        if emails
        else re.compile(b"(?!)")
    )
    return globs, allow


def load_paths(path: str) -> list[str]:
    try:
        return [
            ln.strip()
            for ln in open(path, encoding="utf-8")
            if ln.strip() and not ln.lstrip().startswith("#")
        ]
    except FileNotFoundError:
        return []
    except OSError as e:
        raise NonVerdict(f"private path list unreadable: {path} ({e.strerror})")


class Rules:
    def __init__(self, args: argparse.Namespace):
        priv = args.private_dir
        self.map, self.map_literals, self.map_regexes = load_map(
            args.map or os.path.join(priv, "public-projection", "replace-text.txt")
        )
        self.globs, self.email_allow = load_conf(
            args.conf or os.path.join(HERE, "..", "config", "public-hygiene.conf")
        )
        self.globs += load_paths(
            args.paths or os.path.join(priv, "public-projection", "paths-remove.txt")
        )

    def path_hit(self, path: str) -> str | None:
        for g in self.globs:
            if g.endswith("/"):
                if path.startswith(g) or path == g.rstrip("/"):
                    return g
            elif fnmatch.fnmatchcase(path, g) or path == g:
                return g
        if self.map is not None and self.map.search(path.encode()):
            return "identifier in path"
        return None

    def text_hits(self, data: bytes) -> list[tuple[str, bytes]]:
        out = []
        if self.map is not None:
            out += [("identifier", m.group(0)) for m in self.map.finditer(data)]
        for m in EMAIL_RE.finditer(data):
            if not self.email_allow.match(m.group(0)):
                out.append(("email", m.group(0)))
        out += [
            ("phone", m.group(0))
            for m in PHONE_RE.finditer(data)
            if not phone_allowed(m.group(0))
        ]
        return out


# ── modes ─────────────────────────────────────────────────────────────────────────────────────
def is_binary(data: bytes) -> bool:
    return b"\0" in data[:8000]


def report(findings: list[str], limit: int) -> int:
    for f in findings[:limit]:
        print(f)
    if len(findings) > limit:
        print(f"… and {len(findings) - limit} more")
    return 1 if findings else 0


def mode_own_range(repo: str, rng: str, rules: Rules) -> list[str]:
    findings = []
    added = (
        git(repo, "diff", "--name-only", "--diff-filter=AR", rng).decode().splitlines()
    )
    for p in added:
        why = rules.path_hit(p)
        if why:
            findings.append(f"PATH  {p}  ({why})")
    diff = git(repo, "diff", "-U0", "--no-color", "--no-ext-diff", rng)
    cur = None
    for line in diff.split(b"\n"):
        if line.startswith(b"+++ "):
            cur = (
                line[6:].decode(errors="replace")
                if line.startswith(b"+++ b/")
                else None
            )
        elif line.startswith(b"+") and not line.startswith(b"+++") and cur:
            for kind, hit in rules.text_hits(line[1:]):
                findings.append(
                    f"{kind.upper():5} {cur}: {hit.decode(errors='replace')}"
                )
    return findings


def _scan_blobs(repo: str, entries: list[tuple[str, str]], rules: Rules) -> list[str]:
    """entries: (blob sha, path) — each unique blob scanned once, reported under its first path."""
    findings, seen = [], {}
    for sha, path in entries:
        seen.setdefault(sha, path)
    if not seen:
        return findings
    shas = list(seen)
    if len(shas) > 200 and shutil.which("rg") and not os.environ.get("PUBLIC_HYGIENE_NO_RG"):
        return _scan_blobs_rg(repo, shas, seen, rules)
    out = git(
        repo, "cat-file", "--batch", input_bytes=("\n".join(shas) + "\n").encode()
    )
    i = 0
    for sha in shas:
        nl = out.index(b"\n", i)
        header = out[i:nl].split()
        size = int(header[2])
        data = out[nl + 1 : nl + 1 + size]
        i = nl + 1 + size + 1
        if is_binary(data):
            continue
        for kind, hit in rules.text_hits(data):
            findings.append(
                f"{kind.upper():5} {seen[sha]}: {hit.decode(errors='replace')}"
            )
    return findings


RG_PHONE = (r"tel:\+?1?[0-9]{10}\b|\+1[ .-]?\(?[0-9]{3}\)?[ .-]?[0-9]{3}[ .-]?[0-9]{4}\b"
            r"|\([0-9]{3}\) ?[0-9]{3}-[0-9]{4}\b|\b[0-9]{3}[.-][0-9]{3}[.-][0-9]{4}\b")


def _scan_blobs_rg(repo: str, shas: list[str], seen: dict[str, str], rules: Rules) -> list[str]:
    """Same verdict as the Python scan, at ripgrep speed (~1.3 GB of history blobs in seconds
    instead of minutes): export the TEXT blobs (same 8 KiB NUL test as filter-repo), then one rg
    pass per arm. Map regex rules, if any, still run in Python — rg's dialect differs."""
    findings: list[str] = []
    with tempfile.TemporaryDirectory() as d:
        bdir = os.path.join(d, "b")
        os.makedirs(bdir)
        out = git(repo, "cat-file", "--batch", input_bytes=("\n".join(shas) + "\n").encode())
        i, written = 0, []
        for sha in shas:
            nl = out.index(b"\n", i)
            size = int(out[i:nl].split()[2])
            data = out[nl + 1 : nl + 1 + size]
            i = nl + 1 + size + 1
            if is_binary(data):
                continue
            with open(os.path.join(bdir, sha), "wb") as fh:
                fh.write(data)
            written.append(sha)

        def rg(args: list[str]) -> list[tuple[str, bytes]]:
            p = subprocess.run(["rg", "-o", "-a", "-N", "--no-heading", "--with-filename", "--null",
                                "--no-ignore", "--hidden", *args, bdir], capture_output=True)
            if p.returncode not in (0, 1):
                raise NonVerdict(f"rg failed: {p.stderr.decode(errors='replace')[:200]}")
            res = []
            for line in p.stdout.split(b"\n"):
                if b"\0" in line:
                    f, _, m = line.partition(b"\0")
                    res.append((os.path.basename(f.decode()), m))
            return res

        if rules.map_literals:
            lit = os.path.join(d, "lits.txt")
            with open(lit, "wb") as fh:
                fh.write(("\n".join(rules.map_literals) + "\n").encode())
            findings += [f"IDENTIFIER {seen[s]}: {m.decode(errors='replace')}" for s, m in rg(["-F", "-f", lit])]
        findings += [f"EMAIL {seen[s]}: {m.decode(errors='replace')}"
                     for s, m in rg(["-e", EMAIL_RE.pattern.decode()]) if not rules.email_allow.match(m)]
        findings += [f"PHONE {seen[s]}: {m.decode(errors='replace')}"
                     for s, m in rg(["-e", RG_PHONE]) if not phone_allowed(m)]
        if rules.map_regexes:
            rx = re.compile("|".join(rules.map_regexes).encode())
            for sha in written:
                with open(os.path.join(bdir, sha), "rb") as fh:
                    data = fh.read()
                findings += [f"IDENTIFIER {seen[sha]}: {m.group(0).decode(errors='replace')}" for m in rx.finditer(data)]
    return findings


def mode_tree(repo: str, ref: str, rules: Rules) -> list[str]:
    findings, entries = [], []
    for line in git(repo, "ls-tree", "-r", "-z", "--full-tree", ref).split(b"\0"):
        if not line:
            continue
        meta, path = line.split(b"\t", 1)
        _mode, typ, sha = meta.split()
        p = path.decode(errors="replace")
        why = rules.path_hit(p)
        if why:
            findings.append(f"PATH  {p}  ({why})")
        if typ == b"blob":
            entries.append((sha.decode(), p))
    return findings + _scan_blobs(repo, entries, rules)


def mode_history(repo: str, ref: str, rules: Rules) -> list[str]:
    findings, entries, paths = [], [], set()
    for line in (
        git(repo, "rev-list", "--objects", ref).decode(errors="replace").splitlines()
    ):
        sha, _, path = line.partition(" ")
        if path:
            entries.append((sha, path))
    # PATHS from the log, not from rev-list: rev-list names each object once, under the first path
    # it meets, so identical bytes at a second (local-only) path would be invisible there.
    log_paths = git(
        repo,
        "-c",
        "core.quotepath=off",
        "log",
        "--format=",
        "--name-only",
        "--no-renames",
        ref,
    )
    paths.update(p for p in log_paths.decode(errors="replace").splitlines() if p)
    for p in sorted(paths):
        why = rules.path_hit(p)
        if why:
            findings.append(f"PATH  {p}  ({why}, somewhere in history)")
    types = (
        git(
            repo,
            "cat-file",
            "--batch-check=%(objectname) %(objecttype)",
            input_bytes=("\n".join(s for s, _ in entries) + "\n").encode(),
        )
        .decode()
        .split("\n")
    )
    blobs = {ln.split()[0] for ln in types if ln.endswith(" blob")}
    findings += _scan_blobs(repo, [(s, p) for s, p in entries if s in blobs], rules)
    log = git(repo, "log", "--format=%H%x00%an <%ae>%x00%cn <%ce>%x00%B%x1e", ref)
    for rec in log.split(b"\x1e"):
        rec = rec.strip(b"\n")
        if not rec:
            continue
        sha, author, committer, body = (rec.split(b"\0") + [b"", b"", b""])[:4]
        for label, blob in (
            ("author", author),
            ("committer", committer),
            ("message", body),
        ):
            for kind, hit in rules.text_hits(blob):
                findings.append(
                    f"{kind.upper():5} commit {sha[:10].decode()} {label}: {hit.decode(errors='replace')}"
                )
    return findings


# ── selftest ──────────────────────────────────────────────────────────────────────────────────
def selftest() -> int:
    """Each arm must FLIP the verdict on a planted fixture and stay clean on its control."""
    with tempfile.TemporaryDirectory() as d:
        repo = os.path.join(d, "r")
        os.makedirs(repo)
        env_git = [
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@example.invalid",
            "-c",
            "commit.gpgsign=false",
        ]
        run = lambda *a: subprocess.run(
            ["git", "-C", repo, *a], capture_output=True, check=True
        )  # noqa: E731
        run("init", "-q")
        run(*env_git, "commit", "-q", "--allow-empty", "-m", "base")
        mp = os.path.join(d, "map.txt")
        with open(mp, "w") as fh:
            fh.write(
                "regex:(?i)secret\\.person@corp\\.example==>x@example.com\nTopSecretName==>a name\n"
            )
        conf = os.path.join(d, "conf")
        with open(conf, "w") as fh:
            fh.write("path local-only/*\nemail .*@example\\.com\n")
        paths = os.path.join(d, "paths.txt")
        with open(paths, "w") as fh:
            fh.write("docs/private-matter.md\n")
        ns = argparse.Namespace(private_dir=d, map=mp, conf=conf, paths=paths)
        rules = Rules(ns)
        cases = [
            (
                "clean control",
                {"a.txt": "hello user@example.com, call 555-0100 or +1 555-010-0123\n"},
                False,
            ),
            ("map literal", {"a.txt": "ask TopSecretName\n"}, True),
            (
                "map regex, other case",
                {"a.txt": "mail Secret.Person@CORP.example\n"},
                True,
            ),
            ("unlisted e-mail", {"a.txt": "write to someone@realmail.test\n"}, True),
            ("phone", {"a.txt": "call (303) 867-" + "5309\n"}, True),
            ("local-only path", {"local-only/x.md": "fine text\n"}, True),
            ("private path list", {"docs/private-matter.md": "fine text\n"}, True),
            ("identifier in a path", {"docs/TopSecretName-notes.md": "fine\n"}, True),
        ]
        bad = 0
        for name, files, want in cases:
            base = git(repo, "rev-parse", "HEAD").decode().strip()
            for rel, body in files.items():
                full = os.path.join(repo, rel)
                os.makedirs(os.path.dirname(full), exist_ok=True)
                with open(full, "w") as fh:
                    fh.write(body)
            run("add", "-A")
            run(*env_git, "commit", "-q", "-m", name)
            got = bool(mode_own_range(repo, f"{base}..HEAD", rules))
            got_tree = bool(mode_tree(repo, "HEAD", rules))
            if got != want:
                print(
                    f"selftest FAIL: {name}: own-range verdict {got}, want {want}",
                    file=sys.stderr,
                )
                bad += 1
            run("rm", "-q", "-r", "--", *files)
            run(*env_git, "commit", "-q", "-m", f"undo {name}")
            if want and not got_tree:
                print(f"selftest FAIL: {name}: --tree did not see it", file=sys.stderr)
                bad += 1
        # history arm: every case above is now only in HISTORY, and must still be seen there
        h = mode_history(repo, "HEAD", rules)
        for needle in (
            "TopSecretName",
            "someone@realmail.test",
            "local-only/x.md",
            "867-" + "5309",
        ):
            if not any(needle in f for f in h):
                print(f"selftest FAIL: --history missed {needle}", file=sys.stderr)
                bad += 1
        if bad:
            return 1
        print("selftest: ok (8 own-range cases, tree + history arms)")
        return 0


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--own-range")
    g.add_argument("--tree")
    g.add_argument("--history")
    g.add_argument("--selftest", action="store_true")
    ap.add_argument("--repo")
    ap.add_argument("--map")
    ap.add_argument("--paths")
    ap.add_argument("--conf")
    ap.add_argument("--private-dir", default=DEFAULT_PRIVATE)
    ap.add_argument("--max-findings", type=int, default=50)
    ap.add_argument("--allow-no-map", action="store_true",
                    help="with no private map, run the e-mail/phone/path arms and SAY the identifier arm is off")
    try:
        args = ap.parse_args()
    except SystemExit as e:
        return 2 if e.code else 0
    if args.selftest:
        try:
            return selftest()
        except (NonVerdict, subprocess.CalledProcessError) as e:
            print(f"public-hygiene-lint: selftest NON-VERDICT: {e}", file=sys.stderr)
            return 2
    try:
        repo = (
            args.repo
            or git(os.getcwd(), "rev-parse", "--show-toplevel").decode().strip()
        )
        map_path = args.map or os.path.join(args.private_dir, "public-projection", "replace-text.txt")
        if args.allow_no_map and not os.path.exists(map_path):
            print(f"public-hygiene-lint: advisory — identifier arm DISARMED (no private map at {map_path});"
                  " e-mail, phone and local-only-path arms still run", file=sys.stderr)
            empty = os.path.join(tempfile.mkdtemp(), "empty-map.txt")
            open(empty, "w").close()
            args.map = empty
        rules = Rules(args)
        if rules.map is None and not args.allow_no_map:
            raise NonVerdict(
                "private redaction map is empty — the identifier arm would be blind"
            )
        if args.own_range:
            findings = mode_own_range(repo, args.own_range, rules)
            scope = f"lines and paths added by {args.own_range}"
        elif args.tree:
            findings = mode_tree(repo, args.tree, rules)
            scope = f"every path and text blob of {args.tree}"
        else:
            findings = mode_history(repo, args.history, rules)
            scope = f"every path, text blob, commit message and ident reachable from {args.history}"
    except NonVerdict as e:
        print(f"public-hygiene-lint: NON-VERDICT — {e}", file=sys.stderr)
        return 2
    rc = report(findings, args.max_findings)
    print(f"public-hygiene-lint: {len(findings)} finding(s) over {scope}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
