# D3 — schema first: a decision says what it gates, and only "gates all" may stop a lead

Designer slot D3 (angle: cc-decide schema first) for operator ruling `d610f8473106`. Worktree
`lead-idle-fix` at `958b23030`. Every code anchor is `path:line` in this worktree. `TX:n` is line n of the
B13 transcript `~/.claude-quaternary/projects/-Users-chrisren-Development-agent-context-sync/666022fd-ed3e-4e72-b293-7caae899d585.jsonl`.
`R` = `CLAUDE.rules.slim.10-session-close.md`, `S` = `CLAUDE.global.slim.md`, `G` = `CLAUDE.global.md`.
`maps/X.md:n` = the evidence maps in `docs/research/lead-keeps-working-2026-10-24/maps/`.
Numbers are labelled **measured** (with the command) or **estimated** (with the method). Nothing was
implemented; this file is the only write.

---

## 0. The design in one paragraph

A class-C packet today carries no field saying what it gates, so the ledger treats every open class-C
packet a session filed as "stop everything" (`scripts/wrap-ledger.sh:2603-2610`), and the rules route every
held decision to class C (`R:160`). D3 fixes the data first. `cc-decide open --class C` now **refuses**
unless the filer declares a closed-enum `--category` (`self-mod|money|permission|credential|destructive|escalation|pick`),
a `--gates all|"<the item it blocks>"` and a one-line `--why-gated`; the refusal prints a ready class-B
command (default = the status-quo course, `--default-effect no-change`) and any similar **answered**
packet or standing grant it finds. `cc-decide` stays the one arbiter: its `list --json` view folds each
packet to `gates_all`/`gate_hard` (absent `gates` ⇒ all, so all 691 legacy packets keep today's rung).
The ledger reads ⛔ only when an open class-C packet gates all; a packet that gates part leaves the
session on 🔧 whenever the ledger can see ungated work: dirt, a DoD box, or a new session-scoped
**loop-scope floor** (`LOOP_OPEN`) fed by an intake capture of the session's own contract. The ledger
also emits one predicate, `SCOPE_FLOOR=drive|challenge|none`. One Stop actuator (a fourth floor in
`hooks/session-continue.sh`) blocks an idle close on it, with a per-decision-set latch. One off-Stop
actuator (`nudge_subject` in `scripts/lead-supervisor.sh`) wakes the stalled session itself on the same
predicate, read from the IDL. A standing cross-vendor grant is recorded as a typed record plus one
always-loaded line, paid for by cuts so the slim tier does not grow.

**Replay verdict (§12):** with D3 deployed, the B13 lead's 02:36Z class-C opens are refused at the
`tail -3` the lead piped them through (`TX:4254`), and the last three lines it sees name the 10-day-old
ruling `eb3dbe1e5e94` ("keep looping until dry") and the class-B command. If the lead re-files as class B, the
06:44Z idle close is blocked by the scope floor with "run round 27 as scoped". If the lead files anyway
with a false `--gates all`, that close is challenged once.

If the lead still idles, the supervisor sends its first nudge when STALL? starts, about 09:11Z. Because of
the detached watcher B13 left at 08:34Z, the socket wake lands by about 10:11Z. Today the operator was the
one to wake it, at 18:11Z.

---

## 1. Data flow

```
 producer (session)                 arbiter                     ledger                        actuators
 cc-decide open --class C  ──►  packet {category, gates,   ──►  wrap-ledger count_blocking  ──►  session-continue scope_floor (Stop)
   --category --gates               why_gated, regates[]}         BLOCKED / BLOCKED_ALL /         operator-readout IDL row ──► lead-supervisor
   --why-gated (required)        list --json view:              BLOCKED_ALL_HARD / IDS           nudge_subject (off-Stop)
 cc-decide open --class B          gates_effective, gates_all,  + LOOP_OPEN (DoD store,        completion-assert (fact + log only)
   [--supersedes <C id>]           gate_hard  (one fold)          session-scoped)               operator-readout (render only)
 cc-decide regate <id>                                          ⇒ RUNG + SCOPE_FLOOR
 dod-persist intake (from session-continue at Stop) ───────────►  DoD store (`· session=<sid>`)
```

The one predicate lives in two places only: what a packet gates is folded **in `cc-decide`** (the store's
arbiter, `scripts/wrap-ledger.sh:42-46`, `bin/cc-decide:494-498`), and whether the session must keep
working is decided **in `wrap-ledger.sh`** (`SCOPE_FLOOR`). Every hook and the supervisor consume
`SCOPE_FLOOR`; none re-derives it.

---

## 2. `bin/cc-decide` — the schema change (the core of D3)

### 2.1 New packet fields

| Field | Class | Written by | Read side fold (absent ⇒) | In `mk_id`? |
|---|---|---|---|---|
| `category` | C only | `open --category` (closed enum, aliases `c10`→`self-mod`, `c6`→`money`) | `""` = legacy | no |
| `gates` | C only | `open --gates`; `all` (any case) stored as `"all"`, else the trimmed item text (≤200 chars) | `"all"` | no |
| `why_gated` | C only | `open --why-gated` (≤300 chars, one line); the key already exists on 6 July hand-written packets (`maps/cc-decide.md:235`) | `""` | no |
| `regates[]` | C only | `regate <id>` appends `{sid,ts,gates,why}` | `[]` | no |
| `supersedes` | B only | `open --supersedes <old>` | absent | no |
| `superseded_by` | C (old packet) | the superseding `open` | absent | no |

`mk_id` stays `class+sid+what` (`bin/cc-decide:98`, law at `:341-342`), so an annotated re-open never
mints a second packet.

### 2.2 Validation, in `cmd_open` (`bin/cc-decide:163-245`)

Pseudo-diff (new arms in the schema gate after `:214`, same fail-closed asymmetry as `:189-245`):

```diff
   local project="" deffect="" conviction="" receipt=""
+  local category="" gates="" why_gated="" supersedes=""
   ...
+      --category)    category="${1:-}";   [ $# -gt 0 ] && shift ;;
+      --gates)       gates="${1:-}";      [ $# -gt 0 ] && shift ;;
+      --why-gated)   why_gated="${1:-}";  [ $# -gt 0 ] && shift ;;
+      --supersedes)  supersedes="${1:-}"; [ $# -gt 0 ] && shift ;;
+      -h|--help)     usage; return 0 ;;          # TX:4249-4250: `open --help` was "unknown arg"
   ...
+  # ── CLASS ROUTING (ruling d610f8473106): C is reserved, and says what it gates ───────────────
+  case "$category" in c10) category=self-mod ;; c6) category=money ;; esac
+  if [ "$class" != "C" ] && { [ -n "$category" ] || [ -n "$gates" ] || [ -n "$why_gated" ]; }; then
+    echo "cc-decide open: --category/--gates/--why-gated are class-C fields (a class-B default fires, so it gates nothing)" >&2; return 2
+  fi
+  if [ -n "$supersedes" ] && [ "$class" != "B" ]; then
+    echo "cc-decide open: --supersedes re-files a class-C judgment call as class B; it needs --class B" >&2; return 2
+  fi
+  if [ "$class" = "C" ]; then
+    case "$category" in self-mod|money|permission|credential|destructive|escalation|pick) _cat_ok=1 ;; *) _cat_ok=0 ;; esac
+    gates="$(printf '%s' "$gates" | tr '\n\t' '  ' | sed 's/^ *//; s/ *$//')"
+    case "$(printf '%s' "$gates" | tr '[:upper:]' '[:lower:]')" in all) gates=all ;; esac
+    if [ "$_cat_ok" = 0 ] || [ -z "$gates" ] || [ -z "$why_gated" ]; then
+      # prints: the refusal header, then ruling_hint (§2.6) and grant_hint (§2.7), then the two recipe lines LAST
+      refuse_class_c "$what" "$conviction" "$receipt" "$category" "$gates" "$why_gated" "${options[@]+"${options[@]}"}"
+      return 2
+    fi
+  fi
+  if [ -n "$supersedes" ] && [ "$deffect" != "no-change" ]; then
+    echo "cc-decide open: a superseding class-B packet re-files a held question whose default is the status quo — pass --default-effect no-change (a 'change' default files a backlog row; df779857c4ff is the measured misroute)" >&2; return 2
+  fi
```

Also at `:224`, scope the ">90 is refused" rule to B and C (`[ "$class" != "A" ] &&`). Today it refuses
even class A, the packet its own message tells the filer to write (`maps/cc-decide.md:137`). D3's ruling
step ends in "file class A citing it", so that path must open.

The write at `:344-354` adds `category`, `gates`, `why_gated` (class C) and `supersedes` (class B) through
`--arg`. The drift warning at `:313-327` extends its comparison to `category`, `gates` and `why_gated`, and
names `regate` as the repair for gates, because the warning today says there is no update verb
(`:323-325`).

### 2.3 The refusal is the escape path, so it must be complete in three lines

`cc-decide open` is the way out of a STOP-ASK, and an rc-2 that loses the packet is the failure the header
warns about (`bin/cc-decide:76-80`). The B13 lead piped both opens through `2>&1 | tail -3` and
`| tail -2` (`TX:4254`, `TX:4260`). So `refuse_class_c` prints its most important content **last**, one
fact per line, and every line starts `cc-decide:` so it reads as tool output:

```
cc-decide open: refused — class C waits with no default and is reserved; missing: --category --gates --why-gated
cc-decide: similar answered packet(s): <id> [<status> <date>] "<what, 90 chars>" …          (0-2 lines, §2.6)
cc-decide: LIKELY ALREADY RULED — eb3dbe1e5e94 (class B, expired-actioned 2026-10-15; its default fired: "keep looping until dry (the scope as written)"). An answered packet is a ruling: act on it and file class A citing it.
cc-decide: a judgment call with a status-quo course is class B (its default fires at the deadline; keep driving meanwhile): cc-decide open --class B --what '<the caller's --what, %q-quoted>' --default '<the status-quo course>' --default-effect no-change --deadline <now+72h, ISO Z> --conviction <N> --receipt '<R>' --project <toplevel basename> [--option …as passed]
cc-decide: a hard gate stays class C: add --category self-mod|money|permission|credential|destructive|escalation|pick (pick = new options, no status quo) --gates all|'<the item it blocks>' --why-gated '<one line>'
```

With `tail -3` the lead sees the ruling, the class-B command and the class-C fix. With `tail -2` it
sees both commands. The class-B command reuses the caller's own `--what`, conviction, receipt and options
(printed with `printf %q`), so the only blanks are the default and the deadline.

### 2.4 The read-side fold and `list --blocking` (`bin/cc-decide:494-594`)

One fold, beside `SFOLD` (`:154`), used by **both** list renderings:

```jq
def gates_eff: ((.regates // []) | if (type == "array" and length > 0) then (last.gates // "all") else null end)
               // (.gates // "all") | tostring | if . == "" then "all" else . end;
def gall:  (.class == "C") and ((gates_eff | ascii_downcase) == "all");
def ghard: ((.producer // "") != "")
           or ((.category // "") as $c | ["self-mod","money","permission","credential","destructive","escalation"] | any(. == $c));
```

- The `--json` leg (`:560-561`, `:568-569`) becomes
  `| .status = sopen | .gates_effective = gates_eff | .gates_all = gall | .gate_hard = ghard`. These are
  **view** fields. The file on disk is untouched (inv7, `:529-532`), exactly as `.status = sopen` is.
- `LIST_SELECT` (`:501-506`) gains `or ($mode == "blocking" and sopen == "open" and gall)`, and `cmd_list`
  accepts `--blocking`. This is the "is this a stop" query for humans and scripts. The ledger does not
  call it; it reads the same fold from its existing `--open --class C --json` fork (§4.1), so it pays no
  second fork.
- The polarity. An absent `gates` gives `gates_all=true`, which is today's ⛔. An absent `category`
  gives `gate_hard=false` unless the packet has a `.producer` (the `shipland-esc-*` writer,
  `scripts/ship-land.sh:649-700`), which stays hard. `gate_hard` affects only the one-turn challenge (§5.1),
  never the rung.

### 2.5 `--supersedes` and `regate`: the discharges that change state

The constraint is that a discharge must be a **state change**, not a sentence (`maps/stop-hooks.md:134-136`).
D3 gives the filer three:

1. **Re-file as class B**: `cc-decide open --class B … --default-effect no-change --supersedes <C id>`.
   - Validation, before any write (each failure is rc 2 or 3, and leaves the old file byte-identical):
     - the old packet exists and is open (`sopen`);
     - it is class C;
     - its `session_sid` equals the resolved sid, which must be non-empty (no laundering another session's gate);
     - it has no `.producer`;
     - its category is `""` (legacy) or `pick`. A **hard** category is refused with the message "a hard gate is answered by the operator, never re-filed".
   - After the new class-B packet is written, the old one is transitioned in place (inv7: status is a view;
     the content is kept):
     ```
     .status="actioned" | .resolved=$ts | .superseded_by=$new | .resolved_by=("supersede:"+$sid)
     | .evidence=("superseded by class-B "+$new+" (a judgment call with a status-quo course)")
     ```
     This follows the precedent the research kit already uses (`scripts/research-kit/lib/gate_sweep.py:452-466`,
     `cc_decide("action", …, "--evidence", "…packet superseded")`) and the lead's own manual re-file at
     18:31:35Z (`DEC/e869fac7eb34.evidence`, `maps/incident-replay.md:155`).
   - Order: new packet first, then the old transition. If the transition fails, the old C stays open and ⛔
     stays: fail toward today.
   - If the B packet already exists (an idempotent re-open), the old transition is still attempted, and
     it is a no-op when `superseded_by` already equals the new id.
2. **Mark it gates-all, or narrow it**: `cc-decide regate <id> --gates all|"<item>" --why-gated "<line>"`.
   - It appends `{sid,ts,gates,why}` to `.regates[]`, following the `recheck` precedent (`bin/cc-decide:411-492`): append-only, every refusal leaves the file byte-identical.
   - Refused unless the packet is open, class C, and filed by this sid.
   - The effective gates are those of the last regate (§2.4).
   - It exists because a filer who typed `--gates "everything"` or mis-scoped otherwise has no update verb (`:323-325`).
3. **Do the work.** The ledger state then changes on its own: dirt is committed, a DoD box is checked, or the loop's end is recorded.

### 2.6 Ruling search at `open` (goal c), stderr only

`ruling_hint <what> <class>` runs on class B and C opens and on the class-C refusal path. It never changes
stdout or the exit code: stdout stays exactly the id, because `gate_sweep.py:161-163` and
`lr-reset-poller.sh:1179-1196` parse it (`maps/cc-decide.md:206`).

- **Who pays:** only interactive sessions. It runs only when `CLAUDE_CODE_SESSION_ID` (or
  `CLAUDE_SESSION_ID`) is set and `CC_DECIDE_RULING_HINT != 0`.
  - Daemons (`autonomy-sweep`, `lr-reset-poller`) and every bats suite that unsets the session ids (`tests/cc-decide.bats` setup, `tests/wrap-ledger.bats` setup, `maps/test-infra.md:224-230`) pay nothing.
  - Nothing writes to the live `memory-search.jsonl` from a test with a real `HOME`.
  - `hooks/anti-deference-nudge.sh` `open_packet_B` (`:130-137`) runs inside a Stop hook and discards stderr, so it prefixes `CC_DECIDE_RULING_HINT=0` (constraint: skip the Stop-hook path, about 0.7 s).
- **Engine:** `cc-memory-search --decisions --json --top 3 -- "<what>"`, a new corpus mode (§7.3), under a
  3 s bound (`CC_DECIDE_HINT_TIMEOUT_S`, measured 0.73 s end to end, `maps/ruling-discovery.md:169`). The
  bound binary is `timeout` or `gtimeout`. If neither exists, or the call errors or times out, nothing is
  printed (fail open).
- **Output:** at most 2 lines, strongest last.
  - When top-1/top-2 BM25 ≥ 1.5: `LIKELY ALREADY RULED — <id> (<class>, <status> <date>; <its default if expired-actioned, else its evidence, 120 chars>)`. Otherwise one `similar answered packet(s)` line.
  - The 1.5 cut separated 3 true priors from 4 non-priors on 7 cases, but it was fitted on those same cases. It fires on 113 of 632 historic opens. About 20 of the last 25 flags read as the same subject (`maps/ruling-discovery.md:172-189`; estimated, probably overfit). Hence "LIKELY" and never a refusal.
- **Measured effect on B13** (`maps/ruling-discovery.md:174-175`):
  - decision 1 → `eb3dbe1e5e94` first, ratio 2.88 (the same fork, its default fired 2026-10-15T15:06:34Z; I re-read the packet with `jq -c`: `status expired-actioned`, `default_if_no_veto "keep looping until dry (the scope as written)"`);
  - decision 2 → `a247b7288149` first, ratio 1.62.
- **Audit:** one IDL row per printed hint, `{tool:"cc-decide",verb:"ruling-hint",top1,ratio,grant}`, so the hint's precision can be measured later (`maps/ruling-discovery.md:297-298`).

### 2.7 Standing-grant hint (goal d at the point of asking)

`grant_hint` reads `${CC_STANDING_GRANTS:-$(dirname "$(self_path)")/../config/standing-grants.json}`. The
`self_path` resolution is the precedent at `bin/cc-decide:429`. For each unrevoked grant whose
`match_terms[]` occurs (case-insensitively) in `--what`, it prints

```
cc-decide: COVERED BY STANDING GRANT <id> — <capability>. Inside its envelope (<conditions>) act with no packet; outside it (<excludes>) ask as usual.
```

It prints after the similar-packets line and before the id. It never refuses, because a Codex question
outside the envelope, such as a247's "pay per use" API option, matches the same terms
(`maps/ruling-discovery.md:324-327`). For `290215743799` the terms `codex`, `openai` and `chatgpt` all
hit (the `what_plain` at `maps/incident-replay.md:167`).

### 2.8 Stderr cross-checks on class C (advisory, never a refusal)

- **Hard category vs the router.** When `category ∈ {self-mod,money,permission,credential,destructive}` and
  `scripts/gate-classify.sh "<what>"` returns B, print
  `cc-decide: gate-classify finds no hard surface in this text; if this is not a <category> gate, it is class B`.
  Measured on today's packets (`bash scripts/gate-classify.sh "$(jq -r .what_plain …)"`):
  `e869fac7eb34` → B, `290215743799` → B, `a247b7288149` → B (a money false negative), `d610f8473106` → C.
  So it is printed, never enforced: the router misses real money and self-mod gates
  (`maps/legit-stops.md:112-126`).
- **`pick` with a status-quo option.** When `category=pick` and any option label or outcome matches
  `\b(keep|continue|leave|as[- ]is|no change|unchanged|status quo|stays?|today'?s|current)\b`, print
  `cc-decide: option '<label>' reads as the status quo ("<outcome, 80 chars>"); a question with a status-quo course is class B with that course as --default`.
  On e869 it fires on `no::keep running rounds…` (`maps/incident-replay.md:141-143`). It is a regex
  over operator-facing text, so stderr only (constraint: classifier output never refuses).

### 2.9 Header and usage text

- `bin/cc-decide:13-19` becomes:
  ```
  #   B  QUEUE-FOR-REVIEW — a judgment call with a status-quo course (the frozen scope, today's
  #      behaviour) or external info the values don't settle: carries default_if_no_veto +
  #      veto_deadline; the default FIRES at the deadline and the filer keeps driving meanwhile.
  #   C  HARD-BLOCK (human-only) — --category self-mod (C10) | money (C6) | permission (a denial) |
  #      credential | destructive (prod data / destructive migration) | escalation (a surface a rule
  #      or the repo's CLAUDE.md reserves: auth/session, nav pattern, DB timeout, production deploy,
  #      outbound send/publish, data egress outside a standing grant) | pick (new options, NO
  #      status quo, the next step builds on it). WAITS, has NO default; carries --gates all|<item>
  #      and --why-gated. Only a gates-all packet makes the filer's ⛔ (wrap-ledger).
  ```
- `:103-104` ("A class-C packet is the ⛔ rung: it ends a session's turn holding work") becomes "A
  class-C packet that gates all remaining in-scope work is the ⛔ rung; one that gates part leaves the
  session driving the rest (wrap-ledger § SCOPE FLOOR)" (constraint: change this comment in step with the
  rules).
- The usage block at `:22-36` gains the four flags, the `regate` verb and `list --blocking`.

### 2.10 Producers that must change in the same land

| Producer | Change |
|---|---|
| `scripts/research-kit/lib/gate_sweep.py:119-163` `open_packet` | For class C, pass `--category pick --gates "<decision id>" --why-gated "research-program operator gate <did> (§5.6)"`. Program sessions are exempt from the floor anyway (§4.3) |
| `hooks/anti-deference-nudge.sh:131` | Prefix the call with `CC_DECIDE_RULING_HINT=0` (class B, which is unaffected by the C schema) |
| `scripts/ship-land.sh:649-700` (writes JSON directly, bypassing `open`) | None. Absent `gates` is all, and `.producer` is hard, which is correct for a land block |
| `scripts/limit-recover/lr-reset-poller.sh:1156-1199` | None (class B, no session id, so no hint) |
| Tests: 20 `C_OK` uses (`tests/cc-decide.bats:61`), the `open_blocking` helper (`tests/wrap-ledger.bats:1831-1834`), and about 42 other literal `open --class C` sites in 7 suites | Measured: `grep -c C_OK tests/cc-decide.bats` gives 20; `grep -rn 'open --class C' tests/*.bats \| grep -v C_OK \| wc -l` gives 42. They gain `--category destructive --gates all --why-gated "test"`, so every existing ⛔ pin keeps its meaning |

---

## 3. Back-compat with the store (691 packets, `maps/cc-decide.md:85`)

| Population | Measured count | Read as | Effect |
|---|---|---|---|
| Open class C, no `gates` | 48 across 23 sessions (`maps/wrap-ledger.md:66`) | `gates_all=true`, `gate_hard=false` (no category) | **⛔ unchanged.** New: if that session also has ungated scope (§4.2), one challenge turn per decision set (§5.1). Its legacy `category=""` also makes it eligible for `--supersedes` by its own filer |
| `shipland-esc-*` | 7 (`maps/legit-stops.md:141`) | `.producer` ⇒ hard, gates all | Unchanged, never challenged |
| Terminal packets (actioned, vetoed, expired-actioned) | 633 (`maps/cc-decide.md:195`) | — | Ruling-search corpus (§7.3), minus any with `superseded_by` |
| Open class B | 10 | — | Unchanged (B never counted for ⛔, `scripts/wrap-ledger.sh:47-49`) |
| Packets whose `.options` are strings (`ship-land.sh:686-690`, July) | 19 jq errors in a naive reader (`maps/cc-decide.md:103`) | the corpus builder guards `type=="object"` | No change to them |

There is no migration and no rewrite (inv7). Every new reader treats an absent field as today's
behaviour:

- the ledger's jq treats a missing `gates_all` as true and a missing `gate_hard` as true (via `has()`, §4.1; not `//`, which would also turn `false` into true), so a mid-fast-forward old `cc-decide` view yields today's ⛔ and no challenge;
- consumers read an absent machine field as `none` or `0` (`maps/wrap-ledger.md:263-266`).

---

## 4. `scripts/wrap-ledger.sh`

### 4.1 `count_blocking_decisions` (`:1502-1564`): three counts and two strings, same fork

The jq at `:1527-1546` keeps `$mine`/`$ask` and adds the following, before the free-text cell (TSV-collapse
discipline, `:1514-1520`):

```jq
# NOT `.gates_all // true`: jq's `//` also replaces FALSE, so every part-gating packet would read as all.
def vall:  (if has("gates_all") then .gates_all else true end);    # an old cc-decide view ⇒ today's ⛔
def vhard: (if has("gate_hard") then .gate_hard else true end);    # an old cc-decide view ⇒ no challenge
| ($ask | map(select(vall))) as $all
| ($all | map(select(vhard))) as $allh
| ($ask | map(.id // "?" | tostring) | sort | join(",")) as $ids
| ($ask | map(select(vall | not) | (.gates_effective // .gates // "" | tostring | gsub("[\\t\\r\\n]"; " ")))
        | join("; ") | .[0:200]) as $gp
| [ ($ask|length|tostring), ((($mine|length)-($ask|length))|tostring),
    ($all|length|tostring), ($allh|length|tostring),
    (if $ids == "" then "-" else $ids end), (if $gp == "" then "-" else $gp end),
    (…what_plain as today…) ] | @tsv
```

The read at `:1549` becomes `IFS=$'\t' read -r n u na nah ids gp what`. The digit guards at `:1551-1552`
extend to `na` and `nah`, and any non-digit gives `BLOCKED_SRC=error` exactly as today. `ids` and `gp`
fold `-` to `""`. The new globals are `BLOCKED_ALL`, `BLOCKED_ALL_HARD`, `BLOCKED_IDS` and
`BLOCKED_GATES`, all 0 or empty on every fail-open path (`:1503`, `:1508-1511`, `:1547`). The fork count
is unchanged: one.

### 4.2 The loop-scope floor: session-scoped, computed before the ladder

- **Inside the DoD loop (`:913-944`).** Accumulate the already-filtered text:
  `_WL_DOD_STREAM="${_WL_DOD_STREAM}${_wl_ff}"$'\n'`. When `dod_filter_for` is absent, use the raw file:
  `$(<"$_wl_df")`, which the session filter below makes safe. This adds no fork per file.
- **New `compute_loop_floor`.** It is called after `_wl_resolve_sid` (`:960`) and `compute_research`
  (`:2594`), and before `count_blocking_decisions` (`:2603`). If `compute_research` did not run (not
  machine/full mode) and the loop reads `own`, it calls `compute_research` itself (one fork, only then).
  ```bash
  LOOP_SCOPE=0; LOOP_OPEN=0; LOOP_SRC="skip"; LOOP_HEAD=""
  compute_loop_floor() {
    case "${WRAP_LOOP_FLOOR:-on}" in off|0|no|OFF) LOOP_SRC="off"; return 0 ;; esac
    [ -n "$SID" ] || { LOOP_SRC="none"; return 0; }
    local r
    r="$(printf '%s\n' "$_WL_DOD_STREAM" | awk -v sid="$SID" '
      BEGIN { re = "(^|[^a-z-])(loop|repeat|iterate|keep (going|looping|running))[ \t]+until([^a-z]|$)|until[ \t]+(dry|nothing new|a round confirms)" }
      /^## / { own = (index($0, " · session=" sid) > 0); next }      # the capture header (dod-persist.sh:181-182)
      own && index($0, "Scope (frozen):") { fz = $0; dn = 0; next }   # newest OWN contract wins (append-only store)
      own && index($0, "Scope (done):")   { if (fz != "") dn = 1; next }
      END { if (fz == "") { print "none"; exit }
            lp = (tolower(fz) ~ re); h = fz; sub(/^.*Scope \(frozen\):[ \t]*/, "", h)
            printf "%s\t%d\t%s\n", (lp ? (dn ? "done" : "own") : "n-a"), lp, substr(h, 1, 80) }' 2>/dev/null)" \
      || { LOOP_SRC="error"; return 0; }
    IFS=$'\t' read -r LOOP_SRC LOOP_SCOPE LOOP_HEAD <<< "$r"
    [ "$LOOP_SRC" = own ] && [ "$RESEARCH_PROGRAM" != none ] && LOOP_SRC="research"
    case "$LOOP_SRC" in own) LOOP_OPEN=1 ;; none|n-a|done|research) LOOP_OPEN=0 ;; *) LOOP_SRC="error"; LOOP_OPEN=0 ;; esac
  }
  ```
- **Why the regex is tight.** `loop until` matches 1 of 362 frozen lines in the live store, and
  `repeat until` 1 of 362. Looser words false-positive ("dry-run", "until landed",
  `maps/wrap-ledger.md:174-180`, measured).
- **Why session-scoped.** DoD files are keyed by repo, not session (`maps/wrap-ledger.md:123-126`). An
  unscoped floor would turn every later session in agent-context-sync 🔧 forever (alarm polarity,
  `scripts/wrap-ledger.sh:49-52`).
- **End markers.**
  - A newer own `Scope (frozen):` that is not a loop gives `n-a`.
  - An own `Scope (done): <evidence>` gives `done`. `dod-persist.sh set` must accept that prefix (§5.6).
- `UNGATED=$(( REMAINDER + LOOP_OPEN ))`, computed once before the ladder.

### 4.3 The ladder (`:2603-2625`) and the ✅-eligible branch

```diff
 count_blocking_decisions
-if [ "$BLOCKED" -gt 0 ]; then
+if [ "$BLOCKED_ALL" -gt 0 ]; then                    # a decision that gates ALL ⇒ ⛔, outranks everything (as today)
   RUNG="⛔"; …READOUT exactly as :2605-2609…
+elif [ "$BLOCKED" -gt 0 ] && { [ "$DIRTY" -eq 1 ] || [ "$UNGATED" -gt 0 ]; }; then
+  RUNG="🔧"; READOUT="🔧 Decision open, not gating — ${BLOCKED} open decision(s) of yours gate only: ${BLOCKED_GATES}; keep driving ${_wl_ungated_words}: the frozen scope is the course until answered."
+elif [ "$BLOCKED" -gt 0 ]; then                      # gates part, but the ledger sees nothing else ⇒ the stop stays valid
+  RUNG="⛔"; …READOUT as today…; [ -n "$BLOCKED_GATES" ] && READOUT="${READOUT} It gates only: ${BLOCKED_GATES} — drive anything else in your frozen scope first."
 elif [ "$DIRTY" -eq 1 ]; then …unchanged…
```

`_wl_ungated_words` is chosen from what holds: `${DIRTY_N} uncommitted change(s)`, `${REMAINDER} frozen-DoD
item(s)`, or `the loop ('${LOOP_HEAD}…')`.

In the ✅-eligible branch, add one arm after 🚀 (`:2685-2716`) and before the re-check ⛔ (`:2717`):

```bash
  elif [ "$LOOP_OPEN" -eq 1 ]; then
    RUNG="🔧"; READOUT="🔧 Loose ends — your frozen scope is a loop ('${LOOP_HEAD}…') with no end recorded; run the next round as scoped, or record the stop: ~/.claude/hooks/dod-persist.sh set \"Scope (done): <evidence>\"."
```

Ranking rationale:
- **⛔ stays above 📦 for every open class-C packet.** A packet that gates part, with only unlanded
  commits, reads ⛔, never 📦. So the ship floor (`hooks/session-continue.sh:1216`) is never armed over a
  land that may be the gated act (constraint; `maps/wrap-ledger.md:304-305`).
- **The loop arm sits below custody, resident, filed, unconvicted, close-floor and 🚀.** Those are
  cheaper or more urgent, and custody must win so in-flight lanes are awaited. It sits above the
  re-check ⛔ and 👤, because "a store write must not mask agent-drivable work" (`:2599-2602`).
- **No new glyph.** The parity test and four ladder docs are untouched (`maps/wrap-ledger.md:236-243`).
- **Existing pins.**
  - `tests/wrap-ledger.bats:1934-1961` ("⛔ outranks 🔧/📦") stay green, because `open_blocking` now passes `--gates all`.
  - The readout pins at `:1851` and `:1866-1867` grep substrings, and the ⛔ READOUT text is unchanged.

### 4.4 `SCOPE_FLOOR`: the one keep-working predicate

Computed after the ladder:

```bash
SCOPE_FLOOR="none"; SCOPE_FLOOR_WHY="skip"
compute_scope_floor() {
  case "${WRAP_SCOPE_FLOOR:-on}" in off|0|no|OFF) SCOPE_FLOOR_WHY="off"; return 0 ;; esac
  [ "$RESEARCH_PROGRAM" = none ] || { SCOPE_FLOOR_WHY="research"; return 0; }    # R:74-80
  [ "$UNGATED" -gt 0 ]           || { SCOPE_FLOOR_WHY="no-ungated"; return 0; }
  [ "$BLOCKED_ALL_HARD" -eq 0 ]  || { SCOPE_FLOOR_WHY="gates-all-hard"; return 0; }
  local m="none"
  case "$RUNG" in
    "🔧") { [ "$BLOCKED" -gt 0 ] || [ "$LOOP_OPEN" -eq 1 ]; } && m="drive" ;;
    "⛔") [ "$BLOCKED_ALL" -gt 0 ] && m="challenge" ;;                          # all gates-all packets are soft (pick/legacy)
  esac
  [ "$m" != none ] || { SCOPE_FLOOR_WHY="rung"; return 0; }
  [ "$CUSTODY_SRC" = skip ] && count_open_custody                                 # one cc-custody fork, only here
  [ "$CUSTODY_OPEN" -gt 0 ]      && { SCOPE_FLOOR_WHY="in-flight-custody"; return 0; }
  [ "$LANDING" -eq 1 ]           && { SCOPE_FLOOR_WHY="in-flight-land"; return 0; }
  SCOPE_FLOOR="$m"; SCOPE_FLOOR_WHY="$m"
}
```

- A 🔧 raised by `REMAINDER` alone, with no decision and no loop, stays `none`. That keeps session-continue's
  deliberate refusal to arm on an accumulated remainder (`hooks/session-continue.sh:997-1002`).
- `count_open_custody` normally runs only on the ✅-eligible path (`:2629`). Here it runs only when the floor
  would otherwise fire, so the extra fork is rare. As a side effect, `CUSTODY_*` reads true on those
  🔧/⛔ closes instead of `skip`, which completion-assert can only use to be more accurate.

### 4.5 Emit, memo, header

- **New `--machine` fields**, after `BLOCKED_SRC` (`:2908-2909`), so the BUSY splice position is untouched
  (`LIVE=` stays line 18, `:592`): `BLOCKED_ALL`, `BLOCKED_ALL_HARD`, `BLOCKED_IDS`, `BLOCKED_GATES`,
  `LOOP_SCOPE`, `LOOP_OPEN`, `LOOP_SRC`, `LOOP_HEAD`, `UNGATED`, `SCOPE_FLOOR` and `SCOPE_FLOOR_WHY`.
  `emit_full` prints `LOOP` and `SCOPE_FLOOR` rows. `rung_next` for 🔧 is unchanged.
- **Memo key** (`:637-650`): append `${WRAP_LOOP_FLOOR:-}|${WRAP_SCOPE_FLOOR:-}` and bump `v1|` to `v2|`
  (`:637`), because the emit shape changed (`maps/wrap-ledger.md:255-266`).
- **Header.** `:23` ⛔ becomes "an open class-C decision packet THIS SESSION filed that gates all remaining
  in-scope work (cc-decide's `gates_all` fold; absent `gates` = all)". `:24` 🔧 gains "∨ an open decision
  that gates part while ungated work remains ∨ an own loop scope with no end recorded". Add a § SCOPE FLOOR
  paragraph.

---

## 5. Hooks (only already-registered ones; no settings edit)

### 5.1 `hooks/session-continue.sh`: the one actuator

**(a) `scope_floor()`**, a fourth floor between the ship floor and the wake floor (`:1316-1328`):

```diff
     if ! _sf_json="$(ship_floor)"; then …; fi
