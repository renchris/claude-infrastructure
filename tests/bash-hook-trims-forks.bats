#!/usr/bin/env bats
# bash-hook-trims-forks.bats — the process budget of seven per-call Bash hooks, and proof that the
# W4 trims changed nothing they print, return or leave on disk.
#
# The trims (docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md, W4 fork trims):
#   curl-gate-scope.sh     resolves the real gate's path only when it delegates
#   rm-safe-allowlist.sh   the builtin `rm` test runs before the danger grep
#   research-block.sh, lib/research-router.sh, memory-index-drain.sh, bash-output-offload.sh
#                          dirname(1) by parameter expansion
#   smart-bash-allowlist.sh, bash-output-offload.sh
#                          python3 -S (no site import), plus a stdlib-only import guard
#
# Parity is against the REAL pre-change hooks, rebuilt from git (stop-hook-forks-helpers.bash).
# Every hook is invoked through a symlink, the way the live ~/.claude layer reaches it, so the
# symlink walks the trims touch actually run. The two arms run one after the other over the SAME
# paths from the same blank state. Counts come from PATH stubs that log every external command.
#
# Assertions are simple commands only (bash exempts `[[ ]]` from errexit in a bats body).

load stop-hook-forks-helpers
# The commit just before this wave (the helper's own SHF_BASE belongs to an earlier wave).
SHF_BASE=55d01fcd4fca631650df1dbae16e91cfa30821c5

setup_file() {
  STUB="$BATS_FILE_TMPDIR/stub"
  shf_build_stubs "$STUB"
  # The same stubs with a BSD readlink that refuses -f, so the hooks' fallback symlink walks run
  # (the only path that reaches memory-index-drain's and bash-output-offload's inner dirname).
  STUB_BSD="$BATS_FILE_TMPDIR/stub-bsd"
  cp -R "$STUB" "$STUB_BSD"
  local real_rl
  real_rl="$(command -v readlink)"
  # shellcheck disable=SC2016  # $SHF_FORK_LOG and $1/$@ belong to the generated wrapper
  printf '#!/bin/bash\nprintf %%s\\\\n readlink >> "$SHF_FORK_LOG"\n[ "$1" = -f ] && exit 1\nexec %s "$@"\n' \
    "'$real_rl'" > "$STUB_BSD/readlink"
  chmod +x "$STUB_BSD/readlink"
  export STUB STUB_BSD
}

setup() {
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID CC_HOOK_PROFILE CC_CURL_GATE_BIN \
        CC_CURL_GATE_SCOPE CC_CURL_GATE_ROOT CC_CURL_GATE_WORKTREES_ROOT CC_RESEARCH_BLOCK \
        CC_RESEARCH_ROUTER_INNER CC_RESEARCH_PROGRAM_LIB CC_RESEARCH_ROUTER_PY MEMORY_INDEX_PATH \
        CC_BASH_OFFLOAD CC_BASH_OFFLOAD_CHARS CC_BASH_OFFLOAD_DIR CURL_GATE_DISABLED
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  OLD="$BATS_TEST_TMPDIR/old"
  ROOT="$BATS_TEST_TMPDIR/root"
  export HOME="$ROOT/home"
  export CLAUDE_CONFIG_DIR="$ROOT/cfg"
  export TMPDIR="$ROOT/tmp/"
  export CC_IDL="$ROOT/idl.jsonl"
  export CC_LESSON_RECALL_STATE_DIR="$ROOT/lr"
  export MEMORY_DRAIN_STATE_DIR="$ROOT/drain"
  export CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/no-registry.json"
  export SHF_OUT_DIR="$BATS_TEST_TMPDIR/out"; mkdir -p "$SHF_OUT_DIR"
  W="$BATS_TEST_TMPDIR/w"; mkdir -p "$W"
}

have_old() {
  shf_old_tree "$OLD" "$REPO" hooks/curl-gate-scope.sh hooks/rm-safe-allowlist.sh \
    hooks/research-block.sh hooks/lib/research-router.sh hooks/memory-index-drain.sh \
    hooks/bash-output-offload.sh hooks/smart-bash-allowlist.sh \
    || skip "the pre-change commit $SHF_BASE is not in this clone"
}

