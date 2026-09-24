#!/usr/bin/env python3
"""of_scan.py — per-tool_result format-overhead scan (output-formats measure).

Streams every transcript file listed in extract.sqlite's `ctx` table (same population as the
extract: window ts >= 2026-09-09T00:00:00Z) and, for every model-visible tool_result block,
measures the bytes (characters) spent on per-line / per-item overhead patterns:

  ansi_csi     ESC [ ... final-byte  (SGR colour, cursor moves)
  ansi_osc     ESC ] ... BEL|ST       (hyperlinks, titles)
  ansi_other   any other ESC-introduced sequence / lone ESC
  cr_over      carriage-return overwritten text (bytes before the last \r on a line; invisible on a TTY)
  progress     lines that look like progress bars / spinner frames
  box_chars    U+2500-U+259F box-drawing / block characters (all occurrences)
  banner_lines lines made >=80% of rule characters (─━═=-*#~_ and box chars), len>=10
  abs_home     occurrences of '/Users/chrisren/' (count and bytes of the literal prefix)
  root_prefix  bytes of repo-root / worktree-root / config-dir absolute prefixes
               (/Users/chrisren/Development/<repo>/, .../.worktrees/<wt>/, /Users/chrisren/.claude*/)
               — what cwd-relative or ~-relative rendering would remove
  json_*       for results that parse as JSON: total, indentation whitespace, key bytes,
               repeated-key bytes (keys after their first occurrence)
  readnum      Read results: line-number prefix bytes ('   12\t' / '12→'); lines numbered
  sysrem       <system-reminder>...</system-reminder> blocks appended inside tool_result text
  persisted    Claude Code's <persisted-output> wrapper present (Bash/MCP over the inline cap)

Bash commands are classified by program (see program_of()). Output: an sqlite file of per-result
rows (no content), plus optional token-probe samples written OUTSIDE the repo (/tmp/ofprobe).

Run:  cd /tmp && nice -n 10 python3 of_scan.py [--workers 4] [--samples /tmp/ofprobe/samples]
"""

import argparse, json, os, re, sqlite3, sys, random, hashlib
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(HERE)
EXTRACT = os.path.join(BASE, "data", "extract.sqlite")
OUT = os.path.join(BASE, "data", "output_formats.sqlite")
SINCE = "2026-09-09T00:00:00Z"

CSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
OSC = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")
ESC_ANY = re.compile(r"\x1b[@-Z\\-_]|\x1b")
BOX = re.compile(r"[─-▟]")
RULE_LINE = re.compile(r"^[\s─-▟=\-\*#~_\.·•]+$")
PROGRESS = re.compile(
    r"([█▉▊▋▌▍▎▏░▒▓■□#=]{6,}.*\d{1,3}(\.\d+)?%)"
    r"|(\d{1,3}(\.\d+)?%\s*[\|\[][█#=\->\s\.]{6,}[\|\]])"
    r"|(^\s*[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏◐◓◑◒|/\\-]\s+\S.*\.\.\.$)"
    r"|(\[\s*[=#>\-\.\s]{8,}\])"
)
HOME_P = "/Users/chrisren/"
ROOT = re.compile(
    r"/Users/chrisren/(?:Development/\.worktrees/[^/\s'\"`]+/|Development/[^/\s'\"`]+/|\.claude[a-z\-]*/|\.reso/)"
    r"|/private/tmp/claude-501/[^/\s'\"`]+/"
)
SYSREM = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
READNUM = re.compile(r"^( *\d+)(\t|→)", re.M)
KEYRE = re.compile(r'"((?:[^"\\]|\\.)*)"\s*:')
INDENT = re.compile(r"\n[ \t]+")
PERSIST = "<persisted-output>"
CWDRESET = re.compile(r"^Shell cwd was reset to .*$", re.M)
PERMDENY = re.compile(r"^Permission for this action was denied by the Claude Code auto mode classifier\..*$", re.M)
PADWS = re.compile(r"(?<=\S) {3,}(?=\S)| +$", re.M)
WARNLN = re.compile(r"^\s*(?:\u26a0|WARNING|WARN\b|warning:).*$", re.M)
WSREM = "REMINDER: You MUST include the sources above in your response"
GREPP = re.compile(r"^([^\s:]+/[^\s:]+):(\d+[:\-])?")


