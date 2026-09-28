#!/usr/bin/env bats
# docs/research/memory-eval/recall_eval.py — the memory recall eval (TrueMemory adoption item #5).
#
# Runs the committed SYNTHETIC fixture (docs/research/memory-eval/fixture/) and pins exact metrics
# for the loaded-only and load-everything arms, so a change to tokenising, truncation, bm25 weights
# or gold matching moves a number here instead of silently moving the private field results. The
# private gold under ~/.claude/autonomy/memory-eval/ is never read: HOME is a fixture, and its
# absence is itself asserted (loud NOT-RUN, exit 0). Never skips.
#
# Fixture metrics were computed once by hand-checkable construction: loaded-only is
# query-independent (the MEMORY.md links in file order, then the rules file and the lesson its hook
# links), so each rank below is a position in that fixed list.
#
# Assertions are simple commands only: bash exempts `[[ ]]` from errexit, so a non-final `[[ ]]`
# would be evaluated and discarded (scripts/bats-assert-liveness.py).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  EVAL="$REPO/docs/research/memory-eval/recall_eval.py"
  FX="$REPO/docs/research/memory-eval/fixture"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  STORE="$FX/projects/demo-app/memory"
  CORPUS=(--store "$STORE" --lessons "$FX/lessons" --rules "$FX/rules/always-loaded.md")
  OUT="$BATS_TEST_TMPDIR/out.json"
}

# run_eval <extra args…> — score the fixture corpus, results JSON to $OUT.
run_eval() {
  run python3 "$EVAL" "${CORPUS[@]}" --queries "$FX/queries.json" --out "$OUT" "$@"
}

# metric <arm> <style> <key> — one summary value out of $OUT.
metric() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["arms"][sys.argv[2]][sys.argv[3]][sys.argv[4]])' \
    "$OUT" "$1" "$2" "$3"
}

# row_class <arm> <id> <style> — the outcome class of one scored row.
row_class() {
  python3 -c 'import json,sys; print(next(r["class"] for r in json.load(open(sys.argv[1]))["rows"] if r["arm"]==sys.argv[2] and r["id"]==sys.argv[3] and r["style"]==sys.argv[4]))' \
    "$OUT" "$1" "$2" "$3"
}

@test "loaded-only: exact fixture metrics (ranks 5 and 3 in the fixed list, two unreachable)" {
  run_eval --arms loaded-only
  [ "$status" -eq 0 ]
  [ "$(metric loaded-only op n_scored)" = "4" ]
  [ "$(metric loaded-only op r1)" = "0.0" ]
  [ "$(metric loaded-only op r5)" = "0.5" ]
  [ "$(metric loaded-only op mrr)" = "0.1333" ]
  [ "$(metric loaded-only op reach)" = "2" ]
  [ "$(metric loaded-only op r5_ci)" = "[0.15, 0.85]" ]
  # the one dev authored query's gold is the lesson a resident rules hook links: position 10
  [ "$(metric loaded-only authored mrr)" = "0.1" ]
  [ "$(metric loaded-only authored r5)" = "0.0" ]
}

@test "loaded-only: a file linked only from the COLD archive is not reached" {
  run_eval --arms loaded-only
  [ "$status" -eq 0 ]
  [ "$(row_class loaded-only fx-legacy-1 op)" = "miss" ]
}

@test "load-everything: exact fixture metrics at weights 10,5,1" {
  run_eval --arms load-everything --weights 10,5,1
  [ "$status" -eq 0 ]
  [ "$(metric load-everything op n_scored)" = "4" ]
  [ "$(metric load-everything op r1)" = "1.0" ]
  [ "$(metric load-everything op mrr)" = "1.0" ]
  [ "$(metric load-everything ag r5)" = "1.0" ]
  [ "$(metric load-everything authored r1)" = "1.0" ]
  [ "$(metric load-everything op r1_ci)" = "[0.5101, 1.0]" ]
  [ "$(row_class load-everything fx-legacy-1 op)" = "hit" ]
}

@test "gold-missing is its own class and never counted as a miss" {
  run_eval --arms loaded-only,load-everything
  [ "$status" -eq 0 ]
  [ "$(row_class load-everything fx-gone-1 op)" = "gold-missing" ]
  [ "$(row_class loaded-only fx-gone-1 op)" = "gold-missing" ]
  [ "$(metric load-everything op classes)" = "{'hit': 4, 'miss': 0, 'gold-missing': 2, 'in-context-not-obeyed': 1, 'reinforced-superseding-memory': 1}" ]
  [ "$(metric loaded-only op classes)" = "{'hit': 2, 'miss': 2, 'gold-missing': 3, 'in-context-not-obeyed': 1, 'reinforced-superseding-memory': 0}" ]
}

