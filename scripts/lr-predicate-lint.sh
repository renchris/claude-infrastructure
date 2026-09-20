#!/usr/bin/env bash
# lr-predicate-lint.sh — refuse a THIRTEENTH copy of the limit predicate (LIMIT_DETECT_100P W4 §5).
#
# WHAT WENT WRONG THAT THIS PREVENTS. Sixteen sites in this repo had each grown their own answer to
# "is this session limit-blocked, and on which cap". P9 put ONE real string through nine of them and
# got five different verdicts; 19 of 209 real rate_limit records were missed by four copies, and a
# miss spells `other_api_error`, which means never parked, which means a capped session sits idle
# until a human notices. W4 collapsed them onto scripts/limit-recover/lr_predicate.py. Nothing in
# the repo stopped the seventeenth from being written next week — a consolidation with no gate is a
# snapshot, not an invariant. This is the gate.
#
# WHAT IT REFUSES, precisely: a line of RUNTIME code (scripts/ hooks/ bin/) that MATCHES against the
# cap-TEXT family. Three properties keep it from being noise:
#   · CAP TEXT ONLY. The structured spellings are the SANCTIONED read and are not flagged at all —
#     `error":"rate_limit"` and apiErrorStatus 429 are T1, which is what sites are being migrated
#     TO. A gate that flagged those would refuse its own cure (memory: guard-proxy-fails-in-both-
#     directions).
#   · IT MUST BE A MATCH, not a mention. A notification string, a report heading, a `todo` line and
#     a test fixture all name these phrases legitimately and constantly; only a grep / case-arm /
#     regex assignment / `in txt` / .startswith is a PREDICATE. This is what keeps the allowlist
#     from having to grow a row for every piece of prose.
#   · COMMENTS ARE EXEMPT. This very file quotes the strings, and so does every site's rationale.
#
# WHY AN ALLOWLIST OF (file -> count) AND NOT A DIGEST. A digest pins the exact bytes, so rewording
# a comment on the line would trip it; a count lets a kept predicate be edited and still refuses an
# ADDED one. The residual is stated rather than hidden: swapping one allowed predicate for a
# different one inside the same file is invisible here. That is the cheap half of the gate; the
# expensive half is tests/lr-predicate.bats, which pins the behaviour.
#
# Exit 0 = clean. Exit 1 = an unallowed predicate. Exit 2 = the lint could not run.
set -uo pipefail