def grep_reppath(text):
    n = 0
    prev = None
    for ln in text.split("\n"):
        m = GREPP.match(ln)
        if m:
            p = m.group(1)
            if p == prev:
                n += len(p) + 1
            prev = p
        else:
            prev = None
    return n

ENVASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=(\"[^\"]*\"|'[^']*'|\S*)$")
WRAPPERS = {
    "nice",
    "timeout",
    "gtimeout",
    "env",
    "time",
    "command",
    "exec",
    "caffeinate",
    "nohup",
    "sudo",
    "taskpolicy",
}


def program_of(cmd):
    """Classify a Bash command string into a program label (first simple command of the line)."""
    s = cmd.strip()
    # Skip setup statements (cd, export, set, VAR=... assignments incl. VAR=$(...), comments,
    # mkdir -p) that precede the real program. Statements are split on newlines and on
    # quote-aware ';' / '&&' / '||' tokens.
    SKIP = {"cd", "export", "set", "unset", "local", "trap", "shopt", "umask", "true", ":",
            "then", "do", "fi", "done", "else", "{", "}", "source", "."}
    pick = None
    for line in s.split("\n"):
        ltoks = re.findall(r"(?:[^\s;\"'|&]+|\"[^\"]*\"|'[^']*'|&(?!&)|\|(?!\|))+|;|&&|\|\|", line)
        stmts, cur = [], []
        for tk in ltoks:
            if tk in (";", "&&", "||"):
                stmts.append(cur); cur = []
            else:
                cur.append(tk)
        stmts.append(cur)
        for st in stmts:
            if not st or st[0].startswith("#"):
                continue
            if st[0] in SKIP:
                continue
            if st[0] == "mkdir" and len(s) > len(" ".join(st)) + 5:
                continue
            j = 0
            while j < len(st) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", st[j]):
                j += 1
            if j == len(st) or (j > 0 and "$(" in st[j - 1]):
                continue
            pick = " ".join(st[j:])
            break
        if pick:
            break
    s = pick or ""
    toks = re.findall(r"\"[^\"]*\"|'[^']*'|\S+", s)
    i = 0
    while i < len(toks):
        t = toks[i]
        if ENVASSIGN.match(t):
            i += 1
            continue
        b = os.path.basename(t)
        if b in WRAPPERS:
            i += 1
            # skip wrapper options/args
            while i < len(toks) and (
                toks[i].startswith("-") or re.match(r"^\d+[smh]?$", toks[i])
            ):
                if toks[i] in ("-n", "-c", "-k", "-s") and i + 1 < len(toks):
                    i += 2
                else:
                    i += 1
            continue
        break
    if i >= len(toks):
        return "(empty)"
    t = toks[i].strip("\"'")
    b = os.path.basename(t)
    if b in ("for", "while", "until", "if", "case"):
        return "(" + b + "-loop)"
    nxt = [x.strip("\"'") for x in toks[i + 1 : i + 4]]
    if b in ("bash", "sh", "zsh") and nxt:
        k = 0
        while k < len(nxt) and nxt[k].startswith("-"):
            k += 1
        if k < len(nxt):
            if nxt[k - 1 : k] == ["-c"] if k > 0 else False:
                return b + " -c"
            return os.path.basename(nxt[k])
        return b
    if b in ("python3", "python", "node", "bun", "uv", "npx", "pnpm", "npm") and nxt:
        if b in ("pnpm", "npm", "npx", "uv"):
            return b + " " + nxt[0]
        if nxt[0] in ("-c", "-"):
            return b + " -c"
        if nxt[0] == "-m" and len(nxt) > 1:
            return b + " -m " + nxt[1]
        return os.path.basename(nxt[0]) if not nxt[0].startswith("-") else b
    if b == "git" and nxt:
        k = 0
        while k < len(nxt) and nxt[k].startswith("-"):
            k += 2 if nxt[k] == "-C" else 1
        return "git " + (nxt[k] if k < len(nxt) else "")
    if (
        b
        in (
            "gh",
            "sqlite3",
            "jq",
            "cargo",
            "go",
            "docker",
            "kubectl",
            "aws",
            "gcloud",
            "fly",
            "flyctl",
            "turso",
        )
        and nxt
    ):
        return b + ("" if nxt[0].startswith("-") else " " + nxt[0])
    return b