# live <arm> <hook> → a symlink to the arm's hook inside a live-like hooks/ dir (lib/ beside it).
# bare <arm> <hook> → the same symlink with no lib/ beside it, so a hook takes its fallback path.
live() {
  local tree="$REPO"; [ "$1" = old ] && tree="$OLD"
  mkdir -p "$BATS_TEST_TMPDIR/live-$1/hooks"
  [ -e "$BATS_TEST_TMPDIR/live-$1/hooks/lib" ] || ln -s "$tree/hooks/lib" "$BATS_TEST_TMPDIR/live-$1/hooks/lib"
  ln -sf "$tree/hooks/$2" "$BATS_TEST_TMPDIR/live-$1/hooks/$2"
  printf '%s' "$BATS_TEST_TMPDIR/live-$1/hooks/$2"
}
# rel <arm> <hook> → a RELATIVE symlink to the live one (lib/ beside it): a symlink walk without
# readlink -f takes the relative branch, which is the one that called dirname per hop.
rel() {
  live "$1" "$2" >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/rel-$1/hooks"
  [ -e "$BATS_TEST_TMPDIR/rel-$1/hooks/lib" ] || ln -s "../../live-$1/hooks/lib" "$BATS_TEST_TMPDIR/rel-$1/hooks/lib"
  ln -sf "../../live-$1/hooks/$2" "$BATS_TEST_TMPDIR/rel-$1/hooks/$2"
  printf '%s' "$BATS_TEST_TMPDIR/rel-$1/hooks/$2"
}
bare() {
  local tree="$REPO"; [ "$1" = old ] && tree="$OLD"
  mkdir -p "$BATS_TEST_TMPDIR/bare-$1"
  ln -sf "$tree/hooks/$2" "$BATS_TEST_TMPDIR/bare-$1/$2"
  printf '%s' "$BATS_TEST_TMPDIR/bare-$1/$2"
}

blank() { rm -rf "$ROOT"; mkdir -p "$HOME/.claude" "$CLAUDE_CONFIG_DIR" "$TMPDIR"; }

# snap <label> — every file the arm left under $ROOT: its path, then its bytes with any wall-clock
# field (a JSON "ts", a TSV log's leading timestamp) blanked, so two arms a second apart compare equal.
snap() {
  local f list="$SHF_OUT_DIR/$1.files"
  # The list is its own file: reading the .state file while appending to it never reaches EOF.
  ( cd "$ROOT" && find . -type f | LC_ALL=C sort ) > "$list"
  while IFS= read -r f; do
    printf '== %s\n' "$f"
    sed -E 's/"ts": ?"[^"]*"/"ts":""/g; s/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z/TS/' "$ROOT/$f"
  done < "$list" > "$SHF_OUT_DIR/$1.state"
}

# pair <case> <old hook> <new hook> <payload file> [stub dir] — run both arms from a blank $ROOT,
# then require identical stdout, stderr, rc and state. Leaves counts in <case>.old/.new.forks.
pair() {
  local c="$1" ho="$2" hn="$3" pl="$4" st="${5:-$STUB}" rco=0 rcn=0 k
  blank; STUB="$st" shf_run "$c.old" "$ho" < "$pl" || rco=$?; snap "$c.old"
  blank; STUB="$st" shf_run "$c.new" "$hn" < "$pl" || rcn=$?; snap "$c.new"
  [ "$rco" = "$rcn" ] || { echo "$c: rc old=$rco new=$rcn"; return 1; }
  # A wall-clock value the hook prints (PAIR_NORM, a sed -E script) is blanked in both arms alike.
  if [ -n "${PAIR_NORM:-}" ]; then
    for k in out err state; do
      sed -E -i '' "$PAIR_NORM" "$SHF_OUT_DIR/$c.old.$k" "$SHF_OUT_DIR/$c.new.$k"
    done
  fi
  for k in out err state; do
    cmp -s "$SHF_OUT_DIR/$c.old.$k" "$SHF_OUT_DIR/$c.new.$k" || {
      echo "$c: $k differs"; echo "--- old"; head -c 2000 "$SHF_OUT_DIR/$c.old.$k"
      echo "--- new"; head -c 2000 "$SHF_OUT_DIR/$c.new.$k"; return 1; }
  done
}

