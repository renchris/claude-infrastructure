# D2: Hook and ledger enforcement — a lead keeps working while a decision is open

Designer slot D2 (hook and ledger enforcement), for operator ruling `d610f8473106`. Worktree `lead-idle-fix` at
`958b23030`. Every code anchor is `path:line` in this worktree. `R` = `CLAUDE.rules.slim.10-session-close.md`,
`S` = `CLAUDE.global.slim.md`, `G` = `CLAUDE.global.md`, `TX` = the B13 lead transcript
(`~/.claude-quaternary/projects/-Users-chrisren-Development-agent-context-sync/666022fd-ed3e-4e72-b293-7caae899d585.jsonl`),
`IDL` = `~/.claude/autonomy/idl.jsonl`. Maps cited as `maps/<name>.md`. Numbers are labelled **measured** (command
named) or **estimated** (method named). This is a design only: nothing in the repo or under `~/.claude` was changed.

---

## 0. The design in one paragraph

The ledger learns "ungated in-scope work remains" from **this session's own contract in the DoD store**, not from a
packet schema field and not from prose. Three facts, all read from `## … · session=<SID>` blocks only: an open
**loop scope** (the session's newest `Scope (frozen):` line is a `loop until …` scope with no later
`Scope (done):`), its own **unchecked DoD boxes**, and a **hold declaration** (`Scope (held): <open packet id> — …`)
that the session writes when, and only when, an open decision really gates everything that remains. The default
flips from "an open class-C packet holds the whole session" to "an open decision holds only the act it names";
gating everything becomes a durable, auditable, session-scoped claim. `wrap-ledger.sh` keeps `RUNG=⛔` exactly as
today (no reorder, no new glyph, every pin green) and adds fields; one new floor in the already-registered
`hooks/session-continue.sh` refuses a ⛔ idle (and a loop-🔧 idle) while those fields say ungated work remains,
latched per decision state and HEAD, capped at 2 per decision state; `scripts/lead-supervisor.sh` mails the stalled
session itself (direct `cc-notify`, socket wake) at most 3 times per decision state. The B13 loop scope reaches the
store through an intake capture of the **first** user record (measured: it returns `TX:14`'s line in 0.207 s).
Rule text stops licensing the idle, routes status-quo judgment calls to class B and records the cross-vendor grant,
while the always-loaded tier shrinks by 69 units (measured, §3.11.4).

**The predicate** (computed by the ledger, consumed by hooks):

```
SCOPE_UNGATED = HELD ? 0 : LOOP_OPEN + OWN_REMAINDER
floor fires  ⇔  no sentinel ∧ ¬mechanical arm ∧ ¬ship floor
                ∧ ( (RUNG=⛔ ∧ BLOCKED>0 ∧ SCOPE_UNGATED>0) ∨ (RUNG=🔧 ∧ LOOP_OPEN=1) )
                ∧ ¬kill-switch ∧ ¬operator-hold ∧ ¬assignee ∧ ¬teardown ∧ ¬research-program
                ∧ ¬in-flight(CUSTODY_OPEN ∨ LANDING ∨ RESIDENT_MINE ∨ live workflow wave)
                ∧ ¬latched(sid, decision ids, scope head, HEAD) ∧ count(key) < CC_SCOPE_FLOOR_MAX(2)
```

---

## 1. How the ledger can KNOW "ungated work remains" without a schema field

### 1.1 What exists today, and why each candidate fails alone

| Candidate | What it reads | Why it cannot carry the predicate alone |
|---|---|---|
| `REMAINDER` (unchecked boxes) | lineage-filtered DoD stream, all sessions of the toplevel (`scripts/wrap-ledger.sh:929-941`) | **0** unchecked boxes in the whole store (measured: `cat ~/.claude/autonomy/dod/*.md \| grep -cE '^[[:space:]]*[-*][[:space:]]+\[[[:space:]]\]'` → 0). Not session-scoped, so a floor on it fires on every ⛔ close in a shared checkout (`hooks/session-continue.sh:997-1002` refuses it for exactly that reason). |
| `DOD_SCOPE` | newest `Scope (frozen):` of **any** session in the toplevel (`scripts/wrap-ledger.sh:924-928`) | During the idle it was a 2026-10-08 scope of session `1f572e53` (`maps/incident-replay.md` §0.1). Using it would also make every later session in agent-context-sync inherit the alarm (alarm polarity, `scripts/wrap-ledger.sh:49-52`). |
| Plan checkboxes | nothing: the ledger opens no plan (`maps/wrap-ledger.md` §2.2) | B13's plan had 0 unchecked boxes (measured there). Plan path is unknowable to the ledger. Rejected. |
| A packet field (`--gates`, `--ceiling`) | cc-decide store | Fold-to-`all` keeps the 48 open packets safe but leaves B13 unfixed: the incident packets carried no field (`maps/cc-decide.md` §7). A required flag costs 61 test call sites plus `scripts/research-kit/lib/gate_sweep.py` and is refused on the STOP-ASK escape path (`bin/cc-decide:81-86`). And the packet does not know the session's scope: gating is a relation between a decision and scope items, and the items live in the DoD. Not used here (another slot may add it; §6 item 1 shows how it composes). |
| Close prose | the model's words | "need your call" is the ledger's own mandated readout (`scripts/wrap-ledger.sh:2607-2609`); F2 and F3 carry no hold phrase (`maps/incident-replay.md` §6.3). Rejected as a discriminator. |

### 1.2 The decision: own-session contract facts plus a hold declaration

1. **LOOP_OPEN** — the session's own newest `Scope (frozen):` line (block header carries `· session=<SID>`, written
   by `hooks/dod-persist.sh:182`) matches an **anchored** loop pattern, and no own `Scope (done):` line follows it.
2. **OWN_REMAINDER** — unchecked boxes in own blocks at or after that frozen line.
3. **HELD** — an own `Scope (held):` line after that frozen line names at least one id in this session's **open**
   class-C set (`BLOCKED_IDS`, read in the existing cc-decide fork). A held line naming only answered packets is
   `HELD_SRC=stale`, i.e. not held.
4. **SCOPE_UNGATED** = `HELD ? 0 : LOOP_OPEN + OWN_REMAINDER`.

The default this encodes — an open decision holds only the act it names — is the measured reality: in every
genuine class-C packet sampled, the gate covered one act, not the session's scope (`maps/legit-stops.md` §0.1, §3
L1-L12), and 7 of 11 transcript-checked idles had already exhausted ungated work (`maps/legit-stops.md` §4), which
this design reads as `SCOPE_UNGATED=0` and leaves alone.

### 1.3 The loop pattern, measured

```
LOOP_SCOPE_RE1='^([^.;:!?]{0,40}[^a-z.;:!?-])?(loop|repeat|iterate|keep (going|looping|running))[[:space:]]+until([^a-z]|$)'
LOOP_SCOPE_RE2='^[^.;:!?]{0,40}until[[:space:]]+(dry|nothing new|a round confirms)'
# applied to tolower(<text after "Scope (frozen):">)
```

