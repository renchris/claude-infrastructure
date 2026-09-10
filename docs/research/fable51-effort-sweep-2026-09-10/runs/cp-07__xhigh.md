Four defects found. All four are in the control and anti-rot arms; the classification tests themselves hold up.

**1. What:** The anti-rot test passes with zero fragments checked, because empty fragments are skipped and nothing asserts that the enumeration produced any.

**Where:** lines 243-245 and 252

```bash
  printf '%s\n%s\n%s\n%s\n' \
    "$CC_MODAL_MCP_HEADER" "$CC_MODAL_MCP_OPTION" \
    "$CC_MODAL_TRUST_HEADER" "$CC_MODAL_TRUST_OPTION" | tr '|' '\n'
    [ -n "$frag" ] || continue
```

**Why it is wrong:** Line 25 unsets all four variables before the lib is sourced. If the lib reads them inline with a default, as in `${CC_MODAL_MCP_HEADER:-...}` inside the function, and never assigns them as shell variables, all four lines are empty. Every iteration hits the `continue`, `missing` stays empty, and the test goes green having grepped nothing. Every other test in the file still passes under that lib shape, including the override tests. The positive control on line 264 greps a hardcoded string and never goes through `modal_fragments`, so it cannot detect this. The one arm that exists to catch an inert matcher is itself silently inert.

**2. What:** The anti-rot positive control accepts any non-zero grep status, so a grep error counts as "string absent".

**Where:** lines 270-271

```bash
  run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"
  [ "$status" -ne 0 ] || false
```

**Why it is wrong:** grep exits 1 for no match and 2 for an error. An unreadable binary, a missing `bash`, or a path containing a single quote all satisfy `-ne 0`. Line 270 splices `$BIN` into a single-quoted string, so an apostrophe in the path is a syntax error with status 2. The control then reports that the anchor can fail without grep ever having reported absence, which is the only thing this arm exists to establish. Line 253 has the mirror problem: a grep error is recorded as a missing fragment and line 258 diagnoses it as a reworded dialog. That case at least goes red.

**3. What:** The anchor positive control replaces the lib's fragment text with its own, so it cannot show that the anchor is what refuses the RED-PROOF prose.

**Where:** lines 113-114

```bash
  CC_MODAL_MCP_HEADER=".*New MCP server found"
  CC_MODAL_MCP_OPTION=".*Use this MCP server"
```

**Why it is wrong:** These lines change two things at once: they remove the anchor with `.*` and they substitute a shorter hand-typed string for the default. The RED-PROOF assertion on line 107 passes whenever the defaults fail to match the prose on lines 105-106, for any reason. If the default header carries a trailing colon, as the fixture on line 40 renders it, the prose lacks it and RED-PROOF is refused by the text, not the anchor. The control is then green because its own text does occur. Both tests pass and the "anchor is load-bearing" claim is unproven.

**4. What:** `claude_binary` gives up when the numerically newest track has no binary rather than consulting older tracks, and the skip message then states something false.

**Where:** lines 233-238 and 249

```bash
  [ -n "$t" ] || return 1
  for p in "$REAL_HOME/.claude-$t/node_modules/@anthropic-ai/claude-code/bin/claude.exe" \
           "$REAL_HOME/.claude-$t/node_modules/@anthropic-ai/claude-code/cli.js"; do
    [ -f "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
  BIN="$(claude_binary)" || skip "no claude binary under \$HOME/.claude-*/ — the anchor cannot run, and that is a NON-VERDICT, not a pass"
```

**Why it is wrong:** An empty directory created ahead of an install, a stray file named `.claude-300`, or a half-removed track wins the comparison on line 231. The second loop finds neither file there and returns 1 without looking at the track the comment on lines 211-212 identifies as the one actually launched. Line 249 then skips claiming no binary exists under any track, which is untrue, and the running binary goes unaudited. Line 269 has the same behaviour.
