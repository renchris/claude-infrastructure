Line numbers count `#!/usr/bin/env bats` as line 1. The lib is not in the brief, so items 1 and 2 are conditions on the lib, not observed lib behavior.

**1. The anti-rot fragment list is hard-coded, so it cannot pick up a new class**
- **What:** `modal_fragments` names four specific variables, so a class added to the lib is never checked against the binary.
- **Where:**
  - line 244: `    "$CC_MODAL_MCP_HEADER" "$CC_MODAL_MCP_OPTION" \`
  - line 245: `    "$CC_MODAL_TRUST_HEADER" "$CC_MODAL_TRUST_OPTION" | tr '|' '\n'`
  - The file's own claim is at lines 15–16: `so a class added tomorrow is pinned` / `tomorrow without anyone remembering to extend this file.`
- **Why it is wrong:**
  - If the lib gains a third class, or renames one of these variables, its patterns are never grepped in the binary. A stale or inert fragment for it leaves the test green, which is the silent failure the suite says it exists to prevent.
  - The `unset` list at line 25 is the same closed set, so an inherited value for a new class is not pinned either.

**2. Empty fragments are skipped and nothing checks that any fragment was verified**
- **What:** The loop drops blank fragments and never asserts that at least one was checked, so the test can pass having grepped nothing.
- **Where:** line 252: `    [ -n "$frag" ] || continue`
- **Why it is wrong:**
  - Line 25 unsets all four variables before the lib is sourced, so they hold values only if the lib assigns them at source time.
  - If the lib applies its defaults lazily (`${VAR:-…}` inside the matcher), or a variable is renamed, `modal_fragments` yields only blank lines. The override tests at lines 113–114 and 177–178 are consistent with either lib design.
  - Every iteration then hits `continue`, `missing` stays `""`, and lines 256–261 never fire, so the test passes with zero greps.
  - A single unset variable silently drops only its own fragments.

**3. The positive control never runs the code it claims to prove can fail**
- **What:** It runs a separate hand-written `grep` instead of feeding the mutant string through `modal_fragments` and the loop.
- **Where:** line 270: `  run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"` (title at 264: `the anchor above CAN fail`)
- **Why it is wrong:**
  - The failure modes named at lines 265–266 (a stray `|| true`, a `missing` that is never populated) live in lines 251–261, and none of that code runs here.
  - If the `|| missing=…` on line 253 were replaced by `|| true`, the anchor could never go red and this control would still pass. It only shows that the binary lacks that string.

**4. The control accepts any non-zero exit, not just "no match"**
- **What:** The assertion cannot tell grep's "not found" (exit 1) from an error.
- **Where:** line 271: `  [ "$status" -ne 0 ] || false`. The loop has the same conflation at line 253: `    LC_ALL=C grep -qaF -- "$frag" "$BIN" || missing="$missing`
- **Why it is wrong:**
  - An unreadable `$BIN` makes grep exit 2.
  - A `$BIN` containing a single quote, such as a home directory like `/Users/o'brien`, breaks the `'$BIN'` quoting on line 270 and `bash -c` exits 2.
  - A missing `grep` in the subshell gives exit 127.
  - In all three cases the control passes without demonstrating a no-match.
  - In the loop, the same error exit is reported as "fragment NOT in $BIN … Claude Code reworded a dialog".

**5. "Every slug carries a remedy" checks one slug**
- **What:** Only `mcp-trust-modal` is passed to `pane_modal_remedy`, despite the title.
- **Where:**
  - line 188: `@test "every slug carries a remedy, and an unknown slug still yields one" {`
  - line 189: `  run pane_modal_remedy mcp-trust-modal`
  - line 194: `  [ -n "$output" ] || false`
- **Why it is wrong:**
  - `workspace-trust-modal` (asserted at line 79) is never queried.
  - If it has no remedy, or an empty or wrong one, it takes the fallback path. Lines 192–194 only require that path to return non-empty output for an invented slug, so the suite stays green.

**6. A failed binary lookup, including a bad explicit override, becomes a skip with a wrong reason**
- **What:** `claude_binary` returns 1 in cases where a binary exists or was named, and the callers report "no claude binary under $HOME/.claude-*/" as a skip.
- **Where:**
  - line 222: `    [ -f "$CC_MODAL_ANCHOR_BIN" ] && { printf '%s' "$CC_MODAL_ANCHOR_BIN"; return 0; }`
  - line 223: `    return 1`
  - line 238: `  return 1`
  - line 249: `  BIN="$(claude_binary)" || skip "no claude binary under \$HOME/.claude-*/ — the anchor cannot run, and that is a NON-VERDICT, not a pass"`
  - line 269: `  BIN="$(claude_binary)" || skip "no claude binary under \$HOME/.claude-*/ — the control cannot run"`
- **Why it is wrong:**
  - `CC_MODAL_ANCHOR_BIN` pointing at a nonexistent path (typo, moved file, relative path) returns 1, so both tests skip although the operator named a binary.
  - The highest-numbered `.claude-N` may lack both candidate files (for example, a half-finished install). The function then returns 1 even though older tracks have binaries.
  - Either way the drift check is off. bats reports a skip, not a failure, and the stated cause is false.

**7. The audited binary is "newest installed track", on an unchecked premise that it is the launched one**
- **What:** Nothing in the test establishes which binary is actually launched. It assumes the highest-numbered track is, or is about to be, that binary.
- **Where:** line 231: `    if [ -z "$t" ] || [ "$n" -gt "$t" ]; then t="$n"; fi` (premise only in comments, lines 211–212: `Newest wins because the pin only ever moves FORWARD`)
- **Why it is wrong:**
  - Lines 207–209 show fragments differ by track: absent from 156/161/170, present in 183/219/220. Lines 211–212 describe a pin that lags the installs (183 → 219 → 220).
  - While the launched track is older than the newest installed one, a fragment the newest has and the launched one lacks passes here yet is inert in production.
  - Updating the lib to satisfy a red on the newest wording can also stop it matching the launched track while the test stays green.
  - The claim at lines 213–214, that the residual failure mode is only the "useful direction", covers just one of the two directions.

Items 1–5 are mechanical. Items 6–7 concern unverified premises and I hold them with less confidence.