- **Anchored on purpose.** The unanchored pattern from `maps/wrap-ledger.md` §2.5 matched the research brief that
  launched this very investigation ("…including a loop scope ("loop until …") that has no checkboxes", at char 775
  of 1641) (measured: python `re.finditer` over that transcript's first user record). Anchoring to the scope's own
  first clause (≤40 chars, no sentence break) excludes descriptions of loops.
- **macOS awk (version 20200816) does not treat `^` inside a group as an anchor** (measured: `(^|[^a-z-])loop` fails
  on "loop until green"; variant above passes), hence the `^(…)?` shape.
- **DoD store:** matches **1 of 362** frozen lines, the B13 capture (measured: awk over
  `~/.claude/autonomy/dod/*.md` with the two patterns).
- **Fixtures** (measured, same awk): matches "Loop until dry. Each round", "repeat until a round confirms nothing
  new", "keep going until the backlog is empty"; does not match the research brief, "Fix gate-runaway-loop until
  landed", "DEFAULT-OFF until the operator rules", "dry-run the migration until it passes", "drain-loop until 5pm",
  "fix the flaky test; repeat until green".
- **First-prompt sample:** of 755 transcripts modified in the last 7 days (>20 KB, top-level), 294 carry a
  `Scope (frozen):` line in their first user record; the unanchored pattern matched 7 (6 are the B13 lead's recycle
  lineage `e739e5b5 502bd860 f1997ec3 1e7dc0e1 666022fd 98214164`, 1 is the false positive above); the anchored
  pattern matches the 6 (measured: `find … -mtime -7 -size +20k | head -900`, `head -n 200 | jq first(...)`,
  grep; the 7th excluded by construction since its hit is at char 775).

The two patterns live in ONE new file, `hooks/lib/loop-scope.sh`, sourced by both the ledger and session-continue,
so the producer and the intake capture cannot drift.

### 1.4 Closing the capture gap (the floor was inert for the exact B13 shape)

The loop scope existed only in the recycle brief (`TX:14`) until a manual `set` at 20:15:35Z
(`~/.claude/autonomy/dod/repo-7030c1939664b2e4.md:26-27`, measured `sed -n`). dod-persist runs only on SessionStart
and PreCompact (measured: `jq '.hooks.SessionStart[]?.hooks[]?.command'` / `PreCompact` on `~/.claude/settings.json`;
it is not on UserPromptSubmit or Stop), and the session never compacted (`maps/wrap-ledger.md` §0.2).

**Intake capture in `hooks/session-continue.sh`** (already registered on Stop): once per session per cwd, read the
**first** genuine user record (never the newest line: for a lead the newest is a lane brief, `TX:3875`,
`maps/incident-replay.md` §0.2), take its first `Scope (frozen):` line, and **only if it is a loop scope** and the
store holds no block from this session yet, append it through `dod-persist.sh set` with this session's id.

- Measured on TX: `head -n 400 TX | jq -rn 'first(inputs | select(.type=="user" and …))…' | grep -m1 -oE 'Scope \(frozen\):.*'`
  returns `Scope (frozen): loop until dry. Each round = rehearse …` from `TX:14`, 0.207 s wall.
- **Loop scopes only, deliberately.** Capturing every first-prompt scope would move `DOD_SCOPE`, `DRAIN_SCOPE` and
  the ✅ certificate (`hooks/operator-readout.sh:532-545`) for every other session in the same checkout, because the
  lineage filter separates worktrees, not sessions (`hooks/dod-persist.sh:197-206`). 294 of 755 first prompts carry a
  scope; 6 are loops (measured above). Loop-only capture writes for those 6 and nothing else.
- R:26 is corrected at the same time: it claims "(`dod-persist.sh` captures it)", which is false for an inline scope
  until PreCompact (`hooks/dod-persist.sh:6-17`).

---

## 2. Mechanism per goal

| Goal | Mechanism (this design) | Where |
|---|---|---|
| (a) keep working on every ungated in-scope item | Ledger facts `SCOPE_UNGATED`/`HELD`; ⛔ READOUT and `rung_next` stop saying "nothing below it closes" when ungated work remains; **scope floor** blocks the ⛔ idle; mechanical 🔧 arm also arms on ⛔ for own dirty files ("commit in-progress work first", R:38, unenforced under ⛔ today: `maps/stop-hooks.md` §2.3); rule text R:38/R:103/R:189/R:217 + G twins; tool text that says "disarm on ⛔" fixed | §3.1, §3.3, §3.11 |
| (b) status-quo judgment calls → class B; C only for cc-decide's set | Rule text R:160 (+G:1000-1002) with the full class-B command including `--default-effect no-change --project`; dispatch-assert texts `:237`, `:269`; `bin/cc-decide:103` comment; a non-blocking stderr route hint on every class-C open; the scope floor's discharge (2) teaches the re-file | §3.8, §3.10, §3.11 |
| (c) find an existing ruling before asking | Rule text R:68 (+G:657); optional `cc-decide open` stderr ruling hint (BM25 over answered packets, 3 s bound, never refuses), adopted from `maps/ruling-discovery.md` §6.1 | §3.10, §3.11 |
| (d) standing operator grants every session loads | `R` section "Standing operator grants" beside F2 (paid for by cuts: the always-loaded tier shrinks 69 units, measured); full text with the verbatim quote in `G`; typed record `config/standing-grants.json`; pin test | §3.11, §3.12 |
| (e) close stack refuses a Blocked idle while ungated work remains, incl. a loop scope | `LOOP_OPEN` floor in the ledger (own session, anchored pattern, `Scope (done)` end marker, research-program abstain) + intake capture + **scope floor** in session-continue (one actuator; completion-assert yields through the existing marker) | §3.1-§3.3 |
| (f) wake a stalled session itself | `nudge_subject` in `scripts/lead-supervisor.sh`: oracle = the session's own last scope-floor IDL row; direct `cc-notify <sid>` (socket wake when no watcher); damped per decision state, 3 max with 2 h/4 h back-off, 3 per sweep, fail-closed marker | §3.9 |

---

## 3. File-by-file changes (pseudo-diffs)

### 3.1 `scripts/wrap-ledger.sh` (producer; fields only, RUNG order unchanged)

**(i) Keep the filtered DoD stream** (inside the loop at `:913-944`; zero forks):

```bash
 DOD_SCOPE=""; DRAIN_SCOPE=0
+_WL_FF_ALL=""          # § OWN SCOPE reads this after the session id resolves (:960)
 while IFS= read -r _wl_df; do
   …
   if command -v dod_filter_for >/dev/null 2>&1; then
     _wl_ff="$(dod_filter_for "$PWD" "$_wl_df")"
+    _WL_FF_ALL="${_WL_FF_ALL}${_wl_ff}
+"
```

The no-lib fallback branch (`:926`) leaves `_WL_FF_ALL` empty, so every new field reads 0 there (fail open).

**(ii) `compute_own_scope`, called right after `_wl_resolve_sid` (`:960`)** (one `awk` fork, only when a DoD is
present and the SID resolved):

```bash
+# § OWN SCOPE (decision d610f8473106). This SESSION's contract, never the toplevel's: blocks whose
+# header carries `· session=$SID`. DOD_SCOPE above is the worktree's newest line and is shared by
+# every session in the checkout (alarm polarity, header :49-52); a floor keyed on it would fire on
+# a successor that never held the loop. Fail OPEN: any unknown leaves every field 0 (today).
+LOOP_SCOPE=0; LOOP_OPEN=0; LOOP_SRC="n-a"; LOOP_HEAD=""; OWN_REMAINDER=0
+HELD=0; HELD_SRC="n-a"; SCOPE_UNGATED=0; BLOCKED_IDS=""; BLOCKED_GLOSS=""; _WL_OWN_HELD=""
+compute_own_scope() {
+  case "${WRAP_SCOPE_FLOOR:-on}" in off|0|no|OFF|NO) LOOP_SRC="off"; HELD_SRC="off"; return 0 ;; esac
+  [ "$DOD" = "present" ] || return 0
+  [ -n "$SID" ] || { LOOP_SRC="none"; return 0; }
+  _wl_loop_lib || { LOOP_SRC="error"; return 0; }        # sources hooks/lib/loop-scope.sh (RE1, RE2)
+  local out has lp dn bx head held
+  out="$(printf '%s' "$_WL_FF_ALL" | awk -v sid="$SID" -v re1="$LOOP_SCOPE_RE1" -v re2="$LOOP_SCOPE_RE2" '
+    /^## / { own = (index($0, "session=" sid) > 0); next }
+    !own   { next }
+    /Scope \(frozen\):/ { fz=$0; sub(/^.*Scope \(frozen\):[ \t]*/, "", fz); dn=0; held=""; bx=0; next }
+    /Scope \(done\):/   { if (fz != "") dn=1; next }
+    /Scope \(held\):/   { if (fz != "") { held=$0; sub(/^.*Scope \(held\):[ \t]*/, "", held) }; next }
+    /^[ \t]*[-*][ \t]+\[[ \t]\]/ { if (fz != "") bx++; next }
+    END { s=tolower(fz); lp=(fz != "" && (s ~ re1 || s ~ re2))
+          gsub(/[\t\r\n\037]/, " ", fz); gsub(/[\t\r\n\037]/, " ", held)
+          printf "%d\037%d\037%d\037%d\037%s\037%s\n", (fz != ""), lp, dn, bx, substr(fz,1,160), substr(held,1,300) }' \
+        2>/dev/null)" || { LOOP_SRC="error"; return 0; }
+  # \037, not TAB: two free-text cells, and TAB is IFS whitespace — an empty cell would collapse
+  # and shift the next one (docs/research/TSV_FIELD_COLLAPSE_2026-07-25.md; supervisor :1012-1016).
+  IFS=$'\037' read -r has lp dn bx head held <<< "$out"
+  case "$bx" in ''|*[!0-9]*) bx=0 ;; esac
+  [ "$has" = 1 ] || return 0                              # no own frozen line: n-a
+  OWN_REMAINDER="$bx"; LOOP_HEAD="$head"; _WL_OWN_HELD="$held"
+  [ "$lp" = 1 ] || return 0
+  LOOP_SCOPE=1
+  [ "$dn" = 1 ] && { LOOP_SRC="done"; return 0; }
+  LOOP_OPEN=1; LOOP_SRC="own"
+}
+compute_own_scope
```

Truncation note: macOS awk 20200816 `substr` counts bytes, so the implementer either emits the whole line (scope
lines are single lines) and truncates in bash under the UTF-8 locale, or strips a trailing partial UTF-8 sequence,
so `jq --arg` downstream never sees a split code point.

**(iii) Research-program abstain, mode-independent** (inserted after `compute_research` at `:2594`; the call there
runs only in machine/full modes, so the loop path calls it itself to keep RUNG identical across modes):

```bash
+if [ "$LOOP_OPEN" -eq 1 ] || [ "$OWN_REMAINDER" -gt 0 ]; then
+  [ "$RESEARCH_PROGRAM" != "none" ] || case "$MODE" in machine|full) ;; *) compute_research ;; esac
+  if [ "$RESEARCH_PROGRAM" != "none" ]; then LOOP_OPEN=0; OWN_REMAINDER=0; LOOP_SRC="program"; fi
+fi
```

(R:74-80: inside an active program, residuals are not open work.)

**(iv) Ids and glosses ride the existing cc-decide fork** (`count_blocking_decisions`, jq at `:1527-1546`): one
`GL` row per counted packet, emitted after line 1 and before the `RC` rows; `count_rechecked` already skips any
row whose tag is not `RC` (`:1608-1609`), and line 1 is read alone (`:1550`).

```diff
           (if ($ask | length) == 1
            then ($ask[0].what_plain // "" | tostring | gsub("[\\t\\r\\n]"; " "))
            else "" end) ] | @tsv,
+        ( $ask[] | select(((.id // "") | tostring) != "")
+          | [ "GL", (.id | tostring),
+              ((.what_plain // "") | tostring | gsub("[\\t\\r\\n]"; " ") | .[0:90]) ] | @tsv ),
         ( $all[] | select((.session_sid // "") != $sid) …RC rows unchanged… )' 2>/dev/null)" \
```

```bash
   BLOCKED="$n"; BLOCKED_SRC="$SID_SRC"; UNCONVICTED_PKTS="$u"
+  local _gt _gi _gw
+  while IFS=$'\t' read -r _gt _gi _gw; do                # pure bash: zero forks; free text is the last cell
+    [ "$_gt" = "GL" ] && [ -n "$_gi" ] || continue
+    BLOCKED_IDS="${BLOCKED_IDS:+$BLOCKED_IDS,}$_gi"
+    BLOCKED_GLOSS="${BLOCKED_GLOSS:+$BLOCKED_GLOSS; }$_gi (\"${_gw}\")"
+  done <<< "$line"
```

**(v) HELD and SCOPE_UNGATED, right after `count_blocking_decisions` (`:2603`)** (zero forks):

```bash
+compute_held() {
+  [ "$HELD_SRC" = off ] && return 0
+  [ "${BLOCKED:-0}" -gt 0 ] || return 0                     # n-a: no own open class C
+  [ -n "$_WL_OWN_HELD" ] || { HELD_SRC="absent"; return 0; }
+  local id
+  # shellcheck disable=SC2086  # 12-hex ids, comma-joined by us
+  for id in ${BLOCKED_IDS//,/ }; do
+    case "$_WL_OWN_HELD" in *"$id"*) HELD=1; HELD_SRC="own"; return 0 ;; esac
+  done
+  HELD_SRC="stale"                                           # names only answered packets
+}
+compute_held
+if [ "$HELD" -eq 1 ]; then SCOPE_UNGATED=0; else SCOPE_UNGATED=$(( LOOP_OPEN + OWN_REMAINDER )); fi
```

**(vi) In-flight facts under ⛔, only when they can matter** (custody and residents are today skipped on ⛔,
`scripts/wrap-ledger.sh:2622-2648`; the floor needs them to tell "awaiting lanes" from "idle"):

```diff
 if [ "$BLOCKED" -gt 0 ]; then
   RUNG="⛔"
+  if [ "$SCOPE_UNGATED" -gt 0 ]; then count_open_custody; count_resident_members; fi
   if [ "$BLOCKED" -eq 1 ]; then
     READOUT="⛔ Blocked — need your call: ${BLOCKED_WHAT}."
   else
     READOUT="⛔ Blocked — ${BLOCKED} decision(s) need your call: cc-decide list --open"
   fi
+  if [ "$SCOPE_UNGATED" -gt 0 ]; then
+    if [ "$LOOP_OPEN" -eq 1 ]; then _wl_ug="your loop scope (\"${LOOP_HEAD:0:80}…\")"
+    else _wl_ug="${OWN_REMAINDER} item(s) of your frozen DoD"; fi
+    READOUT="${READOUT} Not gated by it: ${_wl_ug} — keep driving it; the frozen scope is the course until it is answered (stop only once \`dod-persist.sh set \"Scope (held): <id> — …\"\` records that it gates all that remains)."
+  fi
```

The prefix `⛔ Blocked — need your call: <what>.` / `… N decision(s) need your call: cc-decide list --open` is
untouched, so `tests/wrap-ledger.bats:1848-1851`, `:1866-1867` stay green and R:144's "keep the tail" still holds.
Cost: two forks (`cc-custody`, team scan) on ⛔ closes that have ungated work only; 0 sessions today (§5.3). Side
effect, stated: completion-assert's custody contradiction (`hooks/completion-assert.sh:1108`) now sees real custody on
those ⛔ closes; it acts only against a done-assertion and is bounded by its `assert` cap (`:134`), so it can only
strengthen.

**(vii) The loop 🔧 arm**, at CLOSE_FLOOR's rank inside the ✅-eligible branch (after `:2670-2673`):

```diff
   elif [ "$CLOSE_FLOOR" -eq 1 ]; then
     …
+  elif [ "$LOOP_OPEN" -eq 1 ]; then
+    # Same family as the drain floor: a contract-derived 🔧. Without it a class-B re-file of the
+    # B13 decision turns the false ⛔ into a false ✅ (maps/incident-replay.md §7 C5).
+    RUNG="🔧"; READOUT="🔧 Loose ends — your frozen scope is a loop with no recorded stop (\"${LOOP_HEAD:0:80}…\"); run the next round as scoped, or record its stop: ~/.claude/hooks/dod-persist.sh set \"Scope (done): <evidence>\"."
   elif [ -z "$TRUNK" ]; then
```

📦/🚀 still outrank it (`UNLANDED` is decided before the ✅-eligible branch at `:2615`), so a money-landing repo's
terminal 📦 (R:58) is never turned into a loop continuation, and the ship floor's land nudge comes first.

**(viii) `rung_next` (`:3096-3103`)**:

```diff
     "⛔") if [ "$BLOCKED" -eq 0 ] && [ "$BLOCKED_RECHECKED" -gt 0 ]; then
             printf 'STOP-ASK — research done, …'
+          elif [ "${SCOPE_UNGATED:-0}" -gt 0 ]; then
+            printf 'continue → drive the in-scope work the open decision(s) do not gate (%s); STOP-ASK only after `Scope (held): <id> — …` records that a decision gates all that remains' \
+              "$( [ "$LOOP_OPEN" -eq 1 ] && printf 'loop scope: run the next round' || printf '%s DoD item(s)' "$OWN_REMAINDER")"
           else
             printf 'STOP-ASK — put the decision in line 1 and hand it back; nothing below it closes (cc-decide list --open --class C)'
```

**(ix) Emit, after `BLOCKED_SRC=` (`:2909`)** — after `LIVE=` (line 18), so the BUSY splice position check
(`:575-599`) is untouched; numeric fields first, the two free-text fields last:

```bash
+  printf 'BLOCKED_IDS=%s\n' "${BLOCKED_IDS:--}"
+  printf 'LOOP_SCOPE=%s\n' "$LOOP_SCOPE"
+  printf 'LOOP_OPEN=%s\n' "$LOOP_OPEN"
+  printf 'LOOP_SRC=%s\n' "$LOOP_SRC"          # n-a|own|done|program|none|off|error
+  printf 'OWN_REMAINDER=%s\n' "$OWN_REMAINDER"
+  printf 'HELD=%s\n' "$HELD"
+  printf 'HELD_SRC=%s\n' "$HELD_SRC"          # n-a|own|stale|absent|off
+  printf 'SCOPE_UNGATED=%s\n' "$SCOPE_UNGATED"
+  printf 'LOOP_HEAD=%s\n' "$LOOP_HEAD"
+  printf 'BLOCKED_GLOSS=%s\n' "$BLOCKED_GLOSS"
```

**(x) Memo key (`:637`)**: `v1|` → `v2|` (emit shape changed; `maps/wrap-ledger.md` §4) and append
`|${WRAP_SCOPE_FLOOR:-}`. No other new environment seam is added (the loop pattern has no override variable).

**(xi) Header (`:20-31`)**: under ⛔ add "carries SCOPE_UNGATED/HELD: a ⛔ with ungated own scope is a decision to
relay AND work to drive"; under 🔧 add "∨ own loop scope with no recorded stop (§ OWN SCOPE)". The ladder order line
(`:20`) and the four ladder docs (`G:710`, `R:90`, `commands/wrap.md:74`, `hooks/lib/why-tier.sh:83`) stay true:
nothing is reordered.

### 3.2 `hooks/dod-persist.sh` and the new `hooks/lib/loop-scope.sh`

```diff
-    case "$scope" in *"Scope (frozen):"*|*"Scope (grown):"*) ;; *) scope="Scope (frozen): $scope" ;; esac
+    case "$scope" in *"Scope (frozen):"*|*"Scope (grown):"*|*"Scope (held):"*|*"Scope (done):"*) ;;
+      *) scope="Scope (frozen): $scope" ;; esac
     …
-    persist_dod "$f" "$scope" "$PWD" "manual-set" "${CLAUDE_CODE_SESSION_ID:-}"
+    persist_dod "$f" "$scope" "$PWD" "${DOD_SET_SOURCE:-manual-set}" "${CLAUDE_CODE_SESSION_ID:-}"
```

(`hooks/dod-persist.sh:487`, `:498`; usage string `:486` gains the two prefixes.) Today `set "Scope (done): …"`
would be rewritten to `Scope (frozen): Scope (done): …` and become the new contract (`maps/wrap-ledger.md` §2.5 b).
The dedup (`:495`) compares against the newest frozen line, so held/done lines always append. Only dod-persist and
wrap-ledger parse `Scope (` lines (measured: `grep -rnF 'Scope (' hooks scripts bin commands` and an escaped-paren
grep, filtered to grep/awk/case lines: `hooks/dod-persist.sh:140,149,159,341,344,487`, `scripts/wrap-ledger.sh:924,926`),
and both match `frozen`/`grown` only, so the new prefixes are invisible to every other reader; the SessionStart
injection shows them because it prints every own capture newer than the newest frozen line (`:475`).

`hooks/lib/loop-scope.sh` (new, ~15 lines): defines `LOOP_SCOPE_RE1`, `LOOP_SCOPE_RE2` (§1.3) and
`loop_scope_match <text>` (one awk, rc 0 on match). Resolved by both callers through their own-symlink ladders
(`scripts/wrap-ledger.sh:885-891` pattern; `hooks/session-continue.sh:120`). Absent lib ⇒ ledger `LOOP_SRC=error`,
intake capture skipped.

### 3.3 `hooks/session-continue.sh` (the one actuator)

**(i) Intake capture**, a new function called once per Stop right after `SC_SID=` (`:378`), before any floor:

```bash
+# ── SCOPE INTAKE (decision d610f8473106) — the loop contract must be ON DISK while the work runs ──
+# dod-persist captures only at PreCompact/`set`; the B13 lead never compacted, so its loop scope
+# reached the store 2 h after the idle ended. Read the FIRST genuine user record (the brief or the
+# operator's ask), never the newest Scope line (for a lead that is a lane brief, TX:3875). LOOP
+# SCOPES ONLY: any other capture would move DOD_SCOPE/DRAIN_SCOPE for every session in the checkout.
+scope_intake_capture() {
+  case "${CC_SCOPE_INTAKE:-1}" in 0|off) return 0 ;; esac
+  [[ "$cur_sid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || return 0
+  local mk="${f}.intake" seen tp line dodp df
+  IFS= read -r seen < "$mk" 2>/dev/null || seen=""
+  [ "$seen" = "$cur_sid" ] && return 0                      # once per session per cwd
+  printf '%s\n' "$cur_sid" > "$mk" 2>/dev/null || return 0  # marker FIRST: never a per-Stop rescan
+  command -v jq >/dev/null 2>&1 || return 0
+  tp="$(in_field transcript_path)"; case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
+  [ -f "$tp" ] || return 0
+  line="$(head -n "${CC_SCOPE_INTAKE_HEAD:-400}" "$tp" 2>/dev/null | jq -rn '
+     first(inputs | select(.type=="user" and (.isMeta != true) and (.isSidechain != true))
+       | .message.content
+       | if type=="string" then .
+         elif type=="array" then (if ([.[]?|select(.type=="tool_result")]|length) > 0 then empty
+                                  else ([.[]?|select(.type=="text")|.text]|join("\n")) end)
+         else empty end | select(. != ""))' 2>/dev/null | grep -m1 -oE 'Scope \(frozen\):.*')"
+  [ -n "$line" ] || { log_idl abstained "scope-intake-none"; return 0; }
+  _sc_loop_lib && loop_scope_match "${line#*Scope (frozen):}" \
+    || { log_idl abstained "scope-intake-not-loop"; return 0; }
+  dodp="${DOD_PERSIST_BIN:-$_scd/dod-persist.sh}"
+  [ -f "$dodp" ] || dodp="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/dod-persist.sh"
+  [ -f "$dodp" ] || return 0
+  df="$(cd "$cwd" 2>/dev/null && bash "$dodp" path 2>/dev/null)"
+  [ -f "$df" ] && grep -qF "session=$cur_sid" "$df" 2>/dev/null \
+    && { log_idl abstained "scope-intake-already"; return 0; }   # an explicit `set` always wins
+  ( cd "$cwd" 2>/dev/null && CLAUDE_CODE_SESSION_ID="$cur_sid" DOD_SET_SOURCE="intake-first-prompt" \
+      bash "$dodp" set "$line" >/dev/null 2>&1 ) || true
+  log_idl armed "scope-intake-captured" "$(jq -cn --arg h "${line:0:120}" '{scope_head:$h}' 2>/dev/null)"
+}
+scope_intake_capture
```

Cost: one marker read on every Stop; one `head|jq|grep` once per session (0.207 s measured on the 9 MB TX). The
marker holds one sid per cwd, so two sessions alternating in one checkout each rescan once per alternation; the
`session=<sid>` store check prevents a duplicate capture.

**(ii) Mechanical arm also arms on ⛔ for own dirty files** (`:1103`, `:1156`): R:38 already says "commit
in-progress work first", and committing to a branch is never the gated act (G3 local action). Bounded by the
existing `CC_MECH_MAX` × `CLAUDE_CONTINUE_MAX` and self-clearing on commit (`:1112-1154`).

```diff
-  [ "$rung" = "🔧" ] || return 1
+  local _ma_blk=0
+  case "$rung" in "🔧") ;; "⛔") _ma_blk=1 ;; *) return 1 ;; esac
   …
-  printf '%s' "Commit the ${n_files} file(s) … then land per the repo's ship policy. Deliberately parked, …" > "$f"
+  if [ "$_ma_blk" -eq 1 ]; then _ma_land="Commit them (an open decision does not stop a commit), but do not /ship what the open decision gates; land per the ship policy only work it does not gate."
+  else _ma_land="Run the repo's gate, commit with explicit paths, then land per the repo's ship policy."; fi
+  printf '%s' "Commit the ${n_files} file(s) you edited this turn that are still uncommitted: ${shown}. ${_ma_land} Deliberately parked, or not yours? Run \`~/.claude/hooks/session-continue.sh clear\` and say so in your close." > "$f"
   …
-  log_idl armed "mechanical-dirty" "$(jq -cn … '{cwd:$c,files:$n,source:"session-writes"}')"
+  log_idl armed "mechanical-dirty" "$(jq -cn … --arg r "$rung" '{cwd:$c,files:$n,source:"session-writes",rung:$r}')"
```

**(iii) The scope floor** — a fourth floor between `ship_floor` and `wake_floor` (`:1316-1328`):

```diff
   if ! mechanical_arm; then
     if ! _sf_json="$(ship_floor)"; then
       mark_blocked ship-floor; printf '%s' "$_sf_json"; exit 0
     fi
+    if ! _gf_json="$(scope_floor)"; then
+      mark_blocked scope-floor; printf '%s' "$_gf_json"; exit 0
+    fi
     if ! _wf_json="$(wake_floor)"; then
```

```bash
+# ── SCOPE FLOOR (decision d610f8473106; the B13 idle, 2026-10-24) ─────────────────────────────────
+# A ⛔ close used to be terminal by construction: the mechanical arm stood down at :1103 and the ship
+# floor at :1216, both silently, and the lead idled 11 h holding a loop its decisions did not gate.
+# This floor CONSUMES the ledger's SCOPE_UNGATED/HELD (never prose: "need your call" is the ledger's
+# own readout) and blocks ONCE per (sid, decision ids, own scope head, HEAD), at most
+# CC_SCOPE_FLOOR_MAX per decision state. Never per session lifetime (B13's ship-floor and assert
+# budgets were spent days earlier) and never per HEAD alone (a loop lands a commit every round).
+# Discharge is a STATE change only: the work, a class-B re-file, `Scope (held):`, `Scope (done):`.
+# Seams: CC_SCOPE_FLOOR (1|0|shadow) · CC_SCOPE_FLOOR_MAX · WRAP_LEDGER_BIN · SESSION_WRITES_LIB
+SCOPE_HOLD_RE='(wait|hold( off)?|pause)[^.!?]{0,40}(for|until)[^.!?]{0,30}(me|my (answer|call|reply|decision|go))|(don.?t|do not) (start|run|continue)[^.!?]{0,40}until'
+scope_floor() { # → JSON on stdout + rc 1 to BLOCK; rc 0 otherwise. Never fails.
+  case "${CC_SCOPE_FLOOR:-1}" in 0|off) return 0 ;; esac
+  command -v jq >/dev/null 2>&1 || return 0
+  local led; led="$(sc_ledger_read)" || return 0         # SC_LED_CACHE, else the ship-floor resolution
+  local rung blocked ungated loop_open held ids gloss head kind cust land res research waves
+  rung="$(led_field "$led" RUNG)"
+  blocked="$(led_field "$led" BLOCKED)";        case "$blocked" in ''|*[!0-9]*) blocked=0 ;; esac
+  ungated="$(led_field "$led" SCOPE_UNGATED)";  case "$ungated" in ''|*[!0-9]*) ungated=0 ;; esac
+  loop_open="$(led_field "$led" LOOP_OPEN)";    case "$loop_open" in 1) ;; *) loop_open=0 ;; esac
+  held="$(led_field "$led" HELD)";              case "$held" in 1) ;; *) held=0 ;; esac
+  ids="$(led_field "$led" BLOCKED_IDS)";        [ -n "$ids" ] || ids="-"
+  gloss="$(led_field "$led" BLOCKED_GLOSS)";    head="$(led_field "$led" LOOP_HEAD)"
+  case "$rung" in
+    "⛔") [ "$blocked" -gt 0 ] || return 0; kind="blocked" ;;   # re-check ⛔ (foreign) is not ours
+    "🔧") [ "$loop_open" -eq 1 ] || return 0; kind="loop"; ungated=1 ;;
+    *)    return 0 ;;                                            # SILENT: the common no-op (:76-79)
+  esac
+  SCF_RUNG="$rung" SCF_KIND="$kind" SCF_UNG="$ungated" SCF_LOOP="$loop_open" SCF_HELD="$held" SCF_IDS="$ids"
+  [ "$ungated" -gt 0 ] || { scf_log abstained "scope-floor-nothing-ungated"; return 0; }
+  kill_switch_active   && { scf_log abstained "scope-floor-kill-switch";   return 0; }
+  scope_hold_active    && { scf_log abstained "scope-floor-operator-hold"; return 0; }
+  sc_assignee_abstain  && { scf_log abstained "scope-floor-assignee";      return 0; }  # ship_floor :1189-1198 logic
+  wf_teardown_marked   && { scf_log abstained "scope-floor-teardown";      return 0; }
+  research="$(led_field "$led" RESEARCH_PROGRAM)"
+  case "$research" in ''|none) ;; *) scf_log abstained "scope-floor-research-program"; return 0 ;; esac
+  cust="$(led_field "$led" CUSTODY_OPEN)"; land="$(led_field "$led" LANDING)"; res="$(led_field "$led" RESIDENT_MINE)"
+  waves="$(sc_live_waves)"                                  # hooks/lib/live-waves.sh (moved from boundary-handoff :875-903)
+  case "$cust"  in ''|*[!0-9]*) cust=0  ;; esac
+  case "$land"  in ''|*[!0-9]*) land=0  ;; esac
+  case "$res"   in ''|*[!0-9]*) res=0   ;; esac
+  case "$waves" in ''|*[!0-9]*) waves=0 ;; esac
+  if [ "$cust" -gt 0 ] || [ "$land" -gt 0 ] || [ "$res" -gt 0 ] || [ "$waves" -gt 0 ]; then
+    scf_log abstained "scope-floor-inflight"; return 0        # an ARMED WATCHER alone is NOT in flight
+  fi
+  local head_sha skey sfile pkey psha pcnt smax
+  head_sha="$(cd "$cwd" 2>/dev/null && git rev-parse HEAD 2>/dev/null || echo '?')"
+  skey="$(printf '%s|%s|%s|%s' "${cur_sid:-?}" "$ids" "$kind" "$head" | "${CC_SHA1:-/sbin/sha1sum}" 2>/dev/null | cut -c1-12)"
+  [ -n "$skey" ] || return 0
+  sfile="${f}.scope.$(printf '%s' "${cur_sid:-anon}" | tr -c 'A-Za-z0-9-' '_')"
+  [ "${CC_SCOPE_FLOOR:-1}" = shadow ] && sfile="${sfile}.shadow"
+  smax="${CC_SCOPE_FLOOR_MAX:-2}"; case "$smax" in ''|*[!0-9]*) smax=2 ;; esac
+  read -r pkey psha pcnt < "$sfile" 2>/dev/null || { pkey=""; psha=""; pcnt=0; }
+  case "$pcnt" in ''|*[!0-9]*) pcnt=0 ;; esac
+  [ "$pkey" = "$skey" ] || { psha=""; pcnt=0; }             # a new decision state: a fresh budget
+  SCF_KEY="$skey" SCF_HEAD="$head_sha" SCF_N="$pcnt" SCF_MAX="$smax"
+  [ -n "$psha" ] && [ "$psha" = "$head_sha" ] && { scf_log abstained "scope-floor-latched"; return 0; }
+  [ "$pcnt" -ge "$smax" ] && { scf_log abstained "scope-floor-budget"; return 0; }
+  SCF_N=$(( pcnt + 1 ))
+  printf '%s %s %s\n' "$skey" "$head_sha" "$SCF_N" > "$sfile" 2>/dev/null \
+    || { scf_log abstained "scope-floor-unwritable"; return 0; }   # FAIL CLOSED: no bound, no block
+  [ "${CC_SCOPE_FLOOR:-1}" = shadow ] && { scf_log abstained "scope-floor-shadow"; return 0; }
+  scf_log fired "scope-floor"
+  jq -nc --arg r "$(scope_floor_reason "$kind" "$head" "$gloss" "$(led_field "$led" OWN_REMAINDER)")" \
+    '{decision:"block",reason:$r}'
+  return 1
+}
+scf_log() { # every ⛔ evaluation is DECISION-bearing (B-3): the supervisor's oracle reads these rows
+  log_idl "$1" "$2" "$(jq -cn --arg r "${SCF_RUNG:-?}" --arg k "${SCF_KIND:-?}" --argjson u "${SCF_UNG:-0}" \
+    --argjson lo "${SCF_LOOP:-0}" --argjson h "${SCF_HELD:-0}" --arg ids "${SCF_IDS:--}" --arg key "${SCF_KEY:-}" \
+    --arg hd "${SCF_HEAD:-}" --argjson n "${SCF_N:-0}" --argjson m "${SCF_MAX:-2}" \
+    '{rung:$r,kind:$k,ungated:$u,loop_open:$lo,held:($h==1),ids:$ids,key:$key,head:$hd,count:$n,max:$m}' 2>/dev/null)"
+}
+scope_hold_active() { # operator-authored "wait for my answer" — floor-only; KILL_RE (:386) is unchanged
+  [ -n "${_sc_lum:-}" ] || return 1                          # last user message, read ONCE in the memo block
+  printf '%s' "$_sc_lum" | grep -iqE "$SCOPE_HOLD_RE"
+}
```

The kill-switch memo block (`:1305-1315`) also stores the last user message text once (`_sc_lum="$(last_user_msg)"`),
so the hold test adds no transcript read. `sc_ledger_read` factors the resolution already duplicated in
`mechanical_arm` (`:1085-1101`) and `ship_floor` (`:1203-1214`); the second read in one Stop is a wrap-ledger memo
hit (same `WRAP_BUSY=off` key, `scripts/wrap-ledger.sh:630-660`).

**Block reason (`scope_floor_reason`)**, kind `blocked`:

```
⛔ SCOPE FLOOR — you are going idle on ⛔ while in-scope work the open decision(s) do not gate remains:
<your loop scope "loop until dry. Each round = rehearse …" | N unchecked item(s) of your frozen DoD>.
An open decision holds only the act it names; until it is answered the frozen scope is the course (rule:
"Needs a decision → file it, commit, then drive every in-scope item it does not gate"). Open: <id ("what…"); …>.
Do the next ungated step now (a loop scope: run the next round as scoped). Never build the gated act itself.
This floor is discharged only by a STATE change, never by a sentence:
 · the work itself (a landed round re-arms this floor at most once more for this decision state);
 · a judgment call with a status-quo course re-filed as class B, which stops it being ⛔:
   cc-decide open --class B --what "<same question>" --default "<the status-quo course>" --default-effect no-change
   --project <repo> --deadline <ISO> --conviction N --receipt R --option … --option …, then
   cc-decide action <old id> --evidence "superseded by class-B <new id>";
 · if every remaining in-scope item truly waits on it (money, self-modification, permission or credential, or a pick
   with no status-quo course): ~/.claude/hooks/dod-persist.sh set "Scope (held): <id> — <what it gates and why>",
   then close on ⛔;
 · the loop's stop condition met, or every remaining round needs an operator-only act (file that act first):
   ~/.claude/hooks/dod-persist.sh set "Scope (done): <evidence>".
(scope floor n/2 for this decision state)
```

Kind `loop` (no decision open): "🔧 SCOPE FLOOR — your frozen scope is a loop with no recorded stop ("…"), and you are
going idle with nothing in flight (no open custody, land, teammate or workflow wave). Run the next round as scoped.
If its stop condition is met, or every remaining round needs an operator-only act (file it: `cc-backlog needs
"<step>" --class needs-human`), record the stop: `~/.claude/hooks/dod-persist.sh set "Scope (done): <evidence>"`, then
close. (scope floor n/2 for this scope)"

**(iv) Text that tells the agent to disarm on ⛔**: header `:8`, `:14` ("disarm — on ✅/📦/⛔/📤") → "on ✅/📦/held
⛔/📤"; `continue_reason` `:1368` "When done (✅/📦), blocked on the user (⛔), or out of context (📤)" → "When done
(✅/📦), held on the user for everything that remains (⛔ with `Scope (held):`), or out of context (📤)". The
armed path has no rung check (`:1335` onward runs on sentinel presence), so once R:217 allows `set` on an unheld ⛔
the existing actuator drives ungated work with no further change.

### 3.4 `hooks/completion-assert.sh` — no new blocker; informative exoneration only

```diff
   if [ "$_ca_bk_ans" -eq 1 ]; then
-    _ca_exon="${_ca_exon}blocked-answered "
+    _ca_ung="$(lfield SCOPE_UNGATED)"
+    case "$_ca_ung" in ''|*[!0-9]*) _ca_exon="${_ca_exon}blocked-answered " ;;      # older/stub ledger: byte-identical
+      *) _ca_exon="${_ca_exon}blocked-answered:ungated=${_ca_ung} " ;; esac
```

(`hooks/completion-assert.sh:1229-1231`.) The `no-close-tell` gate (`:469-471`), the GENUINE exit (`:475-476`), the
⛔ spare (`:1220-1231`) and the double-block yield (`:1275-1298`) are unchanged; the scope floor writes the per-Stop
marker, so the ledger arm yields when both would fire. Rationale: all three B13 idle closes abstained at `:471`
before the ledger was read, and the `assert` budget was spent since 2026-10-22T07:49Z (`maps/stop-hooks.md` §0.1),
so any conviction here would have been unreachable or capped.

### 3.5 `hooks/anti-deference-nudge.sh` — two narrow changes, no TELLS change

1. **No prose-derived class-B packet under ⛔** (`:477-489`). The genuine-blocker branch auto-filed `f56cf0f827d7`
   (class B, conviction 0, no options) from session 666022fd at 2026-10-24T20:22:32Z while `d610f8473106` held ⛔
   (measured: `jq .what_plain decisions/f56cf0f827d7.json` = "The handoff is complete…"; IDL row
   `genuine-blocker {"packet":"f56cf0f827d7"}`). Hoist the ledger resolution (`:501-506`) above `:477`, read RUNG
   (a memo hit on the shared `WRAP_BUSY=off` key), and when it is ⛔ skip `open_packet_B`, logging
   `{"packet_skipped":"rung-⛔"}`: the session already holds a filed decision. Exit disposition unchanged.
   `open_packet_B` also exports `CC_DECIDE_HINTS=0` so the §3.10 hints never cost this Stop path anything.
2. **Narrow double-block yield** between `FIRE_KIND` (`:526-545`) and the latch (`:600`): when FIRE_KIND is
   `deference` or `false-done` and `${continue_sentinel}.blocked` names `scope-floor` (same lib and fallback as
   `hooks/completion-assert.sh:1281-1293`), abstain `double-block-yield:session-continue-scope-floor`. Shape arms
   (opaque-identifier, pane, category, peer) keep firing, as completion-assert's D-arms do.

Not changed: TELLS (`:170`), CATEGORY_TELLS (`:186`), SOFTCALL/HARD_CORE (`:455-456`) — the pins at
`tests/anti-deference-nudge.bats:294-297`, `:519-545`, `:706-717` stay green.

### 3.6 `hooks/boundary-handoff.sh` — optional (phase P5): free-win on a held or exhausted ⛔

Only when the scope floor would abstain for want of work, and never for a loop scope (a successor's ledger counts
only its own sid's packets, `scripts/wrap-ledger.sh:1529`, so a recycled loop lead would read 🔧-loop and run the
loop its predecessor held):

```diff
-  for w in "${_bscd:-}/../scripts/wrap-ledger.sh" "$HOME/.claude/scripts/wrap-ledger.sh"; do
+  for w in ${WRAP_LEDGER_BIN:+"$WRAP_LEDGER_BIN"} "${_bscd:-}/../scripts/wrap-ledger.sh" "$HOME/.claude/scripts/wrap-ledger.sh"; do
   …(read RUNG plus SCOPE_UNGATED, LOOP_SCOPE, BLOCKED_IDS, BLOCKED_GLOSS in the same loop)…
-  [ "$r" = "✅" ]
+  [ "$r" = "✅" ] && return 0
+  if [ "$r" = "⛔" ] && [ "${CC_BOUNDARY_FREEWIN_BLOCKED:-1}" = 1 ] && [ "${fw_ung:-1}" = 0 ] \
+     && [ "${fw_loop:-1}" = 0 ] && [ -n "$fw_ids" ] && [ "$fw_ids" != "-" ]; then FREEWIN_BLOCKED=1; return 0; fi
+  [ "$r" = "⛔" ] && FREEWIN_RUNG="⛔-ungated:${fw_ung:-?}"
+  return 1
```

Plus: after `elif free_win_now; then freewin=1` (`:670-671`), abstain `freewin-yield:session-continue` when the
per-Stop marker `${continue_sentinel}.blocked` exists (the compose-guard at `:687-694` sees only the sentinel, and
floors run exactly when there is none). ⛔ wording replaces `:958`: "context N% (≥35%) at an IDLE boundary where
every remaining in-scope item waits on open decision(s) <gloss>. They stay on disk under this session's id, so
your successor's ledger will NOT show them: carry the ids in the recycle brief." Cost: the new `WRAP_LEDGER_BIN` seam
enters the hermeticity seam tables (rules 5/6, `maps/test-infra.md` §5); every suite reaching the hook
(`boundary-handoff*.bats`, `session-continue.bats`, `migration-0073-stop-gate-timeouts.bats`,
`operator-surface-scope.bats`, `settings-dedup-stop.bats`, `settings-drift.bats`) must pin it. Not needed for any of
goals (a)-(f); it serves S:166 (idle ≥35% recycles).

### 3.7 `hooks/operator-readout.sh` — render the new 🔧 cause

```diff
         [ "${remainder:-0}" != "0" ] && parts="${parts:+$parts · }${remainder} DoD item(s) open"
+        [ "$(lf LOOP_OPEN)" = "1" ] && parts="${parts:+$parts · }loop scope open (no recorded stop)"
```

(`hooks/operator-readout.sh:1513`.) Without it a loop-only 🔧 renders "🔧 in progress — loose ends", the
renderer-drops-the-cause defect the file records at `:1480-1488`. The ⛔ arm (`:1541-1548`) prints READOUT verbatim,
so the "Not gated by it" clause reaches the operator block with no change.

### 3.8 `hooks/dispatch-assert.sh`, `hooks/lib/why-tier.sh`, `commands/wrap.md` — text only

- `hooks/dispatch-assert.sh:237`, `:269`: "`cc-decide open --class C --what \"…\"` if it is a decision" →
  "`cc-decide open --class B --what \"…\" --default \"<status-quo course>\" --default-effect no-change --project
  <repo> --deadline <ISO>` if it is a judgment call with a status-quo course (class C only for self-modification,
  money, a permission denial or a credential)". No test pins the old text (measured: `grep -n 'class C'
  tests/dispatch-assert*.bats` → none).
- `hooks/lib/why-tier.sh:312-313` and `commands/wrap.md:142-145`: same split.

### 3.9 `scripts/lead-supervisor.sh` — goal (f): mail the stalled session itself

**Why here.** After F3 (08:34:59Z) no Stop fired for 9 h 36 m (`maps/incident-replay.md` §1), so no Stop hook can
act; lead-supervisor logged 160 STALL? and 66 ESCALATED rows for the session (`maps/wake-path.md` §2.1) and told
nobody, because `send_page` returns 1 with no desk (`scripts/lead-supervisor.sh:414-415`). `cc-notify <sid>` to a
watcher-less live pane socket-wakes it; proven on this session at 20:27:36Z (`TX:5065-5069`,
`maps/wake-path.md` §3).

```bash
+SUBJECT_NUDGE="${CC_SUP_SUBJECT_NUDGE:-1}"       # 1 live · shadow (log only) · 0 off
+NUDGE_MAX="${CC_SUP_NUDGE_MAX:-3}"               # per decision state
+NUDGE_BACKOFF_S="${CC_SUP_NUDGE_BACKOFF_S:-7200}" # 2 h, doubled per attempt (2 h, then 4 h)
+NUDGE_SWEEP_MAX="${CC_SUP_NUDGE_SWEEP_MAX:-3}"   # fleet cap per sweep
+nudge_subject(){ # $1=sid — called in assess()'s STALL? branch after both exemptions. Never fails.
+  local sid="$1" row reason ung held ids key kind nf pk pc pl now wait out rc verdict enq nreason sweepf sn
+  [ "$SUBJECT_NUDGE" != 0 ] || return 0
+  [ -n "$NOTIFY_BIN" ] || return 0
+  [[ "$sid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || return 0
+  # ORACLE: the session's OWN last scope-floor row — the ledger's SCOPE_UNGATED as its Stop saw it.
+  row="$(grep -F "\"sid\":\"$sid\"" "$IDL" 2>/dev/null | tail -n 400 \
+        | sup_bounded 3 jq -c -s 'map(select(.hook=="session-continue" and ((.reason//"")|startswith("scope-floor")))) | last // empty' 2>/dev/null)"
+  [ -n "$row" ] || return 0                                   # FAIL CLOSED: no evidence of ungated work
+  IFS=$'\037' read -r reason ung held ids key kind <<EOF
+$(printf '%s' "$row" | jq -r '[.reason//"", (.ungated//0|tostring), (.held//false|tostring), .ids//"-", .key//"", .kind//""] | join("\u001f")')
+EOF
+  case "$reason" in scope-floor|scope-floor-latched|scope-floor-budget|scope-floor-shadow) ;; *) return 0 ;; esac
+  [ "${ung:-0}" -gt 0 ] 2>/dev/null && [ "$held" = false ] && [ -n "$key" ] || return 0
+  sweepf="$PAGEDIR/.nudge-sweep"; read -r _ sn < "$sweepf" 2>/dev/null || sn=0
+  [ "${sn:-0}" -lt "$NUDGE_SWEEP_MAX" ] || return 0            # file-based: assess() runs in $(…)
+  nf="$PAGEDIR/$sid.nudged"; read -r pk pc pl < "$nf" 2>/dev/null || { pk=""; pc=0; pl=0; }
+  [ "$pk" = "$key" ] || { pc=0; pl=0; }                        # a new decision state is new news
+  [ "${pc:-0}" -lt "$NUDGE_MAX" ] || return 0
+  now="$(now)"; wait=$(( NUDGE_BACKOFF_S << (pc > 0 ? pc - 1 : 0) ))
+  [ "${pc:-0}" -eq 0 ] || [ $(( now - pl )) -ge "$wait" ] || return 0
+  { [ -d "$PAGEDIR" ] && [ -w "$PAGEDIR" ] && { [ ! -e "$nf" ] || [ -w "$nf" ]; }; } \
+    || { idl subject_nudge_unwritable "\"sid\":\"$sid\""; return 0; }   # FAIL CLOSED: no marker ⇒ no send
+  if [ "$SUBJECT_NUDGE" = shadow ]; then
+    printf '%s %s %s\n' "$key" "$(( pc + 1 ))" "$now" > "$nf.shadow"
+    idl subject_nudge_shadow "\"sid\":\"$sid\",\"key\":\"$key\",\"attempt\":$(( pc + 1 )),\"ids\":$(json_str "$ids")"
+    return 0
+  fi
+  out="$(sup_bounded "$SUP_NOTIFY_TIMEOUT_S" "$NOTIFY_BIN" "$sid" --from lead-supervisor \
+         --subject "keep driving the ungated scope" "$(nudge_text "$kind" "$ids")" 2>&1)"; rc=$?
+  # cc-notify's OWN token: _wake_pane echoes cc-wake's stderr FIRST (cc-notify:1494), so the first
+  # bare `verdict=` is cc-wake's — the bug advise_subject has today (:557).
+  verdict="$(printf '%s\n' "$out" | sed -n 's/^cc-notify: verdict=\([a-z-]*\).*/\1/p' | tail -1)"
+  enq="$(printf '%s\n' "$out" | sed -n 's/^cc-notify: verdict=[a-z-]* enqueued=\([01]\).*/\1/p' | tail -1)"
+  nreason="$(printf '%s\n' "$out" | grep '^cc-notify: verdict=' | grep -oE 'reason=[^ ]+' | tail -1 | cut -d= -f2)"
+  if [ "$enq" = 1 ]; then                                      # DURABLY in the inbox: record, even if no wake
+    printf '%s %s %s\n' "$key" "$(( pc + 1 ))" "$now" > "$nf"
+    printf '%s %s\n' "$(now)" "$(( sn + 1 ))" > "$sweepf"
+  fi                                                           # enqueued=0 ⇒ no marker ⇒ retried, bounded by the cap
+  idl subject_nudge "\"sid\":\"$sid\",\"key\":\"$key\",\"attempt\":$(( pc + 1 )),\"notify_rc\":$rc,\"verdict\":$(json_str "${verdict:-unreadable}"),\"enqueued\":${enq:-0},\"reason\":$(json_str "${nreason:-}"),\"ungated\":$ung,\"ids\":$(json_str "$ids")"
+}
```

- **Call sites:** in `assess()` (`:1085-1089`), after the permission-beacon (`:1067`) and operator-adopted
  (`:1077`) exemptions and after `page "$sid" "STALL?" …`: `nudge_subject "$sid"`. ESCALATED is reached only
  through the same branch (`:744-752`), so no second site is needed. `sweep()` (`:1356`) resets
  `$PAGEDIR/.nudge-sweep` to `"<now> 0"` before the telemetry loop.
- **Marker lifetime:** `clear_page` (`:524`) and `clear_page_recovered` (`:583-609`) do NOT touch `.nudged` (they
  delete `.advised` today). Only `reap_clean` (`:823`) deletes it, plus a 7-day `-mtime` sweep. A woken-then-reidled
  session therefore cannot re-arm the ladder; only a new decision state (new key) does.
- **Text (`nudge_text`, one line, cc-notify collapses newlines):** "⏯ IDLE WITH UNGATED SCOPE (lead-supervisor,
  machine text addressed to THIS session; not an operator answer). Your last close went idle while in-scope work
  your open decision(s) <ids> do not gate remains. An open decision holds only the act it names: drive the rest now
  (a loop scope: run the next round as scoped; the frozen scope is the course until it is answered). If every
  remaining item truly waits on it, record that with `~/.claude/hooks/dod-persist.sh set "Scope (held): <id> —
  <what it gates>"`, then stop." Kind `loop`: "…your loop scope is open with nothing in flight: run the next round,
  or record its stop with `dod-persist.sh set "Scope (done): <evidence>"`."
