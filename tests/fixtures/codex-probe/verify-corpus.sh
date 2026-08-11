#!/usr/bin/env bash
# Assert the three controls the codex-probe corpus rests on, mechanically.
#
# Run before W2. A corpus that fails any check here returns a confident wrong
# verdict rather than no verdict, which is the expensive failure.
#
#   A  every pre_fix_ref RESOLVES          — the artifact is reachable, not described
#   B  every brief body is BYTE-IDENTICAL  — control 2: the real artifact, never a
#      to `git show <pre_fix_ref>:<path>`    hand-reconstruction (a stand-in passes vacuously)
#   C  shape                               — 8-10 briefs · >=2 clean · every defective
#                                            brief carries ground_truth AND sibling_axis_pinned
#   D  no brief leaks                      — no sha, no defect title, no "pre-fix"/"fix" wording
#   E  one preamble                        — every brief word-identical apart from its opaque
#                                            id and subject path, so no brief is more leading
#
# Usage: bash tests/fixtures/codex-probe/verify-corpus.sh
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"

fail=0
note() { printf '%s\n' "$*"; }

# ── A. every pre_fix_ref resolves ────────────────────────────────────────────
note "── A. pre_fix_ref reachability (git cat-file -e)"
while IFS=$'\t' read -r id ref; do
	if git -C "$REPO" cat-file -e "$ref" 2>/dev/null; then
		printf '   ok   %-8s %s\n' "$id" "$ref"
	else
		printf '   FAIL %-8s %s  (unreachable)\n' "$id" "$ref"
		fail=1
	fi