# Real commands from ~/.claude/logs/bash-commands.log (most are compound), plus the shapes each
# hook decides on: rm forms, catastrophic forms, and curl into the gated project and a worktree.
corpus() {
  cat <<'CORPUS'
git diff -- scripts/kitty-build-swap.sh tests/kitty-build-swap.bats
cat /private/tmp/claude-501/x/tasks/bc8xtg6sc.output | tail -6
until grep -q "GATE rc=" /tmp/r12p-gate.log; do sleep 15; done; grep -E "^FAILED|GATE rc=" /tmp/r12p-gate.log | head -20
sed -n 2640,2740p scripts/limit-recover/lr-upgrade.sh
cd ~/Development/claude-infrastructure; git ls-files | grep -i 'e1k-ab-run3' | head; sed -n 727,775p scripts/research-kit/heldout.py
export PATH=/opt/homebrew/bin:$HOME/.local/bin:$PATH; cc-context 2>/dev/null | tail -2; sysctl -n vm.loadavg
R=docs/research/tm2-cost-vs-outcome-2026-10-16; cat $R/data/k_census.log; python3 -I $R/scripts/p_kit.py 2>&1 | head -60
sed -n 1,25p scripts/research-kit/heldout.py && sed -n 46,60p scripts/research-kit/heldout.py
gh api repos/o/r/issues/835 --jq .body | grep -n -i -B2 -A2 "benchmark methodology" | cut -c1-400
cd /tmp/r12core.bZQQJz && grep -n "def _empty_waits" -A22 src/agentsync/arm_local.py
R=/private/tmp/rehearsal-v20-c; sed "s#$R#<root>#g" $R/logs/report.C1.md | sed -n '14,30p;120,200p'
cd /tmp && grep -n '^_CONVERTED_NOTE_RE' -A8 r12-sr.py
sed -n 3725,3830p /tmp/inst-8814.sh
sed -n 445,565p src/agentsync/loop.py
ls -la ~/.claude/skills/ | grep -i dia; ls -la ~/.claude/skills/dia-agent/ 2>&1 | head
./gate.sh read --help 2>&1 | head -8; echo ---; for w in Day0 W1 W9; do echo "== $w"; ./gate.sh requires --wave $w 2>&1 | head -12; done
for i in $(seq 1 115); do [ -s /tmp/rb-pytest3.txt ] && break; perl -e 'select(undef,undef,undef,5)'; done; tail -4 /tmp/rb-pytest3.txt || echo "still running"
cc-sessions --names 2>&1 | grep -E 'browser|rail|197'; echo "rc=$?"; cc-decide list --open 2>&1 | head
uv run --locked pytest -q -p no:cacheprovider tests/test_setup_report.py -k "earlier" 2>&1 | grep -E "^FAILED|passed|failed" | head -20
timeout 30 agent-browser session list 2>&1; ps aux | grep -c "[a]gent-browser-chrome"
git add tests/lr-team.bats && git commit -q --fixup=4ffe28a70 && git log --oneline -2
tail -c 3000 ~/.claude/logs/bash-execution.log | tail -5 | cut -c1-300
ls docs/research/load-root-cause-2026-10-17/ && wc -l scripts/fseventsd-watch.sh && cat -n scripts/fseventsd-watch.sh
cd /Users/chrisren/Development/.worktrees/w2-capdetect && git status --short | head; git log --oneline -1
git -C ~/Development/reso-management-app diff origin/release 3a9db3a65 -- lib/prefetch-kind.ts | cat
$HOME/.claude/scripts/handoff-fire.sh self-close --terminal 2>&1 | head -40
umask 077; mkdir -p $H/docs/_eval; cp $R/seed/questions.md $R/seed/answers.md $H/docs/_eval/
git status --short && git log --oneline -1
ls tests/ | grep -E 'curl-gate|rm-safe' | wc -l
python3 -m pytest tests/test_x.py -q
echo "rm -rf node_modules"
grep -rn 'rm -rf' hooks/ | head
rm -rf node_modules
rm -rf ./dist/ build
rm -f /tmp/x.log
  rm -r .pytest_cache
rm -rf node_modules; ls
rm -rf src
sudo rm x
rm -rf /
rm -rf / --no-preserve-root
:(){ :|:& };:
curl -s https://example.com/api -o /tmp/x.json
curl -sS http://127.0.0.1:3000/api/health
CORPUS
}

