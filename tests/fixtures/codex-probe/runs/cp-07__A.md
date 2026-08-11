I read the whole file and found four defects, all in the test suite's own machinery rather than in the fixture screens or the true-positive/true-negative assertions. The most serious one is that the anti-rot arm — the part of the suite whose stated purpose is to catch silently-inert matchers — can itself go silently inert.

---

**Defect 1 — The ANTI-ROT test passes vacuously when the fragment enumeration is empty, so the anti-rot arm can itself rot to inert with no signal.**

**Where:** line 252, inside the test at lines 248–262, in combination with line 25:

```bash
    [ -n "$frag" ] || continue
```
```bash
  unset CC_MODAL_MCP_HEADER CC_MODAL_MCP_OPTION CC_MODAL_TRUST_HEADER CC_MODAL_TRUST_OPTION
```

**Why it is wrong:** `setup()` unsets all four `CC_MODAL_*` variables, and the test's only source of fragments is those same variables (`modal_fragments`, lines 243–245). The test assumes sourcing the lib repopulates them, but never verifies it. If the lib applies its defaults at call time inside `pane_modal_reason` (e.g. `${CC_MODAL_MCP_HEADER:-…}`) — a lib shape under which every other test in this file behaves identically and stays green — or if the variable names in the lib ever change, `modal_fragments` emits only empty lines, line 252 skips every one, `missing` stays empty, and the test passes having grepped the binary for nothing. There is no assertion that at least one non-empty fragment was checked, so the exact failure class the file's header says this arm exists to prevent (an audit that "would decay in lockstep with the thing it audits and never go red") applies to the arm itself.

---

**Defect 2 — The option-alone regression test cannot detect the option-only rule its comment claims it guards against; it passes because of the anchor, not the conjunction.**

**Where:** lines 96–97:

```bash
  run classify "the operator answered 1. Use this MCP server, which is session-scoped"
```

**Why it is wrong:** In this input the option text is preceded by the prose "the operator answered", so it sits mid-line. The suite itself establishes that the matcher is column-0-anchored and tolerates only chrome/marker/index prefixes (lines 121–130) while refusing mid-line text (lines 100–108). Therefore even a broken lib that classified on the option alone — precisely the rule the comment at lines 94–95 says "needs its own arm" — would reject this input on the anchor and the test would stay green. The guard does not cover the class it claims to cover; an anchored option-only mutant is only caught incidentally, by the column-0 option-list test at lines 146–153.

---

**Defect 3 — The anti-rot positive control accepts grep's error exit as proof of absence, so it can pass without demonstrating what it claims to demonstrate.**

**Where:** lines 270–271:

```bash
  run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"
  [ "$status" -ne 0 ] || false
```

**Why it is wrong:** `grep -q` exits 1 when the string is absent, but 2 when it fails to run (e.g., `$BIN` exists but is unreadable, or an I/O error). The assertion `-ne 0` accepts both. The control's entire purpose (lines 265–266) is to prove the grep machinery in the test above can genuinely fail on an absent string; under a grep error it passes while proving nothing — the same "unfalsifiable-looking" condition it was written to exclude, just inverted. In that same scenario the main test at lines 248–262 would go red for every fragment with the misdiagnosis "Claude Code reworded a dialog" rather than the true cause.

---

**Defect 4 — A set-but-broken `CC_MODAL_ANCHOR_BIN` override silently skips both anti-rot tests with a message describing a condition that isn't the one that occurred.**

**Where:** lines 221–223, surfaced through the skip at line 249 (and line 269):

```bash
  if [ -n "${CC_MODAL_ANCHOR_BIN:-}" ]; then
    [ -f "$CC_MODAL_ANCHOR_BIN" ] && { printf '%s' "$CC_MODAL_ANCHOR_BIN"; return 0; }
    return 1
  fi
```
```bash
  BIN="$(claude_binary)" || skip "no claude binary under \$HOME/.claude-*/ — the anchor cannot run, and that is a NON-VERDICT, not a pass"
```

**Why it is wrong:** When the override is set but points at a path that is not a file (a typo, or a binary that moved), `claude_binary` returns 1 and both anti-rot tests skip with "no claude binary under `$HOME/.claude-*/`" — a statement about the glob branch that never executed, and possibly false, since working binaries may well exist under `.claude-*`. The one box where an operator deliberately pinned the anchor is the box where a single typo turns the entire anti-rot arm into a non-verdict whose skip message points at the wrong cause, instead of a failure saying the pin is broken.

---

Everything else holds up under scrutiny: the pinned-environment setup, the `run`/`classify` plumbing (unexported overrides are visible to the sourced function, and the herestring loop keeps `missing` in the parent shell), the numeric-track selection in `claude_binary` including the unmatched-glob guard, and the true-positive/true-negative screens are all consistent with the behavior the suite documents.