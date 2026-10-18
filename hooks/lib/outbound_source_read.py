#!/usr/bin/env python3
"""outbound_source_read.py — did this turn hand over a drafted outbound message, and did the SAME
turn read the live medium that message is about?

The decision behind completion-assert.sh arm O (OUTBOUND SOURCE READ). Operator ruling 2026-10-18:
"It's a hard no for us drafting messages to people based off of some medium when we havent read
said medium." The incident: a first text to a landlord was drafted from our own research dossier
written the night before. It asked "Is it still available?", then "from what date?"; the live
Zillow listing said "Available now" the whole time and was read only after the operator objected
twice. The skill's prose rule ("read the thread first") already existed and did not fire, because
reading our own dossier FELT like reading the source. So the source has to be a TOOL, not a file
we wrote: this module counts only primary-source reads, and a Read of our notes is not one.

INPUTS. --transcript <jsonl> and --since <epoch seconds>: the start of the turn, which the caller
takes from hooks/lib/cc-interactive.sh ci_last_interactive_epoch (the "a human actually typed"
predicate, never session-writes.sh's boundary: a Stop-hook feedback re-prompt must not open a new
turn, or the block below would be satisfied by the model's own reply to it — lesson
two-turn-boundary-predicates in ~/Development/personal/docs/lessons).

A DRAFT WAS HANDED OVER when, in this turn's main-chain records:
  · an ms365 create-*-draft tool was called (create-draft-email, create-reply-draft, …), OR
  · the outbound-drafting skill was invoked somewhere in this SESSION, and this turn's assistant
    text holds a message body: a fenced or blockquoted block that opens the way a message opens
    (OPENER_RX: "Hi Sam,", "Thanks Sam,", "Alex — ", "Subject: ") or closes on the operator's
    sign-off, or a text whose first line is a greeting to a named person (the skill's own output
    format is bare sendable text, no fence). Nothing addressed TO the operator counts.
  Gated on the skill on purpose: greetings occur in ordinary prose and in quoted INBOUND messages,
  and a hook that cries wolf trains the model to route around it.

A LIVE READ happened when this turn made a call that succeeded (not is_error) and returned
something (not only "(no matches)" / "0 row(s)") to:
  · Bash whose clause verb is a message store in its THREAD form (msg with|sql, wa thread|recent|sql,
    tg thread|recent; a `search` is how you look for a medium, not a read of it), or zillow-listing,
    curl/wget with a non-local http(s) URL, agent-browser, cc-dia-act, dia-ax, cc-mail-images
    (wrappers such as `timeout N`, `env`, `agent-secrets run --` are looked through);
  · ms365 mail on the email hook's R4 terms (a received-mail list not scoped to drafts; a get whose
    result is not our own draft), or a PowerShell Graph GET of messages ; WebFetch / WebSearch ; a browser MCP (claude-in-chrome,
    chrome-devtools);
  · Read (or a Bash command naming a path) under a live-capture directory — ~/Documents/zillow-listings,
    ~/Documents/mail-images — of a file whose mtime is inside this turn, i.e. one a live tool wrote
    this turn (possibly from a subagent, whose records are not in this file).
  · an image the operator pasted into this turn's prompt (a screenshot of the medium).
  A Read of anything else — research notes, dossiers, plans, memory, STATE files — is NOT a read.

EXIT CODES. 0 nothing to do (no draft, or a draft with a live read) · 1 BLOCK (draft, no live
read; stdout is one JSON object naming what was seen) · 2 cannot tell (unreadable transcript).
`--json` prints the verdict object on every path.

Measurement mode (`--scan`) replays every human turn of a transcript and prints one verdict per
turn; it uses a local port of the same interactive predicate, for corpus measurement only.
"""

import json
import os
import re
import sys
from datetime import datetime

SKILL_NAME = "outbound-drafting"

