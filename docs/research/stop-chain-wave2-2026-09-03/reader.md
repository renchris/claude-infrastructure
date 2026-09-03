# c9c3445be29d — session-continue.sh kill-switch reader is blind to a multi-line message

**VERDICT (see §6 for reasoning): DRIVABLE-NOW.** Confirmed at origin/main `24c598bac`, reproduced
end-to-end with a clean 3-arm discriminator, one-hunk fix already proven in a sibling, no caller wants
the truncating behavior, and zero existing tests depend on it.

Repo read-only. All scratch under `…/scratchpad/drive/`. Nothing in the repo was written.

---

## 1. VERIFY — the shape at today's origin/main

`git diff origin/main -- hooks/session-continue.sh` is **empty**, so the worktree copy IS trunk.

`hooks/session-continue.sh:190-201` (origin/main):

```bash
last_user_msg() {
  local tp
  tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
  [ -n "$tp" ] && [ -f "$tp" ] || return 1
  jq -r 'select(.type=="user")
         | .message.content
         | if type=="string" then .
           elif type=="array" then ([.[]?|select(.type=="text")|.text]|join("\n"))
           else empty end
         | select(. != "")' "$tp" 2>/dev/null | tail -1
}
kill_switch_active() {                                    # :204-208
  local m; m="$(last_user_msg)" || return 1
  [ -n "$m" ] || return 1
  printf '%s' "$m" | grep -iqE "$KILL_RE"
}
```

**Is the shape identical to the pre-fix `ca_last_user_msg`? YES — the jq program is byte-identical.**
Diffing the pre-fix `hooks/completion-assert.sh:161-168` (parent of `c18a55c09`) against
`session-continue.sh:195-200`: the same 6-line jq filter, the same `-r`, the same `| tail -1`. The fix
commit's own body says so: *"The reader was ported verbatim from session-continue.sh:190-201, which
still has it; filed rather than fixed here because it is a second hook with its own proof obligation."*
That filing is this item.

### ⚠️ ONE HALF OF THE REFERENCE FIX DOES **NOT** PORT — the `grep -q` half

`c18a55c09` fixed **two** defects. Only defect 1 (the reader) exists here.

Defect 2 was `grep -q` SIGPIPEing its producer **under `set -o pipefail`**. `session-continue.sh` sets
**no shell options at all** — `grep -n 'pipefail' hooks/session-continue.sh` → **no match**;
`grep -n '^[[:space:]]*set ' hooks/session-continue.sh` → **no match**. Without `pipefail` a pipeline's
status is the *last* command's, i.e. grep's own, so the `grep -iqE` at :207 reads TRUE on a match and
the inversion cannot occur here.

**Do not port the `>/dev/null` drain as a "same fix" without saying why.** Copying it is harmless and
arguably tidy, but it is defence against a pattern that is *provably* not live at this site, and the
reference commit's own lesson is that writing "not reproducible here" without a control is how the
first attempt went wrong. Either leave :207 alone, or drain it **and** state that the site lacks
pipefail so no test can distinguish the branches. Do not claim a second bug fixed.

**Callers of `kill_switch_active` — the blast surface (line numbers differ slightly from the brief):**

| Site | Line | What the miss costs |
|---|---|---|
| wake floor | **:656** | blocks a stop the operator asked for |
| mechanical arm | **:745** | manufactures a sentinel on a kill turn |
| ship floor | **:889** (brief said 863) | nudges 📦/🚀 after "…and stop" |
| armed path (a) | **:997** (brief said 971) | stale sentinel BLOCKS — this is the D-8 bug returning |

Four sites, one predicate. That is the good news for the fix: **one hunk repairs all four.**

---

## 2. REPRODUCE — done, with a clean 3-arm discriminator

Driver: `…/scratchpad/drive/repro.sh` (fixtured `$HOME`, `CLAUDE_CONFIG_DIR`, `CC_MAILBOX_DIR`,
`CONTINUE_IDL`, `CONTINUE_LOG`, pinned `ITERM_SESSION_ID`, `CC_WAKE_FLOOR=0` — the same isolation
`tests/session-continue.bats` `setup()` uses, so the sentinel arm is what is under test). It drives the
**real** `hooks/session-continue.sh` in actuation mode via Stop JSON on stdin.

**Command:**

```
bash /private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/6d405232-4824-4694-80a1-23165ef59be4/scratchpad/drive/repro.sh
```

**Output, verbatim:**

```
CONTROL  single-line, phrase is the whole message : ALLOWED   (expect ALLOWED)
SUBJECT-A phrase on line 1, 5 lines after     : BLOCKED   (expect ALLOWED; BLOCKED = the bug)
SUBJECT-B phrase on the LAST line             : ALLOWED   (expect ALLOWED)

--- reader output, current (jq -r | tail -1) on SUBJECT-A's transcript ---
- and the docs page
--- reader output, FIXED (jq -c | tail -1 | decode) ---
Do the smallest possible fix and stop.

Context for later, do not act on it now:
- the retry loop in foo.sh
- the ledger row for bar
- and the docs page
```

SUBJECT-A's message is the ordinary operator shape — the instruction first, context under it:

```
Do the smallest possible fix and stop.

Context for later, do not act on it now:
- the retry loop in foo.sh
- the ledger row for bar
- and the docs page
```

The armed sentinel **BLOCKED the stop**. The reader returned `- and the docs page` — the last LINE,
not the last RECORD — and `and stop` on line 1 was invisible.

**The control matters:** the single-line arm (CONTROL) and the phrase-last arm (SUBJECT-B) both
ALLOWED, so the red is attributable to line position alone, not to the fixture or the harness. This is
also exactly why the bug survived: **every existing kill-switch test uses a single-line message**, and
a single-line fixture can never reach this bug's regime.

Note this needs no size at all — 6 short lines is enough. The reference commit's 200k-line fixture was
sized for the *pipefail* half, which does not apply here (§1).