- **Also fix `advise_subject`'s parse** (`:557`) the same way (`maps/wake-path.md` §5.2: the 20:15:41Z row recorded
  cc-wake's `refused-busy` while cc-notify's verdict was `delivered`).
- **No** `--no-wake`, no `CC_NOTIFY_WAKE=0`, no `CC_WAKE=off`; no route through `page()`/`send_page`.
- Usage-limited sessions: cc-wake already refuses them (`maps/legit-stops.md` §6 C6, packet `bd6d3c14c1e8`); the line
  is still enqueued (marker written) and is read on the session's next turn, so a limited session spends no turn.

### 3.10 `bin/cc-decide` — comment, plus two stderr-only hints (exit code and stdout unchanged)

- `:103`: "A class-C packet is the ⛔ rung: it ends a session's turn holding work and hands the operator a question."
  → "A class-C packet is the ⛔ rung: it hands the operator a question and holds only the act it names; the session
  keeps driving every in-scope item it does not gate (CLAUDE.rules.slim.10-session-close.md § Disposition)."
- **Route hint (goal b), class C only, after the packet write** (the `echo "$id"` stays the only stdout line, as
  `gate_sweep.py:161-163` and `lr-reset-poller.sh:1179-1196` require): `cc-decide: class C is the ⛔ rung and holds
  only the act it names — keep driving every in-scope item it does not gate. A judgment call with a status-quo course
  (not a self-modification, money path, permission denial or credential) is class B: --class B --default "<course>"
  --default-effect no-change --project <repo> --deadline <ISO>; then cc-decide action <this id> --evidence
  "superseded by class-B <new id>".` Unconditional (no classifier: `scripts/gate-classify.sh` routes the money packet
  `a247b7288149` to B, `maps/cc-decide.md` §5). Opt-out `CC_DECIDE_HINTS=0`.