+    if ! _scf_json="$(scope_floor)"; then
+      mark_blocked scope-floor              # completion-assert yields its ledger arm (:1275-1298 there)
+      printf '%s' "$_scf_json"; exit 0
+    fi
     if ! _wf_json="$(wake_floor)"; then …
```

```bash
scope_floor() { # → JSON to BLOCK (rc 1); rc 0 otherwise. Never fails.
  [ "${CC_SCOPE_FLOOR:-1}" = 1 ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local led="${SC_LED_CACHE:-}"; [ -n "$led" ] || led="$(read the ledger exactly as ship_floor does, :1204-1213)"
  [ -n "$led" ] || return 0
  local sf rung; sf="$(led_field "$led" SCOPE_FLOOR)"; rung="$(led_field "$led" RUNG)"
  case "$sf" in
    drive|challenge) : ;;
    *) # B-3: on ⛔ the stand-down is a DECISION, so it is logged (an absent field = an old ledger = silent)
       [ "$rung" = "⛔" ] && [ -n "$sf" ] && log_idl abstained "scope-floor-$(led_field "$led" SCOPE_FLOOR_WHY)" \
         "$(jq -cn --arg i "$(led_field "$led" BLOCKED_IDS)" '{rung:"⛔",ids:$i}')"
       return 0 ;;
  esac
  kill_switch_active && { log_idl abstained "scope-floor-kill-switch"; return 0; }
  …assignee abstain copied from ship_floor :1190-1197 (confirm rc 0|2 ⇒ log "scope-floor-assignee")…
  wf_teardown_marked && { log_idl abstained "scope-floor-teardown"; return 0; }
  # context high ⇒ boundary-handoff's recycle governs; never two opposite blocks on one Stop
  local up; up="$(jq -r '.used_pct // 0' "${CC_TELEMETRY_DIR:-/tmp/cc-telemetry}/${cur_sid}.json" 2>/dev/null)"
  case "$up" in ''|*[!0-9]*) up=0 ;; esac
  [ "$up" -ge "${CC_BOUNDARY_T:-73}" ] && { log_idl abstained "scope-floor-context-high"; return 0; }
  # background work of THIS cwd in flight (a workflow, a land, a lane runner); watchers are infra (session-busy.sh:166-186).
  # Bounded (CC_SCOPE_FLOOR_BUSY_TIMEOUT_S, default 2): this hook already hits its 5 s timeout on many loaded Stops
  # (:1094-1097). A probe that cannot answer in time reads "unknown" and the floor PROCEEDS — the latch bounds a wrong
  # fire to ≤2 turns, while abstaining under load would reproduce the B13 idle exactly when the box is busy.
  # A shell function cannot be handed to timeout(1), so a child bash sources the lib (seam name shared with
  # operator-readout.sh:2413) and calls it; no timeout binary ⇒ "unknown" ⇒ proceed.
  local _bzl="${SESSION_BUSY_LIB:-$_scd/lib/session-busy.sh}" _tb _bj=""
  _tb="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
  if [ -f "$_bzl" ] && [ -n "$_tb" ]; then
    _bj="$("$_tb" "${CC_SCOPE_FLOOR_BUSY_TIMEOUT_S:-2}" bash -c '. "$1" 2>/dev/null && sb_busy_jobs "$2"' _ "$_bzl" "$cwd" 2>/dev/null)" \
      && [ -n "$_bj" ] && { log_idl abstained "scope-floor-busy" "$(jq -cn --arg s "$_bj" '{job:$s}')"; return 0; }
  fi
  # ── latch: per (sid, sorted open class-C ids, own loop head), reset only by progress ──
  local ids lh setk prog sfile psid pset pprog pcnt ptot max
  ids="$(led_field "$led" BLOCKED_IDS)"; lh="$(led_field "$led" LOOP_HEAD)"
  setk="$(printf '%s|%s|%s' "$cur_sid" "$ids" "$lh" | "${CC_SHA256:-/sbin/sha256sum}" | cut -c1-16)"
  if [ "$sf" = drive ]; then
    prog="$(git -C "$cwd" rev-parse HEAD 2>/dev/null || echo '?'):$(git -C "$cwd" rev-parse "$(led_field "$led" TRUNK)" 2>/dev/null || echo '?')"
    max="${CC_SCOPE_FLOOR_MAX:-2}"
  else prog="-"; max=1; fi                                   # a challenge is asked ONCE per decision set
  sfile="${f}.scope"; read -r psid pset pprog pcnt ptot < "$sfile" 2>/dev/null || true
  { [ "$psid" = "$cur_sid" ] && [ "$pset" = "$setk" ]; } || { pprog=""; pcnt=0; ptot=0; }
  [ "$pprog" = "$prog" ] || pcnt=0
  case "$pcnt$ptot" in *[!0-9]*) pcnt=0; ptot=0 ;; esac
  [ "$pcnt" -ge "$max" ] && { log_idl abstained "scope-floor-latched" "{mode,ids,count}"; return 0; }
  [ "$ptot" -ge "${CC_SCOPE_FLOOR_TOTAL:-16}" ] && { log_idl abstained "scope-floor-budget" "{…}"; return 0; }
  printf '%s %s %s %s %s\n' "$cur_sid" "$setk" "$prog" "$((pcnt+1))" "$((ptot+1))" > "$sfile" 2>/dev/null \
    || { log_idl abstained "scope-floor-state-unwritable"; return 0; }      # FAIL CLOSED: no latch, no block
  …reason text below…
  log_idl fired "scope-floor" "{mode:$sf,ids,ungated,loop_open,count:$((pcnt+1)),total:$((ptot+1))}"
  jq -nc --arg r "$reason" '{decision:"block",reason:$r}'; return 1
}
```

Reason text (drive):

> 🔁 SCOPE FLOOR — you are going idle with in-scope work no open decision gates (${UNGATED words}). Open
> decision(s) ${ids:-none} gate only: ${BLOCKED_GATES:-nothing}. Drive the next ungated step now (a loop
> scope: run the next round as scoped — the frozen scope is the course until a decision is answered); never
> build the gated act itself. If a packet in fact gates everything left: `cc-decide regate <id> --gates all
> --why-gated "<why>"` and close. If the loop has met its stop condition: `~/.claude/hooks/dod-persist.sh
> set "Scope (done): <evidence>"`. (scope floor n/${max} at this commit; ${total}/${CC_SCOPE_FLOOR_TOTAL})

Reason text (challenge):

> 🔁 SCOPE FLOOR (asked once) — ${ids} gate(s) ALL remaining in-scope work by your declaration
> (category pick, or a packet filed before gates existed), yet your frozen scope still shows ungated
> work (${UNGATED words}). A pick gates only what is built on it; a question about when a loop stops, or
> whether to change the scope, never gates the scope it would change. If the next in-scope step truly
> builds on the answer, reply with one line naming that step and stop. Otherwise re-file it:
> `cc-decide open --class B --supersedes <id> --what … --default "<the frozen-scope course>"
> --default-effect no-change --deadline <ISO> --conviction N --receipt R`, and drive the next step.

**(b) Intake capture (goal e).** This fills the store gap: the B13 scope reached the DoD store only at
20:15:35Z (`maps/wrap-ledger.md:30-34`). Placement is at the top of the no-sentinel branch (`:1293`),
before `mechanical_arm`, so the ledger read on the same Stop already sees the capture:

```bash
dod_intake() {   # best effort; never blocks, never fails the hook
  [ "${CC_DOD_INTAKE:-1}" = 1 ] && [ -n "$cur_sid" ] && [ -n "$TP_MECH" ] || return 0
  grep -qxF "$cur_sid final" "${f}.intake" 2>/dev/null && return 0
  local dp="$_scd/dod-persist.sh" rc; [ -f "$dp" ] || return 0
  ( cd "$cwd" 2>/dev/null && CLAUDE_CODE_SESSION_ID="$cur_sid" bash "$dp" intake "$TP_MECH" ) >/dev/null 2>&1; rc=$?
  case "$rc" in 0|4) printf '%s final\n' "$cur_sid" > "${f}.intake" 2>/dev/null || true ;; esac   # 3 = retry next Stop
}
```

- **Cost.** One `bash` plus a `jq` over at most the transcript's first 4 MiB, until the capture lands.
  After that it is one `grep` of a marker. Measured: the scan that finds `TX:14` in the first 2 MB took
  0.042 s wall (`time (head -c 2000000 TX | jq -c 'select(.type=="user" …)' | head -3)`).

**(c) Mechanical arm on ⛔ with own dirt** (`:1103`). Change `[ "$rung" = "🔧" ] || return 1` to
`case "$rung" in "🔧") ;; "⛔") [ "${CC_MECH_BLOCKED:-1}" = 1 ] && [ "$(led_field "$led" DIRTY)" = 1 ] || return 1 ;; *) return 1 ;; esac`.

- R:38's "commit in-progress work first" is then enforced even under a genuine gates-all stop.
- It is bounded by the existing `CC_MECH_MAX` and `CLAUDE_CONTINUE_MAX`, and it self-clears on commit (`:1118-1154`).
- Committing is never the gated act; landing is.

**(d) Text.**
- `:14` and `continue_reason` `:1368` change "blocked on the user (⛔)" to "blocked on a decision that
  gates all remaining work (⛔)".
- The header gains a § SCOPE FLOOR paragraph listing its LOGGED and SILENT exits, following the
  `:64-79` discipline.

### 5.2 `hooks/completion-assert.sh`: no new blocker

- **Log only.** At `:1231` the exoneration token becomes `blocked-answered:ungated=<UNGATED>`, so the
  census can count ⛔ closes that held ungated work. The spare itself is unchanged: the constraint keeps
  `blocked-answered` and the pins at `tests/completion-assert.bats:1265-1278` and `:2579`.
- **One fact** beside `CLOSE_FLOOR` (`:1142-1144`) for done-claims only:
  `LOOPO="$(lfield LOOP_OPEN)"; [ "$LOOPO" = 1 ] && ! _ca_assignee && { contra=1; facts="${facts}your frozen scope is a loop ('$(lfield LOOP_HEAD)…') with no end recorded — run the next round, or record the stop with dod-persist.sh set \"Scope (done): <evidence>\"; "; }`.
  - It fires only behind this hook's existing predicate: a done-assertion or tell, plus a contradiction (`:13-21`).
  - It is bounded by the existing `assert` cap and latch (`:1714-1724`).
  - It cannot reach the B13 "❌ no" closes, which abstain at `:469-471`. That is by design: the actuator is session-continue.

### 5.3 `hooks/operator-readout.sh`: render, and give the supervisor its oracle

- The 🔧 `parts` list (`:1509-1514`) gains two terms: `[ "$(lf LOOP_OPEN)" = 1 ] && parts+="loop scope open
  ('$(lf LOOP_HEAD)…')"`, and, when `BLOCKED>0` on 🔧, `"N decision(s) open, gating only: $(lf BLOCKED_GATES)"`.
  Without them the renderer drops the new cause (the defect class recorded at `:1480-1488`).
