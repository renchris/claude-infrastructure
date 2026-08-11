## Summary

I read the file in full. It contains a number of real defects, concentrated in the anti-rot arm at the bottom (the part that reaches outside the fixture) and in two of the "control" tests whose stated purpose their code does not achieve. Line numbers are counted from `#!/usr/bin/env bats` = line 1.

---

### 1. `modal_fragments` restates the enumeration it claims to read out of the lib, so a new modal class is silently unpinned

**Where** — lines 243–245:
```bash
  printf '%s\n%s\n%s\n%s\n' \
    "$CC_MODAL_MCP_HEADER" "$CC_MODAL_MCP_OPTION" \
    "$CC_MODAL_TRUST_HEADER" "$CC_MODAL_TRUST_OPTION" | tr '|' '\n'
```

**Why it is wrong** — Lines 14–16 and 199–201 state the arm "reads the fragments OUT OF THE LIB rather than restating them, so a class added tomorrow is pinned tomorrow without anyone remembering to extend this file." Only the *values* are read from the lib; the *enumeration* is hardcoded here as four variable names. Add a third class to `hooks/lib/pane-modal.sh` (say `CC_MODAL_THEME_HEADER`/`_OPTION`) and its fragments are never grepped — the exact "stale fragment fails SILENTLY" failure the arm exists to catch, and it reports green while the new matcher rots.

---

### 2. An empty fragment is silently dropped, so a fragment list that is entirely empty is reported as a pass

**Where** — lines 252 and 256:
```bash
    [ -n "$frag" ] || continue
```
```bash
  if [ -n "$missing" ]; then
```

**Why it is wrong** — Nothing asserts that any fragment was actually checked. If the lib renames one of the four variables (or `modal_fragments` gets a name wrong), that fragment expands to the empty string, `continue` skips it, `missing` stays empty and the test passes having verified nothing about that class. In the limiting case — all four names wrong, or the lib defaulting its patterns at point-of-use with `${VAR:-…}` rather than assigning them at source time, which is fully consistent with every override test in this file and with `setup()`'s `unset` at line 25 — the loop performs **zero** greps and the test still exits 0. A test whose sole subject is silent inertness has a silent-inert mode of its own.

---

### 3. The fragments are regexes but are grepped as fixed strings

**Where** — line 253:
```bash
    LC_ALL=C grep -qaF -- "$frag" "$BIN" || missing="$missing
```

**Why it is wrong** — The pattern variables hold regexes: lines 113–114 push `.*`-prefixed values through the same seam and expect them to behave as regex, and `tr '|' '\n'` on line 245 exists precisely because the values carry regex alternation. `tr` splits only top-level `|`; every other metacharacter survives into a `-F` (fixed-string) grep. So a pattern alternative containing a grouped alternation, a character class (line 8 records `[nyae]` as a matcher of exactly this family), or an escape needed for the dialog's own punctuation — the real trust dialog contains `trust?` and `(Like your own code`, lines 54–55 — is searched for byte-for-byte in the binary and cannot be found. The test then reds and prints "Claude Code reworded a dialog" (line 258) about a matcher that is working correctly: a false conviction, which is the very class the suite's item 1 exists to prevent.

---

### 4. The positive control treats grep's *error* exit as proof that the string is absent

**Where** — lines 270–271:
```bash
  run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"
  [ "$status" -ne 0 ] || false
```

**Why it is wrong** — `grep -q` exits 1 for "no match" and 2 for an error (unreadable file, and with `-q` the error status survives when nothing matched). `-ne 0` accepts both. If `$BIN` is a path that exists but cannot be read, or `claude_binary` resolved a wrong-but-present file — the "bad path" this control's own comment (line 266) names as the thing it guards against — the grep never meaningfully ran and the control goes green anyway. The mirror conflation exists at line 253: a grep error there is recorded as "fragment absent," so an unreadable `$BIN` reds with a diagnosis ("Claude Code reworded a dialog") that is not what happened.

---

### 5. The positive control does not exercise the code it claims to falsify

**Where** — line 270 (above) against the loop it is a control for, lines 251–255:
```bash
  while IFS= read -r frag; do
```

**Why it is wrong** — The comment at lines 265–266 says the control catches "a `grep -qa` that always matched (a bad path, a stray `|| true`)" in the test above. It cannot: it is an independent `bash -c` grep of a hardcoded string, sharing nothing with the anti-rot test but `claude_binary`. A stray `|| true` appended to line 253, or the empty-fragment vacuum of defect 2, leaves this control green and unchanged. The mutant it kills is one that does not exist in the subject.