# pre <cmd> <cwd> → a PreToolUse Bash payload file; echoes its path
pre() {
  local f="$BATS_TEST_TMPDIR/pre.json"
  jq -cn --arg c "$1" --arg d "$2" \
    '{session_id:"sidA",transcript_path:"/nonexistent/t.jsonl",cwd:$d,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c,description:"d"}}' > "$f"
  printf '%s' "$f"
}
# post <cmd> <stdout file> → a PostToolUse Bash payload file; echoes its path
post() {
  local f="$BATS_TEST_TMPDIR/post.json"
  jq -cn --arg c "$1" --rawfile o "$2" --arg d "$W" \
    '{session_id:"sidA",transcript_path:"/nonexistent/t.jsonl",cwd:$d,hook_event_name:"PostToolUse",tool_name:"Bash",tool_use_id:"tu1",tool_input:{command:$c},tool_response:{stdout:$o,stderr:"",interrupted:false,isImage:false}}' > "$f"
  printf '%s' "$f"
}
# The odd payloads every hook must survive the same way: empty stdin and malformed JSON.
odd_payloads() {
  : > "$BATS_TEST_TMPDIR/empty.json"
  printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf x"' > "$BATS_TEST_TMPDIR/bad.json"
  printf '%s\n' "$BATS_TEST_TMPDIR/empty.json" "$BATS_TEST_TMPDIR/bad.json"
}

# run_corpus <hook> [cwd] — every corpus command plus the odd payloads, through both arms; prints
# one "<case> <old total> <new total>" row per case into $SHF_OUT_DIR/<hook>.counts.
run_corpus() {
  local hook="$1" cwd="${2:-$W}" ho hn i=0 cmd pl
  ho="$(live old "$hook")"; hn="$(live new "$hook")"
  : > "$SHF_OUT_DIR/$hook.counts"
  while IFS= read -r cmd; do
    i=$((i + 1)); pl="$(pre "$cmd" "$cwd")"
    pair "$hook.$i" "$ho" "$hn" "$pl" || return 1
    printf '%s %s %s\n' "$i" "$(shf_total "$hook.$i.old")" "$(shf_total "$hook.$i.new")" >> "$SHF_OUT_DIR/$hook.counts"
  done < <(corpus)
  while IFS= read -r pl; do
    i=$((i + 1))
    pair "$hook.$i" "$ho" "$hn" "$pl" || return 1
    printf '%s %s %s\n' "$i" "$(shf_total "$hook.$i.old")" "$(shf_total "$hook.$i.new")" >> "$SHF_OUT_DIR/$hook.counts"
  done < <(odd_payloads)
}

@test "corpus: at least 40 commands, most of them compound" {
  local n c
  n="$(corpus | grep -c .)"
  c="$(corpus | grep -cE ';|&&|\|')"
  [ "$n" -ge 40 ]
  [ "$c" -ge 20 ]
}

@test "curl-gate-scope: identical over the corpus; no fork at all when it does not delegate" {
  have_old
  run_corpus curl-gate-scope.sh
  # Not one case delegates from a cwd outside the project: the old shim still walked its symlink
  # (readlink + 2 dirname); the new one starts nothing.
  awk '$2 < 1 || $3 != 0 { print "case " $1 ": old " $2 " new " $3; bad = 1 } END { exit bad }' \
    "$SHF_OUT_DIR/curl-gate-scope.sh.counts"
}

@test "curl-gate-scope: identical when it delegates (project path, worktree curl, kill switch)" {
  have_old
  local ho hn pl proj="/Users/chrisren/Development/reso-management-app"
  ho="$(live old curl-gate-scope.sh)"; hn="$(live new curl-gate-scope.sh)"
  pl="$(pre "curl -s http://169.254.169.254/latest/meta-data" "$proj")"
  pair cg.proj "$ho" "$hn" "$pl"
  [ "$(shf_calls cg.proj.new python3)" = 1 ]
  [ "$(shf_total cg.proj.new)" = "$(shf_total cg.proj.old)" ]
  pl="$(pre "curl -s http://localhost:3000/x" "$HOME/Development/.worktrees/reso-wt")"
  pair cg.wt "$ho" "$hn" "$pl"
  [ "$(shf_calls cg.wt.new python3)" = 1 ]
  pl="$(pre "ls" "$W")"
  CC_CURL_GATE_SCOPE=off pair cg.off "$ho" "$hn" "$pl"
  [ "$(shf_calls cg.off.new python3)" = 1 ]
  # The override still names the gate that runs.
  printf 'import sys; sys.stdout.write("override:" + sys.stdin.read()[:12])\n' > "$BATS_TEST_TMPDIR/g.py"
  CC_CURL_GATE_BIN="$BATS_TEST_TMPDIR/g.py" pair cg.bin "$ho" "$hn" "$(pre "curl x" "$proj")"
  grep -q '^override:' "$SHF_OUT_DIR/cg.bin.new.out"
}

