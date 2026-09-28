I found three defects.

**1. The anti-rot test passes with nothing checked if the fragment list is empty.**
- **Where:** line 251, `    [ -n "$frag" ] || continue`. Line 254 feeds the loop: `  done <<< "$(modal_fragments)"`.
- **Why it is wrong:** `setup` unsets all four `CC_MODAL_*` variables (line 23), so `modal_fragments` only produces fragments if the lib defines them on source. If the lib resolves its defaults inline instead, or renames a variable, all four are empty. `modal_fragments` then prints only blank lines, every one is skipped, `missing` stays empty, and the test reports green having compared nothing against the binary. The same happens to any empty alternative, such as a trailing `|`. Nothing asserts that at least one fragment was actually checked, so this reads as "no drift" when it is really "nothing checked". That is the silent inert-matcher failure the file says it exists to catch.

**2. The positive control passes when grep errors, not only when the string is absent.**
- **Where:** lines 269–270, `  run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"` and `  [ "$status" -ne 0 ] || false`.
- **Why it is wrong:** `grep` exits 1 for "not found" and 2 for an error, such as an unreadable file or a `$BIN` containing a `'` that breaks the quoting. `-ne 0` accepts both. The claude binary can therefore be unreadable, or the path can break the quoting, and the control still passes. It is meant to prove the matcher can fail on a genuinely absent string, and it proves nothing in that case. `claude_binary` only checks `-f`, not readability.

**3. The remedy test claims to cover every slug but checks only one, so the workspace-trust slug is never checked.**
- **Where:** line 186 (`@test "every slug carries a remedy, and an unknown slug still yields one" {`) and line 187 (`  run pane_modal_remedy mcp-trust-modal`).
- **Why it is wrong:** the test title promises a remedy for every slug. Only `mcp-trust-modal` is asserted against real content (`enabledMcpjsonServers`, line 189). `workspace-trust-modal` is never passed to `pane_modal_remedy`. If its remedy were missing or wrong, it would fall through to the generic non-empty answer that the `some-future-modal` check accepts. The suite would stay green while a blocked pane reported the wrong or a useless remedy.