- The packet board label (`:1156-1190`, `$cls`) becomes `C/<category or legacy>/<all|part>`, so a
  "stop the loop?" question tagged `money` is visible at a glance (§11).
- The `steps-surfaced` IDL row (`:2537-2539`) adds `scope_floor`, `scope_floor_why`, `blocked_ids`,
  `loop_open` and `ungated`, all read with `lf` from the ledger it already holds. That row is the
  supervisor's oracle (§6). The live shape today is measured:
  `{"ts":…,"hook":"operator-readout","sid":"666022fd-…","disposition":"fired","reason":"steps-surfaced","rung":"🔧",…}`
  (`grep -F 666022fd ~/.claude/autonomy/idl.jsonl | grep -F steps-surfaced | tail -1`).

### 5.4 `hooks/dispatch-assert.sh`: text only

At `:237` and `:269`, "`cc-decide open --class C --what "…"` if it is a decision" becomes "`cc-decide open
--class B --what "…" --default "<the status-quo course>" --default-effect no-change --deadline <ISO>` if it
is a decision (class C only with `--category self-mod|money|permission|credential|destructive|escalation|pick
--gates …`)". Same edit in `hooks/lib/why-tier.sh:313` and `commands/wrap.md:140-144`.

### 5.5 `hooks/anti-deference-nudge.sh`: one env prefix, nothing else

- `open_packet_B` (`:131`) calls `CC_DECIDE_RULING_HINT=0 "$decide" open …`.
- **No** phrase is added to `TELLS`: "need your call" is the mandated ⛔ readout (`R:92`,
  `scripts/wrap-ledger.sh:2607`) and is pinned silent (`tests/anti-deference-nudge.bats:706-717`).
- No hold arm. The replay shows phrase arms miss F2/F3 (`maps/incident-replay.md:28`), and the actuator
  is session-continue.

### 5.6 `hooks/dod-persist.sh`: `Scope (done):` and an `intake` mode

- `:487`: `case "$scope" in *"Scope (frozen):"*|*"Scope (grown):"*|*"Scope (done):"*) ;;`, so a done line is
  stored verbatim. Today it is rewritten to `Scope (frozen): Scope (done): …`, which would make it the new
  contract (`maps/wrap-ledger.md:186-190`).
- New mode `intake <transcript>` (the producer stays the single writer of the store, `:20-23`):
  1. If any block in `dod_read_files` for this cwd carries ` · session=$CLAUDE_CODE_SESSION_ID`, exit 0.
  2. Otherwise, take the **first** `Scope (frozen):` line from the first 4 MiB of the transcript, reading
     **only**:
     - (i) `type=="user"` records that are not `isMeta`, not `tool_result`, and either have
       `origin.kind=="human"` or (with no origin) are not a machine envelope (the `machine_env` list at
       `scripts/wrap-ledger.sh:1590`);
     - then (ii) the session's own assistant `text` blocks (never `tool_use` inputs, never tool results, never attachments).
  3. If found, `persist_dod "$f" "$line" "$PWD" "intake" "$sid"` and exit 0. If not found and the
     transcript is under 4 MiB, exit 3 (retry). Otherwise exit 4 (final).
- **Why "first", never "newest".** The newest transcript `Scope (frozen):` line is a lane brief in a tool
  result (`TX:3875`; `maps/incident-replay.md:25`). Measured: in B13 the first qualifying record is
  `TX:14`, `origin.kind=="human"`, carrying "Scope (frozen): loop until dry. … repeat until a round
  confirms nothing new …" (jq over `TX` lines 1-20, and `grep 'Scope (frozen):'` on `TX:14`'s text).

### 5.7 `hooks/boundary-handoff.sh`: deliberately unchanged

- Free-win still requires ✅ (`:658`). After D3 the B13 class-B re-file reads 🔧 (loop arm), not a false ✅,
  so free-win can no longer advise a recycle over an unfinished loop (control C5, `maps/incident-replay.md:441`).
- A free-win on ⛔ would launder the decision, because the successor counts only its own sid's packets
  (`scripts/wrap-ledger.sh:1529`). Its wording would also be false ("no operator step filed by this
  session", `hooks/boundary-handoff.sh:958`, `:994`; `maps/stop-hooks.md:257-262`).
- The scope floor abstains at ≥T fill, so the two never send opposite blocks on one Stop (§5.1(a)).

---

## 6. `scripts/lead-supervisor.sh`: waking the session itself (goal f)

After the last idle Stop no Stop hook can act; only an off-Stop actor can (`maps/incident-replay.md:423`).
The send path exists: `cc-notify <sid>` queues the line, then wakes the session by watcher exit or by socket.
That path worked on this very session at 20:27:36Z (`maps/wake-path.md:124-138`).

**`nudge_subject <sid> <tel_age> <transcript_age>`**, a sibling of `advise_subject` (`:546-565`), is called
from the STALL? branch after both exemptions (permission beacon `:1067`, operator-adopted hold `:1077`),
right after `page "$sid" "STALL?" …` at `:1089`:

```bash
SUBJECT_NUDGE="${CC_SUP_SUBJECT_NUDGE:-1}"          # 1 | shadow | 0
NUDGE_MAX="${CC_SUP_NUDGE_MAX:-3}"; NUDGE_BACKOFF_S="${CC_SUP_NUDGE_BACKOFF_S:-7200}"; NUDGE_PER_SWEEP="${CC_SUP_NUDGE_PER_SWEEP:-3}"
nudge_subject(){
  [ "$SUBJECT_NUDGE" = 0 ] && return 0
  [[ "$1" =~ ^[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}$ ]] || return 0      # same guard as :550
  [ "${_NUDGES_THIS_SWEEP:-0}" -lt "$NUDGE_PER_SWEEP" ] || return 0
  # ORACLE: the subject's last operator-readout row (the ledger's own predicate, §5.3). Absent ⇒ no nudge.
  local row sf ids key mk prev pcnt plast now wait out rc verdict reason
  row="$(sup_bounded 3 tail -c 8388608 "$IDL" | grep -F "\"sid\":\"$1\"" | grep -F '"reason":"steps-surfaced"' | tail -1)"
  sf="$(printf '%s' "$row" | jq -r '.scope_floor // "none"' 2>/dev/null)"
  case "$sf" in drive|challenge) ;; *) return 0 ;; esac
  ids="$(printf '%s' "$row" | jq -r '.blocked_ids // ""')"
  key="$(printf '%s|%s|%s|%s|%s' "$1" "$(jq -r .rung <<<"$row")" "$ids" "$(jq -r '.loop_open // 0' <<<"$row")" "$sf" | "${CC_SHA256:-/sbin/sha256sum}" | cut -c1-16)"   # shasum-lint
  mk="$PAGEDIR/$1.nudged"; read -r prev pcnt plast < "$mk" 2>/dev/null || true
  [ "$prev" = "$key" ] || { pcnt=0; plast=0; }
  [ "${pcnt:-0}" -ge "$NUDGE_MAX" ] && return 0
  now="$(now)"; wait=$(( NUDGE_BACKOFF_S * (1 << (${pcnt:-0} > 0 ? pcnt - 1 : 0)) ))
  [ "${pcnt:-0}" -gt 0 ] && [ $(( now - ${plast:-0} )) -lt "$wait" ] && return 0
  : > "$mk.w" 2>/dev/null || return 0                                   # FAIL CLOSED: cannot record ⇒ send nothing
  if [ "$SUBJECT_NUDGE" = shadow ]; then printf '%s %s %s\n' "$key" "$((pcnt+1))" "$now" > "$mk"; idl subject_nudge_shadow "…"; return 0; fi
  out="$(sup_bounded "$SUP_NOTIFY_TIMEOUT_S" "$NOTIFY_BIN" "$1" "<text below>" 2>&1)"; rc=$?
  verdict="$(printf '%s\n' "$out" | sed -n 's/^cc-notify: verdict=\([a-z-]*\).*/\1/p' | tail -1)"   # cc-notify's own token, not cc-wake's
  reason="$(printf '%s\n' "$out" | sed -n 's/^cc-notify: .*reason=\([a-z-]*\).*/\1/p' | tail -1)"
  if [ "$rc" = 0 ]; then
    # a "wake-path-armed" delivery may be a DETACHED watcher that wakes nobody (wake-path §4.3): re-check after 1 h, not 2 h
    [ "$reason" = wake-path-armed ] && now=$(( now - NUDGE_BACKOFF_S + 3600 ))
    printf '%s %s %s\n' "$key" "$((pcnt+1))" "$now" > "$mk"
  fi
  rm -f "$mk.w"; _NUDGES_THIS_SWEEP=$(( ${_NUDGES_THIS_SWEEP:-0} + 1 ))
  idl subject_nudge "\"sid\":\"$1\",\"key\":\"$key\",\"attempt\":$((pcnt+1)),\"notify_rc\":$rc,\"verdict\":$(json_str "${verdict:-unreadable}"),\"reason\":$(json_str "${reason:-}"),\"scope_floor\":\"$sf\",\"ids\":$(json_str "$ids")"
}
```

Text (one line, because cc-notify collapses newlines; machine-authored, so it carries no operator
authority, `R:223`):

> ⏯ IDLE WITH UNGATED SCOPE (lead-supervisor, machine text addressed to THIS session; not an operator
> answer) — idle ~Nm. Your last close left in-scope work no open decision gates (decisions: <ids or none>;
> loop scope: <open|none>). Re-read your frozen scope and drive the next in-scope step now (a loop scope:
> run the next round as scoped; the frozen scope is the course until a decision is answered). If every
> remaining item truly waits on an operator-only act: `cc-decide regate <id> --gates all --why-gated "<the
> act>"` or `dod-persist.sh set "Scope (done): <why>"`, say which act in one line, and stop.

