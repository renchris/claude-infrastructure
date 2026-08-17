#!/bin/bash
# validate-bash-differential.sh — per-site equivalence adjudicator for hooks/validate-bash.sh.
#
# WHAT THIS ANSWERS. Backlog row 8942f3b1506d proposes replacing the hook's ~30 `grep -qE` pattern
# tests with bash-native `[[ =~ ]]`, and blocks itself on "a differential corpus proving identical
# verdicts on every DANGER pattern first". This IS that corpus. For every pattern site it runs BOTH
# forms — the grep the hook actually executes, and the naive bash-native equivalent a converter
# would reach for — over a corpus of true positives, near-miss negatives, and the axes where the
# two engines are known to diverge (multi-line input, `\b`, case folding, locale, empty input).
#
# WHY IT CAN FAIL. tests/fixtures/validate-bash-sites.tsv pins a MEASURED verdict per site. This
# script fails if reality no longer matches it in EITHER direction:
#   * a site pinned EQUIVALENT that starts diverging  → the conversion authorisation is void
#   * a site pinned DIVERGENT that stops diverging    → the corpus lost its counterexample, i.e.
#                                                       the control went vacuous
# It also fails if the hook grows, loses, or moves a pattern site (coverage assertion) or if a
# pinned pattern no longer appears on its line (drift assertion). A new grep site in the hook is
# reported UNTESTED and is a failure, not a silent pass.
#
# THE GREP UNDER TEST is the one the hook resolves, not the interactive one. The hook is
# `#!/bin/bash` and calls bare `grep`; on this box that resolves to /usr/bin/grep (BSD grep
# 2.6.0-FreeBSD), NOT GNU grep and not ugrep. Override with CC_DIFF_GREP for a cross-check.
#
# Usage: bash scripts/validate-bash-differential.sh [--verbose] [--markdown]
#   exit 0 = every site matches its pinned verdict;  1 = a mismatch;  2 = harness/setup error.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${CC_DIFF_HOOK:-$HERE/hooks/validate-bash.sh}"
SITES="${CC_DIFF_SITES:-$HERE/tests/fixtures/validate-bash-sites.tsv}"
CORPUS="${CC_DIFF_CORPUS:-$HERE/tests/fixtures/validate-bash-corpus.txt}"
GREP="${CC_DIFF_GREP:-}"

VERBOSE=0
MARKDOWN=0
for a in "$@"; do
  case "$a" in
    --verbose) VERBOSE=1 ;;
    --markdown) MARKDOWN=1 ;;
    *) printf 'unknown argument: %s\n' "$a" >&2; exit 2 ;;
  esac
done

# Resolve the grep the HOOK would resolve: a bash login shell's PATH lookup, not this shell's.
if [[ -z "$GREP" ]]; then
  GREP="$(command -v grep 2>/dev/null)"
  [[ -n "$GREP" ]] || { echo "no grep on PATH" >&2; exit 2; }
fi
GREP_ID="$("$GREP" --version 2>&1 | head -1)"

for f in "$HOOK" "$SITES" "$CORPUS"; do
  [[ -r "$f" ]] || { printf 'missing fixture: %s\n' "$f" >&2; exit 2; }
done

esc() { printf '%q' "$1"; }   # unambiguous single-line rendering of a multi-line / control-char value

# ── load sites ───────────────────────────────────────────────────────────────────────────────────
S_ID=(); S_LINE=(); S_FORM=(); S_FEED=(); S_SUBJ=(); S_VERIFY=(); S_EXPECT=(); S_PAT=()
while IFS=$'\t' read -r id line form feed subj verify expect pat; do
  case "$id" in ''|'#'*|id) continue ;; esac
  S_ID+=("$id"); S_LINE+=("$line"); S_FORM+=("$form"); S_FEED+=("$feed")
  S_SUBJ+=("$subj"); S_VERIFY+=("$verify"); S_EXPECT+=("$expect"); S_PAT+=("$pat")