- **Ruling hint (goal c), optional phase P4:** `maps/ruling-discovery.md` §6.1 as designed there (BM25 over answered
  packets through a `cc-memory-search --decisions` corpus mode, top 3, "LIKELY ALREADY RULED" at top-1/top-2 ≥ 1.5,
  any `config/standing-grants.json` grant whose `match_terms` hit, bounded 3 s, fail-open, skipped when
  `CC_DECIDE_HINTS=0`). Measured there: it ranks `eb3dbe1e5e94` first for e869's text (ratio 2.88) and
  `a247b7288149` first for 290215743799's (1.62).

### 3.11 Rule text (R and G; S unchanged) — the always-loaded tier shrinks

The user tier is 61,074 of 60,000 with `enforce: true` (`maps/rules-text.md` §6); additions are paid by cuts of
mechanism detail that G already carries. Each block below is the exact old text and its replacement; §3.11.4 gives
the measured deltas.

#### 3.11.1 R edits

```old R:4
 Before writing or debugging a Stop hook, read the reference `~/Development/claude-infrastructure/CLAUDE.global.md` § Session Close Protocol for which hook output fields reach the model and which extend the turn.
```
```new R:4
```

```old R:15
 Where a background verifier owns the full-suite claim (claude-infrastructure v2), *your
  diff green + content-verified land* is the standard — waiting on a trunk-wide stamp you do not
  control is not diligence, it is a hang. The "no operator step left unrun" clause is no longer
  prose discipline: file each one (below) and `wrap-ledger.sh` computes `👤` instead of `✅` for you.
```
```new R:15
```