LIVE_CMDS = {
    "msg",
    "wa",
    "tg",
    "zillow-listing",
    "curl",
    "wget",
    "agent-browser",
    "cc-dia-act",
    "dia-ax",
    "cc-mail-images",
}
# Clause prefixes that run another command: look through them to the real verb.
WRAPPERS = {
    "timeout",
    "gtimeout",
    "env",
    "command",
    "nice",
    "time",
    "caffeinate",
    "exec",
    "nohup",
}

LIVE_TOOL_RX = re.compile(
    r"^(WebFetch|WebSearch"
    r"|mcp__claude-in-chrome__.+|mcp__chrome-devtools[A-Za-z0-9_-]*__.+)$"
)
# Mail counts on the email hook's own terms (hooks/enforce-email-formatting.py R4): a LIST of
# received mail not scoped to drafts. Reading back your own draft is the blind read that let a
# 2026-08-25 dispute letter ship past an acknowledgement sitting unread in the inbox. A single
# get counts here too, because at Stop time its result is visible and can be checked for isDraft.
MS365_LIST_TOOLS = {
    "mcp__ms365__list-mail-messages",
    "mcp__ms365__list-mail-folder-messages",
    "mcp__ms365__list-mail-folder-messages-delta",
}
MS365_GET_TOOLS = {"mcp__ms365__get-mail-message", "mcp__ms365__get-mail-message-mime"}
_DRAFT_FILTER_RX = re.compile(r"isdraft\s+eq\s+true", re.I)
_IS_DRAFT_RESULT_RX = re.compile(r"[\"']?isDraft[\"']?\s*[:=]\s*[\"']?true", re.I)
# The business mailbox is read through PowerShell Graph (memory reference-ms365-two-mailboxes-login):
# a GET of messages that is not aimed at the drafts folder.
_PWSH_MAIL_RX = re.compile(
    r"(Invoke-MgGraphRequest\b(?=[^\n]*\bGET\b)[^\n]*/messages|Get-MgUserMessage|Get-MgUserMailFolderMessage)",
    re.I,
)


def ms365_read(name, inp, result):
    if name in MS365_LIST_TOOLS:
        folder = str(inp.get("mailFolderId", "")).strip().lower()
        if folder in ("drafts", "draftroot"):
            return False
        return not any(_DRAFT_FILTER_RX.search(str(inp.get(k, ""))) for k in ("filter", "search"))
    if name in MS365_GET_TOOLS:
        return not _IS_DRAFT_RESULT_RX.search(result or "")
    return False


def pwsh_mail_read(cmd):
    return any(
        _PWSH_MAIL_RX.search(ln) and not re.search(r"drafts|isDraft", ln, re.I)
        for ln in (cmd or "").split("\n")
    )


DRAFT_TOOL_RX = re.compile(
    r"^mcp__ms365__create-(draft-email|reply-draft|reply-all-draft|forward-draft)$"
)

# How a drafted message OPENS, at the start of a block. Measured against 676 turns of the 103 sessions
# that loaded the skill (2026-10-18): "Hi Sam," is the common shape, but real drafts also open
# "Thanks Sam, …", "Alex — being straight with you", "Totally understand, Sam.", "Hi, this is
# Chris Ren…" and "Subject: …". The operator is never the addressee: "Chris, call me anytime" is a
# QUOTED INBOUND message, and quoting the counterparty is reading them, not drafting to them.
_NAME = r"[A-Z][a-z][\w'’-]*"
OPENER_RX = re.compile(
    r"^\s*(?:"
    r"(?i:hi|hello|hey|hiya|dear|good\s+(?:morning|afternoon|evening))(?=[\s,!.—–-]|$)"
    r"|(?i:thanks|thank\s+you|thx)\b[^.!?\n]{0,20}?\b" + _NAME + r"[,.!—–]"
    r"|" + _NAME + r"(?:\s" + _NAME + r")?\s[—–]\s"
    r"|[^.!?\n]{0,40},\s" + _NAME + r"[.!,]"
    r"|Subject:\s"
    r")"
)
_TO_OPERATOR_RX = re.compile(r"^\s*(?:(?i:hi|hello|hey|hiya|dear|thanks|thank\s+you)[\s,!—–-]*)?Chris\b|,\s*Chris[.!,]")
SIGNOFF_RX = re.compile(
    r"^\s*(?:[-–—]\s*)?(?:Chris(?:\s+Ren)?\s*[.!]?|\S*(?:chris@reso\.gl|ren\.chris@)\S*)\s*$"
)
# The skill's own output format is bare sendable text, no fence: so an unfenced reply counts too,
# but only on the strictest opener (a greeting word), since prose of our own opens every other way.
GREET_RX = re.compile(r"^\s*(?i:hi|hello|hey|hiya|dear|good\s+(?:morning|afternoon|evening))\b[ \t,!]*" + _NAME)


