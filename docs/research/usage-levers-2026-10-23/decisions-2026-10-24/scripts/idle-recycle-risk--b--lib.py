# Shared classifiers for the (b) analysis. Operator-vs-machine on a user record; context-dependence on a prompt.
import re
MACHINE_TYPED = re.compile(r'^\s*(ultracode\b[\s—-]*)?(\[(locate|restore|crash recovery|limit-recover)\]|Reply with (only|exactly)|reply with the single word|Run exactly this one shell command|Do not use any tools\. Answer with exactly|Use the Bash tool to run exactly|You are (a |an |the |one of |continuing |fixing )|TASK —|# (Verifier|Reviewer|Rater) brief|Below is step \d of a setup prompt|The operator (approved|decided|ruled|chose)|HANDOFF-ENGAGE)', re.I)
def kind(o):
    """o: opener dict from extract.py (kind computed there, refined here)."""
    k = o['kind']
    t = (o.get('text') or '').lstrip()
    if k == 'injected' and not MACHINE_TYPED.match(t) and o.get('ok') == 'human':
        k = 'operator'
    if k == 'operator' and MACHINE_TYPED.match(t):
        k = 'injected'
    return k
OPERATOR = ('operator', 'operator-noorigin')

# ---- context-dependence classifiers --------------------------------------------------------------
PATHISH = re.compile(r'(~?/[\w.@-]+/[\w./@-]+|\b[\w-]+\.(md|py|sh|ts|tsx|js|json|html|pdf|mp4|mov|png|jpg|csv|txt)\b|https?://|\b[0-9a-f]{12}\b|\b[0-9a-f]{7,40}\b)', re.I)
DEICTIC = re.compile(r"\b(that|it|this|these|those|them|the above|above|option\s*\d|#\d|yes|yeah|yep|yup|ok|okay|sure|do it|go ahead|go for it|approve[sd]?|approved|proceed|cancel|both|neither|first one|second one|same|again|why|are you sure|no take-?backs)\b", re.I)
def words(t): return len(re.findall(r"[\w'’]+", t))
def v0(t):
    """The brief's rule, literally: a reference token, or a short reply (<15 words) with no path/noun the
    disk would carry (approximated: no path, URL, hex id)."""
    t = t.strip()
    return bool(DEICTIC.search(t)) or (words(t) < 15 and not PATHISH.search(t))
SESSION_CANNED = re.compile(r"^\(?\s*(checking in|chceking in|continue|done, continue|re-connected[^)]*)\s*\)?\.?$|good to close|is this all before we close|short and conci?c?se (scqa|pyramid)|/explain-decisions|/are-we-done|explain-decisions|what is our progress|how did it go|assess our progress", re.I)
OPERATOR_STEP = re.compile(r'^\s*<(bash-input|command-name|command-message)>', re.I)
QUOTED = re.compile(r'^\s*(re:\s*)?["“❯]')
REPLY_HEAD = re.compile(r"^\s*(yes|yeah|yep|yup|no|nope|ok|okay|sure|done|cancel|proceed|approve|approved|go|go ahead|do it|open|both|neither|option|send|ship|land|fire|keep|pause|continue)\b", re.I)
def v1(t):
    """Refined after hand-labelling: H iff the prompt is not an operator step, not quoted, not a canned
    session question, and either (a) opens with a bare reply/imperative and is <= 15 words with no path,
    or (b) is <= 25 words, carries no path/URL/id, and leans on a deictic (that/it/this/these/the above)."""
    s = t.strip()
    if OPERATOR_STEP.match(s) or QUOTED.match(s) or SESSION_CANNED.search(s):
        return False
    if PATHISH.search(s):
        return False
    n = words(s)
    if REPLY_HEAD.match(s) and n <= 15:
        return True
    if n <= 25 and re.search(r"\b(that|it|this|these|those|them|the above|above|that date|option\s*\d)\b", s, re.I) and not re.search(r'\b[A-Z][a-z]+\s+[A-Z][a-z]+', s):
        return True
    return False
def coarse(t):
    s = t.strip()
    if v1(t): return 'H'
    if OPERATOR_STEP.match(s) and not re.search(r'explain-decisions|are-we-done', s): return 'I'
    if SESSION_CANNED.search(s) or QUOTED.match(s): return 'S'
    return 'S/I'