- **Routing.** It never goes through `page()` or `send_page`: that channel is dead (`CC_PAGE_TO=""`, no
  desk file; `:414-415`; `maps/wake-path.md:86-106`). No `--no-wake`, no `CC_NOTIFY_WAKE=0`, no
  `CC_WAKE=off`.
- **`.nudged` survives recovery.** `clear_page` (`:524`) and `clear_page_recovered` (`:583-609`) must
  **not** delete it. A key change (a packet answered, the scope ended) is the only reset; reap and GC drop it.
- **The 8 MiB tail covers the window.**
  - The live IDL was 9,907,277 bytes at about 21:24Z (measured, `ls -la`). It had grown from its 05:04Z
    rotation, which is about 0.6 MB/h (estimated from the size over 16 h).
  - So 8 MiB holds about 13 h of rows. The supervisor can see a session for at most 6 h anyway (`GC_S`, `:146`).
  - If a rotation drops the row, the nudge is skipped (fail closed).
- **Same parse fix for `advise_subject`.** `:557` parses with `grep -oE 'verdict=…' | head -1`, which picks
  up cc-wake's token (`maps/wake-path.md:255-259`). It gets the same `sed` parse.
- **Testing and deployment.** It is tested under `/bin/bash` 3.2, which launchd runs. The daemon picks the
  change up through its sha self-restart (`:92-104`), with no plist edit.