```old R:26
Freeze the DoD at intake: the first time a task will write tracked files, restate the ask as one line, `Scope (frozen): …`, in the plan or else inline (`dod-persist.sh` captures it). Close-time completeness is a diff against that line, not a fresh judgment. If the scope cannot be reconstructed, stop and ask.
```
```new R:26
Freeze the DoD at intake: the first time a task will write tracked files, record the ask as one line: `~/.claude/hooks/dod-persist.sh set "Scope (frozen): …"`. A loop scope (`loop until …`) is open work until `set "Scope (done): <evidence>"`. Close-time completeness is a diff against that line, not a fresh judgment. If the scope cannot be reconstructed, stop and ask.
```

```old R:38
| Needs a decision (destructive migration, auth, navigation pattern, DB timeout) or information | Stop and ask, overriding auto-continue; commit in-progress work first. |
```
```new R:38
| Needs a decision (destructive migration, auth, navigation pattern, DB timeout) or information | File it, commit in-progress work, then drive every in-scope item it does not gate (the frozen scope is the course until it is answered), never the gated act. |
```

```old R:68
 otherwise hand it to the operator with the number, the research receipt and the measured options in operator terms.
```
```new R:68
 otherwise first look for a ruling (answered packets, `cc-decide list --all --json`; standing grants; the operator's words) and act on it, else hand it to the operator with the number, the research receipt and the measured options in operator terms.
```

```old R:103
Only ⛔, and 📦 in a repo whose own `CLAUDE.md` says landing spends money, may end a turn holding work.
```
```new R:103
Only a held ⛔ (`dod-persist.sh set "Scope (held): <id> — <what it gates>"`: every remaining in-scope item waits on it), and 📦 in a repo whose own `CLAUDE.md` says landing spends money, may end a turn holding work.
```

```old R:160
File a decision you are holding the moment you have it; filing is what makes it the `⛔` rung: `cc-decide open --class C --what <plain English, no codenames> --conviction N --receipt R --option "label::outcome" --option "label::outcome"`. A class-B packet also carries `--conviction N --receipt R`; both follow the F2 number rule (Follow-On Gate). `wrap-ledger.sh` computes `⛔` from this session's open class-C packets; an unfiled decision is invisible to it, and `✅ SAFE TO CLOSE` would render over the open question.
```
```new R:160
File a decision you are holding the moment you have it. A judgment call with a status-quo course is class B: `cc-decide open --class B --what <plain English, no codenames> --default "<that course>" --default-effect no-change --project <repo> --deadline <ISO> --conviction N --receipt R --option "label::outcome" --option "label::outcome"`. Class C (no default) is only for self-modification, money, a permission denial, a credential or a pick with no status quo; it is the `⛔` rung. Both follow the F2 number rule (Follow-On Gate). An unfiled decision is invisible to `wrap-ledger.sh`, and `✅ SAFE TO CLOSE` would render over the open question.
```

```old R:189
- BLOCKED: a genuine operator-only gate (credential, sudo, destructive migration, a real value fork). It is S1's `⛔` rung, stated as the decision you need.
```
```new R:189
- BLOCKED: a genuine operator-only gate (credential, sudo, destructive migration, money, self-modification, a pick with no status quo). It is S1's `⛔` rung, stated as the decision you need; it holds only what it gates.
```

```old R:215
### Auto-continue actuation (🔧 only)
```
```new R:215
### Auto-continue actuation (🔧, unheld ⛔)
```

