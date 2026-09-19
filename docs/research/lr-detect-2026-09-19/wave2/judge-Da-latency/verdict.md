# JUDGE Da-event-state — lens: LATENCY · TOKEN COST · COMPOSABILITY
Score 5.5/10. Read-only. Every number below is `cmd => output` run by this unit on this box, or a file:line.

## Measurements this unit ran (the design did not)
| what | design says | measured here |
|---|---|---|
| `agent_assignee_argv` (arm 2 calls it on EVERY death) | "UNMEASURED" (§5.3, §21) | 0.19 / 0.23 / 0.19 s — `ps -axo pid=,ppid=,command=` is 624,351 B piped to awk |
| ancestry walk, 12 hops × 2 `ps` | "≤ 4 ps (~5 ms each) +0.02 s" (§11.4) | 0.12 s — the sketch's loop bound is `i < 12` with TWO ps per hop = up to 24 forks |
| `lr_last_api_error` on a real 7.1 MB transcript | "+0.03–0.05 s" | 0.07 / 0.05 / 0.05 s |
| `oi_origin_class` (fast branch) | not budgeted | 0.03 s; worst branch adds grep 0.08 s + `jq -e -R` 0.28 s over the same 7.1 MB |
| **arm 2's ADDED work, end to end** (sim of §5.2 minus the beat fork, minus launchctl) | **≤ 0.25 s total incl. baseline** | **0.38 / 0.41 / 0.51 s**, i.e. **0.47–0.65 s with the 0.09–0.14 s baseline — 2–2.6× the claim** |

## FATAL
1. **The delegation deletes the network population.** Arm 2 gates on `error == rate_limit` (§5.2) — a
   `server_error`/ENOTFOUND death writes no document. §7.2 then makes `locate)` `exec cc-limited --tsv`
   and retires `lf_locate` (`lr-fleet.sh:143-262`, −140 LOC), leaving no scan fallback. But
   `lr-fleet.sh:121` `NET_RE`/`:123` `BLOCK_RE` exist *because* of a named incident — `:116-117`:
   "2026-09-09, operator report: six panes killed by one DNS outage, `--locate` said '(no
   limit-blocked session anywhere)'". Da re-creates that exact regression by construction. Da's
   disposition enum (§4.3) has no `IDLE-AFTER-ERROR`, no `RESUMING`, no `CWD-GONE`, and no
   `kind=network` — yet `--recover` refuses network rows *by kind* (`lr-fleet.sh:128-131`).
2. **The column-append breaks a shipped consumer, and the design asserts it does not.** §10.1: "every
   existing `IFS=$'\t' read -r _uuid _err _kind _ts` caller keeps working … the shipped callers use
   `_ts` only for display". `hooks/net-recover-arm.sh:192-194` uses neither form — it does
   `_ts="${_rec##*\t}"`, the LAST field. Measured: with four columns appended, `_ts` = `cli`
   (`_err=[rate_limit] _ts=[cli]`). `_ts` is not display — `:200` feeds it to `_turn_ended_after`,
   whose python does `d.get("timestamp") >= ts` (`:175`). `"2026-09-19T19:53:38.683Z" >= "cli"` =>
   `False`, so `:177` returns 1 ("still in flight") forever ⇒ the network asyncRewake never fires.
   Defect 2 silently disables the one arm that partly covers defect 1.

## MAJOR
3. **The census latency headline is borrowed from a prototype of a different store.**
   `cc-limited-proto.py:8` reads `stop-failure/ ∪ parked/ ∪ cc-registry ∪ cc-beats ∪ locks` — Db's
   inputs, not `state/`. §11.4 cites "proto 0.050 s wall today over the same stores" for a census that
   reads none of them. The bottom-up sum (read40 1.0 ms + ps 29.6 ms + python 30 ms) is credible and
   points the right way; it is an estimate, not the measurement it is presented as.
4. **`origin_class` is dead on arrival as sketched.** §5.2 sources only `$_lrlib`, but
   `scripts/limit-recover/lr-lib.sh` sources neither `hooks/lib/agent-identity.sh` nor
   `hooks/lib/origin-identity.sh` (grep => no output), and `stop-failure-marker.sh:47-59` sources only
   `lib/idl-log.sh`. `oi_origin_class` is undefined ⇒ `|| echo unknown` on every death, forever. The
   bind is the point: fix the sourcing and you buy back the 0.19–0.23 s + worst-case 0.36 s above.