@test "rm-safe-allowlist: identical over the corpus; a non-rm command no longer forks grep" {
  have_old
  run_corpus rm-safe-allowlist.sh
  local i=0 cmd nonrm=0
  while IFS= read -r cmd; do
    i=$((i + 1))
    [[ "$cmd" =~ ^[[:space:]]*rm[[:space:]] ]] && continue
    nonrm=$((nonrm + 1))
    [ "$(shf_calls "rm-safe-allowlist.sh.$i.old" grep)" = 1 ] || { echo "case $i old grep"; return 1; }
    [ "$(shf_calls "rm-safe-allowlist.sh.$i.new" grep)" = 0 ] || { echo "case $i new grep"; return 1; }
  done < <(corpus)
  [ "$nonrm" -ge 30 ]
  # An rm command still pays for the danger grep, and still gets the same verdict.
  local safe
  safe="$(corpus | grep -nx 'rm -rf node_modules' | cut -d: -f1)"
  [ "$(shf_calls "rm-safe-allowlist.sh.$safe.new" grep)" = 1 ]
  grep -q allow "$SHF_OUT_DIR/rm-safe-allowlist.sh.$safe.new.out"
}

@test "research-block + research-router: identical with and without a registry; no dirname" {
  have_old
  run_corpus research-block.sh
  awk '$3 >= $2 { print "case " $1 ": old " $2 " new " $3; bad = 1 } END { exit bad }' \
    "$SHF_OUT_DIR/research-block.sh.counts"
  # A registry with no program in it: rr_init runs, so the router's own dirname is in play.
  printf '{"programs":[]}\n' > "$BATS_TEST_TMPDIR/registry.json"
  export CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/registry.json"
  local ho hn pl
  ho="$(live old research-block.sh)"; hn="$(live new research-block.sh)"
  pl="$(pre "git status --short && git log --oneline -1" "$W")"
  pair rb.reg "$ho" "$hn" "$pl"
  [ "$(shf_calls rb.reg.old dirname)" -ge 2 ]
  [ "$(shf_calls rb.reg.new dirname)" = 0 ]
  # No lib/ beside the invoked path: the readlink fallback resolves the router from the target.
  ho="$(bare old research-block.sh)"; hn="$(bare new research-block.sh)"
  pair rb.bare "$ho" "$hn" "$pl"
  [ "$(shf_calls rb.bare.old dirname)" -ge 3 ]
  [ "$(shf_calls rb.bare.new dirname)" = 0 ]
}

@test "memory-index-drain: identical on a located index, GNU and BSD readlink; no dirname" {
  have_old
  local ho hn pl mem="$BATS_TEST_TMPDIR/mem/MEMORY.md"
  mkdir -p "${mem%/*}"
  printf -- '- [A](a.md) — one\n- [B](b.md) — two\n' > "$mem"
  export MEMORY_INDEX_PATH="$mem"
  ho="$(live old memory-index-drain.sh)"; hn="$(live new memory-index-drain.sh)"
  pl="$(pre "git status" "$W")"
  pair mid.gnu "$ho" "$hn" "$pl"
  [ "$(shf_calls mid.gnu.old dirname)" -ge 1 ]
  [ "$(shf_calls mid.gnu.new dirname)" = 0 ]
  pair mid.bsd "$(rel old memory-index-drain.sh)" "$(rel new memory-index-drain.sh)" "$pl" "$STUB_BSD"
  [ "$(shf_calls mid.bsd.old dirname)" -ge 2 ]
  [ "$(shf_calls mid.bsd.new dirname)" = 0 ]
  while IFS= read -r pl; do pair mid.odd "$ho" "$hn" "$pl"; done < <(odd_payloads)
}