```old R:217
On 🔧, and only on 🔧, arm the continuation: `~/.claude/hooks/session-continue.sh set "<the one next step>"`; a Stop hook then feeds that step back as your next turn. Clear it with `~/.claude/hooks/session-continue.sh clear` as soon as the state becomes ✅ / 📦 / ⛔ / 📤, on a read-only turn, or when the kill-switch fires. Nothing bounds an agent-armed chain (each `set` resets the counter; `CLAUDE_CONTINUE_MAX`, default 8, bounds only the mechanical arm as `CC_MECH_MAX × CLAUDE_CONTINUE_MAX`, and `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` catches only a text-only wedge), so the stop conditions are the kill-switch, the frozen DoD, and your judgment; the hook does not judge scope. Within a turn, keep working rather than stopping on 🔧.
```
```new R:217
On 🔧, and on a ⛔ that is not held, arm the continuation: `~/.claude/hooks/session-continue.sh set "<the one next step>"`; a Stop hook then feeds that step back as your next turn. Clear it with `~/.claude/hooks/session-continue.sh clear` as soon as the state becomes ✅ / 📦 / held ⛔ / 📤, on a read-only turn, or when the kill-switch fires. Nothing bounds an agent-armed chain (each `set` resets the counter), so the stop conditions are the kill-switch, the frozen DoD, and your judgment; the hook does not judge scope. Within a turn, keep working rather than stopping on 🔧.
```

```old R:225
read them before changing or disputing one of these rules.
```
```new R:225
read them before changing or disputing one of these rules or writing a Stop hook.
```

```old R:19
 (per `hooks/lib/session-writes.sh`)
```
```new R:19
```

```old R:20
, once per HEAD sha and at most `CC_SHIP_FLOOR_MAX`=2 per session.
```
```new R:20
.
```

```old R:21
 Collect, land, then `cc-custody return <marker|slug>`; if superseded, `cc-custody abandon <token> --why …`.
```
```new R:21
```

```old R:24
Resident teammates: `~/.claude/scripts/wrap-ledger.sh` reports `RESIDENT_MINE`, the members of this session's team whose process is still running, as a 🔧, including their dirty files in a shared cwd; those files are yours to commit, since only the lead can. A teammate ends only when its lead ends it: send each a `shutdown_request` and escalate to `TaskStop` after about 60 s; the rung clears when the process is gone, not when the pane closes. The check kills nothing; to keep a member working, say so in the close as a stated park. Kill switch `WRAP_RESIDENT=off`.
```
```new R:24
Resident teammates: `~/.claude/scripts/wrap-ledger.sh` reports this session's still-running team members as a 🔧 (`RESIDENT_MINE`), and its readout says how to end them; their dirty files in a shared cwd are yours to commit. To keep a member working, say so in the close as a stated park. Kill switch `WRAP_RESIDENT=off`.
```

What the cuts drop from every session, and where it still lives (one-in-one-out, `config/instruction-budget.json`
`destinations.user`): the Stop-hook reference pointer (R:4) folds into R:225's pointer to the same file; the
background-verifier sentence (R:15-17) is kept in full at `G:853`, and R:106 still says "a marker only a background
verifier advances" is not yours; the 👤 sentence (R:17-18) duplicates R:97 and R:193; the session-writes lib path
(R:19) and the ship-floor bound (R:20, kept at `G:547`) are mechanism detail the hooks' own messages print; the
custody verbs (R:21) and the resident-teammate procedure (R:24, kept at `G:581`) are printed verbatim by the
ledger's own READOUT whenever they apply (`scripts/wrap-ledger.sh:2638-2642`, `:2659-2661`); the R:217
parenthetical is kept in full at `G:1129-1137`. If the operator prefers to keep these lines, the alternative is a
separate ruling raising `tiers.user` by 1,207 units (the sum of the cuts, measured in §3.11.4).

#### 3.11.2 R edit for goal (d): the grant lives beside F2, where the ask is decided

Placed in R, not S, so that every always-loaded edit lands in ONE file that shrinks: one whole-file write of R takes
the user tier from 61,074 to 61,005 (§3.11.4), which passes the budget verdict "DENY iff new > budget AND new > cur"
(`hooks/lib/instruction_budget.py:28-30`) under either reading of whether repo sources are tier-checked
(`maps/rules-text.md` §6 says only the 40k per-file cap applies to sources; `maps/ruling-discovery.md` §5.1 reads it
as a tier check). R already records the one other standing ruling with its packet id (R:74), and it deploys to every
session on all five accounts (`maps/rules-text.md` §1).

```old R:82
### Asserting done
```
```new R:82
### Standing operator grants

An act a grant covers needs no ask and no packet (record: `~/Development/claude-infrastructure/config/standing-grants.json`).
- Cross-vendor review (operator, 2026-10-24): in any repo, add non-Claude reviewers beside the Claude review via `codex exec -s read-only` on a `git archive` export of committed code in a fresh tmp dir; no new call at 80% of the weekly meter; never api.openai.com, personal messages, customer data or a repo-listed escalation surface. Routes no `model-config.yaml` slot.

### Asserting done
```

Wording rationale: additive and slot-free, so it does not collide with "uncertified means unrouted"
(`docs/plans/CODEX_ADVERSARIAL_SLOT_PROBE.md:25-31`, `:227-228`; `maps/ruling-discovery.md` §5.4); committed code
only, so the personal-data asks (`f2e2c22bb83e`, `e3876aac762d`, `bb16a9bc1350`) stay asks (`maps/legit-stops.md`
§6 C9). The 80% stop is today enforced only in the untracked `~/.cache/agentsync-bring-back/b13/tools/xverify.py`
(`maps/ruling-discovery.md` §5.3 item 4); the grant names the rule, and moving the meter guard into tracked courier
code (`scripts/research-kit/lib/courier.py`) is a prerequisite tracked separately, not built here.

#### 3.11.3 G twins (not loaded, not budgeted; required because under `global full` only G deploys, `install.sh:1117`)

