## Review — `tests/pane-modal.bats`

I found seven defects plus one wrong claim in the file's own documentation. The most serious cluster is in the anti-rot arm, which is the one part of this suite whose whole purpose is to go red when nothing else can.

---

### 1. The ANTI-ROT arm silently passes when a pattern variable is empty — including, very plausibly, always

**What** — `modal_fragments` reads exactly the four variables that `setup()` has just unset, and the loop treats an empty fragment as "nothing to check" rather than "the enumeration is broken," so the arm can report green having grepped for nothing.

**Where** — lines 25, 244–245, 252:
```bash
  unset CC_MODAL_MCP_HEADER CC_MODAL_MCP_OPTION CC_MODAL_TRUST_HEADER CC_MODAL_TRUST_OPTION
```
```bash
    "$CC_MODAL_MCP_HEADER" "$CC_MODAL_MCP_OPTION" \
    "$CC_MODAL_TRUST_HEADER" "$CC_MODAL_TRUST_OPTION" | tr '|' '\n'
```
```bash
    [ -n "$frag" ] || continue
```

**Why it is wrong** — The arm's stated contract is "reads the fragments OUT OF THE LIB" (line 15), but it reads them out of the *environment*, and the environment was deliberately cleared at line 25. It only works if sourcing the lib assigns those names as globals — which the file never asserts and which is in tension with the override tests at lines 113–114 and 177–178, where the vars are set *after* sourcing and are expected to take effect (i.e. the lib defaults at call time, which would leave the globals unset). If the lib defaults at call time, all four `printf` arguments are empty, every iteration hits `continue`, `missing` stays empty, and the test passes without executing a single `grep`. Even under the favourable reading, an individual pattern that goes empty — the condition that would make the live matcher match *everything* and block every healthy pane — is swallowed by line 252 instead of reported. This is precisely the "inert matcher that nothing could have reported" failure described at lines 12–14.

---

### 2. The positive control does not exercise the mechanism it claims to falsify

**What** — The control greps a hardcoded string directly instead of driving the subject test's fragment extraction, loop and reporting path, so it stays green under the exact failure modes it exists to exclude.

**Where** — lines 270–271:
```bash
  run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"
  [ "$status" -ne 0 ] || false
```

**Why it is wrong** — The comment at lines 265–266 says the control exists because a subject test "that always matched (a bad path, a stray `|| true`) would read exactly the same." But nothing here calls `modal_fragments`, nothing goes through the `while` loop, the `[ -n "$frag" ] || continue` guard, or the `missing`/`false` reporting at lines 256–261. If `modal_fragments` emits four empty lines (defect 1), or if the `missing` accumulation were broken, or if someone appended `|| true` at line 253, this control still passes. It proves only that `grep` can return non-zero against this file — a fact about `grep`, not about the test above it.

---

### 3. The positive control accepts `grep`'s error status as proof of absence

**What** — `[ "$status" -ne 0 ]` treats exit 2 (file unreadable, bad path, I/O error) identically to exit 1 (string genuinely absent).

**Where** — line 271:
```bash
  [ "$status" -ne 0 ] || false
```

**Why it is wrong** — If `$BIN` is unreadable, is a dangling symlink, or contains a `'` that breaks the single-quoted interpolation at line 270, `grep` exits 2 and the assertion passes. "A bad path" is named at line 266 as the very thing this control is supposed to catch, and a bad path is one of the two inputs under which it silently passes. Note the asymmetry with the subject test at line 253, where `|| missing=...` sends a grep *error* to the red side — the control fails in the unsafe direction.

---

### 4. `claude_binary` searches only one track but reports failure as "no claude binary under `$HOME/.claude-*/`"

**What** — The function resolves the highest-numbered directory and then returns failure if *that one* directory lacks the two known binary paths, converting the whole anti-rot check into a skip while five other installed binaries sit unexamined; a misconfigured `CC_MODAL_ANCHOR_BIN` is reported the same way.

**Where** — lines 222–223, 233–238, and the skip messages at 249 and 269:
```bash
    [ -f "$CC_MODAL_ANCHOR_BIN" ] && { printf '%s' "$CC_MODAL_ANCHOR_BIN"; return 0; }
    return 1
```
```bash
  [ -n "$t" ] || return 1
  for p in "$REAL_HOME/.claude-$t/node_modules/@anthropic-ai/claude-code/bin/claude.exe" \
           "$REAL_HOME/.claude-$t/node_modules/@anthropic-ai/claude-code/cli.js"; do
    [ -f "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
```
```bash
  BIN="$(claude_binary)" || skip "no claude binary under \$HOME/.claude-*/ — the anchor cannot run, and that is a NON-VERDICT, not a pass"
```

**Why it is wrong** — Given the box described at line 204 (six tracks, `.claude-156` … `.claude-220`), a partially-unpacked or in-progress `.claude-220` — a directory present, `node_modules` not yet populated — makes `claude_binary` return 1. The suite then announces that no claude binary exists anywhere under `$HOME/.claude-*/`, which is false, and skips the only test in the file that can detect vendor drift. The same message fires when `CC_MODAL_ANCHOR_BIN` is set to a path that does not exist (line 222 fails, line 223 returns 1): an operator error is reported as "not installed" and downgraded to a non-verdict. Separately, both messages name `$HOME`, but the code reads `$REAL_HOME` — `$HOME` at that moment is the empty fixture from line 31, so the message points the reader at a directory that is guaranteed to contain nothing.