---

## 7. Standing operator grants (goal d)

### 7.1 `config/standing-grants.json` (new, tracked; the source of truth)

```json
{ "_what": "Standing operator grants: rulings a session acts on with no ask and no decision packet. Read by bin/cc-decide (grant hint) and bin/cc-memory-search (--decisions corpus); summarised one line each in CLAUDE.global.slim.md § API keys. Schema after docs/research/frontier-hard-2026-07-20/fr-04-authority.md:85.",
  "grants": [
    { "id": "xvendor-review-2026-10-24",
      "issued_at": "2026-10-24T18:11:47Z", "grantor": "operator",
      "verbatim_quote": "I thought you had autonomous zero human in the loop proactiveness and permissions to do this with accounts; didn't we do this for our truememory review hence getting the $100 codex plan just for these adversarial reviews from agents that are not our own claude model class?",
      "quote_source": "~/.claude-quaternary/projects/-Users-chrisren-Development-agent-context-sync/666022fd-ed3e-4e72-b293-7caae899d585.jsonl:4488",
      "builds_on": ["a247b7288149", "d610f8473106"],
      "capability": "add non-Claude reviewers or judges beside the Claude review, in any repo, unasked",
      "entrypoint": "~/.claude/scripts/xvendor-review.sh",
      "scope": { "repos": "*" },
      "conditions": ["ChatGPT Codex subscription CLI only: codex exec -s read-only",
                     "input is a git archive export of committed code in a fresh tmp dir; never the working tree or the live home",
                     "no new call at >= 80% of the plan's weekly meter (Pro has a weekly window only)",
                     "never api.openai.com (no API key in the call's environment)",
                     "additive: Claude still verifies findings; routes no model-config.yaml slot (uncertified means unrouted, CODEX_ADVERSARIAL_SLOT_PROBE.md:25-31)"],
      "excludes": ["personal data: dictations, mail, guest rows (f2e2c22bb83e, e3876aac762d, bb16a9bc1350)",
                   "an export carrying a repo-listed escalation surface (e.g. a tenant name)",
                   "pay-per-token API use"],
      "match_terms": ["codex", "openai", "chatgpt", "gpt-", "cross-vendor", "non-claude", "another vendor", "other vendor"],
      "expiry": null, "revoked_by": null } ] }
```

### 7.2 `scripts/xvendor-review.sh` (new): the envelope in tracked code

The 80% meter guard exists today only in the untracked `~/.cache/agentsync-bring-back/b13/tools/xverify.py`
(`maps/ruling-discovery.md:241-245`). `xvendor-review.sh <repo> <prompt-file|-> [--rev <sha>]` does five
things:

1. It refuses unless `<rev>` (default `HEAD`) is a commit. It exports with `git -C <repo> archive <rev> |
   tar -x -C "$(mktemp -d "${TMPDIR:-/tmp}/xvr.XXXXXX")"`, so the export is never the working tree. Paths
   listed in an optional per-repo `.claude/xvendor-review.exclude` (pathspecs) are dropped, which lets a repo
   keep its escalation surface out mechanically.
2. **The meter.** It reads the newest `~/.codex/sessions/**/rollout-*.jsonl`'s last
   `rate_limits.primary.used_percent`, a weekly window on Pro (`reference-codex-chatgpt-plan-limits.md:19-21`).
   - At 80 or above (`CC_XVR_METER_STOP`) it refuses with rc 5.
   - An unreadable meter is refused (fail closed).
   - If no rollout exists yet it proceeds, with a stderr note.
3. It runs `env -u OPENAI_API_KEY codex exec -s read-only --skip-git-repo-check "<prompt>"` inside the
   export, bounded by `timeout`. It refuses if `codex login status` does not report a ChatGPT login
   (so never api.openai.com).
4. It prints the review on stdout and writes one IDL row
   `{tool:"xvendor-review",repo,rev,meter_before,rc}`.
5. It never runs on a dirty-tree-only change: committed code only, by construction.

This script does not get past the auto-mode permission classifier, which refused a Codex call as "data
exfiltration" at 18:17Z (`TX:4683`). An allow rule for it is a settings change, so the operator's act
(§13).

### 7.3 `bin/cc-memory-search --decisions` (new corpus mode)

`--decisions` replaces the default scope, as `--lessons` does (`bin/cc-memory-search:644`). Its corpus has
two parts:

- **Answered packets.** Every packet under `${CC_DECISIONS_DIR:-~/.claude/autonomy/decisions}` whose
  status is actioned, vetoed or expired-actioned, and that has no `superseded_by`. Each becomes a document:
  - `name` = id;
  - `description` = `<class> <status> <resolved[0:10]> · <default if expired-actioned else evidence[0:120]>`;
  - `body` = `what_plain`, the object options' outcomes (string options are skipped), `recommendation`, `default_if_no_veto` and `evidence`.
- **The standing grants**, one document each (`name` = grant id, `body` = capability, conditions and match terms).

The tokenizer, BM25 and logging stay in one place (`:440-500`, `:741-767`). It skips the 7.4 s
project-store glob (`maps/ruling-discovery.md:79-82`): 0.73 s end to end, measured on this corpus
(`:169`). It is also useful directly: `cc-memory-search --decisions stop the loop`.

---

## 8. Rule text (R, S, G) and the instruction budget

The user tier is over budget: 61,074 > 60,000 measured, against a one-in-one-out policy
(`maps/rules-text.md:185-189`; `config/instruction-budget.json:21`). Every addition below is paid for
in the same tier (§8.4). Each block is the full replacement text for the cited line(s).

### 8.1 `R` (`CLAUDE.rules.slim.10-session-close.md`)