done < "$SITES"
NSITES=${#S_ID[@]}
[[ $NSITES -gt 0 ]] || { echo "sites file parsed to zero rows" >&2; exit 2; }

# ── load corpus ──────────────────────────────────────────────────────────────────────────────────
C_ID=(); C_CLASS=(); C_LABEL=(); C_BODY=()
cur_id=""; cur_class=""; cur_label=""; cur_body=""; in_rec=0
while IFS= read -r ln || [[ -n "$ln" ]]; do
  if [[ $in_rec -eq 0 ]]; then
    case "$ln" in
      '### '*)
        hdr="${ln#\#\#\# }"
        cur_id="${hdr%%|*}";       cur_id="${cur_id%"${cur_id##*[![:space:]]}"}"
        rest="${hdr#*|}"
        cur_class="${rest%%|*}";   cur_class="${cur_class#"${cur_class%%[![:space:]]*}"}"
                                   cur_class="${cur_class%"${cur_class##*[![:space:]]}"}"
        cur_label="${rest#*|}";    cur_label="${cur_label#"${cur_label%%[![:space:]]*}"}"
        cur_body=""; in_rec=1
        ;;
    esac
  else
    if [[ "$ln" == '### END' ]]; then
      # strip the single trailing newline the accumulator adds
      cur_body="${cur_body%$'\n'}"
      [[ "$cur_id" == edge-crlf ]] && cur_body="${cur_body//$'\n'/$'\r'$'\n'}$(printf '\r')"
      C_ID+=("$cur_id"); C_CLASS+=("$cur_class"); C_LABEL+=("$cur_label"); C_BODY+=("$cur_body")
      in_rec=0
    else
      cur_body+="$ln"$'\n'
    fi
  fi
done < "$CORPUS"
NCASES=${#C_ID[@]}
[[ $NCASES -gt 0 ]] || { echo "corpus parsed to zero cases" >&2; exit 2; }

# ── assertion 1: COVERAGE — every code-level grep site in the hook is in the sites file ──────────
HOOK_LINES=""
while IFS= read -r nl; do
  num="${nl%%:*}"; body="${nl#*:}"; body="${body#"${body%%[![:space:]]*}"}"
  case "$body" in \#*) continue ;; esac
  HOOK_LINES="$HOOK_LINES $num"
done < <("$GREP" -n 'grep -' "$HOOK")

SITE_LINES=""
for i in $(seq 0 $((NSITES-1))); do
  case " $SITE_LINES " in *" ${S_LINE[$i]} "*) ;; *) SITE_LINES="$SITE_LINES ${S_LINE[$i]}" ;; esac
done

COVERAGE_FAIL=0
UNTESTED=""
for n in $HOOK_LINES; do
  case " $SITE_LINES " in *" $n "*) ;; *) UNTESTED="$UNTESTED $n"; COVERAGE_FAIL=1 ;; esac
done
STALE=""
for n in $SITE_LINES; do
  case " $HOOK_LINES " in *" $n "*) ;; *) STALE="$STALE $n"; COVERAGE_FAIL=1 ;; esac
done

# ── assertion 2: DRIFT — each verify=lit pattern is literally present on its line ────────────────
DRIFT_FAIL=0
DRIFT_LIST=""
for i in $(seq 0 $((NSITES-1))); do
  [[ "${S_VERIFY[$i]}" == lit ]] || continue
  hookline="$(sed -n "${S_LINE[$i]}p" "$HOOK")"
  case "$hookline" in
    *"${S_PAT[$i]}"*) ;;
    *) DRIFT_FAIL=1; DRIFT_LIST="$DRIFT_LIST ${S_ID[$i]}" ;;
  esac
done

# ── engines ──────────────────────────────────────────────────────────────────────────────────────
feed_stream() { # feed, input  → writes the exact byte stream the hook hands to grep
  case "$1" in
    raw)      printf '%s' "$2" ;;
    nl)       printf '%s\n' "$2" ;;
    pipeline) printf '%s' "$2" \
                | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g' \
                | sed 's/[&|()]/;/g' | tr ';' '\n' | sed 's/^[[:space:]]*//' ;;
  esac
}