@test "gold born after the miss is not time-valid: the row is gold-missing" {
  run_eval --arms load-everything
  [ "$status" -eq 0 ]
  [ "$(row_class load-everything fx-born-late op)" = "gold-missing" ]
}

@test "in-context-not-obeyed comes from the record label and is not a miss" {
  run_eval --arms load-everything
  [ "$status" -eq 0 ]
  [ "$(row_class load-everything fx-retry-1 op)" = "in-context-not-obeyed" ]
}

@test "reinforced-superseding-memory: a top hit that declares 'Replaces:' is reported" {
  run_eval --arms load-everything
  [ "$status" -eq 0 ]
  [ "$(row_class load-everything fx-images op)" = "reinforced-superseding-memory" ]
  run python3 "$EVAL" "${CORPUS[@]}" --queries "$FX/queries.json" --arms load-everything
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -Eq '^load-everything +op +4 .* 0 +2 +1 +1$'
}

@test "the loader's 200-line cap drops every MEMORY.md link below it" {
  mkdir -p "$BATS_TEST_TMPDIR/s"
  cp -R "$STORE" "$BATS_TEST_TMPDIR/s/memory"
  { for _ in $(seq 1 200); do echo "filler line"; done; cat "$STORE/MEMORY.md"; } \
    >"$BATS_TEST_TMPDIR/s/memory/MEMORY.md"
  run python3 "$EVAL" --store "$BATS_TEST_TMPDIR/s/memory" --lessons "$FX/lessons" \
    --rules "$FX/rules/always-loaded.md" --queries "$FX/queries.json" --out "$OUT" --arms loaded-only
  [ "$status" -eq 0 ]
  [ "$(metric loaded-only op reach)" = "0" ]
  [ "$(metric loaded-only authored mrr)" = "0.5" ]
}

@test "the loader's 25,000-unit cap drops links past it even under 200 lines" {
  mkdir -p "$BATS_TEST_TMPDIR/s"
  cp -R "$STORE" "$BATS_TEST_TMPDIR/s/memory"
  { head -c 25000 /dev/zero | tr '\0' 'x'; echo; cat "$STORE/MEMORY.md"; } \
    >"$BATS_TEST_TMPDIR/s/memory/MEMORY.md"
  run python3 "$EVAL" --store "$BATS_TEST_TMPDIR/s/memory" --lessons "$FX/lessons" \
    --rules "$FX/rules/always-loaded.md" --queries "$FX/queries.json" --out "$OUT" --arms loaded-only
  [ "$status" -eq 0 ]
  [ "$(metric loaded-only op reach)" = "0" ]
}

@test "a path-scoped rules file (paths: frontmatter) is not resident, so loaded-only skips it" {
  mkdir -p "$BATS_TEST_TMPDIR/r"
  { printf -- '---\npaths:\n  - "src/**"\n---\n'; cat "$FX/rules/always-loaded.md"; } \
    >"$BATS_TEST_TMPDIR/r/always-loaded.md"
  run python3 "$EVAL" --store "$STORE" --lessons "$FX/lessons" --rules "$BATS_TEST_TMPDIR/r/always-loaded.md" \
    --queries "$FX/queries.json" --out "$OUT" --arms loaded-only
  [ "$status" -eq 0 ]
  [ "$(metric loaded-only authored reach)" = "0" ]
}

@test "a git-tracked lesson is born at its first add, even in a checkout flagged core.bare" {
  r="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$r/docs/lessons" "$r/mem"
  cp "$FX/lessons/lockfile-drift-breaks-ci.md" "$r/docs/lessons/"
  git -C "$r" init -q
  git -C "$r" add docs/lessons
  GIT_AUTHOR_DATE="2001-06-01T00:00:00Z" GIT_COMMITTER_DATE="2001-06-01T00:00:00Z" \
    git -C "$r" -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m lesson
  # the state a shared checkout is left in by a worktree op: `rev-parse --show-toplevel` refuses
  # and `git -C <subdir> log --relative -- .` returns repo-wide, root-relative names
  git -C "$r" config core.bare true
  printf '%s\n' '[{"id": "fx-lesson", "miss_ts": "2005-01-01T00:00:00Z",' \
    '"operator_verbatim": "ci fails because the lockfile no longer matches the package manifest",' \
    '"gold": ["demo:docs/lessons/lockfile-drift-breaks-ci.md"]}]' >"$BATS_TEST_TMPDIR/q.json"
  run python3 "$EVAL" --store "$r/mem" --lessons "$r/docs/lessons" --queries "$BATS_TEST_TMPDIR/q.json" \
    --out "$OUT" --arms load-everything
  [ "$status" -eq 0 ]
  [ "$(row_class load-everything fx-lesson op)" = "hit" ]
}

