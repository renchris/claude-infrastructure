# D4: the minimal sufficient hybrid, so a lead keeps working while a decision is open

Designer slot D4 (minimal sufficient). Operator ruling d610f8473106. Worktree `lead-idle-fix` at `958b23030`, 2026-10-24.

This is read-only research: the only file written is this one. Line numbers refer to this worktree. Every number is labelled:
- **measured** means I ran the named command;
- **estimated** names the method used.

Abbreviations:
- `TX:n` is line n of the B13 transcript `~/.claude-quaternary/projects/-Users-chrisren-Development-agent-context-sync/666022fd-ed3e-4e72-b293-7caae899d585.jsonl`.
- `IDL` is `~/.claude/autonomy/idl.jsonl`.
- `R`, `S` and `G` are, in order, `CLAUDE.rules.slim.10-session-close.md`, `CLAUDE.global.slim.md` and `CLAUDE.global.md`.
- Maps are cited as `maps/<name>.md`.

---

## 0. The design in one screen

### 0.1 Four mechanical components are proof-critical

Each one breaks one step of the incident that no other component breaks.

| # | Component | Incident step it breaks | Files |
|---|---|---|---|
| **K1** | **Stop-time scope capture.** When the DoD store holds no `Scope (frozen):` line from this session, capture the newest one stated in a human-origin prompt. It never overrides a capture the session already has. | The loop contract was not in the store during the idle. Its only capture is `2026-10-24T20:15:35Z (manual-set)` (`~/.claude/autonomy/dod/repo-7030c1939664b2e4.md:26-27`), about 2 h after the operator's reply (maps/incident-replay.md §0.1). | `hooks/dod-persist.sh` (new mode `capture-human`), `hooks/session-continue.sh` (trigger) |
| **K2** | **Ledger facts.** `LOOP_OPEN` (this session's own newest frozen line is a loop), `LOOP_SRC`, `LOOP_HEAD`, `BLOCKED_IDS`. A loop scope turns a ✅-eligible close into 🔧 at the drain floor's rank. Under ⛔ the readout gets a loop clause, and `rung_next` stops saying "nothing below it closes". | A box-less loop reads `REMAINDER=0` / `SCOPE=met` (`scripts/wrap-ledger.sh:935-950`). The ledger itself told the lead "STOP-ASK … nothing below it closes" (`:3101`). | `scripts/wrap-ledger.sh` |
| **K3** | **Loop floor** in `session-continue.sh`. It blocks an idle ⛔/🔧 close when `LOOP_OPEN=1` and nothing is in flight (no custody, no land, no live workflow). The limits are ≤2 per open-decision set and ≤4 per set across scope edits. It does not fire again after an idle forced turn, and it writes `mark_blocked`. | Every Stop hook accepted F1, F2 and F3 (maps/incident-replay.md §6.1). | `hooks/session-continue.sh`, `hooks/lib/live-waves.sh` (moved verbatim from `hooks/boundary-handoff.sh:874-902`) |
| **K4** | **Supervisor subject nudge.** When the newest loop-floor IDL row for a stalled session says `ungated:1`, it sends `cc-notify <sid>` straight to the session. That is a socket wake carrying the instruction. The limit is ≤3 per decision state, with 2 h and 4 h back-off. | The 9 h 36 m gap after F3 (maps/incident-replay.md §1). lead-supervisor reached nobody (maps/wake-path.md §2.2). | `scripts/lead-supervisor.sh`, `scripts/supervisor-e2e.sh`, `tests/lead-supervisor.bats` |

### 0.2 Text and goal-completeness components

These are not needed for the mechanical proof. Each is still tied to a step of the incident.

| # | Component | Step | Files |
|---|---|---|---|
| **R1** | Rule text: R:26, R:38, R:68, R:103, R:160, R:189, R:217 and their G twins. Matching tool and hook prose. The always-loaded total shrinks by **18 UTF-16 units** (measured, §2.5). | The five sentences that licensed the idle (maps/rules-text.md §2a). | R, S, G, `.claude/CLAUDE.md`, `bin/cc-decide`, `hooks/session-continue.sh`, `hooks/dispatch-assert.sh`, `commands/wrap.md`, `hooks/lib/why-tier.sh` |
| **C1** | `cc-decide open` prints a ruling hint on stderr: the top similar answered packets, plus a reminder of the reserved set for class C. It never refuses, and stdout stays exactly the id. | Decision 1 asked again what `eb3dbe1e5e94` had already settled. | `bin/cc-decide`, `bin/cc-memory-search` (`--decisions`), `hooks/anti-deference-nudge.sh` (opt-out flag) |
| **D1** | One standing-grant line in S, with the full record in G. | Decision 2 read `a247b7288149` as covering TrueMemory only (TX:4235). | S, G |
| **D2** | `scripts/codex-meter.sh`: the 80% weekly-meter stop as tracked code. | The guard lives only in the untracked `~/.cache/agentsync-bring-back/b13/tools/xverify.py:21-40`. | `scripts/codex-meter.sh` |

### 0.3 Two choices that make the proof possible under the "never weaken" constraint

1. **The floor never reads packet class, a `gates` field, or close prose.** It keys on the session's own captured contract. B13 filed both packets as class C with no declaration (TX:4254, TX:4260). Any design that waits for a `--gates partial` declaration is therefore inert for B13 as filed (maps/cc-decide.md §7: "only a required flag … would have changed its rung").
   - Because nothing reads `gates`, the 48 open class-C packets keep exactly today's ⛔, so "absent = all" holds trivially.
   - **Measured:** none of those 48 sits in a session that has a loop-scope capture (§1, F6). On day one the floor fires on no session that holds a legacy class-C packet.
2. **⛔ stays first in the ladder** (`scripts/wrap-ledger.sh:2603-2610`). The pins `tests/wrap-ledger.bats:1934`, `:1950` are untouched, ⛔ still outranks 📦 (so the ship floor never demands a gated land), and no new glyph is added. The loop becomes a 🔧 only where ✅ would otherwise be computed.

### 0.4 What is new and what is reused

The only new concept is K3's predicate: "this session's own frozen scope is an open loop, and nothing is in flight." Everything else reuses existing machinery:

| Reused machinery | Where |
|---|---|
| dod-persist's capture/dedupe/persist path | `hooks/dod-persist.sh:140-199` |
| The DRAIN_SCOPE detection site | `scripts/wrap-ledger.sh:913-945` |
| The CLOSE_FLOOR rank | `:2670` |
| The ship floor's shape, abstains, IDL rows and latch file | `hooks/session-continue.sh:1186-1290` |
| `mark_blocked` / completion-assert's yield | `:371`, `hooks/completion-assert.sh:1276-1298` |
| `turn_scan` | `hooks/lib/turn-scan.sh` |
| wake_floor's custody read | `hooks/session-continue.sh:815-844` |
| boundary-handoff's wave counter | `hooks/boundary-handoff.sh:875-902` |
| `advise_subject`'s direct `cc-notify` | `scripts/lead-supervisor.sh:546-564` |
| `cc-memory-search`'s BM25 engine | `bin/cc-memory-search:488` |

---

## 1. Facts this design rests on

The maps supply the base. These measurements are new, or they correct a map.

| # | Fact | How measured |
|---|---|---|
| F1 | Of the 24 transcript records carrying `Scope (frozen):`, the only **user / string-content / `origin.kind=="human"`** record before the idle is TX:14, the recycle brief with the loop scope. The rest are `tool_result` lane briefs (TX:889…3875), assistant `tool_use` (TX:2260…), one `instructions` attachment (TX:27), and after the idle a task-notification (TX:4728, `origin.kind="task-notification"`) and an `isMeta` record (TX:4910). | `grep -n 'Scope (frozen):' TX` then `jq -c '{type,isMeta,origin,ctype:(.message.content\|type)}'` per line |
| F2 | The human-origin extractor, run over the transcript as it stood at F3 (`head -n 4476`), returns exactly `Scope (frozen): loop until dry. Each round = …`, in **0.025 s** wall. | `head -n 4476 TX \| grep -a 'Scope (frozen):' \| jq -r 'select(.type=="user" and (.isMeta != true) and ((.origin.kind // "human")=="human")) \| …' \| grep -aoE 'Scope \(frozen\):.*' \| tail -1`, under `time` |
| F3 | **Correction to maps/incident-replay.md §0.2.** dod-persist's existing PreCompact extractor (`hooks/dod-persist.sh:142-149`), run over the same prefix, also returns only the loop scope. It keeps only `text` items, so `tool_result` lane briefs never reach it. The incident's gap was *when* capture runs (PreCompact or `set` only, `:6-17`), not *what* it extracts. | the same `jq` as `extract_scope`, over `head -n 4476 TX` |
| F4 | `grep -c 'Scope (frozen):'` over the 9.0 MB transcript takes **0.012 s** and returns 24. | `time grep -c`; `ls -la` gives 9,004,044 bytes |
| F5 | Of 362 `Scope (frozen):` lines in the whole DoD store, **1** matches `(loop\|looping\|repeat\|iterate) until` (case-insensitive). It is B13's, in a block headed `session=666022fd…`. | `cat ~/.claude/autonomy/dod/*.md \| grep 'Scope (frozen):' \| grep -ciE …`, plus `awk` over the headers |
| F6 | The store holds 48 open class-C and 10 open class-B packets. Session 666022fd has only class-B packets open (`b4780d7bb60e`, `f56cf0f827d7`). So **0** open class-C packets belong to a session with a loop-scope capture. | `jq -r 'select((.status // "open")=="open") \| [.class,.session_sid,.id]'` over `decisions/*.json` |
| F7 | Custody for B13's cwd: rows opened 23:41-23:45Z, all returned by 05:01:53Z, next open at 20:20:18Z. So custody was 0 at F1-F3 **and** at controls C2/C3 (18:17Z, 18:31Z). | `tail -15 ~/.claude/autonomy/custody/cb2bdf30d6a495298cb26b459fd886e4.jsonl \| jq` |
| F8 | Round 27 ran as Workflow `wf_e887b970-e18`: journal born 13:16 local (18:16Z), last written 14:08 local (19:08Z). The 02:25Z cross-vendor run is `wf_0f21eebe-140` (02:25-02:35Z). No run was live at F1-F3, and round 27 was live at C2/C3. **So the "work in flight" exemption must count live workflow waves, or control C2 false-blocks.** | `stat -f '%SB %Sm'` on `<TX-dir>/subagents/workflows/*/journal.jsonl` (CDT = UTC-5) |
| F9 | The repo-tier `.claude/CLAUDE.md` measures **7,032** loader chars. | `python3 -I hooks/lib/instruction_budget.py measure .claude/CLAUDE.md` |
| F10 | The IDL rotated 8 times between 2026-10-03 and 2026-10-24, about every 2.6 days. | `ls ~/.claude/autonomy/ \| grep idl.jsonl` |
| F11 | The rule edits in §2.5 change S+R by **−18 UTF-16 units** in total. | `python3 -I` over the drafts, units = `len(s.encode('utf-16-le'))//2` |

---

## 2. Components

### 2.1 K1: Stop-time scope capture

**Mechanism.** `session-continue.sh` already reads the ledger at every unarmed Stop (`hooks/session-continue.sh:1099`, `:1203`). When the ledger reports `LOOP_SRC=none`, the store holds no `Scope (frozen):` line from this session. In that case the hook runs `dod-persist.sh capture-human <transcript>` once per new Scope-bearing record. dod-persist then:
- extracts the newest frozen line from human-origin prompts (F1, F2);
- writes it with `· session=<sid>` provenance, but only if the session still has no capture of its own.

The next Stop's ledger sees the capture, so the delay is one Stop. For B13 that is the first unarmed Stop after TX:14 on 2026-10-22. That is two days before the decisions were filed.

**`hooks/dod-persist.sh`** gains a new CLI mode in the `case "${1:-}"` at `:485`, beside `set`, `path` and `get`:

```bash
  capture-human)
    # Stop-time capture (decision d610f8473106). The contract as stated in a HUMAN-origin prompt
    # (type user, not isMeta, origin.kind human or absent; tool_result items never reach it: F1-F3),
    # for a session with NO capture of its own. It NEVER overrides an own capture, because a newer
    # own frozen line is how a loop is ended (K2). Caller: hooks/session-continue.sh. Always exit 0.
    tp="${2:-}"; sid="${CLAUDE_CODE_SESSION_ID:-}"
    { [ -n "$sid" ] && [ -f "$tp" ] && command -v jq >/dev/null 2>&1; } || { echo none; exit 0; }
    scope="$(grep -a 'Scope (frozen):' "$tp" 2>/dev/null \
      | jq -r 'select(.type=="user" and (.isMeta != true) and ((.origin.kind // "human")=="human"))
               | .message.content
               | if type=="string" then . elif type=="array" then ([.[]?|select(.type=="text")|.text]|join("\n")) else empty end
               | select(. != "")' 2>/dev/null | grep -aoE 'Scope \(frozen\):.*' | tail -1)"
    [ -n "$scope" ] || { echo none; exit 0; }
    dod_prime "$PWD"; f="$(dod_path_for "$PWD" write)"
    if [ -f "$f" ] && [ -n "$(dod_filter_for "$PWD" "$f" | awk -v s="· session=$sid" \
         '/^## /{own=index($0,s)>0} own && /Scope \(frozen\):/{print; exit}')" ]; then
      echo own-exists; exit 0
    fi
    persist_dod "$f" "$scope" "$PWD" "stop-capture" "$sid"
    echo captured; exit 0 ;;
```

Also update the header (`:6-17`) to list the fourth mode.

**`hooks/session-continue.sh`** gains a new helper, placed beside `_sc_turn_lib` (`:1388`):

```bash
sc_capture_scope() { # K1 trigger; never blocks, never fails. One-shot per new Scope-bearing record.
  [ "${CC_SC_SCOPE_CAPTURE:-1}" = 1 ] || return 0
  local n mk dp out
  [ -n "${_sc_tp:-}" ] && [ -f "$_sc_tp" ] || return 0
  n="$(grep -c 'Scope (frozen):' "$_sc_tp" 2>/dev/null)"; case "$n" in ''|*[!0-9]*|0) return 0 ;; esac
  mk="${f}.scopecap"
  [ "$(cat "$mk" 2>/dev/null)" = "${cur_sid:-?} $n" ] && return 0
  printf '%s %s' "${cur_sid:-?}" "$n" > "$mk" 2>/dev/null || return 0
  dp="${DOD_PERSIST_BIN:-$_scd/dod-persist.sh}"; [ -f "$dp" ] || return 0
  out="$( cd "$cwd" 2>/dev/null && CLAUDE_CODE_SESSION_ID="${cur_sid:-}" bash "$dp" capture-human "$_sc_tp" 2>/dev/null )"
  [ "$out" = captured ] && log_idl captured "scope-capture" "$(jq -cn --argjson n "$n" '{scope_records:$n}' 2>/dev/null)"
  return 0
}
```

`loop_floor` calls it when `LOOP_SRC=none` (§2.3).

**Bounds.**
- At most one `dod-persist` fork per change in the Scope-line count, and only while `LOOP_SRC=none`.
- Once a capture exists, `LOOP_SRC=own` and the trigger is never reached again.
- The cost per Stop is one `grep -c`: 0.012 s on 9 MB (F4).

**Why not "newest Scope line in the transcript"?** For a lead, that line is a lane brief (TX:3875; maps/wrap-ledger.md §2.3). The human-origin filter picks TX:14 (F1).

### 2.2 K2: ledger facts in `scripts/wrap-ledger.sh`

The fields are computed before the ladder, so they are visible under ⛔. They cost zero forks, because they use the already-filtered `_wl_ff` stream and the existing cc-decide `jq`. They fail open. The new fields come after `LIVE=`, which preserves the BUSY splice (`:575-599`).

**(a) Own loop line.** Initialize at `:906` and fill inside the per-file loop at `:913-941`, right after `_wl_ff` is computed at `:923`:

```bash
+LOOP_OPEN=0; LOOP_SRC="none"; LOOP_HEAD=""; _wl_loop_line=""   # § LOOP (d610f8473106)
 …
+  # The first file that yields an own line wins. That is the repo-key store, where captures are
+  # written (dod_path_for … write). Session-scoped by the capture header (alarm polarity, :49-52).
+  if [ -n "$SID" ] && [ -z "$_wl_loop_line" ] && [ "${WRAP_LOOP_FLOOR:-on}" != off ]; then
+    case "$_wl_ff" in *"session=$SID"*)
+      _wl_own=""
+      while IFS= read -r _wl_ln; do
+        case "$_wl_ln" in
+          "## "*) case "$_wl_ln" in *"· session=$SID"*) _wl_own=1 ;; *) _wl_own="" ;; esac ;;
+          *"Scope (frozen):"*) [ -n "$_wl_own" ] && _wl_loop_line="$_wl_ln" ;;
+        esac
+      done <<< "$_wl_ff" ;;
+    esac
+  fi
```

After `:945` (the DRAIN_SCOPE line), in the same `case` style:

```bash
+if   [ -z "$SID" ]; then LOOP_SRC="nosid"
+elif [ "${WRAP_LOOP_FLOOR:-on}" = off ]; then LOOP_SRC="off"
+elif ! command -v dod_filter_for >/dev/null 2>&1; then LOOP_SRC="nolib"
+elif [ -n "$_wl_loop_line" ]; then
+  LOOP_SRC="own"; LOOP_HEAD="${_wl_loop_line#*Scope (frozen): }"; LOOP_HEAD="${LOOP_HEAD:0:160}"
+  case "$_wl_loop_line" in
+    *[Ll][Oo][Oo][Pp]" "[Uu][Nn][Tt][Ii][Ll]*|*[Ll][Oo][Oo][Pp][Ii][Nn][Gg]" "[Uu][Nn][Tt][Ii][Ll]*|\
+    *[Rr][Ee][Pp][Ee][Aa][Tt]" "[Uu][Nn][Tt][Ii][Ll]*|*[Ii][Tt][Ee][Rr][Aa][Tt][Ee]" "[Uu][Nn][Tt][Ii][Ll]*) LOOP_OPEN=1 ;;
+  esac
+fi
```

- **End marker.** A *newer* own `Scope (frozen):` line that does not match ends the loop, because the field reads the newest own line. That works today (maps/wrap-ledger.md §2.5(a)) and needs no dod-persist change.
- **Precision.** 1 of 362 store lines match (F5).
- **Kept out of REMAINDER.** `handoff-fire`'s self-close refusal (`scripts/handoff-fire.sh:8664-8689`) and anti-deference (`:521`) key on REMAINDER.

**(b) `BLOCKED_IDS`, in the existing fork.** The `jq` at `:1527-1546` gains one cell, placed before the free-text cell and padded so a TSV cell can never collapse (`:1514-1520`):

```diff
       | [ ($ask | length | tostring),
           ((($mine | length) - ($ask | length)) | tostring),
+          (if ($ask|length)==0 then "-" else ($ask | map((.id // "?")|tostring) | sort | join(",")) end),
           (if ($ask | length) == 1 …
```
```diff
-  IFS=$'\t' read -r n u what <<< "$line"            # :1550
+  IFS=$'\t' read -r n u ids what <<< "$line"
+  BLOCKED_IDS=""; [ "${ids:--}" = "-" ] || BLOCKED_IDS="$ids"
```

Initialize `BLOCKED_IDS=""` beside the other BLOCKED defaults.

**(c) Ladder.** ⛔ stays first. A loop is a 🔧 only on the ✅-eligible path.

```diff
 if [ "$BLOCKED" -gt 0 ]; then                       # :2604
   RUNG="⛔"  … READOUT as today …
+  [ "$LOOP_OPEN" = 1 ] && READOUT="${READOUT} · your loop scope is still open: rounds continue as scoped while it waits"
 …
   elif [ "$CLOSE_FLOOR" -eq 1 ]; then …             # :2670, unchanged
+  elif [ "$LOOP_OPEN" = 1 ]; then
+    # Same rank as the drain floor: a loop has no boxes, so REMAINDER=0 cannot say it is unfinished;
+    # only a newer own `Scope (frozen):` line ends it. Without this a class-B re-file reads ✅
+    # (maps/incident-replay.md C5) and boundary-handoff's free-win (:651-658) advises a recycle.
+    RUNG="🔧"; READOUT="🔧 Loose ends — your frozen scope is a loop no newer Scope line has ended (${LOOP_HEAD:0:80}…); run the next round as scoped, or freeze the next contract when a round meets its stop condition."
   elif [ -z "$TRUNK" ]; then …                       # :2674
```

`rung_next` (`:3096-3102`):

```diff
     "⛔") if [ "$BLOCKED" -eq 0 ] && [ "$BLOCKED_RECHECKED" -gt 0 ]; then …
+          elif [ "$LOOP_OPEN" = 1 ]; then
+            printf 'the decision(s) wait for the operator (cc-decide list --open --class C); your loop scope does not: run the next round as scoped'
           else printf 'STOP-ASK — … nothing below it closes …'; fi ;;
```

**(d) Emit and memo.**
- After `:2909` (`BLOCKED_SRC=`), emit `BLOCKED_IDS=`, `LOOP_OPEN=`, `LOOP_SRC=` and `LOOP_HEAD=`.
- Memo key (`:650`): append `|${WRAP_LOOP_FLOOR:-}`, which is the kill-switch seam (rule at `:634-636`). Bump `v1|` to `v2|` at `:637`, so a body in the old shape is never served to the new floor.
- Add the LOOP fields to the header contract (`:20-60`).

**Consumers.**
- Every existing consumer parses keys by name and reads an absent field as 0 (maps/wrap-ledger.md §3).
- The ⛔ READOUT keeps its prefix. The pins `tests/wrap-ledger.bats:1851` and `:1866-1867` use `grep -q` substrings, so they stay green.
- No test pins "nothing below it closes" (measured: `grep -rn` over `tests/` returns nothing).

### 2.3 K3: the loop floor in `hooks/session-continue.sh`

**Placement.** The fourth floor goes between `ship_floor` and `wake_floor`, at `:1316-1328`. It runs in `$(…)` like its siblings, and it marks the double-block marker:

```diff
   if ! mechanical_arm; then
     if ! _sf_json="$(ship_floor)"; then … fi
+    if ! _lf_json="$(loop_floor)"; then
+      mark_blocked loop-floor
+      printf '%s' "$_lf_json"
+      exit 0
+    fi
     if ! _wf_json="$(wake_floor)"; then …
```

**Function.** It goes after `ship_floor` (`:1290`). The ledger read is factored out of `ship_floor` (`:1203-1213`) into `sc_read_ledger` with no change in behaviour. Both floors call it, and `SC_LED_CACHE` from `mechanical_arm` (`:1101`) still serves the common path with zero added ledger forks.

```bash
# ── LOOP FLOOR (decision d610f8473106) — an idle ⛔/🔧 close over THIS session's own open loop scope ──
# Predicate (all from the ledger or a store, never prose): LOOP_OPEN=1 ∧ RUNG∈{⛔,🔧} ∧ ¬kill-switch ∧
# ¬assignee ∧ ¬teardown ∧ ¬research-program ∧ ¬LANDING ∧ custody open = 0 ∧ live waves = 0.
# The packet CLASS is never read, so the 48 legacy class-C packets keep today's force (F6).
# Budget per decision state, never per lifetime (budgets were spent days earlier: maps/stop-hooks.md §0.1).
# Seams: CC_LOOP_FLOOR (0 off) · CC_LOOP_FLOOR_MAX (2) · CC_LOOP_FLOOR_SET_MAX (4) · WRAP_LEDGER_BIN ·
#        CC_CUSTODY_BIN · LIVE_WAVES_LIB · DOD_PERSIST_BIN · TURN_SCAN_LIB
_lf_log() { # $1=disposition $2=reason $3=ungated(0|1) [$4=extra json object]
  log_idl "$1" "$2" "$(jq -cn --argjson u "$3" --arg r "${_lf_rung:-}" --arg i "${_lf_ids:-}" \
     --arg k "${_lf_key:-}" --arg s "${_lf_src:-}" --argjson x "${4:-{\}}" \
     '{ungated:$u,rung:$r,blocked_ids:$i,key:$k,loop_src:$s} + $x' 2>/dev/null)"
}
loop_floor() { # → JSON on stdout to BLOCK (rc 1); rc 0 otherwise. Never fails.
  [ "${CC_LOOP_FLOOR:-1}" = 1 ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local led lo lhead n max smax kf line pk pc ps psc cb waves reason
  led="${SC_LED_CACHE:-}"; [ -n "$led" ] || led="$(sc_read_ledger)"; [ -n "$led" ] || return 0
  _lf_rung="$(led_field "$led" RUNG)"; lo="$(led_field "$led" LOOP_OPEN)"; _lf_src="$(led_field "$led" LOOP_SRC)"
  _lf_ids="$(led_field "$led" BLOCKED_IDS)"; lhead="$(led_field "$led" LOOP_HEAD)"; _lf_key=""
  [ "$_lf_src" = none ] && sc_capture_scope                        # K1
  if [ "$lo" != 1 ]; then                                          # absent field ⇒ today's behaviour
    [ "$_lf_rung" = "⛔" ] && _lf_log abstained loop-floor-no-loop 0   # a ⛔ stand-down is never silent (B-3)
    return 0
  fi
  kill_switch_active && { _lf_log abstained loop-floor-kill-switch 0; return 0; }
  local _a _c
  if _a="$(agent_assignee_argv)" && [ -n "$_a" ]; then
    agent_team_member_confirms "$_a"; _c=$?
    { [ "$_c" -eq 0 ] || [ "$_c" -eq 2 ]; } && { _lf_log abstained loop-floor-assignee 0 \
        "$(jq -cn --arg a "$_a" --argjson c "$_c" '{assignee:$a,confirm_rc:$c}')"; return 0; }
  fi
  wf_teardown_marked && { _lf_log abstained loop-floor-teardown 0; return 0; }
  case "$_lf_rung" in "⛔"|"🔧") : ;; *) _lf_log abstained loop-floor-rung 0; return 0 ;; esac   # 📦/🚀: ship floor's job
  case "$(led_field "$led" RESEARCH_PROGRAM)" in ""|none) : ;; *) _lf_log abstained loop-floor-research 0; return 0 ;; esac
  [ "$(led_field "$led" LANDING)" = 1 ] && { _lf_log abstained loop-floor-inflight 0 '{"what":"land"}'; return 0; }
  for cb in ${CC_CUSTODY_BIN:+"$CC_CUSTODY_BIN"} "$_scd/../bin/cc-custody" \
            "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/cc-custody" "$HOME/.claude/bin/cc-custody"; do
    [ -x "$cb" ] && break; cb=""; done
  [ -n "$cb" ] || { _lf_log abstained loop-floor-custody-unknown 0; return 0; }   # never block on ignorance
  n="$("$cb" count --open --cwd "$cwd" 2>/dev/null)" || n=x
  case "$n" in ''|*[!0-9]*) _lf_log abstained loop-floor-custody-unknown 0; return 0 ;; esac
  [ "$n" -gt 0 ] && { _lf_log abstained loop-floor-inflight 0 "{\"what\":\"custody\",\"n\":$n}"; return 0; }
  waves="$(sc_live_waves "${_sc_tp:-}")"; case "$waves" in ''|*[!0-9]*) waves=0 ;; esac
  [ "$waves" -gt 0 ] && { _lf_log abstained loop-floor-inflight 0 "{\"what\":\"workflow\",\"n\":$waves}"; return 0; }
  # ── ungated in-scope work remains. Latch + caps per DECISION STATE ──
  _lf_key="$(printf '%s|%s|%s' "${cur_sid:-?}" "${_lf_ids:--}" "$lhead" | cksum | cut -d' ' -f1)"
  ps="$(printf '%s|%s' "${cur_sid:-?}" "${_lf_ids:--}" | cksum | cut -d' ' -f1)"
  kf="${f}.loop"; max="${CC_LOOP_FLOOR_MAX:-2}"; smax="${CC_LOOP_FLOOR_SET_MAX:-4}"
  case "$max" in ''|*[!0-9]*) max=2 ;; esac; case "$smax" in ''|*[!0-9]*) smax=4 ;; esac
  line="$(cat "$kf" 2>/dev/null)"; pk="$(printf '%s' "$line" | cut -d' ' -f1)"; pc="$(printf '%s' "$line" | cut -d' ' -f2)"
  psc="$(printf '%s' "$line" | cut -d' ' -f4)"
  [ "$(printf '%s' "$line" | cut -d' ' -f3)" = "$ps" ] || psc=0      # new decision set ⇒ fresh set budget
  [ "$pk" = "$_lf_key" ] || pc=0                                     # new scope or set ⇒ fresh key budget
  case "$pc" in ''|*[!0-9]*) pc=0 ;; esac; case "$psc" in ''|*[!0-9]*) psc=0 ;; esac
  if [ "$pc" -ge "$max" ] || [ "$psc" -ge "$smax" ]; then
    _lf_log abstained loop-floor-budget 1 "{\"count\":$pc,\"max\":$max,\"set_count\":$psc,\"set_max\":$smax}"; return 0
  fi
  if [ "$pc" -ge 1 ] && _lf_idle_after_own_block; then          # no repeat block after an idle forced turn
    _lf_log abstained loop-floor-no-progress 1; return 0
  fi
  printf '%s %s %s %s\n' "$_lf_key" "$(( pc + 1 ))" "$ps" "$(( psc + 1 ))" > "$kf.tmp" 2>/dev/null \
    && mv "$kf.tmp" "$kf" 2>/dev/null || return 0                # latch unwritable ⇒ NO block (fail closed)
  reason="$(lf_reason "$(( pc + 1 ))" "$max" "$lhead")"
  _lf_log fired loop-floor 1 "{\"count\":$(( pc + 1 )),\"max\":$max}"
  jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
  return 1
}
_lf_idle_after_own_block() { # rc 0 ⇔ the turn now ending was opened by THIS floor's block and wrote nothing
  local scan; _sc_turn_lib || return 1
  scan="$(turn_scan "${_sc_tp:-}" 1)" || return 1
  [ "$(printf '%s' "$scan" | jq -r '.w' 2>/dev/null)" = false ] || return 1
  case "$(printf '%s' "$scan" | jq -r '.b' 2>/dev/null)" in *"⟳ LOOP FLOOR"*) return 0 ;; esac
  return 1
}
```

**`lf_reason` (fixed template; it names a discharge that is a state change, never a sentence):**

```
⟳ LOOP FLOOR — you are going idle on <rung> while your own frozen scope is a loop that no newer Scope line has ended:
  "<LOOP_HEAD>…"
Nothing is in flight (no open custody, no land, no live workflow), so nothing will wake you.
Open decision(s) <ids> stay with the operator; each gates only the act it names. The frozen scope is the course until a
decision changes it (operator ruling d610f8473106). Next: run the next round as scoped.
If every remaining round truly needs an operator-only act (money, self-modification, a permission, a credential), record
that in one line, then close:
  ~/.claude/hooks/dod-persist.sh set "Scope (frozen): hold until <decision id> is answered — <the act each round needs>"
A judgment call with a status-quo course is not a hold: re-file it as class B (--default "<the frozen-scope course>"
--deadline <ISO> --default-effect no-change --project <repo>). (loop floor <n>/<max>)
```

The "Open decision(s)" sentence appears only when `BLOCKED_IDS` is non-empty. The suggested hold line contains no `loop|repeat|iterate until` words, so writing it ends `LOOP_OPEN` (K2).

**`sc_live_waves`.**
- `bh_live_waves` (`hooks/boundary-handoff.sh:874-902`) moves verbatim into `hooks/lib/live-waves.sh` as `live_waves_for_transcript <tp>`.
- boundary-handoff keeps a one-line `bh_live_waves() { live_waves_for_transcript "$tp"; }`, so its behaviour and IDL reasons are byte-identical.
- session-continue sources the lib through the same `$0`-symlink resolution as `_sc_turn_lib` (`:1388-1398`).
- The seam default is a path beside the hook. It is neither `/tmp` nor a bare PATH name, so lint rule 5 is unaffected (maps/test-infra.md §5).

**Text edits in the same file.**
- `:13`: `# arm — on 🔧, or on ⛔ while in-scope work the open decision does not gate remains`.
- `:14`: `# disarm — on ✅/📦/📤, on a ⛔ that gates all remaining work, read-only, or "...and stop"`.
- `continue_reason` (`:1368`): "blocked on the user (⛔)" becomes "blocked on the user for ALL remaining work (⛔)". This is the one builder, so the comparison in `reblock_is_idle_repeat` (`:1400-1424`) stays consistent.

### 2.4 K4: subject nudge in `scripts/lead-supervisor.sh`

**Config**, beside `SUBJECT_ADVISE` (`:143`):

```bash
SUBJECT_NUDGE="${CC_SUP_SUBJECT_NUDGE:-1}"     # 1 | shadow | 0 — wake the SUBJECT when its last floor row says ungated:1
NUDGE_MAX="${CC_SUP_NUDGE_MAX:-3}"; NUDGE_BASE_S="${CC_SUP_NUDGE_BASE_S:-7200}"; NUDGE_PER_SWEEP="${CC_SUP_NUDGE_PER_SWEEP:-3}"
```

**Function**, after `advise_subject` (`:564`). It is /bin/bash 3.2-safe: no `${,,}`, no `declare -A`.

```bash
nudge_subject(){ # $1=sid $2=transcript_age_s — fail CLOSED on every unknown
  local sid="$1" tage="$2" nf row ung key ids k0 c0 l0 now out rc v r text
  [ "$SUBJECT_NUDGE" = 0 ] && return 0
  [ -n "$NOTIFY_BIN" ] || return 0
  [[ "$sid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || return 0
  [ "${_SUP_NUDGES:-0}" -lt "$NUDGE_PER_SWEEP" ] || return 0
  nf="$PAGEDIR/$sid.nudged"; now="$(now)"
  read -r k0 c0 l0 < "$nf" 2>/dev/null; case "$c0" in ''|*[!0-9]*) c0=0 ;; esac; case "$l0" in ''|*[!0-9]*) l0=0 ;; esac
  # back-off BEFORE any IDL read: attempt c0+1 waits NUDGE_BASE_S·2^(c0-1) after the last one
  [ "$c0" -ge 1 ] && [ $(( now - l0 )) -lt $(( NUDGE_BASE_S * (1 << (c0 - 1)) )) ] && return 0
  # THE ORACLE — the newest loop-floor row this session's own Stop wrote (session-continue, §2.3).
  row="$(sup_bounded 5 grep -F "\"sid\":\"$sid\"" "$IDL" 2>/dev/null | grep -F '"reason":"loop-floor' | tail -1)"
  [ -n "$row" ] || row="$(sup_bounded 8 sh -c 'f=$(ls -t "$1".*.gz 2>/dev/null | head -1); [ -n "$f" ] && gzip -dc "$f"' _ "$IDL" \
                          | grep -F "\"sid\":\"$sid\"" | grep -F '"reason":"loop-floor' | tail -1)"     # rotation: F10
  ung="$(printf '%s' "$row" | jq -r '.ungated // 0' 2>/dev/null)"; key="$(printf '%s' "$row" | jq -r '.key // empty' 2>/dev/null)"
  ids="$(printf '%s' "$row" | jq -r '.blocked_ids // empty' 2>/dev/null)"
  { [ "$ung" = 1 ] && [ -n "$key" ]; } || return 0                        # legit stops (ungated:0) are never woken
  [ "$key" = "$k0" ] || c0=0                                              # a new decision state = new news
  if [ "$c0" -ge "$NUDGE_MAX" ]; then idl subject_nudge_capped "\"sid\":\"$sid\",\"key\":$(json_str "$key")"; return 0; fi
  : >> "$nf" 2>/dev/null || return 0                                      # marker unwritable ⇒ send nothing
  text="⏯ IDLE WITH UNGATED SCOPE (lead-supervisor machine text addressed to THIS session; not an operator answer) — idle ~$(( tage / 60 ))m; your last Stop found your own frozen loop scope open with nothing in flight${ids:+ (open decisions: $ids)}. An open decision gates only the act it names and the frozen scope is the course until it is answered (operator ruling d610f8473106): run the next round as scoped now. Only if every remaining round truly needs an operator-only act: ~/.claude/hooks/dod-persist.sh set \"Scope (frozen): hold until <id> is answered — <the act each round needs>\", then stop."
  if [ "$SUBJECT_NUDGE" = shadow ]; then
    printf '%s %s %s\n' "$key" "$(( c0 + 1 ))" "$now" > "$nf" 2>/dev/null || true
    idl subject_nudge_shadow "\"sid\":\"$sid\",\"key\":$(json_str "$key"),\"attempt\":$(( c0 + 1 ))"; return 0
  fi
  out="$(sup_bounded "$SUP_NOTIFY_TIMEOUT_S" "$NOTIFY_BIN" "$sid" "$text" 2>&1)"; rc=$?   # NO --no-wake
  v="$(printf '%s\n' "$out" | sed -n 's/^cc-notify: verdict=\([a-z-]*\).*/\1/p' | tail -1)"
  r="$(printf '%s\n' "$out" | sed -n 's/^cc-notify: .* reason=\([a-z-]*\).*/\1/p' | tail -1)"
  [ "$rc" = 0 ] && printf '%s %s %s\n' "$key" "$(( c0 + 1 ))" "$now" > "$nf" 2>/dev/null   # rc 0 = enqueued, even if not woken
  _SUP_NUDGES=$(( ${_SUP_NUDGES:-0} + 1 ))
  idl subject_nudge "\"sid\":\"$sid\",\"key\":$(json_str "$key"),\"attempt\":$(( c0 + 1 )),\"notify_rc\":$rc,\"verdict\":$(json_str "${v:-unreadable}"),\"reason\":$(json_str "${r:-}")"
  return 0
}
```

**Call site.** Insert `nudge_subject "$sid" "$tage"` between `page "$sid" "STALL?" …` (`:1089`) and `[ "$had_page" = 1 ] && resolve_page …` (`:1090`). Reset `_SUP_NUDGES=0` at the top of each sweep.
- That point is already past the permission-beacon (`:1067`) and operator-adopted (`:1077`) exemptions, and past the registered-desk exemption in the STALL? predicate (`:1046`).
- It is inside the [30 min, 6 h] window, before `gc_stale` (`:146`, `:903-918`).
- `cc-wake` W3 refuses a pending permission prompt and a usage-limited session (maps/wake-path.md §4.1; packet `bd6d3c14c1e8`).

**Invariants.**
- The nudge does not ride `page()`/`send_page`, because the desk channel is dead (`:414-415`; maps/wake-path.md §2.2).
- `.nudged` is listed in neither `clear_page` (`:524`) nor `clear_page_recovered` (`:583-609`), so recovery never re-arms it.
- The verdict parse reads cc-notify's own line (`bin/cc-notify:469`), not cc-wake's. The same bug in `advise_subject:557` is fixed in passing with the same two `sed` lines.
- The daemon picks this up through its sha self-restart (`:92-104`). No plist or settings change is needed.

### 2.5 R1: rule and prose text

The always-loaded total must not grow (maps/rules-text.md §6; constraint "one-in-one-out"). Measured deltas are in UTF-16 units over the drafts (F11).

| Where | Change | Δ |
|---|---|---|
| R:26 (append) | "A `loop until …` scope stays open until your newer `Scope (frozen):` line ends it." | +83 |
| R:38 | Action cell becomes: "File it, commit in-progress work, and keep driving what it does not gate: the frozen scope is the course until it is answered. Stop only when it gates all that remains." | +98 |
| R:68 | Replace the flag-mechanics sentence ("`cc-backlog add --why-not-now …` and `cc-decide open --class C` refuse without … `UNCONVICTED_MINE` …, not 👤 or ⛔.") with: "`cc-backlog` and `cc-decide` refuse an ask without the number and the receipt. Before handing a call over, look for a ruling: the answered packets `cc-decide open` prints, `cc-memory-search --all <terms>`, the standing grants; an answered or expired packet on the same question, or a purchase for the purpose, is a ruling: act on it." The tools print the flag details on refusal (`bin/cc-decide:236-245`). | +30 |
| R:103 | "Only ⛔ when all remaining in-scope work waits on an open decision, and 📦 in a repo whose own `CLAUDE.md` says landing spends money, may end a turn holding work." | +59 |
| R:160 | "File a decision you are holding the moment you have it. One with a status-quo course is class B (its default fires at the deadline): `cc-decide open --class B --what <plain English, no codenames> --default "<the frozen-scope course>" --deadline <ISO> --default-effect no-change --project <repo> --conviction N --receipt R`. Class C (`--option "label::outcome"` twice, no default) is only for self-modification, a money path, a permission denial, a credential, or a pick among new options with no status quo; `wrap-ledger.sh` computes `⛔` from your open class-C packets." | +52 |
| R:189 | "a real value fork" becomes "a pick with no status quo" | +8 |
| R:215 | Heading "### Auto-continue actuation (🔧 only)" becomes "### Auto-continue actuation" (the comment at `hooks/session-continue.sh:203` still resolves) | −10 |
| R:217 | "On 🔧, or on ⛔ while in-scope work the open decision does not gate remains, arm the continuation: … Clear it … when the state becomes ✅ / 📦 / 📤 or a ⛔ that gates all that remains, on a read-only turn, or on the kill-switch. Nothing bounds an agent-armed chain (each `set` resets the counter), so the stop conditions are the kill-switch, the frozen DoD, and your judgment. …" The parenthetical about `CLAUDE_CONTINUE_MAX` and the block cap moves to G, which already carries it at G:1128+. | −136 |
| R:17-18 | Delete "The "no operator step left unrun" clause is no longer prose discipline: … computes `👤` …". R:193 already says it. | −155 |
| R:4 | Move "Before writing or debugging a Stop hook, read the reference … which extend the turn." to the repo tier, `.claude/CLAUDE.md` (7,032 chars, F9). Only this repo writes Stop hooks. | −212 |
| R:225 | Delete it; S:3 already points every session at the full text for rationale. | −199 |
| S, § Working rules (after S:34) | New bullet: "- Standing operator grant (2026-10-24): in any repo, unasked, add non-Claude reviewers beside the Claude review via `codex exec -s read-only` on a `git archive` export of committed code; no new call at ≥80% of the weekly meter (`scripts/codex-meter.sh`); never api.openai.com, personal data or a repo-listed escalation surface; routes no `model-config.yaml` slot." | +364 |
| **Total** | | **−18** |

**G twins.** G has no budget. It is the only text under the `global full` variant (`install.sh:1117`).
- **G:592-595**: the loop sentence.
- **G:605**: the R:38 cell.
- **G:657**: append the ruling-search sentence. Keep the long mechanics text.
- **G:766-767**: R:103.
- **G:1000-1002**: R:160 in the long form, keeping the 2026-08-07 history line and adding "(widened to every held decision on 2026-08-07; narrowed back to `cc-decide`'s reserved set by ruling d610f8473106)".
- **G:1042**: "a real value fork" becomes "a pick with no status-quo course", and "the ordinary mid-work `⛔`" becomes "a mid-work `⛔` whose decision gates all remaining work".
- **G:1125-1128**: R:217. "those MUST stop" becomes "a ⛔ that gates all that remains MUST stop; ungated in-scope work keeps the continuation armed".
- **New `## Standing operator grants (All Projects)`** after G:374-377 (Frontier Tier Routing). It holds:
  - the grant;
  - the operator's words verbatim (TX:4488);
  - `builds_on: a247b7288149`;
  - the envelope: `codex exec -s read-only`, never widened (`docs/plans/CODEX_ADVERSARIAL_SLOT_PROBE.md:248-249`); a `git archive` export in a fresh tmp dir only; `scripts/codex-meter.sh` exit ≠ 0 ⇒ no new call; no api.openai.com;
  - "additive; routes no slot; 'uncertified means unrouted' (`CODEX_ADVERSARIAL_SLOT_PROBE.md:25-31`, `:227-228`) still governs slots";
  - exclusions: personal data, as asked in packets `f2e2c22bb83e`, `e3876aac762d` and `bb16a9bc1350`, and repo escalation surfaces;
  - "revoke or narrow by editing this section and the slim line".

**Prose that steers to class C or to disarming.**
- `bin/cc-decide:103-104`: "A class-C packet is the ⛔ rung: it hands the operator a question and holds the act it names; the session keeps driving the in-scope work the packet does not gate (ruling d610f8473106)."
- `hooks/dispatch-assert.sh:237`, `:269`: "`cc-decide open --class C --what "…"` if it is a decision" becomes "`cc-decide open --class B --what "…" --default "<status-quo course>" --deadline <ISO>` if it is a decision with a status-quo course (class C only for self-modification, money, a permission denial or a credential)".
- `commands/wrap.md:142-145`: add the class-B sentence, and "⛔ ends a turn only when it gates all remaining in-scope work".
- `hooks/lib/why-tier.sh:313`: same as `commands/wrap.md`.

**Pins checked.**
- `grep -rlF` over `tests/`, `hooks/`, `scripts/`, `bin/`, `commands/` and `skills/` finds no test pinning any edited phrase.
- "Auto-continue actuation" is referenced only in a comment (`hooks/session-continue.sh:203`), which still resolves.
- "a real value fork" also appears in `hooks/completion-assert.sh:1757`, inside a reason string. Change it there in the same diff, or leave it as a known stale phrase.

### 2.6 C1: ruling hint at `cc-decide open`

**`bin/cc-decide`.** Insert after the existing-packet early return (`:313-328`), so a re-open never searches, and before the options build (`:330`):

```bash
+  # § RULING HINT (decision d610f8473106, goal c). STDERR ONLY: stdout stays exactly the id
+  # (gate_sweep.py:161-163, lr-reset-poller.sh:1179-1196) and the exit code never changes. Fail-open,
+  # bounded. The MOST useful line is printed LAST, immediately before the id, because filers pipe
+  # `2>&1 | tail -3` (TX:4254) and `| tail -2` (TX:4260).
+  if [ "$class" != A ] && [ "${CC_DECIDE_RULING_HINT:-1}" = 1 ]; then _ruling_hint "$class" "$what" "$id" >&2 || true; fi
```

`_ruling_hint`:
1. Resolves `${CC_MEMORY_SEARCH_BIN:-$(dirname "$(self_path)")/cc-memory-search}`. If that is absent, it prints nothing.
2. Runs `--decisions --exclude "$id" --top 3 --json -- "$what"` under the same bounder `scripts/wrap-ledger.sh` uses (`_bounded`), with `CC_DECIDE_HINT_TIMEOUT_S` default 3 s.
3. For class C it prints: "class C is reserved for self-modification, a money path, a permission denial or a credential (this tool's header :13-19); a judgment call with a status-quo course is class B with that course as --default".
4. It prints "an answered or expired packet on this same question, or a covering standing grant, is a ruling: act on it (class A records it)".
5. **Last**, it prints the top match as one line: `cc-decide: <LIKELY ALREADY RULED|similar>: <id> · <status> <resolved[:10]> · "<what_plain[:120]>" · <evidence, or "default fired: <default>">[:120]`. The "LIKELY ALREADY RULED" form applies when top1/top2 ≥ 1.5.
6. It logs one IDL row through the existing `log_idl` (`:157-161`) with verb `ruling-hint`, carrying the top id and the ratio.

**`bin/cc-memory-search`.** Add a new `--decisions` flag, plus `--exclude ID`.
- The corpus is answered packets only (status ≠ open) from `${CC_DECISIONS_DIR:-~/.claude/autonomy/decisions}`.
- The searched text is `what_plain`, `options[].outcome_in_operator_terms` (guarded when options are plain strings, as in `ship-land.sh:686-690`), `default_if_no_veto`, `recommendation` and `evidence`. This is exactly the corpus measured in maps/ruling-discovery.md §4.2.
- It never globs `~/.claude/projects` (that glob is what costs 7.4 s, same map §2).
- It is scored by the existing `search()` (`:488`), and it prints the ratio of the top two scores.
- Measured in that map: `e869fac7eb34` gives `eb3dbe1e5e94` at ratio 2.88; `290215743799` gives `a247b7288149` at 1.62; 0.73 s end to end.

**`hooks/anti-deference-nudge.sh:131`.** Prefix `CC_DECIDE_RULING_HINT=0` on the `open_packet_B` call. That path discards stderr (`:138`) and is a Stop hook, so it must not pay the search.

**No classifier output is used.** `gate-classify.sh` routes the money packet `a247b7288149` to B (maps/cc-decide.md §5). Printing "router says B" could steer a real purchase into a class-B default that fires.

### 2.7 D2: `scripts/codex-meter.sh`

A new read-only script of about 30 lines.
- It reads the newest `${CODEX_HOME:-$HOME/.codex}/sessions/*/*/*/rollout-*.jsonl` and takes the last line containing `"rate_limits"`. This is the logic of `xverify.py:30-40`.
- It picks the window whose `window_minutes` ≥ 10080, or else `primary`. On Pro the primary window is the weekly one (packet `a247b7288149` `.evidence`: "weekly window only (10080 min)").
- It prints `used_percent=<n> window_minutes=<m> source=<file>`.
- It exits 0 when `n < ${CC_CODEX_METER_MAX:-80}`, 3 when at or above it, and 4 when unreadable. **Fail closed**: no reading means no call.
- It has no network access and writes nothing.

---

## 3. Per goal

| Goal | Mechanism | Proof-critical? |
|---|---|---|
| (a) keep working on every in-scope item an open decision does not gate | **K3** blocks the idle and names the next round. **K2**'s ⛔ readout and `rung_next` stop saying "nothing below it closes". R:38, R:103 and R:217 let a lead arm `set` under ⛔ for ungated work, so the armed path, which has no rung check (`hooks/session-continue.sh:1293` onward), drives it with no new hook. | K2 + K3: yes. R1: no. |
| (b) judgment calls with a status-quo course go to class B; class C keeps its reserved set | R:160 (with `--default-effect no-change --project`, so a fired "keep looping" default no longer misroutes as `df779857c4ff` did: maps/cc-decide.md §0.2), the dispatch-assert text, C1's class-C reminder at the moment of filing, and the `cc-decide:103` comment. A class-B re-file leaves ⛔ with no ledger change (`scripts/wrap-ledger.sh:47-49`). With K2, the result is a 🔧, not a false ✅. | No: K3 works whatever the class. |
| (c) find an existing ruling before asking | **C1**: the hint at the only point every filer certainly passes (`cc-decide open`). The R:68 sentence names the sources (packets, `cc-memory-search --all`, grants, purchases). | No |
| (d) record standing grants every session loads | **D1**: one always-loaded line in S; the full record in G; **D2** makes the 80% stop tracked code. | No |
| (e) refuse a Blocked idle while ungated in-scope work remains, including a box-less loop | **K1** (the contract reaches the store), **K2** (`LOOP_OPEN`, and 🔧 instead of a false ✅), **K3** (the refusal). The predicate is ledger state, never prose (maps/incident-replay.md §8.1). | **Yes** |
| (f) wake a stalled session itself | **K4**: `cc-notify <sid>`, which reaches the session by socket wake when no watcher is armed (proven on this session at 20:27:36Z, TX:5065-5069). The text carries the instruction. | **Yes** (for the non-compliant branch) |

---

## 4. Replay

**Assumption: as filed, worst case.** The machinery changes, but the lead behaves exactly as it did:
- both packets filed class C with no declaration (TX:4254, TX:4260);
- the same hold prose;
- no rule followed.

This is the strongest test, because R1, C1 and D1 do not count. The new machinery is assumed live from 2026-10-22.

**Capture (K1).** At the first unarmed Stop after TX:14 (10-22), the ledger reads `LOOP_SRC=none`.
- `sc_capture_scope` takes the Scope count (≥1). The marker is empty, so it runs `capture-human`.
- That returns TX:14's loop line (F2) and writes `## … (stop-capture) · toplevel=…/agent-context-sync · session=666022fd…`.
- From the next Stop on: `LOOP_SRC=own`, `LOOP_OPEN=1`, and K1 is never reached again.

| Time (Z) / TX | Ledger (estimated from maps/incident-replay.md §5 plus K2) | Loop floor | Other hooks | Outcome |
|---|---|---|---|---|
| 02:25:42 / 4199 (🔧, custody open) | 🔧 custody, LOOP_OPEN=1 | abstain `loop-floor-inflight` custody (F7) | as today | stop allowed: correct |
| 02:36:51 / 4273, 02:37:17 / 4294 | ⛔ BLOCKED=2, `BLOCKED_IDS=290215743799,e869fac7eb34`, LOOP_OPEN=1 | abstain custody (lanes open until 05:01:53Z, F7) | handoff-claim-assert blocks as today (TX:4275) | allowed: correct (C1 control) |
| 03:09 / 03:48 / 04:30 (4316/4334/4359) | ⛔, same ids | abstain custody | completion-assert `blocked-answered` as today | allowed: **C1 holds** |
| 05:02:50 / 4420 | ⛔, LANDING=1 (estimated: ship-land in the background, b5yelhdfm; `land_inflight_live` was not replayed) | abstain `inflight` land. If LANDING read 0: one forced turn, then `no-progress` | as today | allowed (or 1 bounded turn) |
| **06:44:40 / 4437 (F1)** | ⛔ BLOCKED=2, LOOP_OPEN=1, custody 0, no wave (F7, F8), READOUT "… need your call: cc-decide list --open · your loop scope is still open: rounds continue as scoped while it waits" | key K1=(666022fd, both ids, loop head), count 0 → **FIRE 1/2**: `⟳ LOOP FLOOR … Next: run the next round as scoped.` `mark_blocked loop-floor`; IDL `fired loop-floor {ungated:1,key:K1}` | anti-deference `no-tell`; completion-assert `no-close-tell` (and it would yield on the marker anyway); boundary-handoff `freewin=⛔` (no block) | **The idle is refused.** Exactly one block on this Stop. |
| F1′ (the forced turn) | — | **Compliant branch (expected):** the lead starts round 27 (lanes or workflow), so the next close sees custody or a wave and abstains. **Evidence:** given one clear prompt at 18:11Z, the same lead answered "Until you answer, I'll keep running the loop as scoped, starting round 27" (TX:4495), and round 27 landed (`f04c61db`, maps/incident-replay.md §0.8). **Non-compliant branch:** it re-closes ⛔ with no write, so `turn_scan` gives `.b` containing "⟳ LOOP FLOOR" and `.w=false`, and the floor abstains `loop-floor-no-progress` (ungated:1). | — | compliant: no idle |
| 07:39:47 / 4458 (F2), non-compliant branch | same | The turn was opened by the watcher timeout, not by our block, so the no-progress test does not apply: **FIRE 2/2** | same | refused again |
| 08:34:59 / 4476 (F3) | same; the watcher has been torn down | count 2 ≥ max: abstain `loop-floor-budget` **ungated:1** | same | allowed (budget spent) |
| ~09:05-09:11 (first STALL? of the episode; maps/wake-path.md §2.1) | — | — | **K4**: the newest floor row is `ungated:1`, key K1, no marker, so nudge 1. `cc-notify 666022fd… "⏯ IDLE WITH UNGATED SCOPE … run the next round as scoped now …"` If the detached watcher from 08:34:49Z is alive, cc-notify reports `wake-path-armed` and no socket wake fires (maps/wake-path.md §4.3). The line waits in the inbox and the marker is written (rc 0). | woken now, or at worst at nudge 2 |
| ≥ +2 h (~11:10) | — | — | nudge 2 (key unchanged; back-off met). The orphan watcher has died (≤3300 s), so this is a socket wake (W3: vendor idle). The UserPromptSubmit drain surfaces both lines (as at 20:27:37Z, TX:5067). | **woken ~7 h before 18:11Z** |
| ≥ +4 h (~15:10) | — | — | nudge 3 if still idle; then `subject_nudge_capped` | bounded |

**Result.** The close stack refuses F1 and F2. In the worst case the session is woken twice more with the instruction. **In the as-filed worst case the maximum idle falls from 9 h 36 m to about 2.5 h** (F3 08:35Z to nudge 2 at about 11:10Z), estimated from the STALL? timing in maps/wake-path.md §2.1 and the 2 h back-off. In the compliant branch, round 27 starts at about 06:45Z, 11 h 26 m earlier than it did.

**The "rules followed" counterfactual, adding R1, C1 and D1:**
- D1 covers decision 2, so `290215743799` is never filed.
- C1: the e869 open's last stderr line before the id, which stays visible through the lead's own `2>&1 | tail -3`, would read `LIKELY ALREADY RULED: eb3dbe1e5e94 · expired-actioned 2026-10-15 · … · default fired: "keep looping until dry (the scope as written)"`. That is estimated from the measured ratio of 2.88 and the output order in §2.6.
- R:160 makes any remaining loop question a class-B packet with default "keep running rounds as scoped".
- So BLOCKED=0, and K2 gives 🔧 (loop) instead of a false ✅ (maps/incident-replay.md C5). boundary-handoff's free-win stays silent, because it needs ✅ (`hooks/boundary-handoff.sh:658`). K3 fires the same way on 🔧.

**Controls (each must pass unchanged):**

| Control | Inputs | Floor result |
|---|---|---|
| C1: ⛔ with lanes in flight (03:09-05:02Z) | custody ≥1 (F7) or LANDING=1 | abstain `inflight`: allowed |
| C2: legitimate class C (d610) over a subset, round 27 running (18:31:59Z, TX:4769) | custody 0 (F7); wave `wf_e887b970-e18` live (F8; estimated `started>result` with fresh agents at 18:31Z) | abstain `inflight` workflow: allowed. **Without the wave check this would be one false forced turn** (F8). |
| C3: permission denial gating Codex only (18:17:32Z, TX:4683) | round 27 live since 18:16Z (F8) | abstain `inflight` workflow: allowed. With nothing in flight, the floor fires "run the next round as scoped" (that is, Claude-only), which is the required push. |
| C4: genuine money or self-mod gate gating everything, non-loop scope | LOOP_OPEN=0 | abstain `loop-floor-no-loop` (logged, ungated:0). The close is allowed exactly as today; no nudge, because ungated:0. **Zero forced turns.** |
| C4′: genuine gate inside a loop scope where every round needs the act | LOOP_OPEN=1, nothing in flight | ≤2 forced turns for this decision set; discharged by one `dod-persist.sh set "Scope (frozen): hold until <id> is answered — …"`, after which LOOP_OPEN=0 and the next floor row is ungated:0, so no nudges. |
| C5: class-B re-file (b4780d7bb60e) and 290215743799 actioned | BLOCKED=0 | 🔧 (loop), the floor fires; free-win silent; no SAFE TO CLOSE certificate |
| Research program, kill phrase, assignee, teardown | — | abstain, logged |

---

## 5. Loop and false-block analysis, per change

| Change | Can it extend a turn? | Infinite-loop bound | False-block bound |
|---|---|---|---|
| K1 capture (`dod-persist capture-human` from session-continue) | No (it writes the DoD only) | One fork per change in the Scope-line count, only while `LOOP_SRC=none`. It refuses when an own capture exists, so it can never re-open a loop the session ended (the end marker is the session's own newer line). | Contract mis-pick: human-origin only. Measured on B13: picks TX:14 alone (F1, F2). |
| K2 ledger fields and the 🔧 rank | No (fields; the rung changes only on the ✅-eligible path) | n/a | A false 🔧 only for a session's *own* loop-regex scope: 1 of 362 store lines (F5). One `dod-persist set` ends it. The pinned ladder order is unchanged (`tests/wrap-ledger.bats:1934`, `:1950`). |
| K3 loop floor | **Yes** (`decision:block`) | (1) ≤`CC_LOOP_FLOOR_MAX`=2 fires per (sid, sorted open class-C ids, loop head). (2) ≤`CC_LOOP_FLOOR_SET_MAX`=4 per (sid, ids) across scope edits. (3) No second fire when the turn our block opened wrote nothing (`turn_scan`). (4) If the latch is unwritable, no block (fail closed). (5) It runs only on the unarmed path, so it never stacks on the armed chain. (6) One floor per Stop (`:1316-1328`), and `mark_blocked` makes completion-assert yield (`hooks/completion-assert.sh:1293-1297`). **Worst case: 2 forced turns per decision state, 4 per decision set.** It never keys on HEAD (a loop lands every round) or on lifetime (budgets were spent on 10-22; maps/stop-hooks.md §0.1). | **Zero** outside the session's own open loop scope: every non-loop ⛔ (C4) and all 48 legacy class-C packets today (F6). Abstains on custody, land, live wave, research program, kill phrase, assignee (rc 0 or 2), teardown, 📦/🚀, and any unreadable custody. Inside a loop with an all-gating gate (C4′): ≤2 turns plus a one-line discharge. Known residuals: a background `Bash` task the floor cannot see, and an operator "wait for my answer" with no kill phrase. Each costs ≤2 turns, the second usually suppressed by no-progress. |
| K4 subject nudge | It starts a turn by mail and socket wake; it blocks nothing | ≤3 per decision-state key (from the floor row), back-off 2 h then 4 h, ≤3 per sweep. The marker survives `clear_page` and `clear_page_recovered`. Fail closed on the marker; the marker is written on rc 0 even when not woken (no duplicate lines). **Worst case: 3 turns per decision state.** A key changes only when the open set or the scope changes. | Fires only when the session's last floor row says `ungated:1`. Legit stops (C4) and usage-limited sessions (cc-wake refuses, `bd6d3c14c1e8`) are never nudged or cannot be woken. The 53 other sessions that escalated behind a class-C packet (maps/legit-stops.md §5) carry no loop floor rows, so 0 nudges (estimated from F5). |
| C1 hint | No | n/a | stdout and the exit code are unchanged. Bounded at 3 s; fail-open. The Stop-hook producer opts out. |
| R1 text, D1, D2 | No | n/a | n/a. D2 fails closed. |

**Combined worst case per decision state:** 2 forced turns (K3) plus 3 woken turns (K4). Every further turn needs a real state change: a new open set, a new scope line, or new custody.

**Interaction accepted as-is.** At ≥73% fill, boundary-handoff's threshold arm can block on the same Stop as K3. That is the same double message the ship floor already produces, because boundary-handoff's compose-guard reads only the sentinel (`hooks/boundary-handoff.sh:687-694`). Both are bounded and compatible: the recycle brief carries the Scope line, and K1 recaptures it in the successor.

---

## 6. Deliberately not done, and why

1. **No `--gates` or `--ceiling` field and no class-C refusal in `cc-decide`.**
   - With "absent = all", it is inert for B13 as filed.
   - Making it required costs `scripts/research-kit/lib/gate_sweep.py` plus 61 test call sites, and `ship-land.sh` bypasses `open` anyway (maps/cc-decide.md §7).
   - The classifier cannot verify it (73% of class C routes to B, and money is missed: maps/legit-stops.md §2).
   - K3 does not need it.
2. **No demotion of ⛔ below 🔧 or 📦.** That keeps `tests/wrap-ledger.bats:1934`, `:1950`, the four ladder docs and the ship floor's no-gated-land property (maps/wrap-ledger.md §6(i)).
3. **No anti-deference phrase arm.** The replay shows 0 blocks (maps/stop-hooks.md §6). "need your call" is the ledger's own text (`scripts/wrap-ledger.sh:2607-2609`). The pins at `tests/anti-deference-nudge.bats:519-545` and `:706-717` stay.
4. **No completion-assert change.** All three idle closes stopped at `no-close-tell` (`hooks/completion-assert.sh:469-471`), with the assert budget spent since 10-22. One actuator only. `blocked-answered` (`:1218-1231`) stays exactly as it is.
5. **No ⛔ free-win in boundary-handoff.** It is not an incident step, and a recycle launders ⛔, because the successor counts only its own sid (`scripts/wrap-ledger.sh:1529`).
6. **No idle-keepalive wake.** It is structurally shadow (`hooks/idle-keepalive.sh:37`), it carries no content, it was not in B13's Stop chain (TX:4440), and its switch-on is an open operator decision.
7. **No REMAINDER or DIRTY floor under ⛔.**
   - 0 of 78 DoD files hold an unchecked box (maps/wrap-ledger.md §0.2).
   - A lineage remainder is the steady state (`hooks/session-continue.sh:997-1002`).
   - The ⛔+own-dirty extension of `mechanical_arm` (`:1103`) is not an incident step, and its worst case is 16 turns. It is the first follow-on.
8. **No class-B-default-fired wake to the filing session** (a two-ended interface: the expire-sweep TSV and `autonomy-sweep.sh:562`). R:160's `--default-effect no-change --project` fixes the misroute that mattered.
9. **No `standing-grants.json` and no grant matching in `cc-decide`.** With one grant, the always-loaded line plus the G record is enough. Add JSON when a second grant arrives.
10. **No repair of `send_page`'s dead desk** (`scripts/lead-supervisor.sh:414-415`). K4 bypasses it. File it separately.
11. **No `validate-bash` denial of a detached `cc-await-ping … &`** (maps/wake-path.md §4.3). It only delays K4 by at most one back-off step. File it separately.
12. **No `operator-readout` 🔧 parts term for the loop.** Under ⛔ it prints READOUT verbatim, which now carries the clause (`hooks/operator-readout.sh:1541-1548`). A loop 🔧 renders "loose ends", exactly as CLOSE_FLOOR does today (`:1509-1514`). A one-line follow-on.
13. **Antigravity/Gemini is not in the grant.** d610's goal (d) names only Codex; the agentsync memory includes it. This is an open question for the operator.
14. **No new auto-filed packets** from any hook (the `f56cf0f827d7` false positive).

---

## 7. Tests

Every suite must be run by hand, because the land smoke will be cut or skipped (maps/test-infra.md §2.2).
- Assert the `1..N` plan line. rc 75 is not a verdict.
- Dates are relative or use 2099 sentinels.
- Assertions use `! cmd || false`.
- "Red without" means red against `origin/main`'s subject, plus one mutant per guard, both recorded in the commit body (maps/test-infra.md §6).

### 7.1 `tests/wrap-ledger.bats` (grandfathered; add to it)

| Test | Fixture | Assertion | Red without the change because |
|---|---|---|---|
| `LOOP: own-session loop scope ⇒ LOOP_OPEN=1, LOOP_SRC=own, visible under ⛔` | `ok_state`; `WRAP_DOD_FILE` holding `## 2099-01-01T00:00:00Z (stop-capture) · session=$SID` + `Scope (frozen): loop until dry …`; `use_real_decide`; `open_blocking` ×2 | `RUNG=⛔`, `LOOP_OPEN=1`, `LOOP_SRC=own`, `BLOCKED_IDS` = the two ids, sorted | the fields do not exist |
| `LOOP: a foreign session's loop scope ⇒ LOOP_OPEN=0` (alarm polarity) | same, header `session=other-sid` | `LOOP_OPEN=0`, `LOOP_SRC=none` | same; also guards against an unscoped mutant |
| `LOOP: a newer own non-loop frozen line ends it` | two own blocks: loop, then `hold until x is answered` | `LOOP_OPEN=0`, `LOOP_SRC=own` | same; mutant "first own line wins" goes red |
| `LOOP on the ✅ path ⇒ RUNG=🔧 with the loop readout (class-B re-file is not a false ✅)` | `ok_state` + own loop; one open class-**B** packet | `RUNG=🔧`; READOUT contains `a loop no newer Scope line has ended` | today it reads `RUNG=✅` (maps/incident-replay.md C5) |
| `LOOP under ⛔: readout keeps "need your call" and adds the loop clause; Next drops "nothing below it closes"` | first fixture | `--machine` READOUT has both substrings; `--full` `Next:` lacks `nothing below it closes` | no clause today |
| `LOOP kill switch: WRAP_LOOP_FLOOR=off ⇒ LOOP_SRC=off, and the memo is not shared` | first fixture, run twice, with and without the env | first `LOOP_OPEN=1`, second `LOOP_SRC=off` | the seam is missing from `_wl_k` (mutant: drop it ⇒ memo serves the stale value) |
| `BLOCKED_IDS pad: one decision keeps BLOCKED_WHAT intact; zero decisions ⇒ empty` | `open_blocking` ×1, ×0 | `BLOCKED_WHAT` equals the text; `BLOCKED_IDS=` empty for 0 | a TSV-collapse mutant (no `-` pad) shifts `what` |
| Existing `⛔ outranks 🔧` / `⛔ outranks 📦` (`:1934`, `:1950`) | unchanged | unchanged | the regression control |

### 7.2 `tests/dod-persist.bats`

| Test | Fixture | Assertion | Red without |
|---|---|---|---|
| `capture-human: the newest human-origin Scope line is persisted with session provenance` | transcript: a user string record (`origin.kind:"human"`) with the loop scope; a **newer** `tool_result` lane brief Scope line; an `isMeta` record and a `task-notification` record each carrying a Scope line (F1 shapes); `CLAUDE_CODE_SESSION_ID=S` | output `captured`; the store gains `(stop-capture) · … · session=S` + the loop line, **not** the lane line | unknown mode, so nothing is written |
| `capture-human: lane-brief-only transcript ⇒ none` | only `tool_result` Scope lines (the TX:3875 shape) | `none`; store unchanged | — (the guard against a raw-grep mutant) |
| `capture-human: never overrides an own capture` | the store already holds an own `manual-set` hold line for S | `own-exists`; no append | a mutant without the guard re-opens the loop |
| `capture-human: no session id ⇒ none` | env unset | `none` | — |

### 7.3 `tests/loop-floor.bats` (new; `export HOME=$BATS_TEST_TMPDIR/home` in `setup()`, per hermeticity rule 1)

The pattern is `tests/ship-floor.bats:25-45`: a `WRAP_LEDGER_BIN` stub driven by env (`STUB_RUNG`, `STUB_LOOP_OPEN`, `STUB_LOOP_SRC`, `STUB_IDS`, `STUB_LANDING`, `STUB_RESEARCH`), a `CC_CUSTODY_BIN` stub (`STUB_CUSTODY`, `STUB_CUSTODY_RC`), `LIVE_WAVES_LIB` pointed at the real lib over a fixture run directory, the `AGENT_IDENTITY_LIB` stub, `CONTINUE_IDL`/`CONTINUE_LOG` isolated, and `CC_WAKE_FLOOR=0`.

| Test | Fixture | Assertion | Red without |
|---|---|---|---|
| `B13 F1 replay: ⛔ + LOOP_OPEN=1 + two ids + nothing in flight ⇒ block` | last assistant text = TX:4437 lines 1-4 verbatim; ids `290215743799,e869fac7eb34` | `decision:block`, reason has `⟳ LOOP FLOOR`, both ids, `run the next round as scoped`, `(loop floor 1/2)`; IDL `fired loop-floor` with `ungated:1` and a key; `${sentinel}.blocked` third field `loop-floor` | silent exit 0 today (maps/stop-hooks.md §2.3) |
| `B13 F3 shape (verdict on line 3, watcher torn down) ⇒ same block` | TX:4476 text | same as above | — (proves prose-independence) |
| `cap: third Stop with the same decision set ⇒ abstain loop-floor-budget, ungated:1` | three runs, `CC_LOOP_FLOOR_MAX=2`, with the turn opened by a task notification (not by our block) | blocks, blocks, then a `systemMessage`-free exit with an IDL `abstained loop-floor-budget` row | a mutant with no cap blocks forever |
| `new decision set re-arms` | after the cap, `STUB_IDS` gains an id | fires `(loop floor 1/2)` | a lifetime-keyed mutant stays silent |
| `set ceiling across scope edits` | four different `LOOP_HEAD`s, same ids | fifth evaluation abstains `loop-floor-budget` with `set_count:4` | a mutant without the set ceiling |
| `no-progress: turn opened by our block, no write ⇒ abstain` | transcript tail: user `Stop hook feedback:\n⟳ LOOP FLOOR …`, then assistant text only | `abstained loop-floor-no-progress`, `ungated:1`, no block | a mutant without `_lf_idle_after_own_block` re-blocks |
| `in flight: LANDING=1 ⇒ abstain` (C1 at 05:02Z) | `STUB_LANDING=1` | no block; `inflight` `{"what":"land"}` | — (the guard) |
| `in flight: open custody ⇒ abstain` (C1 at 03:09-04:30Z) | `STUB_CUSTODY=3` | no block; `{"what":"custody","n":3}` | — |
| `in flight: live workflow wave ⇒ abstain` (C2/C3) | `<tp-dir>/subagents/workflows/wf_x/journal.jsonl` with 2 started / 1 result + `agent-1.jsonl` touched now | no block; `{"what":"workflow","n":1}` | a mutant without the wave check blocks (F8) |
| `custody unreadable ⇒ abstain, never block on ignorance` | `STUB_CUSTODY_RC=1`, and the binary absent | no block; `loop-floor-custody-unknown` | — |
| `genuine all-gating gate in a non-loop scope (C4) ⇒ no block, logged` | `STUB_RUNG=⛔ STUB_LOOP_OPEN=0` | no block; IDL `loop-floor-no-loop ungated:0` | — (the B-3 row is new: red because no row exists today) |
| `absent field: an old ledger with no LOOP_OPEN ⇒ silent` | a stub that prints only `RUNG=⛔` | no output, no block | — (the fail-open control) |
| `kill switch: last user message "…and stop" ⇒ abstain` | user record with the phrase | `loop-floor-kill-switch` | — |
| `assignee rc 0 and rc 2 ⇒ abstain` | `ma_ai_stub` rc 0, then rc 2 | `loop-floor-assignee` with `confirm_rc` | — |
| `research program ⇒ abstain` | `STUB_RESEARCH=tm2` | `loop-floor-research` | — |
| `📦 ⇒ loop floor abstains (money-landing 📦 stays terminal)` | `STUB_RUNG=📦 CC_SHIP_FLOOR=0` | no loop-floor block; `loop-floor-rung` | — |
| `latch unwritable ⇒ no block (fail closed)` | `CLAUDE_CONFIG_DIR` state dir `chmod 555` | no block | a mutant that blocks before writing the latch blocks unboundedly |
| `K1 trigger: LOOP_SRC=none + a human Scope line ⇒ capture-human invoked once; an unchanged count ⇒ not again` | `DOD_PERSIST_BIN` stub that appends its argv to a file and prints `captured` | argv file has 1 line after two Stops; IDL `captured scope-capture` | no trigger today |
| `agent-armed sentinel under ⛔ ⇒ armed path, loop floor not evaluated` | `arm "run round 27"` | the block is the 🔧 `continue_reason`; no loop-floor IDL row | — (guards the placement) |
| `CC_LOOP_FLOOR=0 ⇒ off` | — | no block | — |

Also run, unchanged: `tests/session-continue.bats`, `tests/ship-floor.bats`, `tests/wake-floor.bats`, `tests/mechanical-arm-exemption.bats`, `tests/session-continue-forks.bats`. The common path adds zero forks by construction: when `LOOP_OPEN≠1` and rung ≠ ⛔, only `led_field`, a bash loop, runs. Re-measure anyway.

### 7.4 `tests/boundary-handoff.bats`

| Test | Assertion | Why |
|---|---|---|
| Existing in-flight-wave free-win cases | unchanged rows (`freewin-inflight-wave:N`) | proves the lib move is byte-neutral |
| `bh_live_waves resolves the lib through $0's symlink` | counts 1 on a fixture run when invoked through a symlinked hook path | same lesson as `hooks/session-continue.sh:1067-1070` (a brand-new lib file has no live symlink until install.sh runs) |

### 7.5 `tests/anti-deference-nudge.bats`

| Test | Fixture | Assertion | Why |
|---|---|---|---|
| `new ⛔ readout clause is still no-tell` | F1 lines 1-2, with line 2 carrying the new `· your loop scope is still open: rounds continue as scoped while it waits` | `no-tell` | K2 changed line-2 text; this guards the TELLS (`:170`), DONE (`:173`) and CATEGORY (`:186`) arms |
| `open_packet_B passes CC_DECIDE_RULING_HINT=0` | a stub `cc-decide` that records its env | env shows `=0` | without it, a Stop hook pays the 0.73 s search |

### 7.6 `tests/cc-decide.bats` (grandfathered)

| Test | Fixture | Assertion | Red without |
|---|---|---|---|
| `open B/C prints a ruling hint on stderr; stdout is exactly the id; rc 0` | `CC_DECISIONS_DIR` with an `expired-actioned` class-B packet ("Keep looping until a round confirms nothing at all…", default "keep looping until dry") plus 5 unrelated answered packets; then open class C "Should the loop stop now…" | `[ "$(… 2>/dev/null)" = "$id" ]`; the stderr **last line** names that packet and `default fired`; status 0 | no hint |
| `hint order: the ruling line is last on stderr` | `… 2>&1 \| tail -2` | line 1 = ruling, line 2 = id | the guard for the TX:4254 `tail -3` shape |
| `hint fails open: search absent, or a stub sleeping past the timeout` | `CC_MEMORY_SEARCH_BIN` = absent / `sleep 10` stub, `CC_DECIDE_HINT_TIMEOUT_S=1` | same id, rc 0, no hint, wall < 5 s | — |
| `CC_DECIDE_RULING_HINT=0 ⇒ no search` | a stub that counts its calls | 0 calls | — |
| `re-open of an existing packet ⇒ no search`; `class A ⇒ no search` | stub counter | 0 calls | — |
| `class C prints the reserved-set reminder; class B does not` | — | substring present or absent | — |

### 7.7 `bin/cc-memory-search` suite

The repo's existing `cc-memory-search` bats, extended.

| Test | Assertion |
|---|---|
| `--decisions ranks the same-question packet first, ratio ≥ 1.5` | top id and ratio |
| `--decisions excludes open packets and --exclude id` | — |
| `string-shaped options (ship-land packets) do not crash` | — |
| `--decisions never globs ~/.claude/projects` | runs under a HOME with no `projects/` and still answers |

### 7.8 `scripts/supervisor-e2e.sh` T41 "SUBJECT NUDGE", with `floor=` raised in `tests/lead-supervisor.bats:33-44`

Run under `/bin/bash` 3.2. The template is T40 (`scripts/supervisor-e2e.sh:942-985`). Each check is an `ok`/`no`.

| Check | Fixture | Assertion |
|---|---|---|
| (1) nudges the subject directly when the last loop-floor row says `ungated:1` | a STALL? fixture (sleep pid, stale telemetry/transcript); IDL row `{"hook":"session-continue","sid":S,"reason":"loop-floor-budget","ungated":1,"key":"k1","blocked_ids":"a,b"}`; `CC_NOTIFY_CAPTURE` | the captured argv is `S` and the text contains `IDLE WITH UNGATED SCOPE` and `a,b` |
| (2) back-off: same key within 2 h ⇒ no second send | two sweeps | 1 send |
| (3) a new key resets the count | new row `key:k2` | a send with `attempt 1` |
| (4) a refused send leaves no marker and is retried | `CC_NOTIFY_STUB_RC=3` | no `.nudged`; the next sweep sends |
| (5) kill switch `CC_SUP_SUBJECT_NUDGE=0`; shadow logs only | — | 0 sends; a `subject_nudge_shadow` row |
| (6) a non-uuid sid is never addressed | — | 0 sends |
| (7) cap 3 per key, then `subject_nudge_capped` | `CC_SUP_NUDGE_BASE_S=0` | 3 sends, then a capped row |
| (8) `ungated:0` row (legit stop) or no row ⇒ no nudge | — | 0 sends |
| (9) `clear_page` and `clear_page_recovered` keep `.nudged` | — | the file survives |
| (10) ≤3 per sweep across sessions | 5 candidates | 3 sends |
| (11) the verdict is parsed from the `^cc-notify: verdict=` line | stub stderr carries a `verdict=refused-busy` cc-wake line first, then `cc-notify: verdict=delivered … reason=no-watcher` | IDL `verdict:"delivered"`, `reason:"no-watcher"` |

### 7.9 `tests/lead-keeps-working-rules.bats` (new; fixture HOME in `setup()`)

It names `CLAUDE.rules.slim.10-session-close.md`, `CLAUDE.global.slim.md` and `CLAUDE.global.md` literally, so `scripts/gate-select.sh` selects it. The pattern is `tests/close-research-pending-rules.bats:11-43`.

Each new clause is asserted in R (or S) **and** in G:
- `keep driving what it does not gate`;
- `Only ⛔ when all remaining in-scope work waits on an open decision` (or the G spelling);
- `--default-effect no-change --project`;
- the reserved-set sentence;
- `look for a ruling`;
- `loop until … scope stays open`;
- the R:217 arm-on-⛔ clause;
- grant tokens in S and in G: `codex exec -s read-only`, `git archive`, `80%`, `api.openai.com`, `model-config.yaml`.

Negatives:
- R no longer contains `Stop and ask, overriding auto-continue`, `filing is what makes it the`, or `and only on 🔧`;
- `bin/cc-decide` no longer contains `it ends a session's turn holding work`.

**Budget:** `python3 -I hooks/lib/instruction_budget.py measure` of S + R ≤ 58,790. That is the measured pre-change sum 28,503 + 30,287 (maps/rules-text.md §6). It is red if the edit grows the tier.

### 7.10 `tests/codex-meter.bats` (new; fixture HOME)

| Test | Fixture | Assertion |
|---|---|---|
| under the limit | rollout with `rate_limits.primary` `{used_percent:12, window_minutes:10080}` | exit 0, prints `used_percent=12` |
| at or over the limit | 85 | exit 3 |
| the weekly window is chosen when two windows exist | — | the 10080-minute window's value is used |
| no rollouts, or malformed input | — | exit 4 |

Path dates: `2099/01/01` sentinels.

---

## 8. Rollout, risks, open questions

**Order.** Each step is safe alone.
1. K2 ledger fields. On their own they are inert apart from the 🔧 for own loop scopes. Population F5 = B13 only.
2. K1 and K3, with `hooks/lib/live-waves.sh`.
3. K4. Live by default: its only trigger is a floor row with `ungated:1`. `CC_SUP_SUBJECT_NUDGE=shadow` is available.
4. C1.
5. R1, D1, D2.

Then converge with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`. Rules are live only after `install.sh` copies them (`scripts/deploy-live.sh:52`). Verify by content with `diff -q` of S and R against the live copies (maps/test-infra.md §7).

**Estimated size.** About 620 changed or added lines of code and text, and about 900 lines of tests. Of those, K1-K4 account for about 400 code lines (sum of the §2 sketches).

**Risks.**
- **Timeout pressure.** `session-continue.sh` already hits its 5 s timeout under load (`:1093-1097`). On `LOOP_OPEN=1` Stops, the floor adds roughly 6-10 forks: `cc-custody`, `find`/`stat` for waves, 2×`cksum`, `turn_scan`, `jq` (estimated). A kill means no block, which fails open to today's idle. The cheap checks are ordered first.
- **IDL rotation** (F10) can hide the floor row for up to one rotation. K4 reads the newest `.gz` before giving up. The residual is fail-closed.
- **Model compliance is not mechanical.** The proof is that the stack no longer *accepts* the idle silently: 2 refusals plus 3 wakes, each carrying the instruction. The evidence that one instruction suffices is TX:4495.
- **Instruction re-gate debt.** `docs/plans/INSTRUCTION_BUDGET.md:127` records the operator deferring the F1 re-gate "until the next slim edit". This is such an edit. It is flagged here and not decided (maps/rules-text.md §6).
- **This is self-modification (C10),** authorized by d610f8473106 (resolved 20:41:42Z, maps/incident-replay.md §3.2). An audit `cc-decide open --class A` for the grant is the implementer's write. It must not pass `--conviction >90` (`bin/cc-decide:224-229`).

**Open questions for the operator.**
1. Antigravity/Gemini in the grant?
2. Should a wake via a supervisor nudge re-arm the floor's budget once? This design says no: only a state change re-arms.
3. Should `mechanical_arm` also run on ⛔ with own dirty writes (§6 item 7) as the next change?