def is_opener(line):
    return bool(OPENER_RX.match(line)) and not _TO_OPERATOR_RX.match(line)


FENCE_RX = re.compile(r"^\s*(```|~~~)")


def _ts(rec):
    t = rec.get("timestamp")
    if not isinstance(t, str):
        return None
    try:
        return int(datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp())
    except ValueError:
        return None


def _text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(
            b.get("text", "")
            for b in content
            if isinstance(b, dict) and b.get("type") == "text"
        )
    return ""


def load(path):
    recs = []
    with open(path, "rb") as fh:
        for raw in fh:
            try:
                r = json.loads(raw)
            except (ValueError, UnicodeDecodeError):
                continue
            if isinstance(r, dict):
                recs.append(r)
    return recs


def skill_invoked(recs):
    """The outbound-drafting skill was LOADED in this session (not merely mentioned in a brief)."""
    for r in recs:
        if r.get("isSidechain") is True:
            continue
        c = (r.get("message") or {}).get("content")
        if r.get("type") == "assistant" and isinstance(c, list):
            for b in c:
                if (
                    isinstance(b, dict)
                    and b.get("type") == "tool_use"
                    and b.get("name") == "Skill"
                ):
                    s = str((b.get("input") or {}).get("skill", ""))
                    if s == SKILL_NAME or s.endswith(":" + SKILL_NAME):
                        return True
        elif r.get("type") == "user":
            t = _text_of(c)
            if t.startswith("Base directory for this skill:") and t.split("\n", 1)[
                0
            ].rstrip("/").endswith("/" + SKILL_NAME):
                return True
            if "<command-name>/" + SKILL_NAME + "</command-name>" in t:
                return True
    return False


def _blocks(text):
    """Fenced blocks and blockquote runs, each as a list of its lines."""
    out, lines, i = [], text.split("\n"), 0
    while i < len(lines):
        m = FENCE_RX.match(lines[i])
        if m:
            fence, body, i = m.group(1), [], i + 1
            while i < len(lines) and not lines[i].strip().startswith(fence):
                body.append(lines[i])
                i += 1
            out.append(body)
            i += 1
            continue
        if lines[i].lstrip().startswith(">"):
            body = []
            while i < len(lines) and lines[i].lstrip().startswith(">"):
                body.append(re.sub(r"^\s*>\s?", "", lines[i]))
                i += 1
            out.append(body)
            continue
        i += 1
    return out


def find_draft(text, skill):
    """→ the draft's first line, or None. Without the skill only ms365 draft tools count."""
    if not skill:
        return None
    for body in _blocks(text):
        ne = [ln for ln in body if ln.strip()]
        if not ne:
            continue
        if is_opener(ne[0]) or (len(ne) >= 2 and SIGNOFF_RX.match(ne[-1])):
            return ne[0].strip()[:120]
    first = next((ln for ln in text.split("\n") if ln.strip()), "")
    if GREET_RX.match(first) and not _TO_OPERATOR_RX.match(first):
        return first.strip()[:120]
    return None


_SPLIT_RX = re.compile(r"\n|&&|\|\||;|\||\$\(|`|\(|\)")
_ASSIGN_RX = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=\S*$")
_KEYWORDS = {"then", "do", "else", "if", "elif", "while", "until", "!", "{"}