---

### 5. Regex fragments are searched as fixed strings

**What** — The fragments are split on `|` because they are regex alternations, but each alternative is then matched with `grep -F`, so any remaining metacharacter is searched literally.

**Where** — lines 245 and 253:
```bash
    "$CC_MODAL_TRUST_HEADER" "$CC_MODAL_TRUST_OPTION" | tr '|' '\n'
```
```bash
    LC_ALL=C grep -qaF -- "$frag" "$BIN" || missing="$missing
```

**Why it is wrong** — The `tr '|' '\n'` at line 245 exists only because these values are regexes with alternation; the file's own overrides at lines 113–114 (`".*New MCP server found"`) confirm they are consumed as regexes. Any alternative carrying an anchor, `.`, `?`, or a bracket expression — e.g. `[nyae]`, the very construct named at line 8 — is handed to `-F` verbatim, does not appear in the binary in that literal form, and is reported as INERT. The failure is a false red accompanied by the instruction at line 259 "do not delete this test to make it green," i.e. it sends the reader to rewrite a lib pattern that was correct.

---

### 6. "Every slug carries a remedy" checks one of the two known slugs

**What** — The test named for *every* slug exercises only `mcp-trust-modal` and the unknown-slug fallback; `workspace-trust-modal` is never asked for a remedy.

**Where** — lines 188–194:
```bash
@test "every slug carries a remedy, and an unknown slug still yields one" {
  run pane_modal_remedy mcp-trust-modal
```
```bash
  run pane_modal_remedy some-future-modal
```

**Why it is wrong** — If `pane_modal_remedy` has no case for `workspace-trust-modal`, the slug falls through to whatever the unknown branch returns — generic text that says nothing about trusting a folder — and this suite is green. Since the unknown branch is separately proven to exit 0 with non-empty output (lines 193–194), there is no assertion anywhere in the file that a workspace-trust remedy exists at all, even though `workspace-trust-modal` is a slug this suite itself pins at line 79.

---

### 7. The "override replaces rather than adds" test can only detect an additive *header*

**What** — The replacement half of the test is satisfied by the header alone, so an option pattern whose override is additive rather than replacing passes.

**Where** — lines 177–178 and 184–185:
```bash
  CC_MODAL_MCP_HEADER="Totally New Dialog"
  CC_MODAL_MCP_OPTION="press 1 to continue"
```
```bash
  run classify "$(mcp_screen)"
  [ "$status" -eq 1 ] || false
```

**Why it is wrong** — Classification is a conjunction (header AND option). Once `CC_MODAL_MCP_HEADER` no longer matches `mcp_screen`, the result is status 1 regardless of how `CC_MODAL_MCP_OPTION` was combined. A lib that replaced the header but *appended* the option override to the default — leaving the shipped `Use this MCP server` still live, so a future wording override could never retire a stale matcher — passes this test unchanged. The same gap covers both trust patterns, which the test never touches.

---

### 8. Two assertions pass for a weaker reason than their names claim

**What (a)** — The "unreadable pane" case never sends empty input.

**Where** — lines 66 and 170:
```bash
classify() { printf '%s\n' "$1" | pane_modal_reason; }
```
```bash
  run classify ""
```

**Why it is wrong** — `printf '%s\n' ""` writes one newline, so `pane_modal_reason` receives a one-blank-line pane, not the zero-byte stdin an unreadable/failed `capture-pane` actually produces. A lib that mishandles genuinely empty stdin — returning 0, or erroring with a status that is not 1 — is not exercised by the test that claims it "fails CLOSED to not-wedged, never to wedged."

**What (b)** — The chrome-tolerance test asserts only the exit status, never the slug.

**Where** — lines 124–129:
```bash
  run classify "╭─ New MCP server found in this project: ms365 ─╮
❯ 1. Use this MCP server"
  [ "$status" -eq 0 ] || false
```

**Why it is wrong** — Both true-positive tests at lines 70–80 check `$output` because the identity of the class is the result; here a lib that returned `workspace-trust-modal` for an MCP screen wrapped in box chrome satisfies `[ "$status" -eq 0 ]` and the test is green. Given that the file elsewhere (line 155) treats cross-class contamination as a live failure mode, this arm cannot distinguish "matched the MCP rule despite chrome" from "matched some other rule."

---

### Not a code defect, but a false claim in the file

Line 18 states:
```bash
# Assertions are `[ ]` / `|| false`; `[[ ]]` and `(( ))` are errexit-EXEMPT in bats.
```
Neither is exempt: under `set -e` a failing `[[ ]]` aborts the test like any other command, and `(( ))` returns 1 whenever the expression evaluates to zero, which makes it *more* prone to aborting, not less. Today's assertions don't rely on the claim, but it is the file's stated rule for how future assertions should be written.
