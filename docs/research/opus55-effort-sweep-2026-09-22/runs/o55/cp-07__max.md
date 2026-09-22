Twelve defects, most severe first. The first six are in the anti-rot arm, which can report green without having checked what production actually matches.

**1. The anti-rot arm can pass having checked nothing**
- **What:** An empty fragment is skipped rather than failed, and nothing asserts that any fragment was actually grepped.
- **Where:** line 252: `[ -n "$frag" ] || continue` (fed by line 255: `done <<< "$(modal_fragments)"`)
- **Why:** `modal_fragments` reads four globals that setup has just unset (line 25). Suppose the lib resolves its defaults lazily inside `pane_modal_reason` (`${CC_MODAL_MCP_HEADER:-…}`, the usual env-seam idiom) instead of assigning the globals when sourced. Or suppose it renames one of the four. Either way those variables are empty here. Every classifier test still passes, but this loop sees only blank lines, `missing` stays empty, and the test reports every fragment present having grepped none. That is the silent stale-fragment failure lines 12–16 say this arm exists to catch.

**2. The enumeration is a hard-coded list, not "read out of the lib"**
- **What:** `modal_fragments` names exactly four variables, so a modal class added to the lib is never checked. This contradicts lines 14–16 ("a class added tomorrow is pinned tomorrow without anyone remembering to extend this file").
- **Where:** lines 243–245: `printf '%s\n%s\n%s\n%s\n' \` / `"$CC_MODAL_MCP_HEADER" "$CC_MODAL_MCP_OPTION" \` / `"$CC_MODAL_TRUST_HEADER" "$CC_MODAL_TRUST_OPTION" | tr '|' '\n'`
- **Why:** Add a third class to the lib (e.g. `CC_MODAL_BYPASS_HEADER`/`_OPTION`) whose fragment is not in the binary. That fragment is never grepped, ANTI-ROT stays green, and the new matcher is inert in production with nothing to report it. The `unset` on line 25 uses the same fixed list, so the new seams are not pinned either.

**3. The anti-rot positive control doesn't exercise the arm it vouches for**
- **What:** The control runs its own standalone grep instead of the main arm's loop, so it cannot detect the breakages its comment says it guards against.
- **Where:** line 270: `run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"`
- **Why:** Apply the comment's own example (line 266), a stray `|| true` on line 253. Or delete the `false` on line 260, or let `modal_fragments` go empty (defect 1). In each case the main arm is permanently green while this control still passes. It never touches `modal_fragments`, the `missing` accumulator, or the report block. It is the copy-instead-of-mechanism pattern that lines 199–201 warn against.

**4. The control counts any failure as "string absent"**
- **What:** `-ne 0` accepts grep's error status 2, and a `bash -c` parse failure, as proof that the string is not in the binary.
- **Where:** line 271: `[ "$status" -ne 0 ] || false` (command on line 270)
- **Why:** Two cases where nothing is actually searched:
  - `$BIN` exists but isn't readable, so grep exits 2.
  - `$BIN` contains a single quote (reachable via `CC_MODAL_ANCHOR_BIN`, e.g. a path under `Team's builds/`). The `'$BIN'` interpolation leaves an unterminated quote and bash exits non-zero without running grep.

  Either way "the anchor above CAN fail" is reported as passing. In the unreadable case the main arm does go red, but with the wrong diagnosis: "Claude Code reworded a dialog."

**5. The oracle is the newest installed track, not the binary that runs**
- **What:** `claude_binary` checks the highest-numbered installed track rather than the binary panes are actually launched from. A fragment present only in a newer, not-yet-pinned track therefore passes while the launched binary lacks it.
- **Where:** line 231: `if [ -z "$t" ] || [ "$n" -gt "$t" ]; then t="$n"; fi`; line 258: `echo "Claude Code reworded a dialog. Re-read the strings out of the binary and update"`
- **Why:** Say panes launch on 220 and 221 is installed ahead of the pin, the "one about to be" case that lines 211–214 accept.
  - A rewording in 221 turns this test red.
  - Line 258 says to re-read the strings from `$BIN`, which is 221, into the lib.
  - The test then goes green against 221, while every pane actually launched still renders 220's wording.
  
  That matcher is now inert in production and nothing reports it. The premise that the newest track is, or is about to be, the launched binary is never checked. On a box that pins below its newest track it holds only if someone remembers to set `CC_MODAL_ANCHOR_BIN`.

**6. `claude_binary` gives up where a binary exists, and the skip names the wrong cause**
- **What:** Both anti-rot arms skip with "no claude binary under $HOME/.claude-*/" in two situations where a checkable binary does exist:
  - `CC_MODAL_ANCHOR_BIN` is set but isn't a regular file.
  - The highest-numbered `.claude-N` has no binary.