# RESOLVE THE SYMLINKS FIRST, then derive. ~/.claude/{scripts,hooks,bin} are per-file symlinks into
# the checkout, so through the LIVE layer an unresolved `dirname "$0"/..` is ~/.claude — which has
# no .git, no tests/ and no docs/. This lint would not fail there; `git grep` would simply find
# nothing and it would report a clean tree forever, and only on the live path, which is invisible
# from a worktree. No `readlink -f`: that is GNU-only and this box is BSD. Canonical loop:
# _resolve_self() in scripts/ship-land.sh.
_lrpl_self="${BASH_SOURCE[0]}"
while [ -L "$_lrpl_self" ]; do
  _lrpl_dir="$(cd "$(dirname "$_lrpl_self")" && pwd)"
  _lrpl_self="$(readlink "$_lrpl_self")"
  case "$_lrpl_self" in /*) ;; *) _lrpl_self="$_lrpl_dir/$_lrpl_self" ;; esac
done
ROOT="$(cd "$(dirname "$_lrpl_self")/.." && pwd)"
cd "$ROOT" || { echo "lr-predicate-lint: cannot reach the repo root" >&2; exit 2; }

# The cap-TEXT family. Deliberately NOT `rate_limit` or `429`.
CAP_RE="(hit|reached) your|session limit|weekly limit|usage limit|monthly spend limit|spend limit|limit ·"
# The shapes that make a line a predicate rather than a mention. The last alternative — a cap
# phrase with an alternation pipe welded to it — is not redundant: a `grep -qiE \` puts the verb on
# one line and the pattern on the NEXT, and desk-invariant.sh:156 is exactly that shape, so a
# verb-only test read the tree clean while a real predicate sat in it. A regex alternation is the
# one thing prose never contains.
MATCH_RE="grep|_RE=|=~| in t(xt)?[^A-Za-z_]|re\.(compile|search|match)|\.startswith\(|\*\"[^\"]*\"\*\)|limit\\|"

# ── the allowlist: every predicate that is ALLOWED to carry cap text, and why ────────────────────
# CLI-STDOUT DOMAIN (3). These read a terminal capture, not transcript JSONL. The SSOT gates on an
# envelope a terminal has no way to carry, so delegating would be a category error, not a cleanup.
#   scripts/handoff-fire.sh · scripts/cloud-ceiling-probe.sh · scripts/lib/cloud-create.sh
# UNION VETOES (2). These keep their regex BESIDE the SSOT because a veto must never LOSE coverage:
# desk-invariant's also catches a permission-CLASSIFIER outage, which carries no api-error envelope
# and which the SSOT therefore cannot see at all.
#   bin/cc-classify · scripts/desk-invariant.sh
# CHEAP PRE-FILTER (1). lr-reset-poller's SPEND_RE guards a scan of hundreds of transcripts; the
# SSOT rules AFTER it, once per candidate. Replacing it with a fork per file is what it exists to
# avoid.
#   scripts/limit-recover/lr-reset-poller.sh
# THE SSOT'S OWN DEGRADATION PATH (2) — lr-lib.sh's two python readers each carry a text test
# reached ONLY when `import lr_predicate` raises. They are not copies competing with the module;
# they are what stops an unreachable module reporting a CAPPED fleet as a healthy one, because rc 1
# from lr_last_api_error means "not an api error". Allowed, and counted, so a THIRD one is refused.
#   scripts/limit-recover/lr-lib.sh
# NOT YET MIGRATED (1) — a genuine copy, found by this lint while it was being written, outside
# W4's frozen scope. It is Fable-blind exactly as lr-lib.sh:172 was. Allowed so the lint can ship
# green; it is named here so the debt is legible rather than blessed.
#   scripts/limit-recover/lr-handoff.sh
ALLOW="bin/cc-classify 1
scripts/limit-recover/lr-lib.sh 2
scripts/cloud-ceiling-probe.sh 1
scripts/desk-invariant.sh 1
scripts/handoff-fire.sh 1
scripts/lib/cloud-create.sh 1
scripts/limit-recover/lr-handoff.sh 1
scripts/limit-recover/lr-reset-poller.sh 1"

# ── THE SECOND FAMILY: the TEAMMATE predicate (LIMIT_DETECT_100P § 11 #10) ───────────────────────
# WHY A SECOND FAMILY AT ALL, and it is the same argument this file already makes for the first.
# § 11 #10 abolishes the raw `"agentName"` substring exactly as W4 abolished the cap-text copies,
# and `lr_predicate.is_teammate_head` is its one copy. Nothing gated it — this lint's CAP_RE cannot
# see the teammate family, and the consequence is measured rather than hypothetical: bin/cc-limited
# imported the SSOT at :71 and then ran its OWN `if b'"agentName"' in head:` at :421, a thirteenth
# copy that sat on trunk through W2a's land, W4's migration AND this lint's arrival, because every
# gate in play was keyed on the other family. A consolidation with no gate is a snapshot.
#
# THE DEFECT IT REFUSES IS SPECIFIC, not stylistic. A substring answers TRUE to `"agentName":null`
# exactly as readily as to a real name. Consumers use this test to SKIP — a teammate is ended by
# its lead, never by itself — so a false positive leaves an ordinary live session marked lead-owned
# and unrecoverable, silently, with an authoritative-looking reason on screen.
#
# A PARSED FIELD READ IS NOT A COPY and is deliberately not flagged: `obj.get("agentName")` is the
# SANCTIONED shape (it is what the SSOT itself does), and lr-audit.py:1298 uses it to ask a
# different question entirely — whether a record belongs to a NAMED member of a named team.
# Flagging that would refuse the cure, which is the failure mode the CAP_RE notes above warn about.
TEAM_RE='"agentName"'
TEAM_MATCH_RE="grep|=~| in line| in head| in txt| in data|\.startswith\(|re\.(compile|search|match)"

# NOT YET MIGRATED (5). Every one is a genuine copy and none is in this wave's frozen scope; W4
# migrated only the poller's two. They are allowlisted BY NAME with the reason, which is the same
# treatment lr-handoff.sh gets above: it keeps the debt legible instead of silently permitted, and
# it refuses a SIXTH. One-line migration each, onto `lr-predicate.sh is-teammate-head` (bash) or
# `PRED.is_teammate_head` (python), for whoever owns each file.
#   bin/cc-find · scripts/handoff-fire.sh · scripts/limit-recover/lr-fleet.sh (2) ·
#   scripts/limit-recover/lr-select.py
TEAM_ALLOW="bin/cc-find 1
scripts/handoff-fire.sh 1
scripts/limit-recover/lr-fleet.sh 2
scripts/limit-recover/lr-select.py 1"

allowed_count() { printf '%s\n' "$2" | awk -v f="$1" '$1==f {print $2; found=1} END{if(!found) print 0}'; }

# One scan, two families. The exclusions are shared on purpose: the SSOT, its shim and this file
# all QUOTE both families constantly, and a gate that flagged its own rationale would be deleted.
scan() { # $1 = subject regex, $2 = predicate-shape regex
  git grep -nE "$1" -- scripts bin hooks 2>/dev/null \
    | grep -vE '^scripts/limit-recover/lr_predicate\.py:|^scripts/limit-recover/lr-predicate\.sh:|^scripts/lr-predicate-lint\.sh:' \
    | grep -vE ':[0-9]+: *#' \
    | grep -E "$2"
}

rc=0
report() { # $1 = hits  $2 = allowlist  $3 = family label
  local hits="$1" allow="$2" label="$3" f n want
  [ -n "$hits" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n="$(printf '%s\n' "$hits" | grep -c "^$f:")"
    want="$(allowed_count "$f" "$allow")"
    if [ "$n" -gt "$want" ]; then
      printf 'REFUSED  %-46s %s %s predicate(s), %s allowed\n' "$f" "$n" "$label" "$want" >&2
      rc=1
    elif [ "${LIST:-0}" = 1 ]; then
      printf 'ok       %-46s %s/%s  %s\n' "$f" "$n" "$want" "$label"
    fi
  done < <(printf '%s\n' "$hits" | cut -d: -f1 | sort -u)
}

[ "${1:-}" = "--list" ] && LIST=1
report "$(scan "$CAP_RE" "$MATCH_RE")"   "$ALLOW"      "cap-text"
report "$(scan "$TEAM_RE" "$TEAM_MATCH_RE")" "$TEAM_ALLOW" "teammate"

if [ "$rc" -ne 0 ]; then
  cat >&2 <<'EOF'

lr-predicate-lint: a NEW predicate was added outside the SSOT.
Both families live in ONE place: scripts/limit-recover/lr_predicate.py.
  cap-text — is this session limit-blocked, and on which cap
  · python  — import lr_predicate; classify_record(rec) / classify_text(text, error=, api_error_status=)
  · bash    — bash scripts/limit-recover/lr-predicate.sh classify-tail <transcript>
  teammate — is this session a named TEAMMATE (§ 11 #10)
  · python  — import lr_predicate; lr_predicate.is_teammate_head(head_bytes)
  · bash    — bash scripts/limit-recover/lr-predicate.sh is-teammate-head <transcript>
A raw `"agentName"` substring is NOT equivalent: it answers TRUE to `"agentName":null`, which marks
an ordinary live session lead-owned and stops it ever being recovered.
If the new site really reads a CLI's STDOUT rather than transcript JSONL, it belongs in this
script's allowlist WITH its reason, beside the ones already there.
EOF
  exit 1
fi
printf 'lr-predicate-lint: clean — no cap-text or teammate predicate outside the SSOT and its allowlist.\n'
exit 0