bash_subject() { # feed, input → the string a converter would put on the left of =~
  case "$1" in
    raw|nl)   printf '%s' "$2" ;;
    pipeline) printf '%s' "$2" \
                | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g' \
                | sed 's/[&|()]/;/g' | tr ';' '\n' | sed 's/^[[:space:]]*//' ;;
  esac
}

bash_oe() { # pattern, input → the naive bash-native global extraction (grep -oE equivalent)
  local pat="$1" rest="$2" out="" m pre guard=0
  while [[ -n "$rest" ]]; do
    guard=$((guard+1)); [[ $guard -gt 500 ]] && break
    [[ "$rest" =~ $pat ]] || break
    m="${BASH_REMATCH[0]}"
    if [[ -z "$m" ]]; then rest="${rest:1}"; continue; fi
    out="$out$m"$'\n'
    pre="${rest%%"$m"*}"
    rest="${rest:$(( ${#pre} + ${#m} ))}"
  done
  printf '%s' "$out"
}

# ── the differential ─────────────────────────────────────────────────────────────────────────────
declare -a MEASURED DIVCOUNT APPCOUNT FIRSTDIV
TOTAL_PAIRS=0; TOTAL_DIV=0
DETAIL=""

for i in $(seq 0 $((NSITES-1))); do
  pat="${S_PAT[$i]}"; form="${S_FORM[$i]}"; feed="${S_FEED[$i]}"; subj="${S_SUBJ[$i]}"
  ndiv=0; napp=0; first=""
  for j in $(seq 0 $((NCASES-1))); do
    case ",${C_CLASS[$j]}," in *",$subj,"*) ;; *) continue ;; esac
    napp=$((napp+1)); TOTAL_PAIRS=$((TOTAL_PAIRS+1))
    inp="${C_BODY[$j]}"
    bsub="$(bash_subject "$feed" "$inp")"

    case "$form" in
      qE)
        if feed_stream "$feed" "$inp" | "$GREP" -qE "$pat"; then g=MATCH; else g=no; fi
        if [[ "$bsub" =~ $pat ]]; then b=MATCH; else b=no; fi
        ;;
      qiE)
        if feed_stream "$feed" "$inp" | "$GREP" -qiE "$pat"; then g=MATCH; else g=no; fi
        shopt -s nocasematch
        if [[ "$bsub" =~ $pat ]]; then b=MATCH; else b=no; fi
        shopt -u nocasematch
        ;;
      qF)
        if feed_stream "$feed" "$inp" | "$GREP" -qF -- "$pat"; then g=MATCH; else g=no; fi
        if [[ "$bsub" == *"$pat"* ]]; then b=MATCH; else b=no; fi
        ;;
      oE)
        g="$(feed_stream "$feed" "$inp" | "$GREP" -oE "$pat" 2>/dev/null || true)"
        b="$(bash_oe "$pat" "$bsub")"
        g="${g%$'\n'}"; b="${b%$'\n'}"
        ;;
      *) echo "unknown form ${form} at site ${S_ID[$i]}" >&2; exit 2 ;;
    esac

    if [[ "$g" != "$b" ]]; then
      ndiv=$((ndiv+1)); TOTAL_DIV=$((TOTAL_DIV+1))
      [[ -z "$first" ]] && first="${C_ID[$j]}"
      DETAIL="$DETAIL${S_ID[$i]}	${C_ID[$j]}	$(esc "$inp")	grep=$(esc "$g")	bash=$(esc "$b")
"
    elif [[ $VERBOSE -eq 1 ]]; then
      DETAIL="$DETAIL${S_ID[$i]}	${C_ID[$j]}	AGREE	$(esc "$g")
