Seven defects found. They are ordered by how directly the code contradicts what the test claims to establish.

**1. The anti-rot positive control passes on a grep error, not only on "string absent".**

- **Where:** line 271, and the command it judges on line 270.
  ```bash
    run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"
    [ "$status" -ne 0 ] || false
  ```
- **Why it is wrong:** grep exits 1 when the string is absent and 2 when it could not search at all. An unreadable file, a path containing an apostrophe that breaks the single quotes inside the bash -c string, or a missing bash all satisfy the `-ne 0` test. The control then reports "the anchor can fail" although the binary was never searched. The comment on line 266 says this arm exists to catch a bad path. A bad path is the one case it cannot catch, because a bad path yields exit 2, never 0. Line 253 has the mirror conflation: a grep error there marks every fragment missing and the printed diagnosis blames a vendor rewording that did not happen.

**2. The anti-rot enumeration restates the four known variable names, so a modal class added to the lib is never pinned.**

- **Where:** lines 243 to 245, and the matching list on line 25.
  ```bash
    printf '%s\n%s\n%s\n%s\n' \
      "$CC_MODAL_MCP_HEADER" "$CC_MODAL_MCP_OPTION" \
      "$CC_MODAL_TRUST_HEADER" "$CC_MODAL_TRUST_OPTION" | tr '|' '\n'
  ```
  ```bash
    unset CC_MODAL_MCP_HEADER CC_MODAL_MCP_OPTION CC_MODAL_TRUST_HEADER CC_MODAL_TRUST_OPTION
  ```
- **Why it is wrong:** Lines 14 to 16 and 199 to 201 say the fragments are read out of the lib so that a class added tomorrow is pinned without extending this file. The code does the opposite. A third class with its own header and option variables is not in this list, its fragments can drift freely, and the anti-rot test stays green. Line 25 has the same fixed list, so the new class's seam is inherited from the ambient environment, which lines 23 to 24 describe as replacing the subject with itself.

**3. The anti-rot loop has no guard against an empty enumeration, so it passes having checked nothing.**

- **Where:** line 252, fed by line 255.
  ```bash
      [ -n "$frag" ] || continue
  ```
  ```bash
    done <<< "$(modal_fragments)"
  ```
- **Why it is wrong:** setup unsets the four variables on line 25 and relies on sourcing the lib to repopulate them. Nothing checks that it did. If the lib supplies its defaults inline at call time, or a refactor moves them there, `modal_fragments` prints four empty lines, every line hits the continue, `missing` stays empty, and the test reports success. Line 207 records a real red on the first run, so the lib evidently populated them then. The test has no assertion that it still does, and the positive control on line 264 never calls `modal_fragments`, so it cannot detect this.

**4. The anchor is proven load-bearing only for the MCP class; the workspace-trust class has no both-halves prose test and no positive control.**

- **Where:** lines 105 to 107 and 113 to 118 exercise MCP only. The only trust negative is lines 133 to 134.
  ```bash
    run classify "CC_MODAL_TRUST_OPTION default is Yes, I trust this folder"
    [ "$status" -eq 1 ] || false
  ```
- **Why it is wrong:** That input carries only the option, so the header-and-option conjunction refuses it whether or not the trust patterns are anchored. A lib whose trust header and trust option match mid-line passes every test in this file. A pane quoting both trust lines from the plan is then reported wedged, which is the shipped false positive that lines 7 to 13 name as the reason this suite exists. Lines 158 to 159 pair the MCP header with a trust option, which the per-class conjunction refuses, so they do not cover it either.

**5. The remedy test never queries the workspace-trust slug, and the fallback makes a missing remedy invisible.**

- **Where:** lines 189 to 194.
  ```bash
    run pane_modal_remedy mcp-trust-modal
    [ "$status" -eq 0 ] || false
    echo "$output" | grep -q 'enabledMcpjsonServers' || false
    run pane_modal_remedy some-future-modal
    [ "$status" -eq 0 ] || false
    [ -n "$output" ] || false
  ```
- **Why it is wrong:** The title claims every slug carries a remedy. Only the MCP slug is checked for its own remedy. If the lib has no entry for the workspace-trust slug, the call returns the generic fallback, which exits 0 and is non-empty, so no assertion here can go red. An operator at a wedged trust dialog gets the generic text while the suite says every slug is covered.

**6. The track chooser picks the highest-numbered entry without requiring a binary under it and never falls back, so the anchor skips on a box that has a checkable binary.**

- **Where:** line 231, then lines 233 to 238.
  ```bash
      if [ -z "$t" ] || [ "$n" -gt "$t" ]; then t="$n"; fi
  ```
  ```bash
    [ -n "$t" ] || return 1
    for p in "$REAL_HOME/.claude-$t/node_modules/@anthropic-ai/claude-code/bin/claude.exe" \
             "$REAL_HOME/.claude-$t/node_modules/@anthropic-ai/claude-code/cli.js"; do
      [ -f "$p" ] && { printf '%s' "$p"; return 0; }
    done
    return 1
  ```
- **Why it is wrong:** An empty or half-installed newer track, a track laid out differently from the two hard-coded paths, or a stray file named like a track wins the numeric comparison. Both probes then fail, the function returns 1, and both anti-rot tests skip. bats reports a skip as ok and exits 0, so the run is green with the anchor not executed, while the older track that line 212 says is actually launched still holds the binary.

**7. An override pointing at a nonexistent file degrades to a skip whose message blames a location the code did not consult.**

- **Where:** lines 221 to 223.
  ```bash
    if [ -n "${CC_MODAL_ANCHOR_BIN:-}" ]; then
      [ -f "$CC_MODAL_ANCHOR_BIN" ] && { printf '%s' "$CC_MODAL_ANCHOR_BIN"; return 0; }
      return 1
  ```
- **Why it is wrong:** A typo in the pinned path returns 1, and line 249 skips with "no claude binary under $HOME/.claude-*/". The glob was never run. The operator who set the override believes the anchor is checking their pin. It is not running at all, and the run stays green.
