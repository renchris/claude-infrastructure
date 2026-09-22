I found three defects. All of them are in the anti-rot arm; the classifier tests look sound.

### 1. A misconfigured `CC_MODAL_ANCHOR_BIN` becomes a skip, not a failure

**What:** If the operator sets `CC_MODAL_ANCHOR_BIN` to a path that does not exist, the anti-rot check is silently skipped instead of failing.

**Where:** Lines in `claude_binary()`:
```bash
    [ -f "$CC_MODAL_ANCHOR_BIN" ] && { printf '%s' "$CC_MODAL_ANCHOR_BIN"; return 0; }
    return 1
```
and in both anti-rot tests:
```bash
  BIN="$(claude_binary)" || skip "no claude binary under \$HOME/.claude-*/ — the anchor cannot run, and that is a NON-VERDICT, not a pass"
```

**Why it is wrong:** Suppose the override is set on a box that pins a different binary, and the path has a typo or has gone stale after an upgrade. `claude_binary` returns 1 and both tests `skip`. The skip message says no binary was found under `$HOME/.claude-*`, which misdescribes the cause. The one guard against a stale fragment is disabled by a configuration error, and nothing reports it as an error.

### 2. A newest track without a recognised binary also becomes a skip

**What:** If the newest-numbered track has neither `claude.exe` nor `cli.js`, the function gives up rather than failing or trying the other tracks. The anti-rot arm is then skipped even though valid binaries are installed.

**Where:**
```bash
  for p in "$REAL_HOME/.claude-$t/node_modules/@anthropic-ai/claude-code/bin/claude.exe" \
           "$REAL_HOME/.claude-$t/node_modules/@anthropic-ai/claude-code/cli.js"; do
    [ -f "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
```

**Why it is wrong:** Take a partially installed or aborted `.claude-221` sitting next to a working `.claude-220`. Selection picks 221, finds no file, and returns 1, so the test skips. The same happens if a future package layout moves the entry point. In both cases the drift check stops running, and it is reported as a "non-verdict" rather than a failure. This is the silent-inert failure the suite says it exists to prevent.

### 3. The positive control passes when `grep` errors

**What:** The control asserts `status -ne 0`. `grep` also exits non-zero (status 2) when it cannot read the file, so the control passes whether or not the string is actually absent.

**Where:**
```bash
  run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"
  [ "$status" -ne 0 ] || false
```

**Why it is wrong:** This test is meant to prove the anchor *can* go red on a real absence. It goes green in these cases too:
- `$BIN` is unreadable.
- `$BIN` contains a `'` that breaks the `bash -c` quoting.
- The `grep` invocation is malformed.

In each case the exit status is 2, not 1, so the test passes for the wrong reason. It never distinguishes "absent" (1) from "error" (2), so it does not show that the anchor works.