def rs_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        out = []
        for b in content:
            if isinstance(b, dict) and b.get("type") == "text":
                out.append(b.get("text") or "")
        return "".join(out)
    return ""


def cr_over(text):
    n = 0
    if "\r" not in text:
        return 0
    for line in text.split("\n"):
        if "\r" in line:
            j = line.rfind("\r")
            if (
                j < len(line) - 1
            ):  # text follows the last \r: everything before it was overwritten
                n += j + 1
            else:
                n += 1  # trailing \r (CRLF) — 1 byte of overhead
    return n


def json_stats(text):
    s = text.strip()
    if not s or s[0] not in "[{" or len(s) < 20:
        return None
    try:
        obj = json.loads(s)
    except Exception:
        return None
    ind = sum(len(m.group(0)) - 1 for m in INDENT.finditer(s))
    keys = KEYRE.findall(s)
    kb = 0
    rep = 0
    seen = set()
    for k in keys:
        L = len(k) + 3  # quotes + colon
        kb += L
        if k in seen:
            rep += L
        else:
            seen.add(k)
    try:
        mini = len(json.dumps(obj, separators=(",", ":"), ensure_ascii=False))
    except Exception:
        mini = len(s)
    return (len(s), ind, kb, rep, mini)


COLS = [
    "file",
    "tool_use_id",
    "ts",
    "tool",
    "program",
    "cmd",
    "chars",
    "lines",
    "ansi_csi",
    "ansi_csi_n",
    "ansi_osc",
    "ansi_other",
    "cr_over",
    "progress",
    "box_chars",
    "banner_lines",
    "abs_home_n",
    "root_prefix",
    "root_prefix_n",
    "json_chars",
    "json_indent",
    "json_keys",
    "json_rep_keys",
    "json_mini",
    "readnum",
    "readnum_lines",
    "sysrem",
    "sysrem_n",
    "sysrem_h",
    "persisted",
    "is_error",
    "cwd_reset",
    "perm_denied",
    "pad_ws",
    "warn_lines",
    "ws_reminder",
    "grep_reppath",
]


