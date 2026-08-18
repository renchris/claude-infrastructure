#!/usr/bin/env bash
# Test harness for validate-bash.sh.
#
# Runs the hook with synthetic JSON inputs and asserts the decision (allow /
# deny / ask) plus a reason-substring match. Exits 0 on green, 1 on red.
#
# Usage:
#   ./validate-bash.test.sh          # run all tests
#   ./validate-bash.test.sh -v       # verbose (show pass output)
#   ./validate-bash.test.sh --filter <pattern>   # run subset

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/validate-bash.sh"

if [[ ! -x "$HOOK" ]]; then
  echo "FATAL: hook not executable at $HOOK" >&2
  exit 2
fi

VERBOSE=0
FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose) VERBOSE=1; shift ;;
    --filter) FILTER="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Fresh scratch HOME so the hook's audit log doesn't pollute the real one.
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
export HOME="$SCRATCH"

PASS=0
FAIL=0
SKIPPED=0
FAILED_CASES=()

# Colors (only if stdout is a tty). YELLOW was defined here and never used, and the land gate
# lints every CHANGED file whole, so that dead assignment (SC2034) blocked this file the moment it
# was touched. Deleted rather than suppressed — an unused constant is not a construct worth an
# exemption line. (This comment does not open with the linter's name on purpose: a comment whose
# first word is that name parses as a malformed DIRECTIVE and aborts analysis of the entire file,
# which is how a real finding goes unseen. Memory: shellcheck-prose-comment-aborts-analysis.)
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; GRAY='\033[0;37m'; NC='\033[0m'
else
  GREEN=''; RED=''; GRAY=''; NC=''
fi