@test "a frozen snapshot scores identically to the live corpus" {
  run python3 "$EVAL" "${CORPUS[@]}" --snapshot "$BATS_TEST_TMPDIR/snap"
  [ "$status" -eq 0 ]
  [ -s "$BATS_TEST_TMPDIR/snap/MANIFEST.sha256" ]
  run python3 "$EVAL" --corpus "$BATS_TEST_TMPDIR/snap" --queries "$FX/queries.json" \
    --arms loaded-only,load-everything --out "$OUT"
  [ "$status" -eq 0 ]
  [ "$(metric loaded-only op mrr)" = "0.1333" ]
  [ "$(metric load-everything op r1)" = "1.0" ]
  [ "$(row_class load-everything fx-born-late op)" = "gold-missing" ]
}

@test "a snapshot file that no longer matches its manifest refuses to score, exit 3" {
  run python3 "$EVAL" "${CORPUS[@]}" --snapshot "$BATS_TEST_TMPDIR/snap"
  [ "$status" -eq 0 ]
  echo "tampered" >>"$BATS_TEST_TMPDIR/snap/stores/demo-app/cron-utc-offset.md"
  run python3 "$EVAL" --corpus "$BATS_TEST_TMPDIR/snap" --queries "$FX/queries.json" --arms loaded-only
  [ "$status" -eq 3 ]
  printf '%s\n' "$output" | grep -q 'REFUSED: corpus'
  printf '%s\n' "$output" | grep -q 'sha mismatch: stores/demo-app/cron-utc-offset.md'
}

@test "an unlisted file added to a snapshot also refuses, exit 3" {
  run python3 "$EVAL" "${CORPUS[@]}" --snapshot "$BATS_TEST_TMPDIR/snap"
  [ "$status" -eq 0 ]
  echo "# stray" >"$BATS_TEST_TMPDIR/snap/lessons/stray.md"
  run python3 "$EVAL" --corpus "$BATS_TEST_TMPDIR/snap" --queries "$FX/queries.json" --arms loaded-only
  [ "$status" -eq 3 ]
  printf '%s\n' "$output" | grep -q 'unlisted: lessons/stray.md'
}

@test "absent private gold prints a loud NOT-RUN and exits 0" {
  run python3 "$EVAL" "${CORPUS[@]}"
  [ "$status" -eq 0 ]
  [ "$output" = "NOT-RUN: private gold absent at $HOME/.claude/autonomy/memory-eval/field-queries.json" ]
}

@test "retriever arm with no executable is NOT-RUN and excluded, never scored as zero" {
  run_eval --arms retriever,load-everything --retriever-cmd "$BATS_TEST_TMPDIR/no-such-cli"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q "ARM retriever NOT-RUN: no executable at $BATS_TEST_TMPDIR/no-such-cli"
  run python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sorted(d["arms"]), sorted(d["not_run"]))' "$OUT"
  [ "$output" = "['load-everything'] ['retriever']" ]
}

@test "retriever arm runs the CLI with the hook's argv and scores its --json output" {
  fake="$BATS_TEST_TMPDIR/fake-search"
  cat >"$fake" <<EOF
#!/bin/sh
printf '%s\n' "weights=\$CC_MEMORY_SEARCH_WEIGHTS \$*" >>"$BATS_TEST_TMPDIR/argv.log"
printf '[{"path":"%s","name":"sqlite-locked-writes","description":"","store":"demo-app","score":2.0,"score_space":"bm25"},' "$STORE/sqlite-locked-writes.md"
printf '{"path":"%s","name":"cron-utc-offset","description":"","store":"demo-app","score":1.0,"score_space":"bm25"}]\n' "$STORE/cron-utc-offset.md"
EOF
  chmod +x "$fake"
  run_eval --arms retriever --retriever-cmd "$fake" --weights 5,3,1
  [ "$status" -eq 0 ]
  # sqlite at rank 1, cron at rank 2, legacy and the lesson missed: R@1 1/4, MRR (1 + 1/2)/4
  [ "$(metric retriever op n_scored)" = "4" ]
  [ "$(metric retriever op r1)" = "0.25" ]
  [ "$(metric retriever op r5)" = "0.5" ]
  [ "$(metric retriever op mrr)" = "0.375" ]
  [ "$(row_class retriever fx-images op)" = "gold-missing" ]
  grep -q -- "^weights=5,3,1 --json --top 5 --store $STORE --lessons $FX/lessons --rules $FX/rules/always-loaded.md the app keeps throwing database is locked" "$BATS_TEST_TMPDIR/argv.log"
}