"
    fi
  done
  if [[ $ndiv -gt 0 ]]; then MEASURED[$i]=DIVERGENT; else MEASURED[$i]=EQUIVALENT; fi
  DIVCOUNT[$i]=$ndiv; APPCOUNT[$i]=$napp; FIRSTDIV[$i]="$first"
done

# ── report ───────────────────────────────────────────────────────────────────────────────────────
FAIL=0
if [[ $MARKDOWN -eq 1 ]]; then
  printf '| site | line | form | subject | cases | diverging | measured | pinned | first counterexample |\n'
  printf '|---|---|---|---|---|---|---|---|---|\n'
else
  printf 'grep under test : %s (%s)\n' "$GREP" "$GREP_ID"
  printf 'bash            : %s\n' "$BASH_VERSION"
  printf 'sites           : %d   corpus cases: %d   scored pairs: %d   diverging pairs: %d\n\n' \
    "$NSITES" "$NCASES" "$TOTAL_PAIRS" "$TOTAL_DIV"
  printf '%-6s %-5s %-5s %-8s %5s %5s  %-11s %-11s %s\n' \
    SITE LINE FORM SUBJECT CASES DIV MEASURED PINNED 'FIRST COUNTEREXAMPLE'
fi

for i in $(seq 0 $((NSITES-1))); do
  ok=OK
  [[ "${MEASURED[$i]}" == "${S_EXPECT[$i]}" ]] || { ok=MISMATCH; FAIL=1; }
  if [[ $MARKDOWN -eq 1 ]]; then
    printf '| %s | %s | `%s` | %s | %d | %d | **%s** | %s | %s |\n' \
      "${S_ID[$i]}" "${S_LINE[$i]}" "${S_FORM[$i]}" "${S_SUBJ[$i]}" \
      "${APPCOUNT[$i]}" "${DIVCOUNT[$i]}" "${MEASURED[$i]}" "${S_EXPECT[$i]}" \
      "${FIRSTDIV[$i]:-—}"
  else
    printf '%-6s %-5s %-5s %-8s %5d %5d  %-11s %-11s %s%s\n' \
      "${S_ID[$i]}" "${S_LINE[$i]}" "${S_FORM[$i]}" "${S_SUBJ[$i]}" \
      "${APPCOUNT[$i]}" "${DIVCOUNT[$i]}" "${MEASURED[$i]}" "${S_EXPECT[$i]}" \
      "${FIRSTDIV[$i]:-—}" "$([[ $ok == OK ]] && echo '' || echo '   <<< MISMATCH')"
  fi
done

if [[ $MARKDOWN -eq 0 ]]; then
  eq=0; dv=0
  for i in $(seq 0 $((NSITES-1))); do
    [[ "${MEASURED[$i]}" == EQUIVALENT ]] && eq=$((eq+1)) || dv=$((dv+1))
  done
  printf '\nSAFE TO CONVERT: %d of %d sites.  MUST NOT CONVERT: %d.\n' "$eq" "$NSITES" "$dv"

  if [[ -n "$UNTESTED$STALE" ]]; then
    printf '\nCOVERAGE FAILURE\n'
    [[ -n "$UNTESTED" ]] && printf '  UNTESTED grep sites in the hook (line numbers):%s\n' "$UNTESTED"
    [[ -n "$STALE" ]]    && printf '  sites file references lines with no grep site:%s\n' "$STALE"
  fi
  if [[ $DRIFT_FAIL -eq 1 ]]; then
    printf '\nDRIFT FAILURE — pinned pattern absent from its line:%s\n' "$DRIFT_LIST"
  fi
  if [[ -n "$DETAIL" ]]; then
    printf '\nDIVERGENCES (site, case, input, grep verdict, bash verdict — %%q-escaped)\n'
    printf '%s' "$DETAIL"
  fi
fi

[[ $COVERAGE_FAIL -eq 1 || $DRIFT_FAIL -eq 1 ]] && FAIL=1
exit "$FAIL"