# A message store is READ only in its thread-reading form. `msg search "Elm"` returning
# "(no matches)" was the incident turn's only live call: a search is how you LOOK FOR a medium, and
# its empty answer is the evidence that the medium is somewhere else (here, the listing).
THREAD_SUBS = {
    "msg": {"with", "sql"},
    "wa": {"thread", "recent", "sql"},
    "tg": {"thread", "recent"},
}
_URL_RX = re.compile(r"https?://[^\s'\"`<>]+", re.I)
_LOCAL_URL_RX = re.compile(r"^https?://(localhost|127\.|0\.0\.0\.0|\[::1\])", re.I)


def _clause_verb(words):
    """→ index of the clause's real verb (keywords, env assignments and wrappers skipped)."""
    i = 0
    while i < len(words):
        tok = words[i]
        base = tok.rsplit("/", 1)[-1]
        if tok in _KEYWORDS or _ASSIGN_RX.match(tok):
            i += 1
        elif base in WRAPPERS:
            i += 1
            while i < len(words) and (
                words[i].startswith("-")
                or re.match(r"^\d+[smhd]?$", words[i])
                or _ASSIGN_RX.match(words[i])
            ):
                i += 1
        elif base == "agent-secrets" and i + 1 < len(words) and words[i + 1] == "run":
            i += 2
            while i < len(words) and words[i] != "--":
                i += 1
            i += 1
        else:
            return i
    return None


def bash_live_reads(cmd):
    """→ labels of the primary-source reads a Bash command makes (e.g. ["msg with"])."""
    out = []
    # URLs are read off the WHOLE command: a quoted User-Agent such as "Mozilla/5.0 (Macintosh; …)"
    # splits a curl clause at its parenthesis, which would strand the URL in a later fragment.
    urls = [u for u in _URL_RX.findall(cmd or "") if not _LOCAL_URL_RX.match(u)]
    for clause in _SPLIT_RX.split(cmd or ""):
        w = clause.split()
        i = _clause_verb(w)
        if i is None:
            continue
        base, rest = w[i].rsplit("/", 1)[-1], w[i + 1 :]
        if base not in LIVE_CMDS:
            continue
        if base in THREAD_SUBS:
            sub = next((a for a in rest if not a.startswith("-")), "")
            if sub in THREAD_SUBS[base]:
                out.append(base + " " + sub)
        elif base in ("curl", "wget"):
            if urls:
                out.append(base)
        else:
            out.append(base)
    return out


_EMPTY_LINE_RX = re.compile(
    r"^\s*(\(no matches\)|0 row\(s\)|-+|\[exited with code \d+\]|no results?\.?)?\s*$",
    re.I,
)


def result_empty(text):
    """A read that returned nothing read nothing: every line blank or a no-match marker."""
    return all(_EMPTY_LINE_RX.match(ln) for ln in (text or "").split("\n"))


LIVE_DIRS = ("~/Documents/zillow-listings", "~/Documents/mail-images")


def live_dirs():
    return [os.path.realpath(os.path.expanduser(d)) for d in LIVE_DIRS]


def fresh_live_file(path, since, dirs):
    p = os.path.realpath(os.path.expanduser(path))
    if not any(p == d or p.startswith(d + os.sep) for d in dirs):
        return False
    try:
        return since is None or os.path.getmtime(p) >= since
    except OSError:
        return False


_PATH_RX = re.compile(r"""(?:~|/)[^\s'"`;|&<>()]+""")


