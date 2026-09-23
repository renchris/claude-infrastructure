<!-- arm A = claude-sonnet-5 @max · brief T1-custody · settle run 1 (wf_e43f474d-ad0) · raw worker output, verbatim -->

# The Custody-Debt Lifecycle in claude-infrastructure

## 1. RECORDING

**Store location.** One append-only JSONL file per originator cwd, directory `${CC_CUSTODY_DIR:-$HOME/.claude/autonomy/custody}` (`bin/cc-custody:65`, documented `bin/cc-custody:13`). The physical file is `$CUSTODY_DIR/<cwd-key>.jsonl` (`bin/cc-custody:134`, in `_files_for()`), where `<cwd-key> = _fired_cwd_key "$cwd"` (`bin/cc-custody:133`, and `bin/cc-custody:76-83` sources the lib). `_fired_cwd_key` is defined in `hooks/lib/origin-identity.sh:68-77`: it resolves the directory to its physical path (`cd "$d" && pwd -P`, so symlinks and `/tmp` vs `/private/tmp` collapse to one key) and then takes `shasum -a 256` of that resolved path, truncated to the first 32 hex characters (`hooks/lib/origin-identity.sh:74-76`). So the filename is `sha256(physical-cwd-path)[:32].jsonl` — the *same* normalisation the fired-peer store uses (`bin/cc-custody:14`).

**Row fields** (`_row()`, `bin/cc-custody:93-104`): always `ts`, `kind` (`open|return|abandon`), `cwd`; optionally `originatorPane`, `targetPane`, `marker`, `slug`, `notifyBack`, `why`, `provenance` — each key is omitted entirely (not written as empty-string) when its argument is `""` (`bin/cc-custody:97-103`). `provenance` (`proven` or `unproven-rc<N>`) is written only on `open` rows (`bin/cc-custody:87-92`).

**Open-set derivation at read time** — `_OPEN_JQ` (`bin/cc-custody:106-112`):
```
map(. + {k: (if (.marker//"")!="" then ("m:"+.marker) else ("s:"+(.slug//"")+"|"+(.targetPane//"")) end)})
| group_by(.k) | map(sort_by(.ts) | last) | map(select(.kind == "open"))
```
- **Join key** = `marker` when non-empty; **when the primary key (marker) is missing**, it falls back to the composite `"s:"+slug+"|"+targetPane` (`bin/cc-custody:110`) — never treated as unkeyable.
- **When several rows share a key**, they are grouped and sorted by `ts`, and the **last (most recent) row wins** as that key's current verdict (`bin/cc-custody:111`); only keys whose winning row is still `kind=="open"` remain in the open set — a later `return`/`abandon` silently removes that key.
- The log itself is never rewritten or deleted; the open set is entirely re-derived on every read (`bin/cc-custody:20`, `:47-48`).

**The boolean condition that opens a row at all** (local/handoff-fire producer), `scripts/handoff-fire.sh:13219`:
```
if [ -n "${NB_ARMED_TARGET:-}" ] && [ -n "${SPAWNED_PANE:-}" ] && engage_rc_consequence "$rc" custody; then
```
Three conjuncts: a back-channel was armed (`NB_ARMED_TARGET` — non-empty *iff* the `--notify-back` trailer was written, `scripts/handoff-fire.sh:13208-13211`), a pane actually spawned, and the engagement-check's return code is one `engage_rc_consequence` approves for `custody`.

**Which directory it's keyed on**: `_hf_custody open --cwd "$PWD" --target "$SPAWNED_PANE" ...` (`scripts/handoff-fire.sh:13220-13223`). This runs inside the *firing/originator* process, so `$PWD` is the **originator's** cwd, explicitly **not** the fired peer's worktree — "record the debt where the ORIGINATOR's ledger can count it (keyed on the FIRING cwd, not the target worktree)" (`scripts/handoff-fire.sh:13198-13199`). The peer's pane becomes `targetPane` instead.

**Engagement-check outcomes and the consequence table** — `engage_rc_consequence()` (`scripts/handoff-fire.sh:3547-3595`):