@test "holdout is sealed by default and scores only with --unseal" {
  run python3 "$EVAL" "${CORPUS[@]}" --queries "$FX/queries.json" --split holdout
  [ "$status" -eq 0 ]
  [ "$output" = "SEALED: holdout numbers print only with --split holdout --unseal" ]
  run_eval --arms load-everything --split holdout --unseal
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; print(sorted({r["id"] for r in json.load(open(sys.argv[1]))["rows"]}))' "$OUT"
  [ "$output" = "['q-docker']" ]
}

# ── fusion_eval.py (Wave E #4b): FTS5 + model2vec RRF over the same corpus ─────────────────────────
# A STUB model2vec on PYTHONPATH returns fixed vectors (letter counts), so no model is downloaded.

FUSE_PY="docs/research/memory-eval/fusion_eval.py"

stub_m2v() {
  # the CLI's feedback sweep globs $CLAUDE_CONFIG_DIR/projects: pin it inside the fixture HOME
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  unset MEMORY_INDEX_PATH
  mkdir -p "$BATS_TEST_TMPDIR/stub/model2vec"
  cat >"$BATS_TEST_TMPDIR/stub/model2vec/__init__.py" <<'PY'
class StaticModel:
    @classmethod
    def from_pretrained(cls, name):
        return cls()

    def encode(self, texts):
        return [[float(t.lower().count(c)) + 0.01 for c in "abcdefghijklmnopqrstuvwxyz"] for t in texts]
PY
}

# run_fuse — the fused eval over the fixture corpus, results JSON to $OUT.
run_fuse() {
  run env PYTHONPATH="$BATS_TEST_TMPDIR/stub" python3 "$REPO/$FUSE_PY" "${CORPUS[@]}" \
    --queries "$FX/queries.json" --out "$OUT"
}

# fuse_row <id> <style> <key> — one field of one row out of $OUT.
fuse_row() {
  python3 -c 'import json,sys; print(next(r[sys.argv[4]] for r in json.load(open(sys.argv[1]))["rows"] if r["id"]==sys.argv[2] and r["style"]==sys.argv[3]))' \
    "$OUT" "$1" "$2" "$3"
}

@test "fusion: RRF k=60 arithmetic on a hand case, ties kept in first-appearance order" {
  cd "$REPO/docs/research/memory-eval"
  # a = 1/61 + 1/62, c = 1/63 + 1/61, b = 1/62, d = 1/63
  run python3 -c 'import fusion_eval as f; print(f.rrf([[1, 2, 3], [3, 1, 4]]), f.rrf([[7], [8]]))'
  [ "$status" -eq 0 ]
  [ "$output" = "[1, 3, 2, 4] [7, 8]" ]
  run python3 -c 'import fusion_eval as f; print(f.sign_test(5, 0), f.sign_test(7, 1), f.sign_test(4, 0), f.sign_test(0, 0))'
  [ "$output" = "0.03125 0.03515625 0.0625 1.0" ]
}

@test "fusion: the fused arm ranks the fixture deterministically, identical across runs" {
  stub_m2v
  run_fuse
  [ "$status" -eq 0 ]
  first="$(fuse_row fx-sqlite op top5_fused)"
  [ "$first" = "['store:demo-app/sqlite-locked-writes.md', 'store:demo-app/csv-quote-escaping.md', 'store:demo-app/flaky-network-retry.md', 'lessons:retry-needs-jitter.md', 'store:demo-app/color-palette-choice.md']" ]
  [ "$(fuse_row fx-sqlite op top5_fts)" = "['store:demo-app/sqlite-locked-writes.md']" ]
  run_fuse
  [ "$status" -eq 0 ]
  [ "$(fuse_row fx-sqlite op top5_fused)" = "$first" ]
  printf '%s\n' "$output" | grep -qx 'op  sign wins=0 losses=0 ties=7 p=1.0'
  printf '%s\n' "$output" | grep -qx 'VERDICT op DROP'
}

