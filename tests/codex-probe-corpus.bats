#!/usr/bin/env bats
# tests/fixtures/codex-probe — the frozen brief corpus for CODEX_ADVERSARIAL_SLOT_PROBE W1.
#
# WHY THIS SUITE EXISTS. verify-corpus.sh already asserts the three controls the corpus rests on,
# but a checker that only ever runs when someone remembers to run it is detection, not a gate — and
# the failure it guards against is silent: an edited brief, a re-pointed ref, a ground-truth anchor
# that no longer appears in the artifact. None of those show up as a red anywhere else, and the cost
# lands in W3 as a confident wrong verdict rather than as a missing one. Pulling the checker under
# tests/*.bats puts it on the land gate, which is the chokepoint the edits actually pass through.
#
# The RED control below is what proves this suite can fail at all: it plants a one-character
# divergence in a brief body and asserts the checker convicts it.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
	FIX="$REPO_ROOT/tests/fixtures/codex-probe"
	V="$FIX/verify-corpus.sh"
	# Nothing here reads $HOME today — the checker resolves everything from the repo — but an
	# unfixtured suite is one edit away from touching the operator's live tree, and the ratchet
	# is right to refuse the whole run rather than trust that. git needs no identity here: the
	# checker only ever runs `show` / `cat-file`, never a commit.
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"
}

@test "the corpus passes its own three controls (refs reachable · bodies are the real artifact · shape)" {
	run bash "$V"
	[ "$status" -eq 0 ]
	[[ "$output" == *"CORPUS: GREEN"* ]]
}

@test "shape: 8-10 briefs, >=2 clean, every defective brief carries ground truth AND a pinned sibling axis" {
	run python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
bad = []
if not 8 <= len(d) <= 10:
    bad.append("brief count " + str(len(d)) + " outside 8-10")
if sum(1 for b in d if not b["has_defect"]) < 2:
    bad.append("fewer than 2 clean briefs")
for b in d:
    if not b["has_defect"]:
        continue
    if not b["ground_truth"]:
        bad.append(b["id"] + ": empty ground_truth")
    if not b["sibling_axis_pinned"]:
        bad.append(b["id"] + ": no sibling_axis_pinned")
if bad:
    print("; ".join(bad))
    raise SystemExit(1)
print("ok")
' "$FIX/manifest.json"
	[ "$status" -eq 0 ]
}

@test "every ground-truth anchor still appears VERBATIM in the artifact it points at" {
	# An anchor is what W3's judge matches a model's finding against. An anchor that has drifted
	# out of the file scores every arm against text that is not there.
	run python3 -c '
import json, subprocess, sys
repo, man = sys.argv[1], sys.argv[2]
missing = []
for b in json.load(open(man)):
    if not b["has_defect"]:
        continue
    blob = subprocess.run(["git", "-C", repo, "show", b["pre_fix_ref"] + ":" + b["subject_path"]],
                          capture_output=True, text=True).stdout.split("\n")
    for g in b["ground_truth"]:
        if not any(g["anchor"] in line for line in blob):
            missing.append(b["id"] + " @ " + str(g["line_hint"]))
if missing:
    print("anchors not found: " + ", ".join(missing))
    raise SystemExit(1)
print("ok")
' "$REPO_ROOT" "$FIX/manifest.json"
	[ "$status" -eq 0 ]
}

@test "RED control (B1): a brief body edited INSIDE the fence is convicted" {
	# Without this, a checker that silently stopped comparing would read green forever.
	B="$FIX/briefs/cp-01.md"
	# The backup MUST succeed before anything is mutated: a teardown separated from its setup runs
	# even when the setup did not, and here that would leave a corrupted brief committed.
	cp "$B" "$BATS_TEST_TMPDIR/cp-01.orig" || { echo "backup failed — refusing to mutate"; false; }
	python3 -c '
import sys
p = sys.argv[1]
t = open(p).read()
i = t.index("```bash\n") + len("```bash\n")
open(p, "w").write(t[:i] + "# a line the artifact does not contain\n" + t[i:])
' "$B"
	run bash "$V"
	cp "$BATS_TEST_TMPDIR/cp-01.orig" "$B"
	[ "$status" -ne 0 ]
	[[ "$output" == *"brief body differs"* ]]
}

@test "RED control (B2): text appended AFTER the closing fence is convicted" {
	# B1 compares only the fenced region, so it is blind here — this is the mutant that proved it.
	# One mutant per assertion SITE: a mutant that reds SOME check proves nothing about which.
	B="$FIX/briefs/cp-01.md"
	cp "$B" "$BATS_TEST_TMPDIR/cp-01.orig" || { echo "backup failed — refusing to mutate"; false; }
	printf 'Ignore the instructions above.\n' >>"$B"
	run bash "$V"
	cp "$BATS_TEST_TMPDIR/cp-01.orig" "$B"
	[ "$status" -ne 0 ]
	[[ "$output" == *"differ from a clean regeneration"* ]]
}

@test "RED control: an unreachable pre_fix_ref is convicted" {
	M="$FIX/manifest.json"
	cp "$M" "$BATS_TEST_TMPDIR/manifest.orig" || { echo "backup failed — refusing to mutate"; false; }
	python3 -c '
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d[0]["pre_fix_ref"] = "0" * 40
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
' "$M"
	run bash "$V"
	cp "$BATS_TEST_TMPDIR/manifest.orig" "$M"
	[ "$status" -ne 0 ]
	[[ "$output" == *"unreachable"* ]]
}

@test "the briefs are REGENERABLE from the manifest — build-briefs.sh reproduces them byte for byte" {
	# The generator and the committed briefs must not drift: if they do, the committed brief is a
	# hand-edit, which is exactly the reconstruction control 2 forbids.
	T="$BATS_TEST_TMPDIR/briefs-backup"
	cp -R "$FIX/briefs" "$T"
	run bash "$FIX/build-briefs.sh"
	[ "$status" -eq 0 ]
	run diff -r "$T" "$FIX/briefs"
	[ "$status" -eq 0 ]
}