@test "bash-output-offload: identical on a 240 KB output, a small one and odd payloads; no dirname" {
  have_old
  local ho hn pl big="$BATS_TEST_TMPDIR/big.txt" small="$BATS_TEST_TMPDIR/small.txt"
  ho="$(live old bash-output-offload.sh)"; hn="$(live new bash-output-offload.sh)"
  # The offload file is named <epoch seconds>-<hash>.txt: two arms can straddle a second.
  export PAIR_NORM='s#claude-bash-output/[0-9]+-#claude-bash-output/EPOCH-#g'
  awk 'BEGIN { for (i = 0; i < 4000; i++) printf "line %05d %s\n", i, "abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmn" }' > "$big"
  [ "$(wc -c < "$big")" -ge 240000 ]
  printf 'ok\n' > "$small"
  pl="$(post "./run-tests.sh" "$big")"
  pair bo.big "$ho" "$hn" "$pl"
  [ -s "$SHF_OUT_DIR/bo.big.new.out" ]
  [ "$(shf_calls bo.big.old dirname)" = 1 ]
  [ "$(shf_calls bo.big.new dirname)" = 0 ]
  pair bo.bsd "$(rel old bash-output-offload.sh)" "$(rel new bash-output-offload.sh)" "$pl" "$STUB_BSD"
  [ "$(shf_calls bo.bsd.old dirname)" -ge 2 ]
  [ "$(shf_calls bo.bsd.new dirname)" = 0 ]
  pl="$(post "git status" "$small")"
  pair bo.small "$ho" "$hn" "$pl"
  while IFS= read -r pl; do pair bo.odd "$ho" "$hn" "$pl"; done < <(odd_payloads)
}

@test "smart-bash-allowlist: python3 -S gives identical decisions over the corpus" {
  have_old
  run_corpus smart-bash-allowlist.sh
  # Same process count: -S removes interpreter work, not a process.
  awk '$2 != $3 { print "case " $1 ": old " $2 " new " $3; bad = 1 } END { exit bad }' \
    "$SHF_OUT_DIR/smart-bash-allowlist.sh.counts"
  # The corpus reaches both answers, so parity is not parity of silence.
  cat "$SHF_OUT_DIR"/smart-bash-allowlist.sh.*.new.out | grep -q permissionDecision
}

# ── The -S guard: under -S, site-packages is not on sys.path, so a third-party import would fail
# at run time. Every python body these two hooks run imports stdlib or its own sibling only. ──
@test "python3 -S bodies import only the stdlib or their own siblings" {
  python3 -c 'import sys; sys.stdlib_module_names' 2>/dev/null || skip "python3 < 3.10 has no stdlib_module_names"
  local body="$BATS_TEST_TMPDIR/offload-body.py"
  # The inline offload body: from the `python3 -S -c '` line to the closing quote.
  awk '/python3 -S -c .$/ { on = 1; next } on && /^'\'' / { exit } on' "$REPO/hooks/bash-output-offload.sh" > "$body"
  grep -q 'import lesson_recall' "$body"
  run python3 - "$REPO/hooks/lib" "$body" "$REPO/hooks/lib/smart-bash-allowlist.py" <<'PY'
import ast, os, sys
lib = sys.argv[1]
siblings = {f[:-3] for f in os.listdir(lib) if f.endswith(".py")}
todo, seen, bad = list(sys.argv[2:]), set(), []
while todo:
    path = todo.pop()
    if path in seen:
        continue
    seen.add(path)
    for node in ast.walk(ast.parse(open(path).read())):
        names = []
        if isinstance(node, ast.Import):
            names = [a.name for a in node.names]
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            names = [node.module]
        for n in names:
            top = n.split(".")[0]
            if top in siblings:
                todo.append(os.path.join(lib, top + ".py"))
            elif top not in sys.stdlib_module_names and top != "__future__":
                bad.append(f"{os.path.basename(path)}: {n}")
print("checked:", " ".join(sorted(os.path.basename(p) for p in seen)))
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *lesson_recall.py* ]] || false
  [[ "$output" == *curl_ssrf.py* ]] || false
}

@test "both per-call python hooks run under -S" {
  grep -q '^exec python3 -S "\$_CORE"$' "$REPO/hooks/smart-bash-allowlist.sh"
  grep -q 'python3 -S -c '\''$' "$REPO/hooks/bash-output-offload.sh"
}