---

### 6. A set-but-invalid `CC_MODAL_ANCHOR_BIN` disables the whole arm as a skip, under a message that asserts something false

**Where** — lines 221–223, and the consumers at 249 and 269:
```bash
    [ -f "$CC_MODAL_ANCHOR_BIN" ] && { printf '%s' "$CC_MODAL_ANCHOR_BIN"; return 0; }
    return 1
```
```bash
  BIN="$(claude_binary)" || skip "no claude binary under \$HOME/.claude-*/ — the anchor cannot run, and that is a NON-VERDICT, not a pass"
```

**Why it is wrong** — An operator who typos the override path, or points it at a binary that was moved by an upgrade, gets `return 1`, which is indistinguishable at the call site from "nothing is installed." Both anti-rot tests then skip, and the skip text tells the reader no claude binary exists under `$HOME/.claude-*/` — a claim the code never checked in this branch, and which is typically false on a box that pins its own binary. The one arm that can detect matcher rot goes quiet on operator error, with a message that sends the reader to the wrong place.

---

### 7. If the newest track lacks both binary paths, the arm skips instead of falling back to the tracks that have them

**Where** — lines 234–238:
```bash
  for p in "$REAL_HOME/.claude-$t/node_modules/@anthropic-ai/claude-code/bin/claude.exe" \
           "$REAL_HOME/.claude-$t/node_modules/@anthropic-ai/claude-code/cli.js"; do
    [ -f "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
```

**Why it is wrong** — `t` is fixed to the numerically highest `.claude-N` before this loop and there is no retry with the next-highest. On the box described at line 204 (six tracks side by side), a newest directory that is a config-only dir, or one mid-install with no `node_modules` yet, yields `return 1` even though 183/219/220 — including the binary the repo actually pins per line 212 — are present and greppable. The test skips with "no claude binary under `$HOME/.claude-*/`", which is false: five of them are sitting there.

---

### 8. The env-seam test cannot detect an *additive* pattern, which is the one thing it claims to rule out

**Where** — lines 177–178 and 184–185:
```bash
  CC_MODAL_MCP_HEADER="Totally New Dialog"
  CC_MODAL_MCP_OPTION="press 1 to continue"
```
```bash
  run classify "$(mcp_screen)"
  [ "$status" -eq 1 ] || false
```

**Why it is wrong** — Both halves of the conjunction are overridden at once, and the "replacement" proof is a screen that requires both to match. Suppose the lib appended rather than replaced for the header (effective pattern `<default>|Totally New Dialog`) while replacing the option. Feeding `mcp_screen` then matches the header via the surviving default, fails the option, and returns 1 — line 185 passes, and the test named "an env override replaces a pattern rather than adding to it" reports the property holds for a lib that violates it. Neither variable is shown to be a replacement on its own, and the two trust variables are never exercised as seams at all.

---

### 9. "every slug carries a remedy" tests one of the two enumerated slugs

**Where** — lines 188–195:
```bash
@test "every slug carries a remedy, and an unknown slug still yields one" {
  run pane_modal_remedy mcp-trust-modal
```

**Why it is wrong** — `workspace-trust-modal`, named as a shipping slug at line 79, is never passed to `pane_modal_remedy`. A workspace-trust remedy that is missing, empty, or that silently falls through to the unknown-slug default text ships green: the unknown-slug arm at line 192 only proves the default branch produces *something*, and would not distinguish a known slug that fell into it. The test asserts a universal ("every slug") from a single instance.

---

## Minor — inaccurate claims, no behavioural consequence in this file

- **Line 18**: `# Assertions are `[ ]` / `|| false`; `[[ ]]` and `(( ))` are errexit-EXEMPT in bats.` — this is not true of bash: a failing `[[ ]]` or `(( ))` as a standalone command under `set -e` does abort the test. The convention the file actually follows is safe either way, so nothing here misbehaves, but the stated rationale would mislead a later edit.
- **Lines 205 and 226**: the claim that lexical glob order "resolved 2.1.156 over 2.1.220" cannot be the cause described — all six names at line 204 are three digits, so lexical and numeric order coincide; the original symptom must have come from taking the *first* glob entry rather than the last. The current code takes the numeric maximum and is correct for these names regardless.
- **Line 170**: `run classify ""` sends one empty line (`printf '%s\n' ""`), not the zero-byte capture that an actually unreadable pane produces, so the test's name overstates what it exercises.
- **Lines 126 and 129**: neither arm of the box-chrome test checks `$output`, so a status-0 return carrying the *wrong* slug would pass.