| rc | meaning | custody | goal |
|---|---|---|---|
| 0 | ENGAGED, proven | open (`:3550`) | arm (`:3550`) |
| 1 | NEVER INGESTED (window expired, no ingestion evidence) | **open** (`:3574`, `return 0`) | **do not arm** (`:3580`, `return 1`) |
| 2 | PANE PARKED (no session at all) | do not open (`:3583`) | do not arm (`:3583`) |
| 4 | WEDGED (session exists, stuck on a dialog) | open (`:3589`) | arm (`:3589`) |
| 5 | CANNOT TELL (non-verdict) | open, fail-open (`:3592`) | arm, fail-open (`:3592`) |
| unknown | undocumented rc | open, fail-open, loud stderr (`:3593-3595`) | same |

**Does the same rule govern the `/goal` arm? No — they diverge exactly at rc=1.** Custody opening is cheap and reversible (`cc-custody abandon`), so a merely-expired window still opens the debt; arming `/goal` there would paste into a composer that never received the brief, "a wrong first instruction" (`scripts/handoff-fire.sh:3576-3580`). At every other code they move together.

**Every producer that opens rows** (three, one is a decoy):
1. `scripts/handoff-fire.sh` — local dispatched peers, via `_hf_custody open` at `scripts/handoff-fire.sh:13220-13223`, gated by the boolean at `:13219`.
2. `bin/cc-offload` — cloud fires via the API lane: `"$CUSTODY_BIN" open --cwd "$PWD" --target "cloud:$sid" --marker "$sid" --slug "cloud-$sid" ...` (`bin/cc-offload:747-750`), unconditional once the binary resolves — "CUSTODY OPENS AT THE FIRE, not at the return" (`bin/cc-offload:728`).
3. `bin/cc-dispatch` — cloud fires via the CLI/dispatcher lane, **two** call sites for two code paths: the adopted-legacy-leg path (`bin/cc-dispatch:903-905`) and the main declare path (`bin/cc-dispatch:931-934`), both `"$cbin" open --cwd "$PWD" --target "cloud:$sid" --marker "$sid" ...`.
- `bin/cc-cloud` is **not** a producer despite carrying a `--custody` flag: that flag only stores the marker string as a field on the cloud *declaration* record (`bin/cc-cloud:983,988,1069,1490-1492`) for the discharge paths below to find later; it never calls `cc-custody open`.

## 2. DISCHARGING

Five discharge sites, exhaustive:

**A. `scripts/handoff-fire.sh` self-close** — `[ -n "$_sc_cmk" ] && _hf_custody return "$_sc_cmk" --why "$SC_LEDGER_STAMP"` (`scripts/handoff-fire.sh:8707`). Verb `return`. Join key: **MARKER**, read off the peer's own fired-peer stamp, `_sc_cmk="$(jq -r '.marker // ""' "$FIRED_DIR/$SC_SID.json" ...)"` (`scripts/handoff-fire.sh:8654`). Scope: **store-wide** — no `--cwd` is passed, so `_files_for ""` walks every file in `$CUSTODY_DIR` (`bin/cc-custody:130-139`). Why marker-only works here: marker is globally unique, so the call can run from any cwd (`bin/cc-custody:26-27`). Condition: fires only for a marker-bearing stamp, after the ledger stamp is written and after the `--terminal`-with-no-successor refusal gate has passed (`scripts/handoff-fire.sh:8668-8703`); a marker-less schema-1 stamp discharges nothing (`scripts/handoff-fire.sh:8656-8657`).

**B. `hooks/mailbox-drain.sh` ping-receipt discharger** (custody v1.1) — condition `if [ "${CC_DRAIN_CUSTODY_RETURN:-1}" != 0 ] && printf '%s\n' "$body" | grep -q 'HANDOFF-PING'; then` (`hooks/mailbox-drain.sh:558`), then per matched slug: `if [ -z "$("$_cust_bin" return "$_slug" --cwd "$_cust_cwd" 2>&1 >/dev/null)" ]; then` (`hooks/mailbox-drain.sh:579`). Verb `return`. Join key: **SLUG** — the only custody field a received ping carries; the marker is never echoed to the peer (`hooks/mailbox-drain.sh:532-535`). Scope: `--cwd "$_cust_cwd"` — the *receiving* (originator) session's own cwd, deliberately, because a slug is only a prompt-file basename and two originators could collide on it; a store-wide discharge on a collided slug would silently drop a different cwd's custody (`hooks/mailbox-drain.sh:543-547`). Deduped and capped at 8 slugs/drain; idempotent (a `return` on an already-discharged key is a no-op) (`hooks/mailbox-drain.sh:552-555`).