@test "fusion: born-late gold is gold-missing in both arms; a superseding top hit is counted" {
  stub_m2v
  run_fuse
  [ "$status" -eq 0 ]
  [ "$(fuse_row fx-born-late op class)" = "gold-missing" ]
  [ "$(fuse_row fx-born-late op rank_fused)" = "11" ]
  [ "$(fuse_row fx-images op sup_fts)" = "True" ]
  [ "$(fuse_row fx-images op sup_fused)" = "True" ]
}

@test "fusion: a gold file the CLI dropped as a same-name twin counts through its kept twin" {
  stub_m2v
  mkdir -p "$BATS_TEST_TMPDIR/a/memory" "$BATS_TEST_TMPDIR/b/memory"
  cp "$STORE/sqlite-locked-writes.md" "$BATS_TEST_TMPDIR/a/memory/"
  cp "$STORE/sqlite-locked-writes.md" "$BATS_TEST_TMPDIR/b/memory/"
  printf '%s\n' '[{"id": "tw", "miss_ts": "2099-01-01T00:00:00Z",' \
    '"operator_verbatim": "database is locked when two workers write",' \
    '"gold": ["store:b/sqlite-locked-writes.md"]}]' >"$BATS_TEST_TMPDIR/q.json"
  run env PYTHONPATH="$BATS_TEST_TMPDIR/stub" python3 "$REPO/$FUSE_PY" --store "$BATS_TEST_TMPDIR/a/memory" \
    --store "$BATS_TEST_TMPDIR/b/memory" --queries "$BATS_TEST_TMPDIR/q.json" --out "$OUT"
  [ "$status" -eq 0 ]
  [ "$(fuse_row tw op top5_fts)" = "['store:a/sqlite-locked-writes.md']" ]
  [ "$(fuse_row tw op rank_fts)" = "1" ]
  [ "$(fuse_row tw op rank_fused)" = "1" ]
}

@test "fusion: --project-map resolves the shipped default scope per query through MEMORY_INDEX_PATH" {
  stub_m2v
  root="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$root/docs/lessons" "$root/.claude/rules" "$BATS_TEST_TMPDIR/demo-app"
  cp -R "$STORE" "$BATS_TEST_TMPDIR/demo-app/memory"
  cp "$FX/lessons/lockfile-drift-breaks-ci.md" "$root/docs/lessons/"
  printf '{"demo-app": {"store": "%s", "root": "%s"}}\n' "$BATS_TEST_TMPDIR/demo-app/memory" "$root" >"$BATS_TEST_TMPDIR/map.json"
  run env PYTHONPATH="$BATS_TEST_TMPDIR/stub" python3 "$REPO/$FUSE_PY" --project-map "$BATS_TEST_TMPDIR/map.json" \
    --queries "$FX/queries.json" --out "$OUT"
  [ "$status" -eq 0 ]
  [ "$(fuse_row fx-sqlite op rank_fts)" = "1" ]
  [ "$(fuse_row fx-lesson op rank_fts)" = "1" ]
  # the lesson came from the map's repo root (docs/lessons), resolved by the CLI's own scope rule
  fuse_row fx-lesson op top5_fts | grep -q "^\['lessons:lockfile-drift-breaks-ci.md'"
  printf '%s\n' "$output" | grep -qx 'UNMAPPED 2 record(s) with no --project-map entry: q-docker q-jitter-1'
}

@test "fusion: with model2vec absent the fused arm is NOT-RUN, FTS5 still scores, no log is written" {
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl" CLAUDE_CONFIG_DIR="$HOME/.claude"
  run env PYTHONPATH="$BATS_TEST_TMPDIR/no-such-dir" python3 "$REPO/$FUSE_PY" "${CORPUS[@]}" \
    --queries "$FX/queries.json" --out "$OUT"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q "^ARM fused NOT-RUN: model2vec unavailable (ModuleNotFoundError"
  printf '%s\n' "$output" | grep -qx 'VERDICT op NOT-RUN'
  run python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sorted(d["styles"]["op"]["arms"]), d["styles"]["op"]["arms"]["fts"]["r1"])' "$OUT"
  [ "$output" = "['fts'] 1.0" ]
  [ ! -e "$CC_IDL" ]
  [ ! -e "$HOME/.claude/state/memory-search.jsonl" ]
}