- **Where:** lines 222–223: `[ -f "$CC_MODAL_ANCHOR_BIN" ] && { printf '%s' "$CC_MODAL_ANCHOR_BIN"; return 0; }` / `return 1`; lines 233–234: `[ -n "$t" ] || return 1` / `for p in "$REAL_HOME/.claude-$t/node_modules/@anthropic-ai/claude-code/bin/claude.exe" \`
- **Why:** A mistyped override, or one pointing at the track directory instead of the file, turns an explicitly requested check into a skip blamed on a missing install. Separately, any all-digit `.claude-N` without that layout wins the max; examples are a half-finished install or a dated copy like `.claude-20260922`. It has no `claude.exe` or `cli.js`, so the anchor stops running even though `.claude-220` has a good binary. Lower tracks are never probed.

**7. The anchor's positive control changes the patterns, not just the anchor**
- **What:** It replaces the lib's default MCP patterns with hand-written ones. So it cannot show that the anchor, rather than the default pattern text, is what makes RED-PROOF (line 107) return 1.
- **Where:** lines 113–114: `CC_MODAL_MCP_HEADER=".*New MCP server found"` / `CC_MODAL_MCP_OPTION=".*Use this MCP server"`
- **Why:** Suppose a default is stricter than these copies. For example, the option is end-anchored (`Use this MCP server[[:space:]│]*$`), or the header includes the `: ` before the server name. Every default-pattern positive test still passes, because they all render `: ms365` after the header and only padding or `│` after the option. But RED-PROOF's prose (`project and BLOCKS`, `server, which…`) is then refused by the pattern text alone, and stays green even with the leading anchor deleted. This control still fires on its looser copies, so the pair certifies "the anchor is load-bearing" when it isn't.

**8. The override test never exercises an override present when the lib is sourced**
- **What:** The seam variables are assigned after setup has already sourced the lib. An operator's override arrives differently: in the environment, before sourcing.
- **Where:** lines 177–178: `CC_MODAL_MCP_HEADER="Totally New Dialog"` / `CC_MODAL_MCP_OPTION="press 1 to continue"` (lib sourced on line 33: `. "$LIB"`)
- **Why:** A lib that assigns its defaults unconditionally when sourced (`CC_MODAL_MCP_HEADER='New MCP server found…'`) discards an exported override in cc-spawn-verify and handoff-fire. This test still passes, because its assignment lands after that overwrite. Line 174's "one-line override, not a redeploy" is broken while the suite stays green.

**9. The "replacement" check can't see an additive override on one seam**
- **What:** The class needs header AND option, so the "old dialog no longer matches" check passes as soon as either override replaces its default. An additive override on the other seam goes undetected.
- **Where:** lines 184–185: `run classify "$(mcp_screen)"` / `[ "$status" -eq 1 ] || false`
- **Why:** Suppose the header override is ORed onto the default (`default|Totally New Dialog`) while the option override replaces. `mcp_screen` still satisfies the header but not "press 1 to continue", so status is 1. The test "replaces a pattern rather than adding to it" passes even though the header seam is additive.

**10. "Every slug carries a remedy" checks one slug**
- **What:** Only `mcp-trust-modal` is checked. `workspace-trust-modal`, the other slug the classifier emits (line 79), is never passed to `pane_modal_remedy`.
- **Where:** line 188: `@test "every slug carries a remedy, and an unknown slug still yields one" {`; line 189: `run pane_modal_remedy mcp-trust-modal`
- **Why:** If the lib's `workspace-trust-modal` arm is missing or misspelled, that slug falls through to the generic fallback (lines 192–194 prove one exists). A pane wedged on the trust dialog then gets no trust-specific remedy, and this test stays green.

**11. The unknown-slug check is satisfied by stderr**
- **What:** `[ -n "$output" ]` passes on anything written to stderr, because bats `run` merges stderr into `$output`.
- **Where:** line 194: `[ -n "$output" ] || false`
- **Why:** A fallback that only prints a warning to stderr and returns 0 gives the caller no remedy on stdout. `$output` is still non-empty, so the test passes.

**12. The option-alone regression can't catch the rule its comment names** (low impact)
- **What:** The option is quoted mid-line, so the anchor refuses it whether or not a header is required. This arm therefore cannot detect the "rule that required only the option" it says it needs its own arm for.
- **Where:** line 96: `run classify "the operator answered 1. Use this MCP server, which is session-scoped"`
- **Why:** A lib that drops the header requirement but keeps the anchor returns 1 here, and the test passes. Only the column-0 option-list test (lines 146–153) goes red. The suite still catches the bug, but this arm passes for a different reason than it claims.

Checked and not reported: lines 225–226 misdiagnose the first-run failure. For 156…220, lexical and numeric order agree, so the old code must have taken the first match. The numeric max on line 231 is correct, so there is no behavioral defect.