**C. `scripts/cloud-retire-terminal.sh` `settle_custody()`** — `landed) "$CUSTODY_BIN" return "$marker" ...` / `*) "$CUSTODY_BIN" abandon "$marker" --why "$why" ...` (`scripts/cloud-retire-terminal.sh:206-207`). Verb `return` (on a `landed` verdict) or `abandon` (every other terminal verdict). Join key: **marker**, read from the cloud declaration's `custody` field (`scripts/cloud-retire-terminal.sh:201`). Scope: store-wide (no `--cwd`). Condition: gated on `[ -n "$marker" ] && [ -n "$CUSTODY_BIN" ]` (`scripts/cloud-retire-terminal.sh:204`) and a terminal declaration verdict — "`landed` outranks `superseded`: both are terminal, but only the first RETURNS custody" (`scripts/cloud-retire-terminal.sh:251`).

**D. `scripts/cloud-return.sh`**, two sites: (i) superseded path, `abandon` — `"$CUSTODY_BIN" abandon "$custody" --why "cloud session superseded — item $item already done"` (`scripts/cloud-return.sh:536-537`); (ii) normal-completion path, `return` — `if "$CUSTODY_BIN" return "$custody" ...` (`scripts/cloud-return.sh:979`). Both keyed by marker (the row's `custody` field, `scripts/cloud-return.sh:514`), both store-wide.

**E. Bulk/age-driven path** — `cc-custody abandon --stale --why <text> [--cwd <dir>]` (`bin/cc-custody:182-210`), the bulk branch at `bin/cc-custody:186-210`. It discharges **every** row whose derived `stale` flag is true (`ageHours >= CC_CUSTODY_TTL_HOURS`, default 24h) in one pass, appending one `abandon` row per stale key, all carrying the same operator-supplied `--why` (`bin/cc-custody:194-201`). This is an explicit, human/agent-invoked act, never automatic — confirmed by grep: outside `bin/cc-custody`'s own doc/usage text (`bin/cc-custody:56,183,268`) and its own test suite (`tests/cc-custody.bats:139-158`), **nothing in the production codebase ever calls `abandon --stale`**. `docs/research/backlog-drain-audit-2026-09-22/a7-worker-path.md:345` independently corroborates: "Discharge requires a human/agent `abandon --stale --why …`. Correct design."

**Does anything expire or delete a row automatically? No.** `bin/cc-custody:45-48` explicitly rejects a TTL-delete design ("NOT expiry... Nothing here deletes, nothing here rewrites; the log stays append-only"). `ageHours`/`stale` are computed only at read time from `ts` (`bin/cc-custody:50-53,118-122`); staleness is visible, never a write.

**Does the deathwatch/reaper discharge anything? Explicitly, no.** Its own header states it twice: "It NEVER discharges a debt, never closes a row, never kills a process. Detection is not disposition." (`scripts/custody-deathwatch.sh:44`) and "This script can only ever ADD a notification. It cannot discharge custody..." (`scripts/custody-deathwatch.sh:66-67`). The code matches: it only ever calls `"$CUSTODY_BIN" list --open --json` (read-only, `scripts/custody-deathwatch.sh:282`), `$NOTIFY_BIN` (`:355`), or `$BACKLOG_BIN needs` (`:389`) — no `return`/`abandon` call appears anywhere in the file. It runs periodically from `scripts/autonomy-sweep.sh` (`sweep_yield 2e-custody-deathwatch` at `:1894`, invocation `bash "$_custdw" --sweep` at `scripts/autonomy-sweep.sh:1919-1920`), store-wide (no `--cwd`), specifically to see the launchd-dispatched (`cwd=/`) cloud shard no `--cwd .` consumer can see (`scripts/custody-deathwatch.sh:39-41,280-281`). Its report condition is `GONE (oracle) OR stale (age)` (`scripts/custody-deathwatch.sh:59`), and delivery is either a direct `cc-notify` to a live originator pane or one aggregated `cc-backlog needs` row per pass (`scripts/custody-deathwatch.sh:79-90,376-403`) — purely additive.

## 3. CONSUMING

### Close-ledger rung (`scripts/wrap-ledger.sh`)
`count_open_custody()` (`scripts/wrap-ledger.sh:1048-1085`): resolves the binary, then computes `pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; pane="${pane##*:}"` (`:1061`). If a pane id and jq exist, it calls `cc-custody list --open --cwd "$PWD" --json` (`:1063`) and evaluates:
```
def known: ((.originatorPane // "") != "") or ((.notifyBack // "") != "");
def mine:  ((.originatorPane // "") == $p) or ((.notifyBack // "") == $p) or ((.notifyBack // "") | endswith("-" + $p));
```
(`scripts/wrap-ledger.sh:1066-1069`) — `CUSTODY_MINE` = count where `known and mine`; `CUSTODY_UNK` = count where `known` is false (no ownership field at all); a row that *is* attributable but to a **different** pane is dropped from both buckets ("`theirs` is DROPPED", `:1018`). `CUSTODY_OPEN = CUSTODY_MINE + CUSTODY_UNK`, `CUSTODY_SRC="pane"` (`:1076`). Without a pane id (or on jq/JSON failure), it falls back to `cc-custody count --open --cwd "$PWD"` and treats the whole count as unattributed: `CUSTODY_OPEN="$n"; CUSTODY_MINE=0; CUSTODY_UNK="$n"; CUSTODY_SRC="cwd"` (`:1081-1084`).

**Identity spellings that count as "yours":** `originatorPane` OR `notifyBack` (exact match, or `notifyBack` ending in `-<pane>` for `<worktree>-<pane>` forms) — a disjunction of *two* ownership spellings, per the `def mine` above.

**Where in the ladder the count is taken:** `count_open_custody` is invoked (`scripts/wrap-ledger.sh:1997`) only inside the branch already judged "✅-eligible on the git facts" — i.e. strictly **after** the dirty-tree/gate-red/unlanded-commit (📦) checks have all passed without deciding the rung. The comment is explicit: "ONLY here do the custody count... matter — on the 🔧/📦 paths none can change the answer, so none is ever paid for" (`scripts/wrap-ledger.sh:1991-1994`). **Implication:** for a turn whose rung is already decided earlier (dirty, gate-stale, unlanded), custody is never even queried that turn — `CUSTODY_SRC` stays at its `"skip"` default (`:1047`), rendered downstream as "not counted (a worse rung governs)". Then: `if [ "$CUSTODY_OPEN" -gt 0 ]; then RUNG="🔧"` (`scripts/wrap-ledger.sh:1998`) — open custody outranks every remaining arm including the no-trunk check, and is checked *before* resident-teammate/filed/unconvicted 🔧 causes (comment at `:2018-2020` ranks resident members "beside the custody arm... one step below it"). Two READOUT variants: `CUSTODY_SRC="pane" && CUSTODY_MINE -eq 0` → hedge naming `CUSTODY_UNK` (`:2007`); else → assert `CUSTODY_OPEN` (`:2009`). Machine output: `CUSTODY_OPEN=`/`CUSTODY_SRC=`/`CUSTODY_MINE=`/`CUSTODY_UNK=` (`:2202-2208`); human line via `case "$CUSTODY_SRC" in pane) ... cwd) ...` (`:2313-2328`).

### Done-claim/completion gate (`hooks/completion-assert.sh`)
```
CUSTODY="$(lfield CUSTODY_OPEN)"; case "$CUSTODY" in ''|*[!0-9]*) CUSTODY=0 ;; esac      # :718
[ "$CUSTODY" -gt 0 ] && { contra=1; facts="${facts}${CUSTODY} dispatched session(s) have NOT returned..."; }   # :719
```
Consumes the ledger's field rather than re-deriving it ("CONSUME the ledger's count, never re-derive", `:715-717`). Setting `contra=1` marks a "done" assertion as contradicted while custody is open. `:1065` and `:1196` corroborate this is what actually convicts mid-wave false-done claims from a dispatched-wave lead.

### Stop/wake floor (`hooks/session-continue.sh`)
Resolves the binary (`:738-742`) then, if a pane id is known, uses the identical `def known`/`def mine` jq (`hooks/session-continue.sh:749-750`) against `cc-custody list --open --cwd "$cwd" --json`, splitting `cust_mine`/`cust_unk` (`:755-757`); otherwise falls back to `cust_unk="$("$_cb" count --open --cwd "$cwd" ...)"` (`:762-764`). Scoped `--cwd "$cwd"`, attributed the same way as the ship floor (`:714-728`). A live `/goal` with no pending mail makes the whole floor abstain before reaching custody (the "FOURTH STATE" block, `hooks/session-continue.sh:~688-705`). Then:
```
if [ "$cust_mine" -gt 0 ]; then                       # :878
  _custmsg="🧵 ${cust_mine} dispatched session(s) YOU fired have NOT returned ..."
elif [ "$cust_unk" -gt 0 ]; then                       # :881
  _custmsg="🧵 ${cust_unk} dispatched session(s) are open against this cwd, and the store cannot say whose ..."
```
prepended to the reason string that arms the watcher-recommendation block, and logged with `--argjson cm "$cust_mine" --argjson cu "$cust_unk"` (`:890-891`).

### Operator-facing readouts (`hooks/operator-readout.sh`)
```
custody="$(lf CUSTODY_OPEN)"; case "$custody" in ''|*[!0-9]*) custody=0 ;; esac      # :915
...
[ "$custody" != "0" ] && parts="${parts:+$parts · }${custody} dispatched session(s) NOT returned"   # :929
...
elif [ "$custody" != "0" ]; then state="${state} → cc-custody list --open --cwd ."   # :939-940
```
Pulled from the same `wrap-ledger.sh --machine` shell-out (`:812-818`), rendered only inside the `"🔧"` rung branch, and explained as necessary precisely because a custody-driven 🔧 otherwise arrives with every other field (`DIRTY_N`, `GATE`, `REMAINDER`) empty, which would render a contentless "loose ends" line (`:898-902`).

### Other touchpoints found
- `hooks/lib/session-busy.sh:302` — `case "${CC_BUSY_CUSTODY_OPEN:-0}" in ''|0|*[!0-9]*) : ;; *) arms="$arms custody" ;; esac`. This does **not** re-read the store; it consumes an env var wrap-ledger itself injects (`_wl_sbo="$(CC_BUSY_CUSTODY_OPEN="${CUSTODY_OPEN:-0}" ...`, `scripts/wrap-ledger.sh:2143`), feeding only the ⏳ working-vs-idling `BUSY_STATE` display, not the rung ("Custody is INJECTED... rather than re-read", `hooks/lib/session-busy.sh:279-281`).
- `hooks/lib/why-tier.sh:203-213` — a static `why-tier custody` help topic; documents the mechanism but issues no query.
- `hooks/lead-crash-watchdog.sh:218,1050` — mentions custody only in prose, as an assumed precondition of a `retired-by-desk` death classification (i.e., that site (A)'s self-close discharge already ran before the kill); it never calls `cc-custody` itself.
- `hooks/validate-bash.sh:633,713` — classifies `cc-custody` invocations as non-write/reporting commands exempt from the write-lease gate; not a reader of the open-set count.

## Citation checks (per the brief's grounding instruction)

Two cross-file citations inside this very subsystem do **not** hold against this snapshot:

1. `scripts/custody-deathwatch.sh:334` states: *"scripts/wrap-ledger.sh:1020 and hooks/session-continue.sh:655 both define `known` as the DISJUNCTION of the two and `mine` as a match on EITHER."* Checked against the file: `scripts/wrap-ledger.sh:1021` actually reads "MEASURED 2026-09-03, so the unattributable class is not hypothetical: 441 open rows store-wide," — unrelated prose. The real `def known:`/`def mine:` pair lives at `scripts/wrap-ledger.sh:1066-1067` and `hooks/session-continue.sh:749-750` — 45 and ~94 lines from the cited numbers respectively. The underlying *fact* (both files share one disjunction) is true; the line numbers are stale.
2. `docs/research/stop-chain-wave2-2026-09-03/custody.md:53` cites the fire-side open guard at handoff-fire.sh "**10523–10526**" and `FIRING_SID` as "set at **8916**". In this snapshot the guard is at `scripts/handoff-fire.sh:13219` (open call `:13220-13223`), and `FIRING_SID` is assigned at `scripts/handoff-fire.sh:11279` — both roughly 2,300+ lines later, consistent with the file having grown substantially since that doc's 2026-09-03 date. The described logic and field names otherwise match current behavior; only the line numbers have drifted.

No other examined header/doc citation (`bin/cc-custody:35-38`, `:44-46` self-citations; `hooks/session-continue.sh:608-612`; `hooks/mailbox-drain.sh:532-547`) was checked and found wrong — each held at the cited location.