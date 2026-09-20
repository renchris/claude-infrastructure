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
# THE SSOT'S OWN DEGRADATION PATH (2 + 1) — three python readers across two files each carry a
# text test reached ONLY when `import lr_predicate` raises. They are not copies competing with the
# module; they are what stops an unreachable module reporting a CAPPED fleet as a healthy one,
# because rc 1 from lr_last_api_error means "not an api error". Allowed, and COUNTED, so one more
# in either file is still refused.
#   scripts/limit-recover/lr-lib.sh      (2: the tier read and lr_last_api_error)
#   scripts/limit-recover/lr-handoff.sh  (1: the bundle's last-message-before-the-limit read)
ALLOW="bin/cc-classify 1
scripts/limit-recover/lr-handoff.sh 1
scripts/limit-recover/lr-lib.sh 2
scripts/cloud-ceiling-probe.sh 1
scripts/desk-invariant.sh 1
scripts/handoff-fire.sh 1
scripts/lib/cloud-create.sh 1
scripts/limit-recover/lr-reset-poller.sh 1"

allowed_count() { printf '%s\n' "$ALLOW" | awk -v f="$1" '$1==f {print $2; found=1} END{if(!found) print 0}'; }

hits="$(git grep -nE "$CAP_RE" -- scripts bin hooks 2>/dev/null \
        | grep -vE '^scripts/limit-recover/lr_predicate\.py:|^scripts/limit-recover/lr-predicate\.sh:|^scripts/lr-predicate-lint\.sh:' \
        | grep -vE ':[0-9]+: *#' \
        | grep -E "$MATCH_RE")"

rc=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  f="${line%%:*}"
  n="$(printf '%s\n' "$hits" | grep -c "^$f:")"
  want="$(allowed_count "$f")"
  [ "$n" -le "$want" ] && continue
  rc=1
done < <(printf '%s\n' "$hits" | cut -d: -f1 | sort -u | sed 's/$/:/')

if [ "$rc" -ne 0 ] || [ "${1:-}" = "--list" ]; then
  printf '%s\n' "$hits" | cut -d: -f1 | sort | uniq -c | while read -r n f; do
    want="$(allowed_count "$f")"
    if [ "$n" -gt "$want" ]; then
      printf 'REFUSED  %-46s %s cap-text predicate(s), %s allowed\n' "$f" "$n" "$want" >&2
    else
      printf 'ok       %-46s %s/%s\n' "$f" "$n" "$want"
    fi
  done
fi

if [ "$rc" -ne 0 ]; then
  cat >&2 <<'EOF'

lr-predicate-lint: a NEW limit predicate was added outside the SSOT.
The limit predicate lives in ONE place: scripts/limit-recover/lr_predicate.py.
  · python  — import lr_predicate; classify_record(rec) / classify_text(text, error=, api_error_status=)
  · bash    — bash scripts/limit-recover/lr-predicate.sh classify-tail <transcript>
If the new site really reads a CLI's STDOUT rather than transcript JSONL, it belongs in this
script's allowlist WITH its reason, beside the three that are already there.
EOF
  exit 1
fi
printf 'lr-predicate-lint: clean — no cap-text predicate outside the SSOT and its allowlist.\n'
exit 0