# assert_case <name> <command> <expected: allow|deny|ask> <reason_substring_or_empty>
assert_case() {
  local name="$1" cmd="$2" expected="$3" reason_substr="${4:-}"

  if [[ -n "$FILTER" ]] && [[ ! "$name" =~ $FILTER ]]; then
    SKIPPED=$((SKIPPED+1))
    return 0
  fi

  # Build safe JSON payload
  local payload
  payload=$(jq -nc --arg c "$cmd" '{tool_input: {command: $c}}')

  local out
  out=$(printf '%s' "$payload" | "$HOOK" 2>/dev/null) || {
    FAIL=$((FAIL+1))
    FAILED_CASES+=("$name (hook exited non-zero)")
    printf "${RED}FAIL${NC}  %-42s  hook exited non-zero  cmd=%q\n" "$name" "$cmd"
    return 1
  }

  local got_decision reason
  if [[ -n "$out" ]]; then
    got_decision=$(echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null || echo "allow")
    reason=$(echo "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null || echo "")
  else
    got_decision="allow"
    reason=""
  fi

  if [[ "$got_decision" != "$expected" ]]; then
    FAIL=$((FAIL+1))
    FAILED_CASES+=("$name (expected=$expected got=$got_decision)")
    printf "${RED}FAIL${NC}  %-42s  expected=%-5s got=%-5s  cmd=%q\n" "$name" "$expected" "$got_decision" "$cmd"
    [[ -n "$reason" ]] && printf "      ${GRAY}reason:${NC} %s\n" "$reason"
    return 1
  fi

  if [[ -n "$reason_substr" ]] && [[ "$reason" != *"$reason_substr"* ]]; then
    FAIL=$((FAIL+1))
    FAILED_CASES+=("$name (reason missing '$reason_substr')")
    printf "${RED}FAIL${NC}  %-42s  reason missing %q\n" "$name" "$reason_substr"
    printf "      ${GRAY}actual:${NC} %s\n" "$reason"
    return 1
  fi

  PASS=$((PASS+1))
  if [[ "$VERBOSE" == "1" ]]; then
    printf "${GREEN}PASS${NC}  %-42s  (%s)\n" "$name" "$got_decision"
  fi
}

echo "Running validate-bash.sh test matrix…"
echo ""

# ────────────────────────────────────────────────────────────────────────
# A. FALSE POSITIVES — commands that MUST be allowed
# ────────────────────────────────────────────────────────────────────────
echo "── A. false positives (must allow) ──"

assert_case "A01-commit-message-no-verify"       "git commit -m 'docs: --no-verify is forbidden'"                        "allow"  ""
assert_case "A02-commit-F-file"                  "git commit -F /tmp/msg.txt"                                            "allow"  ""
assert_case "A03-commit-heredoc-no-verify"       $'git commit -F - <<EOF\ndocs: --no-verify rationale\nEOF'              "allow"  ""
assert_case "A04-no-verify-ssl"                  "curl --no-verify-ssl https://api.example.com"                          "allow"  ""
assert_case "A05-echo-flag-as-text"              "echo --no-verify"                                                      "allow"  ""
assert_case "A06-grep-for-flag"                  "grep -q 'no-verify' README.md"                                         "allow"  ""
assert_case "A07-log-describes-flag"             'echo "user ran: git commit --no-verify"'                               "allow"  ""
assert_case "A08-commit-message-equals-form"     "git commit --message='talk about --no-verify'"                         "allow"  ""
assert_case "A09-tag-message"                    "git tag -m 'v1: --no-verify was used' v1"                              "allow"  ""
assert_case "A10-notes-message"                  "git notes add -m '--no-verify debate' HEAD"                            "allow"  ""
assert_case "A11-printf-flag-as-data"            "printf '%s\\n' --no-verify"                                            "allow"  ""
assert_case "A12-ddl-in-commit-message"          "git commit -m 'fix: block DROP TABLE in migration'"                    "allow"  ""
assert_case "A13-alter-in-commit-message"        "git commit -m 'note: ALTER TABLE is DDL'"                              "allow"  ""
assert_case "A14-pip-no-verify-ssl"              "pip install --no-verify-ssl pkg"                                       "allow"  ""
assert_case "A15-comment-mentions-flag"          "ls  # do not use --no-verify here"                                     "allow"  ""
assert_case "A16-git-log-grep-flag"              "git log --grep='no-verify'"                                            "allow"  ""
assert_case "A17-commit-with-env-prefix"         "GIT_EDITOR=true git commit -m 'skip --no-verify'"                      "allow"  ""
assert_case "A18-heredoc-body-flag"              $'cat <<EOF\ndiscuss --no-verify\nEOF'                                  "allow"  ""
assert_case "A19-force-in-commit-msg"            "git commit -m 'warn: --force bypasses safety'"                         "allow"  ""
assert_case "A20-drop-index-in-msg"              "git commit -m 'migration removes DROP INDEX step'"                     "allow"  ""
# A21-A25 — an innocent `git add` is not a force-add, whatever else shares the command line. A21 is
# the reported symptom: a plain `git add f.txt` in a throwaway fixture repo, refused because the
# line that made the fixture began `rm -f f.txt` (backlog 44750ff72ae7).
assert_case "A21-add-file-named-f"               "git add f.txt"                                                         "allow"  ""
assert_case "A22-add-after-rm-f"                 "rm -f f.txt && echo x > f.txt && git add f.txt"                        "allow"  ""
assert_case "A23-add-beside-grep-f"              "grep -f pats.txt in.txt && git add out.txt"                            "allow"  ""
assert_case "A24-add-before-rsync-f"             "git add out.txt && rsync -f rules a b"                                 "allow"  ""
assert_case "A25-add-force-after-dashdash"       "git add -- -f.txt"                                                     "allow"  ""

# ────────────────────────────────────────────────────────────────────────
# B. TRUE POSITIVES — commands that MUST be blocked (deny)
# ────────────────────────────────────────────────────────────────────────
echo ""
echo "── B. true positives (must deny) ──"

assert_case "B01-commit-no-verify"               "git commit --no-verify -m 'x'"                                         "deny"   "--no-verify"
assert_case "B02-commit-no-verify-trailing"      "git commit -m 'x' --no-verify"                                         "deny"   "--no-verify"
assert_case "B03-commit-no-verify-env"           "GIT_EDITOR=true git commit --no-verify"                                "deny"   "--no-verify"
assert_case "B04-commit-no-verify-chained"       "git add . && git commit --no-verify -m 'x'"                            "deny"   "--no-verify"
assert_case "B05-commit-n-short-form"            "git commit -n -m 'skip hooks'"                                         "deny"   "-n"
assert_case "B06-commit-n-trailing"              "git commit -m 'x' -n"                                                  "deny"   "-n"
assert_case "B07-no-gpg-sign"                    "git commit --no-gpg-sign -m 'x'"                                       "deny"   "--no-gpg-sign"
assert_case "B08-git-add-f"                      "git add -f .env.local"                                                 "deny"   "gitignore"
assert_case "B09-git-add-force"                  "git add --force build/"                                                "deny"   "gitignore"
assert_case "B10-rm-rf-root-literal"             "rm -rf / "                                                             "deny"   "system damage"
assert_case "B10b-rm-rf-etc-asks"                "rm -rf /etc"                                                           "ask"    "non-build-artifact"
assert_case "B11-rm-rf-home-tilde"               "rm -rf ~/important"                                                    "deny"   "system damage"
assert_case "B12-sudo-rm"                        "sudo rm /usr/bin/foo"                                                  "deny"   "system damage"
assert_case "B13-drop-table-sql"                 "turso db shell harbour 'DROP TABLE users'"                             "deny"   "DDL"
assert_case "B14-alter-table-sql"                "sqlite3 app.db 'ALTER TABLE users ADD COLUMN x TEXT'"                  "deny"   "DDL"
assert_case "B15-create-table-sql"               "echo 'CREATE TABLE foo (id INT)' | sqlite3 app.db"                     "deny"   "DDL"
assert_case "B16-drizzle-kit-push"               "drizzle-kit push"                                                      "deny"   "drizzle-kit push"
assert_case "B17-drop-table-case-insensitive"    "echo 'drop table users' | sqlite3 app.db"                              "deny"   "DDL"
assert_case "B18-fork-bomb"                      ":(){ :|:& };:"                                                         "deny"   "system damage"
assert_case "B19-chained-add-f"                  "cd /repo && git add -f .env"                                           "deny"   "gitignore"
# B20-B24 — the spellings the two-condition rule could not see, because the flag had to be its own
# bare token and `add` had to be argv[1] (backlog 44750ff72ae7). Read off git add's argv now.
assert_case "B20-add-force-bundled"              "git add -fv .env.local"                                                "deny"   "gitignore"
assert_case "B21-add-force-bundle-tail"          "git add -Af node_modules"                                              "deny"   "gitignore"
assert_case "B22-add-force-behind-global-opt"    "git -C /tmp/repo add -f .env"                                          "deny"   "gitignore"
assert_case "B23-add-force-abbreviated"          "git add --forc .env"                                                   "deny"   "gitignore"
assert_case "B24-stage-force-synonym"            "git stage -f .env"                                                     "deny"   "gitignore"

# ────────────────────────────────────────────────────────────────────────
# C. ASK — destructive but may be intentional
# ────────────────────────────────────────────────────────────────────────
echo ""
echo "── C. ask-before-run (must ask) ──"

assert_case "C01-rm-rf-src"                      "rm -rf src"                                                            "ask"    "non-build-artifact"
assert_case "C02-rm-rf-compound-mix"             "rm -rf node_modules && rm -rf docs"                                    "ask"    "non-build-artifact"
assert_case "C03-git-reset-hard"                 "git reset --hard origin/main"                                          "ask"    "git reset --hard"
assert_case "C04-git-clean-fdx"                  "git clean -fdx"                                                        "ask"    "gitignored"
assert_case "C05-git-clean-fxd"                  "git clean -fxd"                                                        "ask"    "gitignored"

# ────────────────────────────────────────────────────────────────────────
# D. SAFE NO-OPS — common commands should pass through with no decision
# ────────────────────────────────────────────────────────────────────────
echo ""
echo "── D. common commands (must allow silently) ──"

assert_case "D01-ls"                             "ls -la"                                                                "allow"  ""
assert_case "D02-git-status"                     "git status"                                                            "allow"  ""
assert_case "D03-pnpm-install"                   "pnpm install"                                                          "allow"  ""
assert_case "D04-gh-issue-list"                  "gh issue list"                                                         "allow"  ""
assert_case "D05-rm-rf-node-modules"             "rm -rf node_modules"                                                   "allow"  ""
assert_case "D06-rm-rf-next"                     "rm -rf .next"                                                          "allow"  ""
assert_case "D07-commit-safe-m-flag"             "git commit -m 'feat: new thing'"                                       "allow"  ""
assert_case "D08-git-push"                       "git push origin main"                                                  "allow"  ""
assert_case "D09-pnpm-typecheck"                 "pnpm typecheck"                                                        "allow"  ""
assert_case "D10-curl-url"                       "curl https://api.example.com/status"                                   "allow"  ""

# ────────────────────────────────────────────────────────────────────────
# E. EDGE CASES
# ────────────────────────────────────────────────────────────────────────
echo ""
echo "── E. edge cases ──"

assert_case "E01-unclosed-quote-with-flag"       'git commit -m "discuss --no-verify'                                    "deny"   ""  # layer1 hits, layer2 UNCLEAR → fail-safe block
assert_case "E02-pipeline-real-flag"             "git commit --no-verify | tee log.txt"                                  "deny"   "--no-verify"
assert_case "E03-subst-msg-body"                 "echo 'topic: --no-verify' | git commit -F -"                           "allow"  ""
assert_case "E04-commit-with-cd"                 "cd /tmp && git commit --no-verify"                                     "deny"   "--no-verify"
assert_case "E05-git-dash-C-commit"              "git -C /path commit --no-verify"                                       "deny"   "--no-verify"

# ────────────────────────────────────────────────────────────────────────
# F. CATASTROPHIC-RM SPELLING EQUIVALENCE (codex-security dc12c8db finding 1)
#
# The deny regex hardcoded ONE flag bundle, `-rf`, and the warn regex one bundle set,
# `-(r|rf|fr)`. 11 of the 13 spellings below walked past the shipped hook — some downgraded to
# `ask`, some emitting NO DECISION AT ALL. They are all the same command. The rule is now read off
# argv (hooks/lib/is-true-flag.sh :: rm_argv_scan), so spelling cannot decide enforcement.
#
# The gate-enforced twin of this section is tests/rm-argv-normalize.bats, which additionally
# replays the pre-fix hook out of git to prove this corpus convicts it (11/13) rather than passing
# against an approximation nobody ever ran.
# ────────────────────────────────────────────────────────────────────────
echo ""
echo "── F. catastrophic-rm spelling equivalence (must deny) ──"

assert_case "F01-rf-root-glob"                   'rm -rf /*'                                                             "deny"   "system damage"
assert_case "F02-fr-bundle-reversed"             'rm -fr /*'                                                             "deny"   "system damage"
assert_case "F03-split-r-f"                      'rm -r -f /*'                                                           "deny"   "system damage"
assert_case "F04-long-form"                      'rm --recursive --force /*'                                             "deny"   "system damage"
assert_case "F05-bare-root-end-of-input"         'rm -rf /'                                                              "deny"   "system damage"
assert_case "F06-capital-R-bundle"               'rm -Rf /'                                                              "deny"   "system damage"
assert_case "F07-no-preserve-root-flag"          'rm -rf --no-preserve-root /'                                           "deny"   "system damage"
assert_case "F08-long-form-tilde"                'rm --force --recursive ~'                                              "deny"   "system damage"
# The next three MUST stay single-quoted: the literal text `$HOME` / `${HOME}` is what has to reach
# the hook. Expanding it here would substitute this machine's home path and test a different case
# entirely — one the guard is not even claiming to catch.
# shellcheck disable=SC2016
assert_case "F09-split-home-var"                 'rm -r -f $HOME'                                                        "deny"   "system damage"
# shellcheck disable=SC2016
assert_case "F10-quoted-home-var"                'rm -rf "$HOME"'                                                        "deny"   "system damage"
# shellcheck disable=SC2016
assert_case "F11-braced-home-var"                'rm -rf ${HOME}'                                                        "deny"   "system damage"
assert_case "F12-force-before-recursive"         'rm -f -r /'                                                            "deny"   "system damage"
assert_case "F13-second-clause-of-compound"      'rm -rf src && rm -rf /'                                                "deny"   "system damage"
assert_case "F14-end-of-flags-separator"         'rm -rf -- /'                                                           "deny"   "system damage"
assert_case "F15-bundle-with-company"            'rm -vrf /'                                                             "deny"   "system damage"
assert_case "F16-nested-shell-c-string"          "bash -c 'rm -rf /'"                                                    "deny"   "system damage"
assert_case "F17-eval"                           'eval rm -rf /'                                                         "deny"   "system damage"
assert_case "F18-absolute-rm-path"               '/bin/rm -rf /'                                                         "deny"   "system damage"
assert_case "F19-find-exec"                      'find . -name x -exec rm -rf / ;'                                       "deny"   "system damage"

echo ""
echo "── F′. the same fix's other half: reach unchanged, text is not execution ──"

# Spellings the WARN clause was equally blind to — `-R` and the long form emitted no decision.
assert_case "F20-capital-R-etc-asks"             'rm -Rf /etc'                                                           "ask"    "non-build-artifact"
assert_case "F21-long-form-src-asks"             'rm --recursive --force src'                                            "ask"    "non-build-artifact"
assert_case "F22-multi-target-second-unsafe"     'rm -rf node_modules /etc'                                              "ask"    "non-build-artifact"
assert_case "F23-multi-target-both-safe"         'rm -rf node_modules dist'                                              "allow"  ""
# The mirror-image defect: the old text regex DENIED a commit message about this very rule, so the
# guard blocked its own fix from being committed.
assert_case "F24-commit-msg-describes-rule"      'git commit -m "fix(hooks): rm --recursive --force / must deny"'        "allow"  ""
assert_case "F25-commit-msg-tilde-and-home"      "git commit -m 'fix: rm -rf ~ and rm -rf \$HOME both blocked'"          "allow"  ""
assert_case "F26-quoted-echo-is-not-execution"   'echo "never run rm -rf /"'                                             "allow"  ""

# ────────────────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────"
TOTAL=$((PASS+FAIL))
if [[ "$FAIL" == "0" ]]; then
  printf "${GREEN}PASSED${NC}  %d/%d   (skipped: %d)\n" "$PASS" "$TOTAL" "$SKIPPED"
  exit 0
else
  printf "${RED}FAILED${NC}  %d failed, %d passed   (skipped: %d)\n" "$FAIL" "$PASS" "$SKIPPED"
  echo ""
  echo "Failed cases:"
  for f in "${FAILED_CASES[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