done < <(python3 -c '
import json, sys
for b in json.load(open(sys.argv[1])):
    print("\t".join([b["id"], b["pre_fix_ref"]]))
' "$HERE/manifest.json")

# ── B. brief body == the artifact at that ref, byte for byte ─────────────────
note "── B. brief body is the real artifact (byte-identical to the ref)"
while IFS=$'\t' read -r id subject ref prompt; do
	# the body is everything between the first ```bash fence and the final fence
	if python3 - "$HERE/$prompt" >/tmp/codex-probe-body.$$ <<'PY'; then
import sys
t = open(sys.argv[1]).read()
i = t.index("```bash\n") + len("```bash\n")
j = t.rindex("```\n")
sys.stdout.write(t[i:j])
PY
		if git -C "$REPO" show "$ref:$subject" | diff -q - /tmp/codex-probe-body.$$ >/dev/null; then
			printf '   ok   %-8s %s\n' "$id" "$subject"
		else
			printf '   FAIL %-8s %s  (brief body differs from %s:%s)\n' "$id" "$subject" "$ref" "$subject"
			fail=1
		fi
	else
		printf '   FAIL %-8s %s  (no fenced body)\n' "$id" "$prompt"
		fail=1
	fi
	rm -f /tmp/codex-probe-body.$$
done < <(python3 -c '
import json, sys
for b in json.load(open(sys.argv[1])):
    print("\t".join([b["id"], b["subject_path"], b["pre_fix_ref"], b["prompt_path"]]))
' "$HERE/manifest.json")

# ...and the WHOLE file, not just the fenced region. The fence-scoped comparison above
# cannot see text appended after the closing fence or edited into the preamble — a RED
# control (tests/codex-probe-corpus.bats) caught exactly that, by appending one line to a
# brief and watching this checker stay green.
note "── B2. whole brief == a clean regeneration (nothing outside the fence, preamble intact)"
REGEN="$(mktemp -d)"
if CODEX_PROBE_OUT="$REGEN" bash "$HERE/build-briefs.sh" >/dev/null 2>&1 &&
	diff -r "$REGEN" "$HERE/briefs" >/tmp/codex-probe-regen.$$ 2>&1; then
	printf '   ok   all briefs reproduce byte for byte\n'
else
	printf '   FAIL brief(s) differ from a clean regeneration:\n'
	# awk, not `| head -20`: under pipefail an early-exiting consumer SIGPIPEs the producer, so
	# the pipeline reads non-zero exactly when there IS output — and under errexit that would
	# abort the verifier here, in the branch that exists to report a failure.
	awk 'NR<=20 { print "        " $0 }' /tmp/codex-probe-regen.$$ 2>/dev/null
	fail=1
fi
rm -rf "$REGEN" /tmp/codex-probe-regen.$$

# ── C/D/E. shape, leakage, and one preamble ──────────────────────────────────
note "── C/D/E. shape, leak scan, preamble identity"
python3 - "$HERE" <<'PY' || fail=1
import json, os, re, sys

here = sys.argv[1]
briefs = json.load(open(os.path.join(here, "manifest.json")))
bad = []

# C. shape
n, clean = len(briefs), sum(1 for b in briefs if not b["has_defect"])
if not (8 <= n <= 10):
    bad.append(f"brief count {n} outside 8-10")
if clean < 2:
    bad.append(f"only {clean} clean briefs, need >=2")
for b in briefs:
    if b["has_defect"]:
        if not b.get("ground_truth"):
            bad.append(f"{b['id']}: has_defect but empty ground_truth")
        if not b.get("sibling_axis_pinned"):
            bad.append(f"{b['id']}: has_defect but no sibling_axis_pinned")
        for g in b.get("ground_truth", []):
            for k in ("defect", "file", "line_hint", "why_it_survives_a_first_look"):
                if not g.get(k):
                    bad.append(f"{b['id']}: ground_truth entry missing {k}")
    else:
        if b.get("ground_truth"):
            bad.append(f"{b['id']}: clean brief must have an empty ground_truth")
    if len(set(x["id"] for x in briefs)) != n:
        bad.append("duplicate ids")

# D. no brief may leak the answer: shas, titles, or the fact that a fix exists
shas = set()
for b in briefs:
    for v in (b.get("culprit_commit"), b.get("pre_fix_ref"), b.get("subject_blob_sha")):
        if v:
            shas.add(v[:8])
leaky_words = ("pre-fix", "pre_fix", "culprit", "ground truth", "ground_truth",
               "codex", "probe corpus")
# a brief must not name ANOTHER brief's subject either: running the corpus in one
# context would then prime that brief. This is what disqualified the first two clean
# candidates — one narrated cp-01's defect outright, the other shared its subject.
subjects = {b["id"]: os.path.basename(b["subject_path"]) for b in briefs}
for b in briefs:
    text = open(os.path.join(here, b["prompt_path"])).read()
    low = text.lower()
    for s in shas:
        if s.lower() in low:
            bad.append(f"{b['id']}: brief contains sha fragment {s}")
    for w in leaky_words:
        if w in low:
            bad.append(f"{b['id']}: brief contains leaking word {w!r}")
    if b["title"].lower() in low:
        bad.append(f"{b['id']}: brief contains its own manifest title")
    # an exemption is recorded per (brief, referenced-basename) PAIR in the manifest and
    # must say why the mention does not disclose the other brief's defect. Never widen the
    # rule instead — a widened rule stops catching the case it was built for.
    ok_refs = {a["names"] for a in b.get("cross_reference_adjudicated", []) if a.get("why")}
    for other, base in subjects.items():
        if other != b["id"] and base.lower() in low and base not in ok_refs:
            bad.append(f"{b['id']}: brief names {other}'s subject {base!r} (cross-brief priming, "
                       f"not adjudicated in the manifest)")

# E. one preamble — normalise away the two fields a brief is allowed to vary
pres = {}
for b in briefs:
    text = open(os.path.join(here, b["prompt_path"])).read()
    pre = text.split("```bash\n")[0]
    pre = pre.replace(b["id"], "<ID>").replace(b["subject_path"], "<SUBJECT>")
    pres.setdefault(pre, []).append(b["id"])
if len(pres) != 1:
    bad.append("preambles differ across briefs: " + " | ".join(str(v) for v in pres.values()))

if bad:
    for x in bad:
        print("   FAIL " + x)
    raise SystemExit(1)
print(f"   ok   {n} briefs · {clean} clean · {n - clean} with ground truth · one preamble · no leaks")
PY

if [ "$fail" -ne 0 ]; then
	note "CORPUS: RED"
	exit 1
fi
note "CORPUS: GREEN"