5. **Exit 5 outranks 1 (§11.2), so the work-present signal is not composable.** With one FAULT and six
   RECOVERABLEs the census exits 5; a consumer testing `-eq 1` — which is what "1 = needs recovery"
   invites — sees no work the moment any fault exists. Severity and work-present are two axes on one code.
6. **"`--tsv` … 11-field lr-fleet row, byte-compatible" is unsatisfiable on two columns.** `tier` is
   `null at birth` (§3) while `lf_locate:203` computes it via `lr_tier_from_transcript`, and
   `tests/lr-fleet.bats:55` pins "with its pane and transcript **tier**". `kind`/`kinds` have no source
   for the dropped network class. §16's "byte-equal to the lr-fleet.bats locate expectations" is red.
7. **Three stores for one population, indefinitely.** marker (kept by design, §2) + `parked/` ("a view
   after one release" — unscheduled) + `state/`. §19 admits it and ships `--verify DISSENT` to render the
   disagreement. The lens asked ONE census; this is one census over three stores plus a 10-subcommand
   mutation CLI (`lr-state`) that five separate actors must remember to call — §19 concedes a forgotten
   transition leaves RECOVERING and calls the resulting false FAULT "deliberate polarity".
8. **Burst CPU is unbudgeted.** §9's concurrency argument is about file writes only ("30 DISTINCT
   files, no shared read-modify-write"). 30 simultaneous deaths = 30 × (`ps -axo` 624 KB + awk +
   possible 7 MB grep+jq) on a box that is loaded *because* 30 sessions just died. No jitter, no
   per-death CPU cap.
9. **Agent surface cost is real and unbudgeted.** Three new surfaces (`cc-limited` 8 modes,
   `lr-state` 10 subcommands, `lr_predicate.py`) and edits to `commands/{recover,limit-recover}.md` —
   resident skill text in every session. §10.1 cites LR-o (the skill listing quotes the limit strings
   into every session) and then does not count its own growth.

## Where it genuinely wins the lens
- **~500–1,000× on the read path, and the window matters more than the ratio.** P8 R1: `--locate`
  43.558 s vs proto 0.067 s, and a transplant completed *inside* the 43.6 s window — `--locate` rows
  are not a snapshot. Da's census window is effectively atomic.
- **Token cost on the operator's actual ask is a ~100× win**: one grouped ~15-line table (§11.5)
  replaces 14 pane screenshots. Scriptable end to end — python, exit codes, `--json`/`--tsv`, no model.
- **Zero-fork statusline chip.** `${KITTY_WINDOW_ID}` / `${PAY_SID:0:8}` are parameter expansions, and
  `statusline.sh` is 486 lines with the echo at `:486` — the insertion point checks out. `#` over `⌗`
  is the right call, and refusing `refreshInterval 1` is correct.

## Best ideas worth grafting
- **`claim{actor, run, ts, deadline, log}` + the reaper (§8).** The only mechanism in any of the three
  designs that can NAME a claimed resume that produced nothing, with the log path attached. §19 is right
  that a read-time join over markers cannot hold a claim. Graft this into Db as a claim *file* rather
  than a whole state store, and it costs one directory.
- **`kind:"limited"` through the EXISTING `session-beat.sh` writer with ZERO consumer edits** —
  `spawn-presence.sh:319` selects `.kind=="prompt"`, so the phantom dies by construction. Pair it with
  the `kind=zzz` contract test (§16) and the retirement of the `lr-fleet.sh:293-335` phantom shim.
- **T0-mandatory / T1-structural / T2-open-scope-group predicate, with F9 (skill-listing text, no
  envelope) as the FIRST assertion.** The open `(?P<scope>…|[A-Z][a-z]+)` group catches the next
  model-scoped cap without an edit; F9 is the only test that can catch a T0 regression.
- **Exit 4 = store unreadable, NEVER an empty list at exit 0**, citing `lr-fleet.sh:439-445`.
- **Resolver refuses on ≥2 hits (exit 3, candidates printed), never disambiguates by recency** — two
  live panes on different accounts share the title "limit-recover optimization".
- **`--reap` as the only persisting mode; a census is otherwise a pure read.**
- **Backfill's transcript resolution**: glob all config dirs for `<sid>.jsonl ∪ .handed-off`,
  realpath-dedupe the `~/.claude-next → ~/.claude` mirror, newest copy with ≥1 assistant record.
- **The `-k` deletion** at `lr-fleet.sh:534` and `commands/limit-recover.md:437` — bare kickstart only.