def scan_file(args):
    fp, sample_dir, want_samples = args
    tool = {}
    rows = []
    samples = {}
    try:
        fh = open(fp, "rb")
    except OSError:
        return rows, samples
    with fh:
        for raw in fh:
            if b'"tool_use"' not in raw and b'"tool_result"' not in raw:
                continue
            try:
                r = json.loads(raw)
            except Exception:
                continue
            if not isinstance(r, dict):
                continue
            t = r.get("type")
            m = r.get("message")
            if not isinstance(m, dict):
                continue
            c = m.get("content")
            if not isinstance(c, list):
                continue
            if t == "assistant":
                for b in c:
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        inp = b.get("input") if isinstance(b.get("input"), dict) else {}
                        nm = b.get("name") or ""
                        cmd = str(inp.get("command") or "") if nm == "Bash" else ""
                        tool[b.get("id")] = (nm, cmd)
                continue
            if t != "user":
                continue
            ts = r.get("timestamp") or ""
            if ts < SINCE:
                continue
            for b in c:
                if not isinstance(b, dict) or b.get("type") != "tool_result":
                    continue
                tid = b.get("tool_use_id")
                nm, cmd = tool.get(tid, ("?", ""))
                text = rs_text(b.get("content"))
                prog = program_of(cmd) if nm == "Bash" else ""
                a_csi = CSI.findall(text) if "\x1b" in text else []
                csi_b = sum(len(x) for x in a_csi)
                osc_b = sum(len(x) for x in OSC.findall(text)) if "\x1b" in text else 0
                other = 0
                if "\x1b" in text:
                    t2 = OSC.sub("", CSI.sub("", text))
                    other = sum(len(x) for x in ESC_ANY.findall(t2))
                lines = text.split("\n")
                prog_b = 0
                ban_b = 0
                for ln in lines:
                    if len(ln) >= 10 and RULE_LINE.match(ln) and len(ln.strip()) >= 10:
                        ban_b += len(ln) + 1
                    elif (
                        "%" in ln or "[" in ln or "█" in ln or "..." in ln
                    ) and PROGRESS.search(ln):
                        prog_b += len(ln) + 1
                boxc = (
                    len(BOX.findall(text))
                    if any(0x2500 <= ord(ch) <= 0x259F for ch in text[:0])
                    or re.search(r"[─-▟]", text)
                    else 0
                )
                homen = text.count(HOME_P)
                roots = (
                    ROOT.findall(text)
                    if homen or "/private/tmp/claude-501/" in text
                    else []
                )
                js = json_stats(text) if nm != "Read" else None
                rn = rnl = 0
                if nm == "Read":
                    ms = READNUM.findall(text)
                    rnl = len(ms)
                    rn = sum(len(a) + 1 for a, _ in ms)
                srs = SYSREM.findall(text) if "<system-reminder>" in text else []
                srh = ""
                if srs:
                    srh = hashlib.md5(
                        re.sub(r"\d+", "N", srs[0][:400]).encode()
                    ).hexdigest()[:10]
                row = (
                    fp,
                    tid,
                    ts,
                    nm,
                    prog,
                    cmd[:300],
                    len(text),
                    len(lines),
                    csi_b,
                    len(a_csi),
                    osc_b,
                    other,
                    cr_over(text),
                    prog_b,
                    boxc,
                    ban_b,
                    homen,
                    sum(len(x) for x in roots),
                    len(roots),
                    js[0] if js else 0,
                    js[1] if js else 0,
                    js[2] if js else 0,
                    js[3] if js else 0,
                    js[4] if js else 0,
                    rn,
                    rnl,
                    sum(len(x) for x in srs),
                    len(srs),
                    srh,
                    1 if PERSIST in text else 0,
                    1 if b.get("is_error") else 0,
                    sum(len(z) + 1 for z in CWDRESET.findall(text)) if "Shell cwd was reset" in text else 0,
                    sum(len(z) + 1 for z in PERMDENY.findall(text)) if "auto mode classifier" in text else 0,
                    sum(len(z) for z in PADWS.findall(text)) if "   " in text or " \n" in text else 0,
                    sum(len(z) + 1 for z in WARNLN.findall(text)),
                    (len(text) - text.find(WSREM)) if WSREM in text else 0,
                    grep_reppath(text) if ":" in text else 0,
                )
                rows.append(row)
                if want_samples and len(text) >= 200:
                    keys = []
                    if csi_b > 50:
                        keys.append("ansi")
                    if boxc > 30 or ban_b > 60:
                        keys.append("box")
                    if len(roots) >= 5:
                        keys.append("paths")
                    if js and js[0] > 500:
                        keys.append("json")
                    if rnl >= 20:
                        keys.append("readnum")
                    if nm == "Bash" and not keys:
                        keys.append("bash_plain")
                    if prog_b > 100 or cr_over(text) > 100:
                        keys.append("progress")
                    for k in keys:
                        samples.setdefault(k, []).append(text[:12000])
    return rows, samples


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--samples", default="/tmp/ofprobe/samples")
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()
    x = sqlite3.connect(EXTRACT)
    files = [r[0] for r in x.execute("SELECT file FROM ctx ORDER BY file")]
    if a.limit:
        files = files[: a.limit]
    random.seed(7)
    samp_files = set(random.sample(files, min(600, len(files))))
    if os.path.exists(OUT + ".tmp"):
        os.remove(OUT + ".tmp")
    db = sqlite3.connect(OUT + ".tmp")
    db.execute("CREATE TABLE tr (" + ",".join(COLS) + ")")
    allsamp = {}
    n = 0
    with Pool(a.workers) as p:
        for rows, samples in p.imap_unordered(
            scan_file, [(f, a.samples, f in samp_files) for f in files], chunksize=8
        ):
            db.executemany(
                "INSERT INTO tr VALUES (" + ",".join("?" * len(COLS)) + ")", rows
            )
            for k, v in samples.items():
                allsamp.setdefault(k, []).extend(v)
            n += 1
            if n % 500 == 0:
                print("files", n, file=sys.stderr)
    db.execute("CREATE INDEX tr_ft ON tr(file, tool_use_id)")
    db.commit()
    db.close()
    os.replace(OUT + ".tmp", OUT)
    os.makedirs(a.samples, exist_ok=True)
    for k, v in allsamp.items():
        random.shuffle(v)
        with open(os.path.join(a.samples, k + ".json"), "w") as fh:
            json.dump(v[:400], fh)
    print(
        "done files=%d out=%s samples=%s"
        % (n, OUT, {k: len(v) for k, v in allsamp.items()})
    )


if __name__ == "__main__":
    main()