R:4 — **cut** the last sentence ("Before writing or debugging a Stop hook, read the reference … which extend
the turn."). Its pointer moves into R:225, which already sends the reader to the same G section.
<!-- budget:R4 -->
```text
Drive in-scope work to a finished, verified, committed state (landed per the ship policy) without stopping to ask; surface everything else; end every write turn with one state readout taken from live reads (`~/.claude/scripts/wrap-ledger.sh`, or `/wrap`), not from memory. Stop hooks check facts only, never scope: `completion-assert.sh` blocks a done-claim the live ledger contradicts, and `operator-readout.sh` renders the operator's close block from disk as a `systemMessage`.
```

R:13-18 — **cut** three restatements:
- the 🚀 parenthetical, which repeats R:96;
- the background-verifier sentence, which repeats R:106 ("a marker only a background verifier advances …
  name it in one line and close on your own state");
- the "no operator step left unrun … 👤" sentence, which repeats R:97 and R:193.

G keeps all three (`G:854`).
<!-- budget:R13-18 -->
```text
  live layer's source — the landed sha **observable in the enforcing store**, not merely on trunk
  (else `🚀`). Any one unknown ⇒ not ✅; say which.
```

R:26 — append the loop end-marker (goal e). The parenthesis "(`dod-persist.sh` captures it)" becomes true
for the brief and the session's own text once the intake capture (§5.1(b)) lands.
<!-- budget:R26 -->
```text
Freeze the DoD at intake: the first time a task will write tracked files, restate the ask as one line, `Scope (frozen): …`, in the plan or else inline (`dod-persist.sh` captures it). Close-time completeness is a diff against that line, not a fresh judgment. If the scope cannot be reconstructed, stop and ask. A loop scope ("loop until …") stays open until `dod-persist.sh set "Scope (done): <evidence>"`.
```

R:38 — goal (a). This drops the session-wide "overriding auto-continue" (`maps/rules-text.md:57`).
<!-- budget:R38 -->
```text
| Needs a decision (destructive migration, auth, navigation pattern, DB timeout) or information | Commit in-progress work, file it, and keep driving every in-scope item it does not gate (a question that would change the frozen scope gates none of it); stop only when it gates all remaining in-scope work. |
```

R:39 — **cut** the PASS/FAIL clause, which R:72 states in full ("On PASS, append `Scope (grown): +<item>`
and execute. On FAIL, drop it … unless it passes the FILED test").
<!-- budget:R39 -->
```text
| Out-of-scope discovery | Follow-On Gate (below). Security or data-integrity issues: stop and surface now. |
```

R:68 — goal (c), and names `cc-decide open` for both classes:
<!-- budget:R68 -->
```text
- F2 well-researched: grounded in this session's disk-truth investigation or an equally verified source. If unverified, verify it; that is drivable work. A decision carries a number: state your conviction, in percent, in the course you would take. At or below 90%, research exhaustively, then implement if you are now above 90%; otherwise hand it to the operator with the number, the research receipt and the measured options in operator terms. Above 90% there is nothing to ask: implement. First look for a ruling (a standing grant, an answered packet `cc-decide open` prints, a fired class-B default, a purchase for the purpose, the operator's words this session); if one covers it, act and file class A citing it. `cc-backlog add --why-not-now "needs-human: …"` and `cc-decide open` refuse without `--conviction N --receipt PATH|"<cmd> => <output>"` and refuse N > 90. Inside an active research program, a timebox receipt satisfies the below-90% rule (exemption below).
```

The dropped clause, "`wrap-ledger.sh` counts an unconvicted ask of yours as your own 🔧", is printed by the
ledger itself whenever it applies (`scripts/wrap-ledger.sh:2669`), and G:657 keeps it.

R:92 — the ⛔ definition. The prescribed readout phrase is kept byte-for-byte.
<!-- budget:R92 -->
```text
- ⛔ Blocked: a decision that gates all remaining work, or information, is needed. `⛔ Blocked — need your call: <decision>.`
```

R:103 — goal (a)/(e):
<!-- budget:R103 -->
```text
Only ⛔ (a decision gating all remaining in-scope work), and 📦 in a repo whose own `CLAUDE.md` says landing spends money, may end a turn holding work.
```

R:160 — goal (b):
<!-- budget:R160 -->
```text
File a decision you are holding the moment you have it. A judgment call with a status-quo course is class B (`cc-decide open --class B --what <plain English> --default "<the status-quo course>" --default-effect no-change --deadline <ISO> --conviction N --receipt R`): its default fires at the deadline; keep driving meanwhile. Class C waits and needs `--category self-mod|money|permission|credential|destructive|escalation|pick`, `--gates all|"<the item it blocks>"`, `--why-gated` and two `--option`s; `wrap-ledger.sh` reads `⛔` only from your class-C packets that gate all. Re-file a mis-classed one with `--supersedes <id>`. An unfiled decision is invisible to the ledger.
```

R:189 — narrow "a real value fork":
<!-- budget:R189 -->
```text
- BLOCKED: a genuine operator-only gate (credential, sudo, destructive migration, a pick with no status-quo course). It is S1's `⛔` rung, stated as the decision you need. At the exhaustion close — every Follow-On Gate pass and every item at 90%+ conviction driven, only operator decisions left — itemize only the decisions this session drove to the wall, one line each, answer-first: the decision as a sentence, its conviction number, its measured options.
```

R:217 — **cut** only. Its semantics stay correct: ⛔ now means gates-all, so "clear on ⛔" is right. The
one ⛔ that still holds ungated work is the challenge, and both of its discharges either stop (one line) or
re-file, which makes the rung 🔧. The cap mechanics move to G, which already states them (`G:1129-1137`).
<!-- budget:R217 -->
```text
On 🔧, and only on 🔧, arm the continuation: `~/.claude/hooks/session-continue.sh set "<the one next step>"`; a Stop hook then feeds that step back as your next turn. Clear it with `~/.claude/hooks/session-continue.sh clear` as soon as the state becomes ✅ / 📦 / ⛔ / 📤, on a read-only turn, or when the kill-switch fires. Nothing bounds an agent-armed chain and the hook does not judge scope: the stop conditions are the kill-switch, the frozen DoD and your judgment. Within a turn, keep working rather than stopping on 🔧.
```

R:146 — **cut** the example, which repeats R:144's (`13 runnable now, 207 need your call`):
<!-- budget:R146 -->
```text
S1 carries one rung and states a conclusion, not a category. Neither it nor the verdict hedges, and nothing later withdraws either. If something is parked or is theirs, that is the rung (`📦` / `👤`); if it is immaterial, it stays out; unfiled work the Follow-On Gate passes that nobody drives makes S2 a no, "research only" or not.
```

R:225 — takes over R:4's Stop-hook pointer:
<!-- budget:R225 -->
```text
The measurements behind the close rules, and which Stop-hook output fields reach the model, are in ~/Development/claude-infrastructure/CLAUDE.global.md § Session Close Protocol; read it before writing a Stop hook or changing or disputing these rules.
```

### 8.2 `S` (`CLAUDE.global.slim.md`): one bullet appended to `## API keys`, after S:77

The grant goes in an existing section, which saves a heading. It sits beside the egress rule it contrasts
with: a new API host is an ask, while the Codex subscription CLI under this grant is not.
<!-- budget:S-grants -->
```text
- Standing grant, cross-vendor review (2026-10-24, builds on `a247b7288149`; records: `config/standing-grants.json`): unasked and with no packet, add non-Claude reviewers beside your Claude review via `~/.claude/scripts/xvendor-review.sh` (Codex plan, `codex exec -s read-only` on a `git archive` export of committed code, no new call at 80% of the weekly meter, never api.openai.com). Personal data or a repo-listed escalation surface still needs an ask; it routes no `model-config.yaml` slot.
```

`workflow-lean` subagents load no rules (`S:117`), so they never see this. They are read-only slots that
do not ask the operator anything, and the `cc-decide` grant hint (§2.7) covers any session that does ask.

### 8.3 `G` (`CLAUDE.global.md`, not loaded, but the only text under the `full` variant, `install.sh:1117`)

| Line | Change |
|---|---|
| G:605 | Same sentence as new R:38, in G's bold style |
| G:657 | Insert the R:68 ruling-search sentence after "…measured options in operator terms." Change "`cc-decide open --class C` both REFUSE" to "`cc-decide open` (classes B and C) REFUSE" |
| G:714 | ⛔ row: "needs a **decision** that gates all remaining in-scope work (destructive migration / auth / nav / timeout) or **info**" |
| G:766-767 | Same as new R:103 |
| G:1000-1003 | Replace the Corollary with: "**Corollary — a decision you are holding is a packet, and its class says whether it stops you.** A judgment call with a status-quo course is class B (`--default "<status-quo course>" --default-effect no-change --deadline <ISO>`): the default fires and you keep driving. Class C is reserved (`--category …`) and declares `--gates all\|<item>`; `wrap-ledger.sh` computes `⛔` only from your own open class-C packets that gate all (absent `gates` = all, so packets filed before 2026-10-24 keep their ⛔), and a part-gating one leaves you on 🔧 while the ledger sees ungated work (dirt, a DoD box, an own loop scope)." Keep the conviction-protocol parenthetical. Add the B13 incident as the measured reason (`maps/incident-replay.md:56-70`) |
| G:1042 | "a real value fork" becomes "a pick with no status-quo course", and append "that the remaining in-scope work waits on". The sentence "'the one decision you need' describes the ordinary mid-work `⛔`" becomes "a mid-work `⛔` is a decision that gates everything left; a part-gating decision is not a `⛔`" |
| G:1126-1128 | Add after "those MUST stop": "(`⛔` means a decision that gates all remaining in-scope work; a part-gating decision reads 🔧 and you keep the continuation armed)" |
| G § Stop-hook arms (near G:854) | Add the **Scope floor** paragraph: predicate `SCOPE_FLOOR`, latch per (sid, open class-C ids, loop head) reset only by a new HEAD or trunk commit, `CC_SCOPE_FLOOR_MAX`=2, `CC_SCOPE_FLOOR_TOTAL`=16, the one-shot challenge, every abstain, and the intake capture |
| G near the DoD freeze text (G:592-595) | The `intake` capture and the `Scope (done):` end marker, with the TX:14/TX:3875 measurement as rationale |
| G near G:374 (Frontier Tier Routing) | A full `## Standing operator grants` section: the S text plus the verbatim quote, the `a247b7288149` history, and why `CODEX_ADVERSARIAL_SLOT_PROBE.md:227-228` is not contradicted (additive reviewer, no routed slot) |

### 8.4 Budget accounting (measured)

Measured with `python3 -I`, reading this file's `budget:` blocks and the current lines of `R`/`S`, in UTF-16
code units, each line counted with its newline:

| Block | Old units | New units | Delta |
|---|---|---|---|
| R:4 | 692 | 480 | −212 |
| R:13-18 | 630 | 149 | −481 |
| R:26 | 310 | 406 | +96 |
| R:38 | 171 | 307 | +136 |
| R:39 | 260 | 110 | −150 |
| R:68 | 896 | 973 | +77 |
| R:92 | 92 | 124 | +32 |
| R:103 | 103 | 151 | +48 |
| R:146 | 397 | 333 | −64 |
| R:160 | 518 | 676 | +158 |
| R:189 | 442 | 457 | +15 |
| R:217 | 733 | 525 | −208 |
| R:225 | 199 | 251 | +52 |
| S grant bullet (new) | 0 | 495 | +495 |
| **R net / S net / total** | | | **−501 / +495 / −6** |

- **Tier and per-file limits.** The user tier does not grow (−6), so one-in-one-out holds. Per file, R moves
  away from its 40k cap and S uses 495 of its 11,497 headroom (`maps/rules-text.md:180-181`).
- **What the cuts cost.** Every cut is a restatement of a sentence that stays in R or S (named above), or
  rationale that G keeps.
- **Not counted.** `G` is not budgeted (`config/instruction-budget.json` `_deploy_sources`), so its twins
  carry the full wording and the rationale.

---

## 9. Goals (a)–(f)

| Goal | Mechanism |
|---|---|
| (a) keep working on every in-scope item an open decision does not gate | `--gates` on every class-C packet (§2.2). The ledger demotes a part-gating packet to 🔧 while it sees ungated work (§4.3). The `SCOPE_FLOOR=drive` actuator blocks the idle close (§5.1). R:38/R:103/R:189 and their G twins say the same (§8) |
| (b) judgment calls with a status-quo course → class B; C only for its reserve | `open --class C` refuses without a closed-enum `--category` and prints the ready class-B command (§2.2-2.3). `--supersedes` turns a mis-classed C into B in one state change (§2.5). R:160, the cc-decide header, dispatch-assert and why-tier text are updated |
| (c) find an existing ruling before asking | The `cc-memory-search --decisions` stderr hint on every session-filed B/C open and on the C refusal (§2.6), and the grant hint (§2.7). The F2 sentence (R:68) names the four ruling sources, including a fired class-B default |
| (d) standing grants where every session loads them | `config/standing-grants.json` (§7.1), one S bullet paid for by R cuts (§8.2, §8.4), `xvendor-review.sh` enforcing the envelope including the 80% meter (§7.2), the grant hint at `open` (§2.7) |
| (e) the close stack refuses a Blocked idle while ungated work remains, incl. a loop scope | Intake capture puts the contract in the store (§5.1(b), §5.6). `LOOP_OPEN` makes a loop scope ungated work (§4.2). ⛔ is only gates-all (§4.3). `SCOPE_FLOOR` drive or challenge blocks the close with a per-decision-set latch (§5.1). completion-assert convicts a done-claim over an open loop (§5.2) |
| (f) wake a stalled session itself | `nudge_subject` (§6) on the same ledger predicate, read from the operator-readout IDL row, sent by direct `cc-notify <sid>` (watcher or socket wake). Damped per decision state, at most 3 |

---

## 10. Infinite-loop and false-block analysis, per change

| Change | Can it loop? Bound | Can it false-block? Bound |
|---|---|---|
| `cc-decide` class-C refusal (§2.2) | No: a CLI call, not a hook | It refuses a **declaration's absence**, never a similarity score. A genuine hard gate files with three more flags; the recipe line names them. The cost is one re-run. The risk of losing the packet at STOP-ASK is mitigated by the copy-paste class-B command built from the caller's own arguments (§2.3). Producers: `gate_sweep.py` changes in the same land; ship-land bypasses `open` |
| Ruling and grant hints (§2.6-2.7) | No | No: stderr only, rc and stdout unchanged, 3 s bound, fail open. Only for sessions that carry an id |
| `--supersedes`, `regate` (§2.5) | No | A hard category, a foreign sid, a non-open or a producer packet is refused, so no gate weakens |
| Ledger ladder + `LOOP_OPEN` (§4) | No (a pure function of stores) | ⛔ → 🔧 happens only for a **declared** part-gating packet with visible work. Legacy packets read gates-all (⛔ unchanged). `LOOP_OPEN` is session-scoped (no inherited alarm), has an end marker the session writes in one action, and is 0 in an active research program. An unreadable store gives today's rung (`:1354-1356`). The new loop 🔧 can withhold operator-readout's ✅ certificate, which is the intended effect |
| `scope_floor` drive (§5.1) | **Bounded.** At most `CC_SCOPE_FLOOR_MAX`=2 forced turns per (sid, sorted open class-C ids, own loop head, HEAD:trunk). A no-progress re-close at the same commit is latched after 2. A new commit, which requires real work, re-arms. Hard total `CC_SCOPE_FLOOR_TOTAL`=16 per (sid, ids, loop head). An unwritable latch means no block (fail closed). The budget is never per session lifetime (the B13 budgets were spent two days earlier, `maps/stop-hooks.md:20-24`) and never per HEAD alone (`maps/stop-hooks.md:129-132`) | Abstains, each logged: kill switch, assignee, teardown, ≥T context fill, a busy job of this cwd (watchers are infra), and, at the ledger, custody open, a land in flight, a research program, a hard gates-all packet, or no ungated work. One block per Stop, the `.blocked` marker makes completion-assert yield, and boundary-handoff's free-win needs ✅ |
| `scope_floor` challenge | Exactly 1 per (sid, ids, loop head) | Only soft (pick or legacy) gates-all packets with visible ungated work. A legit pick that gates the next round costs one turn ("name the step and stop") |
| Intake capture (§5.1(b), §5.6) | No (no block; a marker ends it) | It can capture the wrong line only if the first operator or own-text `Scope (frozen):` is not the contract. It is session-scoped and appends only (dod-persist is INTEGRATE-only), and a later `dod-persist set` supersedes it |
| Mechanical arm on ⛔ + dirt (§5.1(c)) | Existing bound: `CC_MECH_MAX` × `CLAUDE_CONTINUE_MAX`, self-clearing on commit | Needs dirt this session wrote (`session_dirty_mine` rc 0) |
| completion-assert fact + log (§5.2) | Existing latch and `assert` cap | Done-claims only. The B13 "❌ no" closes abstain at `:469-471`; the honest-no spare is untouched |
| operator-readout (§5.3) | No | No: `systemMessage` only |
| `nudge_subject` (§6) | Out of Stop, so it cannot create a Stop loop. At most 3 per decision-state key, backoff 2 h then 4 h (1 h after a "watcher-armed" delivery), at most 3 per sweep. The marker fails closed and survives `clear_page*`. Each nudge costs at most 1 turn, plus at most 2 floor fires if that turn does nothing new | Fires only on `scope_floor ∈ {drive, challenge}` in the last readout row, so a legit all-gated stop (UNGATED=0 or a hard gates-all) is never woken. A usage-limited session: cc-wake refuses (`refused-limited`) and the queued line surfaces after the reset |

---

## 11. The lie: `--gates all` and `--category`, and what bounds them

An agent that wants to stop can still declare a stop. D3 cannot read intent. What it does is make the
claim explicit, cheap to audit, and capped in cost.

| Lie | What happens | Bound |
|---|---|---|
| A judgment call filed `--category pick --gates all` (the B13 shape) | ⛔, then a **challenge** turn if ungated work is visible, then up to 3 supervisor nudges per decision state | 1 + 3 forced turns, each telling the model the scope-change rule. Stderr at `open` already showed the status-quo-option warning, the ruling hint and the class-B command. The operator's board label reads `C/pick/all` |
| A judgment call filed as a hard category (`money`, `self-mod`, …) with `--gates all` | ⛔ with no floor and no nudge: today's behaviour | It must state `--why-gated`, which is stored and shown on the board next to the category tag. The gate-classify disagreement goes to stderr (measured: e869 and 2902 route B). The IDL `open` row carries `category`/`gates`, so a census can count hard-category claims the router disputes. **Residual: not mechanically preventable.** No regex separates a real C from a judgment call in either direction (`maps/legit-stops.md:112-126`); 50% of class-C packets were mis-classed (estimated, 29/58, `maps/legit-stops.md:103`) |
| A false `Scope (done):` to end a loop | `LOOP_OPEN=0` | A durable, dated, sid-stamped line in the store that the next SessionStart injects. Auditable, not prevented |
| `--gates "everything"` (not the literal `all`) | Reads as part ⇒ 🔧 and the drive floor | Fails toward driving. The floor text names `regate <id> --gates all` |
| Superseding a hard gate, or another session's packet, to escape | Refused | §2.5 validation |
| Disabling the floor with `CC_SCOPE_FLOOR=0` from its own shell | No effect | Hooks run in the harness environment, not the agent's Bash shell; changing it needs a settings edit |
| Never filing, just idling with "waiting" | `BLOCKED=0`; with an own loop scope, the 🔧 loop arm and drive floor. With no loop or DoD box, ✅ | Outside this incident class. Goal (a)'s rule text covers it |

Two facts matter for the residual. In the legit-stops sample, the honest hard gates (L1-L8) almost never
gated the whole session: 7 of 11 transcript-checked idles had already finished their ungated work
(`maps/legit-stops.md:150-173`). And a lie of the hard kind is visible on the operator's board as a
category tag that plainly does not fit the question.

---

## 12. B13 replay with D3 deployed

Inputs are the packets and closes at `maps/incident-replay.md:105-191,368-433`.

**02:36Z, decision 1** (`TX:4254`, `cc-decide open --class C --what "Should the B13 loop stop now…" --conviction 85 --receipt R --option yes::… --option "no::keep running rounds…" 2>&1 | tail -3`):

- The open is refused, with rc 2 and no file, because `--category`, `--gates` and `--why-gated` are missing.
- The three lines the lead sees:
  1. `LIKELY ALREADY RULED — eb3dbe1e5e94 (class B, expired-actioned 2026-10-15; its default fired: "keep looping until dry (the scope as written)")…`
  2. the class-B command with its own `--what`, conviction 85 and receipt filled in;
  3. the class-C fix line.
- The ruling is the same fork, settled 10 days earlier, and the lead's own plan records it
  (`bring-back-ocr.md:885-886`, `maps/ruling-discovery.md:28-29`). Either branch the lead takes ends with
  no ⛔:
  - it acts on the ruling (class A citing eb3dbe1e5e94);
  - or it files class B with default "keep running rounds as scoped", `no-change`, deadline +72 h.

**02:36Z, decision 2** (`TX:4260`, `| tail -2`):

- Refused the same way. The last two lines are the two commands, and the grant hint sits on line -3.
- With the grant recorded (§7), the lead runs `xvendor-review.sh`.
- Without the grant, it files `--category escalation --gates "the Codex reviewer lane" --why-gated "data egress to another vendor"`. That packet gates part, so round 27 runs Claude-only.

**First Stop after deploy** (for example the 02:36:51Z close): the intake captures `TX:14`'s loop scope
under `session=666022fd…`. Then `LOOP_SRC=own`, `LOOP_OPEN=1` and `UNGATED=1`.

**F1 06:44:40Z** (`TX:4437`). Ledger inputs (`maps/incident-replay.md:258-275`): DIRTY 0, UNLANDED 0,
CUSTODY 0, LANDING 0, 64% fill.

| Variant | RUNG | SCOPE_FLOOR | session-continue | Outcome |
|---|---|---|---|---|
| B: re-filed as class B (or class A on the ruling) | 🔧, the loop arm | drive | mechanical arm: rung 🔧, no own dirt, rc 1 → ship floor: not 📦/🚀 → **scope floor**: no kill phrase (the last operator text `TX:4163` has none), not an assignee, 64 < 73, the only background job is watcher `bpctefji1` (`cc-await-ping` from `~/.claude/bin`, infra) → **block**: "run round 27 as scoped" | Round 27 starts at about 06:45Z instead of about 18:12Z (`TX:4495`) |
| P: decision 2 as a part-gating class C, decision 1 as B | 🔧 "Decision open, not gating" | drive | same | same |
| L: the lead lies, `--category pick --gates all` on decision 1 | ⛔ | challenge | **block once**: the challenge text | One turn. Re-filing via `--supersedes` gives the drive floor at the next close |
| Today (control) | ⛔ | — | silent `return 1` at `:1103` | 11 h 26 m idle (`maps/incident-replay.md:70`) |

**F2 07:39:47Z, F3 08:34:59Z** (only if the model ignored F1 and committed nothing):

- In variant B, the second drive fire happens at F2. F3 is then latched (`scope-floor-latched`, logged).
- In variant L, F2 and F3 are latched.

**Supervisor.** STALL? begins at about 09:11Z (`maps/wake-path.md:60-72`). The last readout row has
`scope_floor=drive` (or `challenge`).

- **Nudge 1 at about 09:11Z.** If B13's detached watcher from 08:34:49Z (`TX:4469`) were still alive,
  cc-notify would report `wake-path-armed`, and that watcher wakes nobody (`maps/wake-path.md:174-197`).
  So the marker's re-check is set to 1 h, not 2 h.
- **Nudge 2 at about 10:11Z.** By then the orphan has died: its 3,300 s timeout from 08:34Z ends at about
  09:29Z. The socket wake fires (`cc-notify` sees no watcher, then `cc-wake`, W1-W5 ✓ while idle at ⛔/🔧).
  The UserPromptSubmit drain surfaces the line, and the lead takes a turn about 8 h before the operator's
  18:11Z message.
- The inbox-guard "NOW-DEAD" misread (`IDL:12341`) does not matter: the path is `cc-notify`'s registry or
  pid check, not inbox-guard's verdict.

**Controls** (`maps/incident-replay.md:435-441`):

| Control | D3 reading | Result |
|---|---|---|
| C1: ⛔ with lanes in flight (03:09Z) | part-gating or gates-all; custody open | `SCOPE_FLOOR=none` (`in-flight-custody`); the stop is allowed ✓ |
| C2: d610f8473106 C10 self-mod, round 27 running (18:31Z) | `--category self-mod --gates "the claude-infrastructure rules/hooks change"` → part → 🔧; custody open | none (in flight) ✓. Filed with `--gates all` instead → hard → ⛔, none ✓ |
| C3: Codex permission denial (18:17Z) | `--category permission --gates "the Codex reviewer"` → part | in flight → none ✓. If nothing were in flight → drive: "run round 27 Claude-only" ✓ (the replay's MUST) |
| C4: all-gating money or self-mod, scope exhausted | hard, gates all | ⛔, `SCOPE_FLOOR=none` (`gates-all-hard`), `blocked-answered` spare unchanged ✓ |
| C5: class-B re-file, no loop floor | today: false ✅ and free-win recycle advice | 🔧 loop arm, drive floor; free-win needs ✅, so no recycle advice ✓ |
| Legit stops 43055acd, e582464c, c56c729c, 79076bcf, fd91140d (`maps/legit-stops.md:156-167`) | no ungated work (no loop scope, no DoD box) | `UNGATED=0` → none; ⛔ unchanged; no nudge ✓ |

---

## 13. What D3 deliberately does not do

1. **It never refuses on similarity or a grant match.** Precision is too low: about 20% of strong flags are
   unrelated (estimated), and `open` is the STOP-ASK escape (`maps/ruling-discovery.md:191-200`).
2. **It never refuses on a classifier verdict** (gate-classify, the status-quo regex). Those go to stderr only.
3. **No new rung glyph, and ⛔ stays above 📦 for every open class-C packet.**
4. **No phrase added to anti-deference, and no hold arm.** The actuator is ledger-keyed (§5.5).
5. **No boundary-handoff ⛔ free-win.** It would launder the packet to a successor and use false wording (§5.7).
6. **No idle-keepalive wake.** It is structurally shadow (`hooks/idle-keepalive.sh:28-37`), it carries no
   content, and B13's hook set did not include it (`maps/incident-replay.md:30`).
7. **No settings, hook-registration or plist change.** That includes no allow rule for `codex exec`: the
   18:17Z classifier denial stays the operator's (a class-C `permission` packet).
8. **No auto-filing of packets from close prose.** The `f56cf0f827d7` false positive (`maps/incident-replay.md:238`) stays a separate defect.
9. **No notice to the filing session when its class-B default fires.** It is a two-ended TSV change
   (`bin/cc-decide:640` and `scripts/autonomy-sweep.sh:562`). Mail to a dead session can also escalate to
   the phone through cc-inbox-guard. Filed as a follow-on, together with the `subject_project` and
   `default_effect` misroute of `b4780d7bb60e` (measured: `jq` shows `default_effect ""`,
   `subject_project ""`).
10. **No `validate-bash` deny for a detached `cc-await-ping … &`** (`maps/wake-path.md:194-197`). This is a
    separate defect; §6 only shortens the re-check.
11. **No repair of `send_page`'s dead-desk silence** (`scripts/lead-supervisor.sh:414-415`). Recommended separately.
12. **No validation of class-B deadline format.** 7 legacy packets carry non-Z deadlines, and a refusal
    would add a way for `open` to fail.
13. **No stop on agents `action`-ing their own hard-gate packet.** That path exists today and is out of scope.
14. **No ledger view of one-line scopes such as "build X, Y and Z".** The ledger cannot see their
    remaining items. A part-gating packet there reads ⛔ with "drive anything else in your frozen scope
    first" (§4.3), and the rule text carries the duty. Mechanical enforcement covers DoD boxes, dirt and loop
    scopes only.
15. **No Gemini/Antigravity in the grant.** Goal (d) names only the Codex plan (§16).
16. **No rewrite of the 691 packets** (inv7).

---

## 14. Tests

Every new suite sets a fixture `HOME` in `setup()` (hermeticity rule 1, `maps/test-infra.md:466-470`).
Dates are relative or `2099-…`. Assertions use `! cmd || false`. Each "red today" is the run against
`origin/main`'s subject; each guard also gets a mutant (the repo's method, `maps/test-infra.md:486-519`).
Run the direct suites by hand and check the `1..N` plan line; a cc-bats rc 75 means no verdict
(`maps/test-infra.md:35-58`).

### 14.1 `tests/cc-decide.bats` (grandfathered file; `C_OK` gains the three flags)

| # | Name | Fixture | Assertion | Red without the change |
|---|---|---|---|---|
| D1 | class C without --category is refused, recipe last | `open --class C --what X --conviction 40 --receipt "p => r" --option a::x --option b::y` | rc 2; no `*.json`; last stderr line contains `--category self-mod\|money`; line -2 contains `--class B` and `--default-effect no-change` and the caller's `--what` | rc 0, packet written |
| D2 | unknown category, empty gates, missing why-gated each refused | three variants | rc 2 each, store empty | unknown arg (rc 2, but a different message: assert the message) |
| D3 | class-C fields refused on A and B | `--class B … --gates all` | rc 2 | unknown arg message differs |
| D4 | compliant C stores the fields; ALL normalised; id unchanged | `--category money --gates ALL --why-gated w` | `jq .gates` = `all`, `.category` = `money`; id = `printf 'C\037<sid>\037X' \| sha256 \| cut -c1-12` | unknown arg |
| D5 | `c10`/`c6` aliases | `--category c10` | `.category` = `self-mod` | unknown arg |
| D6 | view fold: legacy, producer, part, regated | `_raw_pkt` legacy C (no gates), producer C, part C, part C + `regates:[{gates:"all"}]` | `list --open --class C --json`: `gates_all` true/true/false/true; `gate_hard` false/true/(per category)/… | fields absent |
| D7 | `list --blocking` | C all, C part, B | ids = the C-all only | unknown arg |
| D8 | drift warning covers gates | re-open the same what with a different `--gates` | stderr names `gates`; file `cmp`-identical | no warning |
| D9 | supersede happy path | legacy C by sid S; `open --class B --supersedes <C> --default d --deadline 2099-… --default-effect no-change --conviction 40 --receipt "p => r"` as S | old `.status` = `actioned`, `.superseded_by` = new id, `.resolved_by` = `supersede:S`; new `.supersedes` = old | unknown arg |
| D10 | supersede refusals | hard-category C; C of sid T; actioned C; producer C; B without no-change | rc 2/3; the old file `cmp`-identical to a pre-copy | unknown arg (mutant: drop the sid check ⇒ T case goes green-wrong) |
| D11 | regate | open part C; `regate <id> --gates all --why-gated w` | `.regates \| length` = 1; view `gates_all` true; foreign sid rc 2; class B rc 2 | unknown verb |
| D12 | ruling hint on stderr, stdout exactly the id | `CLAUDE_CODE_SESSION_ID` set; `CC_DECIDE_MEMSEARCH_BIN` stub printing a 2-row JSON (ratio 2.9, id `eb3dbe1e5e94`) | stdout line count 1 and equals the id; stderr's last line before exit contains `LIKELY ALREADY RULED — eb3dbe1e5e94` | no hint |
| D13 | hint fails open | stub exits 1; stub sleeps 10 with `CC_DECIDE_HINT_TIMEOUT_S=1` | rc 0, id on stdout, no hint, wall < 5 s | (mutant: drop `\|\| return 0` ⇒ rc ≠ 0) |
| D14 | hint skipped without a session id, or with `CC_DECIDE_RULING_HINT=0` | stub that `touch`es a sentinel | sentinel absent | (mutant: drop the guard) |
| D15 | grant hint | `CC_STANDING_GRANTS=<fixture>`; `--what "…ChatGPT Codex plan…"` | stderr contains `COVERED BY STANDING GRANT xvendor-review-2026-10-24` | none printed |
| D16 | refusal path also prints the ruling hint before the recipe | as D1 plus the D12 stub | stderr line -3 = the LIKELY line | no hint |
| D17 | `open --help` | — | rc 0; output contains `HARD-BLOCK` and `--gates` | rc 2 "unknown arg --help" (`TX:4250`) |
| D18 | class A accepts conviction > 90 | `open --class A --what X --conviction 95` | rc 0 | rc 2 (`bin/cc-decide:224`) |
| D19 | hard category vs router disagreement on stderr only | `--category money` with the e869 text | rc 0; stderr contains `gate-classify finds no hard surface` | absent |

### 14.2 `tests/wrap-ledger.bats` (real `bin/cc-decide`, per-test store; `open_blocking` gains `--category destructive --gates all --why-gated t`)

| # | Name | Fixture | Assertion | Red without |
|---|---|---|---|---|
| W1 | part-gating C + own loop ⇒ 🔧 drive | `ok_state`; real open with `--category escalation --gates "codex lane"`; `WRAP_DOD_FILE` = `## <ts> (intake) · toplevel=$PWD · session=$SID` + `Scope (frozen): loop until dry …` | RUNG 🔧, BLOCKED 1, BLOCKED_ALL 0, LOOP_OPEN 1, SCOPE_FLOOR `drive`, READOUT contains `gate only: codex lane` | RUNG ⛔, fields absent. Mutant: `.gates_all // true` in place of `has()` ⇒ BLOCKED_ALL 1, RUNG ⛔ (jq's `//` replaces `false`; measured: `printf '{"gates_all":false}' \| jq '.gates_all // true'` prints `true`) |
| W2 | hard gates-all + loop ⇒ ⛔ none | as W1 with `--category money --gates all` | RUNG ⛔, SCOPE_FLOOR `none`, WHY `gates-all-hard` | fields absent (RUNG green: a control) |
| W3 | pick gates-all + loop ⇒ ⛔ challenge | `--category pick --gates all` | SCOPE_FLOOR `challenge` | absent |
| W4 | legacy C (`mk_bare_packet`, no gates) + loop ⇒ ⛔ (unchanged), BLOCKED_ALL 1, HARD 0 | | as stated | absent (the back-compat control) |
| W5 | foreign session's loop ⇒ not mine | DoD block `session=OTHER` | LOOP_OPEN 0, LOOP_SRC `none`, RUNG ✅ | (mutant: drop the session filter ⇒ 🔧) |
| W6 | own loop then own `Scope (done):` ⇒ ✅ | | LOOP_SRC `done`, RUNG ✅ | (mutant: ignore done) |
| W7 | **C5**: class-B packet + own loop, clean, landed ⇒ 🔧 not ✅ | real `open --class B …` | RUNG 🔧, READOUT names the loop | RUNG ✅ today (the false ✅) |
| W8 | part C + only unlanded ⇒ ⛔ (never 📦) | commit, no push | RUNG ⛔, READOUT contains `It gates only:` | RUNG ⛔ (control for the order), text absent |
| W9 | part C + dirty ⇒ 🔧 | `echo dirt >> base.txt` | RUNG 🔧 | ⛔ |
| W10 | custody open ⇒ none, in-flight | `CC_CUSTODY_BIN` stub count 1 | SCOPE_FLOOR_WHY `in-flight-custody` | absent |
| W11 | research program ⇒ none | `CC_RESEARCH_REGISTRY` fixture naming `$PWD` | LOOP_SRC `research`, SCOPE_FLOOR none | absent |
| W12 | unreadable store ⇒ fail open | `CC_DECIDE_BIN` → `exit 1` stub | BLOCKED_SRC `error`, SCOPE_FLOOR none (no loop) | (guard) |
| W13 | `LIVE=` is still line 18; new fields after `BLOCKED_SRC` | | `sed -n 18p` starts `LIVE=` | (guard, BUSY splice) |
| W14 | existing pins `:1934-1961` | unchanged bodies, new helper | green | — |

`tests/wrap-ledger-memo.bats` M1: `WRAP_LOOP_FLOOR=off` and `WRAP_SCOPE_FLOOR=off` change the memo key and
are never served the other's body. Red: the key ignores them.

### 14.3 `tests/scope-floor.bats` (new; template `tests/ship-floor.bats:12-50`, ledger stub driven by env `STUB_*`)

| # | Name | Assertion | Red without |
|---|---|---|---|
| F1 | drive blocks once per commit, names the loop and the ids | `"decision":"block"`; reason contains `run the next round` and the ids; IDL `fired scope-floor` | no block |
| F2 | second same-commit idle blocks again, third is latched | blocks 2, then `abstained scope-floor-latched` | — |
| F3 | a new commit re-arms | `git commit --allow-empty` ⇒ block | — |
| F4 | total cap | `CC_SCOPE_FLOOR_TOTAL=2`, 3 commits ⇒ third `scope-floor-budget` | — |
| F5 | challenge asks once per decision set, a new id re-asks | | — |
| F6 | kill phrase ⇒ abstain, logged | `mkuser_tx "…and stop"` | — |
| F7 | assignee confirmed ⇒ abstain | `AGENT_IDENTITY_LIB` stub rc 0 | — |
| F8 | busy job ⇒ abstain; watcher-only ⇒ fires; probe slower than `CC_SCOPE_FLOOR_BUSY_TIMEOUT_S` ⇒ fires (unknown ⇒ proceed) | `SESSION_BUSY_LIB` seam stub whose `sb_busy_jobs` prints a job / prints nothing / sleeps 5 | — (mutant: treat a timeout as busy ⇒ the third case goes silent) |
| F9 | used_pct ≥ T ⇒ abstain `context-high` | telemetry fixture 80 | — |
| F10 | **old ledger** (no `SCOPE_FLOOR` line) ⇒ silent, no row | the stub omits the field | (fail-open control) |
| F11 | ⛔ + SCOPE_FLOOR none ⇒ logged `abstained scope-floor-gates-all-hard` | | no row today (B-3) |
| F12 | unwritable state ⇒ no block, logged | `chmod 500` on the sentinel dir | (mutant: `\|\| true` on the write ⇒ blocks) |
| F13 | the block writes `${f}.blocked` with arm `scope-floor` | | — |
| F14 | `CC_SCOPE_FLOOR=0` ⇒ silent | | — |
| F15 | intake: TX:14-shaped human record captured under `session=<sid>`; a tool_result lane scope is not; second Stop appends nothing | `WRAP_DOD_DIR` fixture; transcript with both records | DoD file holds exactly one `(intake)` block, scope = the human line | nothing captured |
| F16 | mechanical arm on ⛔ + own dirt arms | `ma_fixture` stub `RUNG=⛔ DIRTY=1` | sentinel armed | `return 1` at `:1103` |

### 14.4 Others

| Suite | # | Name / fixture | Assertion | Red without |
|---|---|---|---|---|
| `tests/dod-persist.bats` | P1 | `set "Scope (done): r27 confirmed nothing new"` | the stored line starts `Scope (done):` | prefixed `Scope (frozen): Scope (done):` |
| | P2 | `intake` rc 0 / 3 / 4 cases; `assistant` text fallback; `tool_use` input ignored | rc and store contents | unknown mode |
| `tests/completion-assert.bats` | A1 | `mkledger … RUNG=⛔ BLOCKED=1 UNGATED=1` + honest-no close containing "landed" | exoneration contains `blocked-answered:ungated=1` | token is `blocked-answered` |
| | A2 | done-claim, `mkledger … RUNG=🔧 LOOP_OPEN=1 LOOP_HEAD=loop` | block; facts contain `loop` | no fact |
| | A3 | existing `:1265-1278`, `:2579` | green, unchanged | — |
| `tests/operator-readout.bats` | O1 | ledger stub `RUNG=🔧 LOOP_OPEN=1 LOOP_HEAD=x` | state contains `loop scope open` | "loose ends" only |
| | O2 | the IDL `steps-surfaced` row | has `scope_floor`, `blocked_ids` | absent |
| | O3 | board label for a `money`/`all` packet | `C/money/all` | `C` |
| `scripts/supervisor-e2e.sh` (T41) + `tests/lead-supervisor.bats` floor raised | N1-N9 | IDL fixture rows for a `sleep`-pid session; `CC_NOTIFY_CAPTURE` | (1) nudged directly on `scope_floor=drive`; (2) damped within backoff; (3) second after `CC_SUP_NUDGE_BACKOFF_S`, third after 2×, none after 3; (4) stub rc 3 leaves no marker, retried; (5) `CC_SUP_SUBJECT_NUDGE=0` none, `shadow` logs only; (6) non-uuid never addressed; (7) a new ids key resets; (8) `scope_floor` none or absent ⇒ none; (9) `clear_page` keeps `.nudged`; plus verdict parse reads `^cc-notify: verdict=` | none of it exists |
| `tests/lead-keeps-working-rules.bats` (new; names `CLAUDE.rules.slim.10-session-close.md` literally so gate-select picks it) | R1-R8 | grep `R`, `S`, `G` | R and G each contain (case-insensitive): "keep driving every in-scope item it does not gate"; "stop only when it gates all remaining in-scope work"; "gating all remaining in-scope work"; "A judgment call with a status-quo course is class B"; `--category self-mod\|money`; "look for a ruling"; `Scope (done):`. S and G each contain `config/standing-grants.json`, `80%`, `git archive`, `routes no`. R:92 still contains `need your call: <decision>`. The cut sentences (R:4's Stop-hook pointer, R:15-18) still exist in G (`grep -F 'waiting on a trunk-wide stamp' CLAUDE.global.md`) | sentences absent |
| `tests/standing-grants.bats` (new) | G1-G3 | the JSON parses; every grant has the schema keys; S names `config/standing-grants.json` and every grant's `entrypoint` | | file absent |
| `tests/xvendor-review.bats` (new) | X1-X6 | stub `codex` and `git`; rollout fixture at 79 / 80 / unreadable; `OPENAI_API_KEY` set in the caller | 79 runs, 80 rc 5, unreadable refuses; the stub sees no `OPENAI_API_KEY`; the export lacks an uncommitted file and `.claude/xvendor-review.exclude` paths; `-s read-only` in argv | script absent |
| `tests/cc-memory-search.bats` | M1-M2 | `CC_DECISIONS_DIR` fixture: answered, open, superseded, string-options packets | `--decisions` ranks the answered twin first; never returns open or superseded; no jq error on string options | unknown flag |
| `tests/research-kit-gate.bats` | K1 | class-C program packet | carries `category` `pick` and `gates` = the decision id | refused after D1 lands (this is the in-land fix) |
| `tests/anti-deference-nudge.bats` | AD1 | `ANTIDEF_DECIDE_BIN` stub records env | `CC_DECIDE_RULING_HINT=0` seen | absent |

---

## 15. Rollout order (one land unless noted) and verification

1. **cc-decide** (§2) + `gate_sweep.py` + the test call-site edits + `cc-memory-search --decisions` +
   `config/standing-grants.json`. These have to land together, or the research kit's class-C opens fail.
2. **Ledger** (§4) + operator-readout (§5.3) + completion-assert (§5.2) + dod-persist (§5.6). Consumers read
   absent fields as today.
3. **session-continue** (§5.1) + dispatch-assert, why-tier and wrap.md text.
4. **lead-supervisor** (§6). The first week runs with `CC_SUP_SUBJECT_NUDGE=shadow`, read from IDL
   `subject_nudge_shadow` rows. Then live.
5. **Rules** (§8) + `xvendor-review.sh` (§7.2). After converge (`deploy-live.sh` runs `install.sh`,
   `deploy-live.sh:52`), check that `diff -q` of R and S against `~/.claude/rules/10-session-close.md` and
   `~/.claude/CLAUDE.md` is silent (`maps/test-infra.md:562-567`).
6. **Precheck.** `scripts/ship-land.sh --precheck --working` runs every lint arm. The smoke will cut at
   900 s with more than 50 direct suites (`maps/test-infra.md:192-195`).

Estimated size (estimated by summing per-file sketches above):

| Area | Lines |
|---|---|
| `bin/cc-decide` | ~240 |
| `scripts/wrap-ledger.sh` | ~150 |
| `hooks/session-continue.sh` | ~170 |
| `hooks/dod-persist.sh` | ~60 |
| `scripts/lead-supervisor.sh` | ~90 |
| `bin/cc-memory-search` | ~70 |
| `scripts/xvendor-review.sh` | ~130 |
| `hooks/operator-readout.sh` | ~40 |
| `hooks/completion-assert.sh` | ~15 |
| config, gate_sweep.py and the text edits | ~60 |
| Rule text | ~20 changed lines |
| Tests | ~950 |
| **Total** | **~2,000** |

---

## 16. Open questions for the operator (none blocks the design)

1. Should the cross-vendor grant include Google's Antigravity CLI (`agy`)? The agentsync memory note and
   the incident report's draft include it (`maps/ruling-discovery.md:332-334`); goal (d) names only the
   Codex plan.
2. Defaults: `CC_SCOPE_FLOOR_TOTAL=16` and the 72 h class-B deadline the refusal suggests are judgment
   values, not measured.
3. The held-out INSTRUCTION_BUDGET F1 re-gate ("deferred until the next slim edit", about $403 list,
   `maps/rules-text.md:203`) is triggered by any slim edit, including this one. It is the operator's to
   run or keep deferring.