| G anchor | Change (same canonical phrases as R, so one pin test greps both) |
|---|---|
| `G:592-595` | "restate … as one line — **`Scope (frozen): …`**" → record it with `dod-persist.sh set`; add the loop sentence with `Scope (done):` |
| `G:605` | STOP-ASK cell → "File it, commit in-progress work, then **drive every in-scope item it does not gate** (the frozen scope is the course until it is answered), never the gated act." |
| `G:657` (F2) | insert "first look for a ruling (answered packets, `cc-decide list --all --json`; standing grants; the operator's words) and act on it, else" before the hand-over clause; G may add the reasoning (B13: `eb3dbe1e5e94` had already fired "keep looping until dry", and a purchase made for the purpose counts) |
| `G:766-767` | "**Only a held ⛔** (`dod-persist.sh set "Scope (held): <id> — <what it gates>"`: every remaining in-scope item waits on it), and 📦 in a repo whose OWN `CLAUDE.md` says landing spends money, may end a turn holding work." |
| `G:1000-1002` | Corollary: "a decision you are holding IS the rung **only when it is class C**"; the class-B command with `--default`, `--default-effect no-change`, `--project`, `--deadline`; class C only for self-modification, money, permission, credential, a pick with no status quo |
| `G:1042` | BLOCKED row: same narrowing as R:189; drop "the ordinary mid-work ⛔"; add "it holds only what it gates" |
| `G:1124-1128` | "On the 🔧 state, **and on a ⛔ that is not held**, arm …; clear … ✅ / 📦 / **held ⛔** / 📤 … those MUST stop." |
| new section after the research-program exemption (G's Follow-On Gate) | "Standing operator grants" with R:82's text plus the verbatim 18:11:47Z quote (`TX:4488`) and the envelope list of `config/standing-grants.json` |

#### 3.11.4 Measured deltas

Measured: `python3 -I -B` reading THIS file's ```` ```old R:n ```` / ```` ```new R:n ```` blocks, checking each old
block occurs exactly once in `CLAUDE.rules.slim.10-session-close.md`, applying them in memory, and measuring with
`hooks/lib/instruction_budget.py` `parse()`/`jslen()` (`:94-96`, `:163-196`), the same predicate the land gate uses.
Nothing was written.

| Edit | old found | old units | new units | delta |
|---|---|---|---|---|
| R:4 cut (Stop-hook pointer, folded into R:225) | 1 | 212 | 0 | -212 |
| R:15 cut (background-verifier + 👤 sentences; kept at G:853, R:97, R:106, R:193) | 1 | 382 | 0 | -382 |
| R:19 cut (lib path) | 1 | 36 | 0 | -36 |
| R:20 cut (ship-floor bound; kept at G:547) | 1 | 66 | 1 | -65 |
| R:21 cut (custody verbs; the ledger's custody READOUT carries them, `scripts/wrap-ledger.sh:2638-2642`) | 1 | 108 | 0 | -108 |
| R:24 compaction (resident teammates; the ledger READOUT carries the procedure, `:2659-2661`; full text G:581) | 1 | 568 | 321 | -247 |
| R:26 intake + loop end marker | 1 | 309 | 369 | +60 |
| R:38 scope the stop | 1 | 170 | 257 | +87 |
| R:68 ruling search | 1 | 116 | 249 | +133 |
| R:82 standing grants section (goal d) | 1 | 18 | 546 | +528 |
| R:103 held ⛔ | 1 | 102 | 214 | +112 |
| R:160 class B route | 1 | 517 | 644 | +127 |
| R:189 BLOCKED narrowed | 1 | 155 | 218 | +63 |
| R:215 heading | 1 | 37 | 42 | +5 |
| R:217 arm on unheld ⛔ (parenthetical kept at G:1129-1137) | 1 | 732 | 575 | -157 |
| R:225 pointer | 1 | 58 | 81 | +23 |
| **R total** | | **30,287** | **30,218** | **-69** |

User tier (R + S 28,503 unchanged + mission board 2,284): **61,074 → 61,005** (measured). Per-file R stays under
40,000. One whole-file write of R satisfies "DENY iff new > budget AND new > cur" (new < cur).

### 3.12 New files

- `hooks/lib/loop-scope.sh` (§3.2), `hooks/lib/live-waves.sh` (`bh_live_waves` moved verbatim from
  `hooks/boundary-handoff.sh:875-903`, which then sources it; lib absent ⇒ 0 waves).
- `config/standing-grants.json`:

```json
{
  "_what": "Standing operator grants. An act a grant covers needs no ask and no decision packet. Always-loaded text: CLAUDE.rules.slim.10-session-close.md § Standing operator grants; full text: CLAUDE.global.md.",
  "grants": [{
    "id": "cross-vendor-review-2026-10-24",
    "issued_at": "2026-10-24T18:11:47Z",
    "grantor": "operator",
    "verbatim_quote": "I thought you had autonomous zero human in the loop proactiveness and permissions to do this with accounts; didn't we do this for our truememory review hence getting the $100 codex plan just for these adversarial reviews from agents that are not our own claude model class?",
    "quote_source": "~/.claude-quaternary/projects/-Users-chrisren-Development-agent-context-sync/666022fd-ed3e-4e72-b293-7caae899d585.jsonl:4488",
    "ratified_by": "d610f8473106",
    "builds_on": ["a247b7288149", "290215743799"],
    "capability": "add non-Claude reviewers or judges beside the Claude review through the ChatGPT Codex subscription CLI",
    "scope": {"repos": "*"},
    "conditions": ["codex exec -s read-only", "input: a git archive export of committed code in a fresh tmp dir", "no new call at >= 80% of the weekly meter (newest ~/.codex/sessions rollout, rate_limits.primary.used_percent)"],
    "excludes": ["api.openai.com (pay-per-token)", "personal messages, mail, dictations, customer or guest data", "a repo-listed escalation surface", "routing any model-config.yaml slot"],
    "match_terms": ["codex", "openai", "chatgpt", "gpt", "cross-vendor", "non-claude"],
    "expiry": null,
    "revoked_by": null
  }]
}
```

- `tests/lead-keeps-working-rules.bats`, `tests/scope-floor.bats`, `tests/scope-intake.bats` (§7).

---

## 4. Infinite-loop and false-block analysis, per change

| Change | Can it loop? Bound | False-block risk | Mitigation / control |
|---|---|---|---|
| Ledger fields (§3.1) | No actuator. +1 awk fork per close with a DoD and a SID; +2 forks only on ⛔ with ungated work | READOUT clause on a session whose scope is not really a loop | Anchored pattern: 1/362 store lines, 6/6 true first-prompt loops, 0 false (§1.3). Own-session blocks only. `WRAP_SCOPE_FLOOR=off` restores today's bytes |
| Loop 🔧 arm (§3.1 vii) | No actuator by itself | A loop session that is truly finished reads 🔧 until it writes `Scope (done):` | One `set` discharges it; the readout names the command |
| Intake capture (§3.3 i) | Once per (session, cwd): marker written before any work, so a failure never repeats | Captures a first-prompt line that quotes another loop | Loop-only, first record only, never when this session already has a block; an explicit later `set` is newer and wins `DOD_SCOPE`/own-newest |
| Mechanical arm on ⛔ (§3.3 ii) | Existing bound `CC_MECH_MAX` (2) × `CLAUDE_CONTINUE_MAX` (8) per session, self-clearing on commit (`:1112-1154`) | Dirt that is the gated act's draft | Committing to a branch is not landing; the ⛔ text forbids shipping what the decision gates; `clear` remains the escape (`:1156`) |
| **Scope floor** (§3.3 iii) | Latch: one fire per (key, HEAD); a re-close with no commit is `scope-floor-latched`. Cap: `CC_SCOPE_FLOOR_MAX`=2 per key = (sid, open class-C ids, kind, own scope head). Re-arm needs a landed commit AND a count below cap; a new key needs a real state change (a packet filed/answered, a new scope). Worst case **2 forced turns per decision state**. State file write fails ⇒ no block (fail closed). Harness block counter is not relied on (`maps/stop-hooks.md` §1) | (1) awaiting lanes/land/teammates/waves; (2) genuine all-gating gate; (3) operator said wait; (4) research program; (5) assignee/teardown; (6) old ledger | (1) `scope-floor-inflight` from CUSTODY_OPEN/LANDING/RESIDENT_MINE/waves, a watcher alone does not count; (2) `Scope (held):` ⇒ SCOPE_UNGATED=0, and a scope with nothing ungated (C2 sessions 43055acd, e582464c, c56c729c, 79076bcf, fd91140d) never fires; (3) `SCOPE_HOLD_RE` on the operator's last message, plus KILL_RE; (4) `RESEARCH_PROGRAM≠none`; (5) copied from ship floor; (6) absent field ⇒ 0 ⇒ silent |
| completion-assert (§3.4) | Log string only | None | Exoneration byte-identical when the field is absent (pins `tests/completion-assert.bats:1265-1278` stay green) |
| anti-deference (§3.5) | Fewer packets and fewer blocks only | None added | `packet_skipped` logged; yield narrow to two arms |
| boundary-handoff ⛔ free-win (§3.6, optional) | Existing latch per HEAD, re-armed by +10% fill / +10 MB / 30 min idle (`:796-832`) | A forced turn on a correctly held idle at ≥35% | That is S:166's intent; excluded for loop scopes and whenever ungated work exists; yields to the scope-floor marker |
| Supervisor nudge (§3.9) | Out-of-session, blocks no Stop. ≤3 per decision state per session (2 h, then 4 h), ≤3 per sweep, cc-wake W5 ≤1 wake/120 s/sid (`bin/cc-wake:266-272`). Marker survives recovery; fails closed. Key = the floor's key, so a woken ⛔ re-close (same state) never re-arms it | Waking a session that is correctly idle | Fires only on the session's own floor row with ungated>0 ∧ ¬held ∧ reason ∈ {fired, latched, budget, shadow}; never on inflight, nothing-ungated, kill-switch, operator-hold, research rows; exemptions for permission beacon (`:1067`) and operator-adopted hold (`:1077`) apply first |
| Rule text (§3.11) | n/a | A lead declares `Scope (held)` dishonestly | Residual (§9); the claim is durable, session-stamped and shown in the operator's DoD injection |

Combined worst case for one stubborn session in one decision state: 2 floor blocks + 3 supervisor wakes = **5
model turns**, then silence until the state changes or the operator writes.

---

## 5. Replay against the B13 incident

### 5.1 Inputs (from `maps/incident-replay.md` §5, measured there)

BLOCKED=2 (`e869fac7eb34`, `290215743799`), DIRTY=0, UNLANDED=0, CUSTODY_OPEN=0 by 05:01:53Z, LANDING=1 until the
06:44:17Z task notification, context 64%, no `/goal`, a watcher only (F1, F2) or nothing (F3).

### 5.2 Counterfactual with this design live since before 2026-10-22

| Time (Z) | Event | Design's outcome |
|---|---|---|
| 10-22 07:41 | Recycle brief `TX:14` | First Stop: intake capture writes `Scope (frozen): loop until dry. …` with `session=666022fd…`, label `intake-first-prompt` (measured extraction §1.4). From here: LOOP_OPEN=1, LOOP_SRC=own (estimated from §3.1 logic). |
| 10-24 02:36 | Filing | New R:160 makes both class B with "keep running rounds" / "keep the review all-Claude" as defaults; with the grant in R, 290215743799 is never filed; R:68 points at answered packets (eb3dbe1e5e94 already fired "keep looping until dry", `maps/cc-decide.md` §0.1). **If filed class C anyway:** the class-C stderr hint names the B route at 02:36. |
| 02:36-05:02 | ⛔ closes with round-26 lanes landing (C1) | ⛔ ∧ SCOPE_UNGATED=1 ⇒ ledger computes custody: open ⇒ `scope-floor-inflight` (allow). 05:02: LANDING=1 ⇒ inflight (allow). READOUT already reads "…Not gated by it: your loop scope (…) — keep driving it…". |
| **06:44:40 F1** | "❌ Good to close: no — the loop is waiting on your answers…" | Ledger: RUNG=⛔, SCOPE_UNGATED=1, HELD=0, CUSTODY_OPEN=0, LANDING=0, waves 0. Mechanical arm: DIRTY=0, no arm. Ship floor: rung ⛔, returns. **Scope floor fires** (1/2), writes the marker; completion-assert (`no-close-tell`) and anti-deference (`no-tell`) are silent as before; boundary-handoff 64%<73% and free-win declines ⛔-ungated. The block names the loop, both decisions with gloss, the class-B re-file command and the held/done discharges. |
| after F1 | Expected (estimated from `TX:4495`, where the same lead, told the same thing at 18:12Z, answered "Until you answer, I'll keep running the loop as scoped, starting round 27") | Round 27 dispatches ⇒ custody open ⇒ later closes inflight; round lands ⇒ HEAD moves. F2 and F3 do not occur. Idle avoided: **~11 h 27 m** (`maps/incident-replay.md` §1, F1 Stop to the 18:11 reply). |
| stubborn variant | Lead re-closes ⛔ with no state change at F1+, F2 (07:39:47), F3 (08:34:59) | Same key, same HEAD ⇒ `scope-floor-latched` rows (ungated=1, held=false). |
| ~09:05-09:11 | First STALL? (STALL_S 1800 after the 08:35 Stop; measured STALL? rows resume at 09:11Z, `maps/wake-path.md` §2.1) | `nudge_subject`: last floor row `scope-floor-latched`, ungated 1 ⇒ `cc-notify 666022fd… --from lead-supervisor …`; no live watcher ⇒ socket wake (W1-W5 pass while idle, `maps/wake-path.md` §4.1) ⇒ a turn carrying the instruction. Attempts 2 and 3 at ≥2 h and ≥4 h later (≈11:1x, ≈15:1x), all before the 15:38Z GC. In the stubborn variant the gap after F3 shrinks from 9 h 36 m to about 36 min before the first wake (estimated: first STALL? row after F3 at 09:11Z, measured in `maps/wake-path.md` §2.1, minus the 08:35:08Z last Stop). |

### 5.3 Controls (must not change)

| Control | Expected under this design | Why |
|---|---|---|
| C1 ⛔ with lanes in flight (03:09-05:02Z) | allow | `scope-floor-inflight` (custody, then LANDING) |
| C2 legit class C (d610, self-mod) gating a subset while round 27 runs (18:31:59Z, `TX:4769`) | allow | inflight; and with nothing in flight the floor would correctly push round 27 |
| C3 permission denial on Codex only (18:17:32Z, `TX:4683`) | allow (inflight); if idle, push "drive round 27 Claude-only" | the decision holds only the Codex act |
| C4 all-gating money/self-mod gate, scope exhausted | allow, unchanged | SCOPE_UNGATED=0 (no loop, no own boxes) ⇒ `scope-floor-nothing-ungated`; ⛔ readout byte-identical to today |
| C5 class-B re-file (b4780d7bb60e) | 🔧 loop, not ✅ | loop arm in the ✅-eligible branch; floor kind `loop`; free-win needs ✅ so no recycle advice |
| The 23 sessions holding the 48 open class-C packets today | unchanged | none has an own loop capture and the store has 0 unchecked boxes (measured: `jq` over decisions for open C → 48 packets / 23 sids; awk over the DoD store → the only loop capture is 666022fd's, whose class-C packets are all actioned) ⇒ SCOPE_UNGATED=0 for all (estimated ledger output from that store state) |

---

## 6. What this design deliberately does NOT do

1. **No packet schema field** (`--gates`, `--ceiling`): it would not have fixed B13 unless required, and a required
   flag rc-2s producers on the STOP-ASK escape path (`bin/cc-decide:81-86`). If another slot adds one, it composes:
   a packet declaring `gates=all` can be read as an implicit `Scope (held)` for that id (one more jq term in §3.1 iv).
2. **No rung reorder and no new glyph**: ⛔ still outranks 🔧/📦/🚀 (`tests/wrap-ledger.bats:1934-1961` stay as they
   are), so a C6/C10 land gate never arms the ship floor (`hooks/session-continue.sh:1216`), and renderers'
   `case` arms (`hooks/operator-readout.sh:1543-1546`) see no unknown member.
3. **No new blocker in completion-assert** and no change to its `no-close-tell` gate or `blocked-answered` spare.
4. **No anti-deference phrase additions**, not even "nothing more runs until": F2/F3 carry no hold phrase and
   "need your call" is the mandated readout (`maps/incident-replay.md` §6.3; pins `tests/anti-deference-nudge.bats:706-717`).
5. **No idle-keepalive wake**: its EXIT trap forces exit 0 (`hooks/idle-keepalive.sh:37`), it is content-free, its
   switch-on is an open operator decision (USAGE_LEVERS W3), and it was absent from B13's Stop chain (`TX:4440`).
6. **No `page()`/`send_page` route** for the nudge, and no repair of the dead desk channel (`:414-415`); that is a
   separate strengthening fix (`maps/wake-path.md` §6.1).
7. **LOOP_OPEN never folds into REMAINDER or SCOPE**: handoff-fire's self-close refusal (`scripts/handoff-fire.sh:8664-8689`),
   anti-deference's contradiction (`:521`) and completion-assert's done contradiction keep reading REMAINDER only.
   completion-assert does not convict a done-claim on LOOP_OPEN (a mid-loop "round 27 done" would false-block, and
   its custody arm already spent B13's assert budget).
8. **No plan-file reads and no newest-transcript-line reads.**
9. **No capture of non-loop first-prompt scopes** (crosstalk on DOD_SCOPE/DRAIN_SCOPE/certificate, §1.4).
10. **No refusal in `cc-decide open`** on similarity or grant matches (precision ≈0.8 related, `maps/ruling-discovery.md` §4.3).
11. **No class-B-fired → filing-session wake**: it needs a two-ended change (`bin/cc-decide` expire-sweep TSV and
    `scripts/autonomy-sweep.sh:562`); recorded as a follow-on, not built.
12. **No change to KILL_RE**; the operator-hold phrases bind only the new floor.
13. **No mechanical enforcement of "never build the gated act"**: G2 (R:45), repo escalation greps and the `/ship`
    landing-range refusal (R:62) keep owning it; the floor's text forbids it.
14. **No fix for the detached-watcher hole** (`cc-await-ping … &`, `maps/wake-path.md` §4.3); it can delay a nudge's
    wake by up to one back-off step. Separate `validate-bash.sh` follow-on.

---

## 7. Tests

Every new suite sets a fixture `HOME` in `setup()` (hermeticity rule 1, `maps/test-infra.md` §5), unsets
`CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID WRAP_SESSION_ID`, uses relative dates or `2099-` sentinels, and writes
`! cmd || false` for negative assertions. "Red without" means: run against `origin/main`'s subject and the test
fails; plus one mutant per new guard (`maps/test-infra.md` §6).

### 7.1 `tests/wrap-ledger.bats` (real `bin/cc-decide`, `use_real_decide`, `open_blocking`, `WRAP_DOD_FILE`)

| # | Name | Fixture | Assertion | Red without the change because |
|---|---|---|---|---|
| L1 | B13 F1: loop scope + open class C ⇒ ⛔ with SCOPE_UNGATED=1 | `ok_state`; DoD block `## … (intake-first-prompt) · toplevel=… · session=$SID` + `Scope (frozen): loop until dry. Each round = …`; `open_blocking "$SID" "Should the B13 loop stop now…"` | RUNG=⛔, BLOCKED=1, LOOP_OPEN=1, LOOP_SRC=own, HELD=0, SCOPE_UNGATED=1, BLOCKED_IDS=<id>; one-line readout contains `need your call: Should the B13 loop stop now` AND `Not gated by it: your loop scope` | fields absent; readout lacks the clause |
| L2 | held declaration zeroes SCOPE_UNGATED and restores today's readout bytes | L1 + own `Scope (held): <id> — every round needs it` after the frozen line | HELD=1, HELD_SRC=own, SCOPE_UNGATED=0; READOUT exactly `⛔ Blocked — need your call: <what>.` | HELD absent |
| L3 | stale held (answered packet) is not a hold | L2, then `cc-decide action <id>`; open a second packet | HELD=0, HELD_SRC=stale, SCOPE_UNGATED=1 | — |
| L4 | another session's loop scope is not ours (alarm polarity) | loop block with `session=<other>`; class C from `$SID` | LOOP_OPEN=0, SCOPE_UNGATED=0, READOUT has no clause | (positive control L1 proves it can fire) |
| L5 | `Scope (done):` ends the loop | L1 + own `Scope (done): round 33 confirmed nothing new` | LOOP_OPEN=0, LOOP_SRC=done | done line would be a new frozen contract today |
| L6 | C5: class-B re-file + open loop + clean landed ⇒ 🔧, not ✅ | `ok_state`; own loop block; class-B packet only | RUNG=🔧, READOUT names the loop and `Scope (done):`; `! grep -q '^RUNG=✅'` | today RUNG=✅ |
| L7 | research-brief false positive | own frozen line "PHASE 1 — research … loop scope ("loop until …") …" | LOOP_SCOPE=0 | — (guards the anchored pattern; mutant: unanchored RE1 reds it) |
| L8 | research program cwd | L1 + `CC_RESEARCH_REGISTRY` listing the cwd as `registered` | LOOP_OPEN=0, LOOP_SRC=program, same RUNG in default and `--machine` modes | mode divergence without §3.1 iii |
| L9 | kill switch and no-SID fail open | L1 with `WRAP_SCOPE_FLOOR=off`; L1 with no SID | LOOP_SRC=off / none, SCOPE_UNGATED=0, READOUT identical to today | — |
| L10 | custody computed under ⛔ only when ungated | L1 + an open `cc-custody` row for the cwd (`CC_CUSTODY_DIR`) | CUSTODY_OPEN=1, CUSTODY_SRC≠skip; and with L2's held line CUSTODY_SRC=skip | today always skip under ⛔ |
| L11 | existing precedence pins unchanged | `tests/wrap-ledger.bats:1934-1961` as they are | still ⛔ over dirty and unlanded | regression control |
| L12 | memo key carries the switch and v2 | two runs with the same transcript, `WRAP_SCOPE_FLOOR` on then off | different answers (no stale memo) | stale serve |
| L13 | `rung_next` under ungated ⛔ | L1, `--full` | Next line starts `continue → drive the in-scope work`; with L2 it is the STOP-ASK text | — |

### 7.2 `tests/scope-floor.bats` (new; ledger stub via `WRAP_LEDGER_BIN` printing env-driven lines, as `tests/ship-floor.bats:34-37`)

Common stub (F1, from `maps/incident-replay.md` §7): `RUNG=⛔ BLOCKED=2 BLOCKED_IDS=e869fac7eb34,290215743799
SCOPE_UNGATED=1 LOOP_OPEN=1 HELD=0 CUSTODY_OPEN=0 LANDING=0 RESIDENT_MINE=0 RESEARCH_PROGRAM=none DIRTY=0
LOOP_HEAD=loop until dry. Each round = … BLOCKED_GLOSS=e869fac7eb34 ("Should the B13 loop stop now…"); 290215743799 ("May agentsync's…")`.
Transcript: `mkfix` of `TX:4437` lines 1-4 verbatim. `CC_SHIP_FLOOR=0` is NOT set (the ship floor must itself
decline ⛔); `CC_WAKE_FLOOR=0`, `CC_MECH_CONTINUE=0` unless stated.

| # | Name | Assertion | Red without |
|---|---|---|---|
| S1 | F1 ⇒ BLOCKS once, names loop, both ids, class-B command, held/done discharges | `"decision":"block"`; reason contains `loop until dry`, `e869fac7eb34`, `--class B`, `Scope (held):`, `Scope (done):`; IDL row `reason:"scope-floor"`, `ungated:1`, `key` non-empty; `${sentinel}.blocked` ends `scope-floor` | no floor exists |
| S2 | F2 latch: same HEAD re-close ⇒ allow, logged | second actuate: no block; IDL `scope-floor-latched` | (mutant: drop HEAD latch ⇒ red) |
| S3 | progress re-arms once, then budget | commit in the fixture repo ⇒ block 2/2; commit again ⇒ allow + `scope-floor-budget` | mutant: no cap ⇒ red |
| S4 | new decision state resets | change `BLOCKED_IDS` ⇒ blocks again 1/2 | — |
| S5 | per-session budget is not shared | sid A spends 2/2; sid B same cwd ⇒ fires | shared-file mutant reds |
| S6 | in flight ⇒ allow: CUSTODY_OPEN=1; LANDING=1; RESIDENT_MINE=1; a workflow journal with started>result and a warm agent file under `${tp%.jsonl}/subagents/workflows/` | no block; `scope-floor-inflight` | — |
| S7 | an armed watcher alone is NOT in flight | live `<sid>.watching` marker in `CC_MAILBOX_DIR`, nothing else | still blocks | mutant counting the watcher reds |
| S8 | held / nothing ungated ⇒ allow | `HELD=1 SCOPE_UNGATED=0` | no block; `scope-floor-nothing-ungated` | — |
| S9 | old ledger (no new fields) ⇒ silent | stub without SCOPE_UNGATED | no block; no scope-floor row with `fired` | fail-open control |
| S10 | kill switch and operator hold | last user message "…and stop"; then "wait for my answer before round 27" | no block; `scope-floor-kill-switch` / `scope-floor-operator-hold` | — |
| S11 | assignee rc 0 and rc 2; teardown marker | `ma_ai_stub 0`/`2`; `wf_teardown` fixture | no block; matching abstain rows | — |
| S12 | research program | `RESEARCH_PROGRAM=tm2` | `scope-floor-research-program` | — |
| S13 | loop 🔧 kind (C5) | `RUNG=🔧 BLOCKED=0 LOOP_OPEN=1 DIRTY=0` | blocks with the 🔧 text; mechanical arm did not arm | no floor |
| S14 | shadow mode | `CC_SCOPE_FLOOR=shadow` | no block; `scope-floor-shadow`; live state file untouched | — |
| S15 | unwritable state ⇒ no block | state dir read-only | no block; `scope-floor-unwritable` | mutant writing `|| true` reds (unbounded) |
| S16 | non-⛔/🔧 rungs are silent | `RUNG=✅`, `📦` | no scope-floor row at all | B-3 silent class |
| S17 | completion-assert yields on the same Stop | run session-continue then completion-assert (`CA_BLOCKED_LEDGER` + `SCOPE_UNGATED=1`, a close with a CLOSE token) | completion-assert exoneration contains `double-block-yield:session-continue-scope-floor` | marker not written |

### 7.3 `tests/scope-intake.bats` (new; real `hooks/dod-persist.sh`, `WRAP_DOD_DIR` fixture)

| # | Name | Fixture | Assertion | Red without |
|---|---|---|---|---|
| I1 | first-record loop scope captured with this session's id | transcript: 13 non-user records then `TX:14`'s shape (user, origin human, text with `Scope (frozen): loop until dry…` on line 5) | store has a block `(intake-first-prompt) · … · session=<sid>` with that line; IDL `scope-intake-captured` | no capture exists (the B13 gap) |
| I2 | newest-line trap | I1 + a later tool_result quoting `Scope (frozen): build items B91 …` | captured line is the loop line | — (mutant: last instead of first reds) |
| I3 | non-loop first scope not captured | first record `Scope (frozen): build W11 W13 …` | store unchanged; `scope-intake-not-loop` | — |
| I4 | once per session | actuate twice | one block; second Stop writes nothing | — |
| I5 | explicit set wins | store already has a `session=<sid>` block | no new block; `scope-intake-already` | — |
| I6 | switch off | `CC_SCOPE_INTAKE=0` | nothing | — |
| I7 | dod-persist accepts held/done | `dod-persist.sh set "Scope (held): e869fac7eb34 — …"`; `set "Scope (done): …"` | lines written verbatim, not prefixed `Scope (frozen):`; `dod-persist.sh get` still prints the frozen line | today rewritten to `Scope (frozen): Scope (held): …` |

### 7.4 Other suites

| Suite | Test | Assertion | Red without |
|---|---|---|---|
| `tests/session-continue.bats` (`ma_fixture` with `RUNG=⛔`) | mechanical arm arms on ⛔ own dirt, ⛔ wording | block; step text contains `do not /ship what the open decision gates`; IDL `mechanical-dirty` with `rung:"⛔"` | `:1103` returns |
| same | `continue_reason` no longer says clear on ⛔ | reason contains `held on the user` | text |
| `tests/completion-assert.bats` | ⛔ honest no with `SCOPE_UNGATED=1` | IDL reason `ledger-clean:exonerated:blocked-answered:ungated=1` | string unchanged |
| same | existing `:1265-1278`, `:2579-2580` | unchanged | regression |
| `tests/anti-deference-nudge.bats` | genuine branch under ⛔ files no packet | `WRAP_LEDGER_BIN` stub RUNG=⛔; message "your call: whether to stop the loop"; `CC_DECISIONS_DIR` stays empty; IDL `packet_skipped` | `open_packet_B` fires today (f56cf0f827d7 shape) |
| same | control: RUNG=✅ still files the class-B packet | packet exists (pin `:321-324` unchanged) | regression |
| same | narrow yield | marker `… scope-floor` + a TELLS deference message ⇒ abstain `double-block-yield…`; opaque-id message still fires | no yield |
| `tests/operator-readout*.bats` | 🔧 with LOOP_OPEN=1 | state contains `loop scope open` | renderer drops the cause |
| `tests/boundary-handoff.bats` (P5 only) | ⛔ ∧ SCOPE_UNGATED=0 ∧ LOOP_SCOPE=0 at 40% (`CC_BOUNDARY_T_FREEWIN=35`, stub) | free-win fires, text names the ids; with SCOPE_UNGATED=1 ⇒ `freewin=⛔-ungated:1`; with the marker ⇒ `freewin-yield` | `[ "$r" = "✅" ]` only |
| `scripts/supervisor-e2e.sh` (new T-checks) + `tests/lead-supervisor.bats` floor raised | (1) subject nudged directly when its last floor row has ungated>0 ∧ ¬held; (2) no second send inside the back-off; (3) 2 h / 4 h ladder via marker epochs, cap 3; (4) `enqueued=0` stub ⇒ no marker, retried next sweep; (5) `CC_SUP_SUBJECT_NUDGE=0` sends nothing, `=shadow` logs only; (6) non-uuid sid never addressed; (7) new key resets; plus: no floor row / `scope-floor-inflight` / `held:true` ⇒ no send; `clear_page_recovered` keeps `.nudged`; ≤3 per sweep; verdict parsed from `^cc-notify: verdict=` when the stub prints a cc-wake `verdict=refused-busy` line first. Run under `/bin/bash` 3.2 | all red today (no function) |
| `tests/lead-keeps-working-rules.bats` (new; fixture `HOME` in `setup()`; names `CLAUDE.rules.slim.10-session-close.md` and `CLAUDE.global.md` literally so `scripts/gate-select.sh` selects it, pattern `tests/close-research-pending-rules.bats:11-43`) | grep each canonical phrase in BOTH R and G: `drive every in-scope item it does not gate`, `Scope (held):`, `Scope (done):`, `held ⛔`, `status-quo course`, `--default-effect no-change`, `look for a ruling`, `Standing operator grants`, `git archive`, `model-config.yaml` slot; `jq -e '.grants[]|select(.id=="cross-vendor-review-2026-10-24")' config/standing-grants.json`; `! grep -q 'Stop and ask, overriding auto-continue' CLAUDE.rules.slim.10-session-close.md \|\| false`; and a budget guard: `python3 -I hooks/lib/instruction_budget.py measure CLAUDE.rules.slim.10-session-close.md` ≤ 30,287 | phrases absent |

Run the selected suites yourself and check the `1..N` plan line; `bats` is the cc-bats shim and exit 75 is no
verdict (`maps/test-infra.md` §1.1); run `scripts/ship-land.sh --precheck --working` for the lints.

---

## 8. Phasing and verification

| Phase | Contents | Alone, does it stop B13? |
|---|---|---|
| P1 | §3.1, §3.2, §3.3, §3.7, §3.11, §3.12 (loop-scope lib, rules pin) | Yes (F1 block) |
| P2 | §3.4, §3.5, §3.8, §3.10 comment + route hint | adds the class-B teaching at filing time |
| P3 | §3.9 supervisor nudge, 24-48 h in `shadow`, then live | covers the stubborn variant and any other idle |
| P4 | §3.10 ruling hint, `config/standing-grants.json` consumers, tracked meter guard | (c)/(d) at the moment of asking |
| P5 | §3.6 boundary-handoff ⛔ free-win | not needed for (a)-(f) |

All of it is self-modification of the shared layer; ruling `d610f8473106` is the authority. It goes live only after
`scripts/deploy-live.sh` runs install.sh (`scripts/deploy-live.sh:52`). After converge: `diff -q
CLAUDE.rules.slim.10-session-close.md ~/.claude/rules/10-session-close.md` and the slim global are silent; a
`--machine` run in agent-context-sync with `WRAP_SESSION_ID=666022fd-…` prints the new fields; the IDL shows
`scope-intake-*` and `scope-floor-*` rows.

---

## 9. Residual risks and open questions

1. **Honest mis-declaration.** A lead convinced a decision gates everything can write `Scope (held):` and idle; the
   claim is durable, session-stamped, visible in the store file (`dod-persist.sh path`) and re-injected into the
   session's own SessionStart DoD context (`hooks/dod-persist.sh:475`). The floor's text says when a hold is legitimate. A packet-level `gates` field would not remove this either
   (`maps/cc-decide.md` §8).
2. **`Scope (done):` abuse.** Same shape; same visibility.
3. **IDL rotation hides the oracle.** If the last floor row rotated into a gz, the supervisor sends nothing (fail
   closed) until the next Stop writes a row.
4. **User-tier budget.** The cuts in §3.11.1 remove guidance from every session (kept in G); the alternative is a
   separate operator ruling to raise `tiers.user`. The re-gate deferral of 2026-10-04 (`docs/plans/INSTRUCTION_BUDGET.md:127`)
   names slim edits; flagged, not decided.
5. **Open question:** should a supervisor nudge re-arm the floor once (a fresh latch epoch)? This design says no:
   the nudge carries the instruction itself, and a re-arm would turn each woken re-close into a block.
