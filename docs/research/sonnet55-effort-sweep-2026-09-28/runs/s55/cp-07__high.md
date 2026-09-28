I found three defects.

**1. The anti-rot positive control passes when grep fails outright, not only when the fragment is absent.**
- **What:** The control accepts any non-zero exit as proof that the string is absent from the binary.
- **Where:** line 270, `[ "$status" -ne 0 ] || false`, checking the result of line 269, `run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"`.
- **Why it is wrong:** `grep -q` exits 1 for "no match" and 2 for an error. If `$BIN` is unreadable, is removed between resolution and use, contains a `'` that breaks the single-quoted string, or `bash -c` fails for any other reason, the exit is non-zero and the control passes. The comment at lines 264–266 says the control exists to catch "a bad path" in the grep. A broken grep invocation is exactly what this line would report as success.

**2. The anti-rot test can pass without checking a single fragment.**
- **What:** Empty fragments are skipped and nothing checks that at least one was compared against the binary.
- **Where:** line 251, `[ -n "$frag" ] || continue`, with line 254, `done <<< "$(modal_fragments)"`, and the pass condition at line 255, `if [ -n "$missing" ]; then`.
- **Why it is wrong:** `modal_fragments` (lines 241–245) reads `$CC_MODAL_*` shell variables. `setup` unsets them (line 24) and then sources the lib. If the lib does not assign these as shell variables (for example, it uses inline `${VAR:-default}` expansions), all four are empty. Every line is skipped, `missing` stays empty, and the test passes green, having verified nothing. This is the inert-matcher failure the suite says the anchor exists to catch, and there is no non-empty count check to prevent it.

**3. The remedy test claims to cover every slug but checks only one.**
- **What:** The test named "every slug carries a remedy" exercises only `mcp-trust-modal` and a made-up unknown slug.
- **Where:** line 188, `run pane_modal_remedy mcp-trust-modal`, with line 190, `echo "$output" | grep -q 'enabledMcpjsonServers' || false`, and line 191, `run pane_modal_remedy some-future-modal`.
- **Why it is wrong:** `workspace-trust-modal` is a slug the suite asserts the lib emits (line 78), but its remedy is never checked. If it is missing or empty, the fallback for unknown slugs may still return something non-empty, and the suite passes. The guard does not cover the class its title says it covers.
