#!/usr/bin/env bats
# emote-review-completeness — the two properties `scripts/emote-review.py` claims in prose.
#
# WHAT IS BEING GUARDED, and why prose was not enough.
#
# 1. COMPLETENESS. The generator's own comment says it plainly — *"a review surface that can be
#    quietly incomplete is worse than none"* — and then nothing checked it. The page is the surface
#    a promotion ruling gets made on, so a candidate that is built, gated and shipping but absent
#    from the page is invisible to the only reader who matters, and absent silently: the page still
#    renders, still looks complete, and still prints a candidate count that agrees with itself.
#
# 2. THE RESERVATION RENDERS. `Emote.review` carries an unresolved cut-or-keep question to the page
#    where it gets settled. It exists because the question for THE UNSWITCHED and THE HEAVY THING
#    YIELDS spent a week in an autonomy decision record — a store nobody reads while looking at
#    artwork — so the operator could open the page and never learn that two of the twenty-seven
#    panels were the ones being asked about. A reservation that fails to render puts it straight
#    back in that state, and does so invisibly.
#
# NOTHING HERE PINS AN OPERATOR DECISION, and that is deliberate. This suite never asserts that a
# particular candidate exists, that a particular candidate is flagged, or how many of either there
# are. Decision 47b392d6e9eb defaults to *"keep all eight on the review page and decide by eye"* —
# it leaves the operator free to cut a candidate or settle a reservation, and a guard that went red
# when they did would be convicting the right action. Every assertion below is therefore derived
# from the corpus at run time: whatever is in `EMOTES` must reach the page, and whatever carries a
# `review` must render it. Both stay true after a cut, and after the last reservation is cleared.
#
# HERMETIC, AND STUBBED ONLY WHERE THE PROPERTY DOES NOT LIVE. The REAL corpus is used — a
# hand-written stand-in would pass vacuously, being exactly the thing whose structure is in
# question. Only `data_uri` is stubbed, which replaces each panel's image payload with a placeholder
# so no SVG has to be rendered to disk. The properties under test are structural (is the figure
# there, is the reservation beside it) and cannot be reached by the payload, so the stub buys ~30 s
# per run without weakening anything. No browser, no network.
#
# THE RED CASES ARE THE POINT. Each mutates the REAL generated page — deleting one figure, deleting
# one reservation — and asserts the audit names that specific candidate. A guard nobody has watched
# convict is a guess, and an audit that merely returns non-zero could be counterfeited by an import
# error.
#
# BATS ERREXIT: a non-final bare `[[ ]]` is errexit-EXEMPT and therefore a DEAD assertion — every
# non-final assertion below is `|| false` or a live final `[ ]`.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

# audit <mutation> — build the real review page, optionally damage it, then audit it.
#
# Mutations: none | drop-figure | strip-flag. Prints "ACCEPTED", or "REFUSED: <diagnosis>", or
# "NOTHING-TO-MUTATE" when the corpus holds no reservation for the mutation to remove. Always exits
# 0, so a test asserts on the VERDICT rather than on a status an import failure would also produce.
audit() {
  python3 - "$REPO" "$1" <<'PY'
import html
import importlib.util
import re
import sys
from pathlib import Path

repo, mutation = Path(sys.argv[1]), sys.argv[2]

spec = importlib.util.spec_from_file_location("emote_review", repo / "scripts" / "emote-review.py")
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)
import emotes

# The payload, and only the payload. Every property audited below is structural.
review.data_uri = lambda p: "data:image/svg+xml,stub"

emotes.load_packs()

import tempfile

with tempfile.TemporaryDirectory() as td:
    doc = Path(td) / "index.html"
    review.build_page(doc, Path(td))
    txt = doc.read_text(encoding="utf-8")

flagged = [e for e in emotes.EMOTES if e.review]

# ── mutate ───────────────────────────────────────────────────────────────────────────────────────
victim = None
if mutation == "drop-figure":
    victim = emotes.EMOTES[0]
    pat = re.compile(r"<figure id='%s'.*?</figure>" % re.escape(victim.key), re.S)
    txt, n = pat.subn("", txt)
    if n != 1:
        print(f"REFUSED: mutation anchor matched {n} times, not once — the control is unsound")
        raise SystemExit(0)
elif mutation == "strip-flag":
    if not flagged:
        print("NOTHING-TO-MUTATE")
        raise SystemExit(0)
    victim = flagged[0]
    pat = re.compile(
        r"(<figure id='%s'.*?)<div class=\"flag\">.*?</div>" % re.escape(victim.key), re.S
    )
    txt, n = pat.subn(r"\1", txt)
    if n != 1:
        print(f"REFUSED: mutation anchor matched {n} times, not once — the control is unsound")
        raise SystemExit(0)

# ── audit ────────────────────────────────────────────────────────────────────────────────────────
panels = {}
for m in re.finditer(r"<figure id='([^']+)'(.*?)</figure>", txt, re.S):
    panels[m.group(1)] = m.group(2)

bad = []
for e in emotes.EMOTES:
    if e.key not in panels:
        bad.append(
            f"{e.key} is in the corpus but has no panel on the review page — it is shipping and "
            f"invisible to the ruling"
        )
        continue
    body = panels[e.key]
    if e.review:
        if html.escape(e.review) not in body:
            bad.append(
                f"{e.key} carries a reservation that does not render — the cut-or-keep question is "
                f"back in a store nobody reads while looking at artwork"
            )
        if 'class="flagged"' not in body:
            bad.append(f"{e.key} renders its reservation but the panel is not outlined")
        if "chip q" not in body:
            bad.append(f"{e.key} renders its reservation but has no scan chip")
    elif 'class="flag"' in body:
        bad.append(f"{e.key} shows a reservation block with no reservation behind it")

n_blocks = txt.count('<div class="flag">')
if n_blocks != len(flagged):
    bad.append(f"{n_blocks} reservation blocks on the page for {len(flagged)} reservations")

print("REFUSED: " + "; ".join(bad) if bad else "ACCEPTED")
PY
}

# ── the shipping corpus ──────────────────────────────────────────────────────────────────────────

@test "every candidate in the corpus reaches the review page" {
  run audit none
  [ "$status" -eq 0 ] || false
  [[ "$output" == "ACCEPTED" ]]
}

# ── the red cases ────────────────────────────────────────────────────────────────────────────────

@test "a candidate missing from the page is named, not merely counted" {
  run audit drop-figure
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"REFUSED"* ]] || false
  [[ "$output" == *"shipping and invisible to the ruling"* ]]
}

@test "a reservation that fails to render is named" {
  run audit strip-flag
  [ "$status" -eq 0 ] || false
  # Green by construction when no candidate carries a reservation: the operator settling the last
  # open question must not turn this suite red. Guarded, not silently vacuous.
  if [[ "$output" == "NOTHING-TO-MUTATE" ]]; then
    skip "no candidate carries a reservation — nothing for this control to strip"
  fi
  [[ "$output" == *"REFUSED"* ]] || false
  [[ "$output" == *"nobody reads while looking at artwork"* ]]
}
