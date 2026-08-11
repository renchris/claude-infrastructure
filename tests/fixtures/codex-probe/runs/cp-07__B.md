1. **What** — The remedy test claims to cover every slug but never tests `workspace-trust-modal`.

   **Where** — Lines 187–193:

   ```bash
   @test "every slug carries a remedy, and an unknown slug still yields one" {
     run pane_modal_remedy mcp-trust-modal
     [ "$status" -eq 0 ] || false
     echo "$output" | grep -q 'enabledMcpjsonServers' || false
     run pane_modal_remedy some-future-modal
     [ "$status" -eq 0 ] || false
     [ -n "$output" ] || false
   }
   ```

   **Why it is wrong** — If `pane_modal_remedy workspace-trust-modal` fails or returns no remedy while the MCP and unknown-slug paths work, this test passes even though one of the two slugs produced by `pane_modal_reason` has no remedy.

2. **What** — `claude_binary` chooses the highest-numbered directory before establishing that it contains a binary, so a lower valid installation can be ignored.

   **Where** — Lines 227–235 and 248:

   ```bash
     for p in "$REAL_HOME"/.claude-[0-9]*; do
       n="${p##*/.claude-}"
       case "$n" in ''|*[!0-9]*) continue ;; esac     # also catches the unmatched literal glob
       if [ -z "$t" ] || [ "$n" -gt "$t" ]; then t="$n"; fi
     done
     [ -n "$t" ] || return 1
     for p in "$REAL_HOME/.claude-$t/node_modules/@anthropic-ai/claude-code/bin/claude.exe" \
              "$REAL_HOME/.claude-$t/node_modules/@anthropic-ai/claude-code/cli.js"; do
       [ -f "$p" ] && { printf '%s' "$p"; return 0; }
   ```

   ```bash
     BIN="$(claude_binary)" || skip "no claude binary under \$HOME/.claude-*/ — the anchor cannot run, and that is a NON-VERDICT, not a pass"
   ```

   **Why it is wrong** — If an incomplete or stray `.claude-221` directory exists while `.claude-220` contains the shipping binary, the helper selects `221`, finds no candidate there, and causes the anti-rot test to skip despite an available binary.

3. **What** — The fragment enumerator is hard-coded to the current four variables and therefore does not automatically cover a newly added modal class as claimed.

   **Where** — Lines 241–245:

   ```bash
   modal_fragments() {
     printf '%s\n%s\n%s\n%s\n' \
       "$CC_MODAL_MCP_HEADER" "$CC_MODAL_MCP_OPTION" \
       "$CC_MODAL_TRUST_HEADER" "$CC_MODAL_TRUST_OPTION" | tr '|' '\n'
   }
   ```

   **Why it is wrong** — If the library adds another modal with new header and option variables, those values never reach the anti-rot loop, so its stale matchers can be absent from the binary while the test still passes.

4. **What** — `modal_fragments` treats every vertical bar as a top-level alternation separator even though the seam values are regular-expression patterns.

   **Where** — Line 244:

   ```bash
       "$CC_MODAL_TRUST_HEADER" "$CC_MODAL_TRUST_OPTION" | tr '|' '\n'
   ```

   **Why it is wrong** — If a default pattern contains an escaped literal `\|` or an alternation inside a larger expression such as `prefix (foo|bar)`, the code searches for broken pieces rather than the rendered alternatives and can pass or fail for unrelated substring occurrences.

5. **What** — Empty or unset modal fragments are silently omitted from the anti-rot check.

   **Where** — Line 251:

   ```bash
       [ -n "$frag" ] || continue
   ```

   **Why it is wrong** — If the library accidentally leaves a pattern empty, or contains an empty alternative, the loop performs no binary check for it and can report success despite an invalid enumeration.

6. **What** — The main anti-rot test treats every `grep` failure as proof that a fragment is absent.

   **Where** — Lines 252–256:

   ```bash
       LC_ALL=C grep -qaF -- "$frag" "$BIN" || missing="$missing
     $frag"
   ```

   ```bash
       echo "These fragments are NOT in $BIN — the matcher for them is INERT:$missing"
   ```

   **Why it is wrong** — If `grep` exits with an error such as an unreadable file or an I/O failure, the fragment is recorded as missing and the test falsely reports that the vendor reworded the dialog.

7. **What** — The positive control accepts any nonzero shell status as evidence that its deliberately absent string was searched successfully and not found.

   **Where** — Lines 269–270:

   ```bash
     run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"
     [ "$status" -ne 0 ] || false
   ```

   **Why it is wrong** — A `grep` error returns a nonzero status just like “no match,” and a binary path containing a single quote can also make the constructed shell command fail, so the control passes without proving that the anchor actually performed a valid negative search.