def judge(recs, since, skill=None):
    """Verdict for the turn that starts at `since` (epoch s; None = the whole transcript)."""
    if skill is None:
        skill = skill_invoked(recs)
    dirs = live_dirs()
    turn = [
        r
        for r in recs
        if r.get("isSidechain") is not True
        and (since is None or (_ts(r) or 0) >= since)
    ]
    errored, results = set(), {}
    for r in turn:
        c = (r.get("message") or {}).get("content")
        if r.get("type") == "user" and isinstance(c, list):
            for b in c:
                if isinstance(b, dict) and b.get("type") == "tool_result":
                    if b.get("is_error") is True:
                        errored.add(b.get("tool_use_id"))
                    results[b.get("tool_use_id")] = _text_of(b.get("content"))
    texts, draft, reads, draft_tools = [], None, [], []
    # A screenshot the operator pasted THIS turn is the medium handed over live (rule 2's
    # screenshot-only channels, e.g. Messenger E2EE). Only a human prompt's image counts: a
    # tool-returned image is a tool_result, whose record is not a prompt.
    for r in turn:
        c = (r.get("message") or {}).get("content")
        if r.get("type") == "user" and r.get("isMeta") is not True and isinstance(c, list):
            if not any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c) and any(
                isinstance(b, dict) and b.get("type") == "image" for b in c
            ):
                reads.append("prompt-image")
                break
    for r in turn:
        if r.get("type") != "assistant":
            continue
        for b in (r.get("message") or {}).get("content") or []:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "text":
                texts.append(b.get("text", ""))
            elif b.get("type") == "tool_use":
                name, inp = b.get("name", ""), b.get("input") or {}
                if DRAFT_TOOL_RX.match(name):
                    draft_tools.append(name)
                if b.get("id") in errored or result_empty(results.get(b.get("id"), "")):
                    continue
                if name == "Bash":
                    cmd = str(inp.get("command", ""))
                    v = bash_live_reads(cmd)
                    if pwsh_mail_read(cmd):
                        v.append("pwsh-graph-mail")
                    if v:
                        reads.extend("Bash:" + x for x in v)
                    elif any(
                        fresh_live_file(m, since, dirs) for m in _PATH_RX.findall(cmd)
                    ):
                        reads.append("Bash:live-file")
                elif name == "Read":
                    if fresh_live_file(str(inp.get("file_path", "")), since, dirs):
                        reads.append("Read:live-file")
                elif LIVE_TOOL_RX.match(name) or ms365_read(name, inp, results.get(b.get("id"))):
                    reads.append(name)
    for t in texts:
        draft = find_draft(t, skill)
        if draft:
            break
    if not draft and draft_tools:
        draft = draft_tools[0]
    return {
        "skill": skill,
        "draft": draft,
        "reads": reads,
        "block": bool(draft) and not reads,
    }


# ── measurement mode only: a port of hooks/lib/cc-interactive.sh's predicate ──
_AUTO_RX = re.compile(
    r"^<task-notification>|^<local-command-stdout>|^<teammate-message|^Stop hook feedback:|^\[Request interrupted|^⟳|^⚑|^⚠|^⛔"
)


def _interactive(r):
    if (
        r.get("type") != "user"
        or r.get("isMeta") is True
        or r.get("isSidechain") is True
    ):
        return False
    c = (r.get("message") or {}).get("content")
    if isinstance(c, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
            return False
        t = _text_of(c)
        img = any(isinstance(b, dict) and b.get("type") == "image" for b in c)
        if not t and not img:
            return False
    elif isinstance(c, str):
        t = c
        if not t:
            return False
    else:
        return False
    return not _AUTO_RX.search(t)


def scan(path):
    recs = load(path)
    skill = skill_invoked(recs)
    starts = [i for i, r in enumerate(recs) if _interactive(r)]
    for k, s in enumerate(starts):
        end = starts[k + 1] if k + 1 < len(starts) else len(recs)
        v = judge(recs[s:end], None, skill)
        v["prompt"] = _text_of((recs[s].get("message") or {}).get("content"))[:100]
        v["file"] = path
        v["turn"] = k
        print(json.dumps(v))


def main(argv):
    args, i = {}, 0
    while i < len(argv):
        a = argv[i]
        if a in ("--transcript", "--since"):
            args[a] = argv[i + 1] if i + 1 < len(argv) else ""
            i += 2
        else:
            args[a] = True
            i += 1
    tp = args.get("--transcript", "")
    if args.get("--scan"):
        scan(tp)
        return 0
    since = args.get("--since")
    since = int(since) if since and str(since).isdigit() else None
    try:
        recs = load(tp)
    except OSError:
        print(json.dumps({"error": "unreadable"}))
        return 2
    v = judge(recs, since)
    if v["block"] or args.get("--json"):
        print(json.dumps(v))
    return 1 if v["block"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
