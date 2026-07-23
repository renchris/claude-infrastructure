<!-- source: /Users/chrisren/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/d521032c-ca95-402f-bc5a-28625fa9d4f6.jsonl
 turns=75 assistant_texts=9 last_stop=end_turn mail_injections=[] -->

SendMessage isn't available in this subagent context (consistent with the documented "named bg subagents can't SendMessage" constraint). Returning findings as my final report for lead to harvest from the transcript.

---

# STATE/CONFIG POOL CENSUS — claude-infrastructure

Read-only, ~22 tool calls. Every claim path:line or empirical-command cited. Empirical vs theoretical marked. Brief was clean (no drift triggers — internal infra census).

## (a) STORE CENSUS

| Store | Format | Writers (path:line) | Readers | Reconciler | Locking | GC | Race-risk |
|---|---|---|---|---|---|---|---|
| **idl.jsonl** | JSONL append | **7+ hooks DIRECT-append UNLOCKED**: boundary-handoff:108, waiting-recycle:290, anti-deference-nudge:69, cc-decide:54, cc-reaper:158/164, autonomy-sweep:123, gate-manifest; **+1 LOCKED**: cc-idl:174 (`append`) | cc-audit, cc-digest:181, cc-discover, cc-reaper, operator-readout, cc-wave-plan | none | mkdir-mutex **only on cc-idl path** (cc-idl:65-77) — **bypassed by every hook** | rotate-autonomy-logs.sh (size/mtime→.gz) | **⚠ chain desync** (c#1); append interleave theoretical only (O_APPEND per-line atomic) |
| **idl.jsonl.chain** | TSV hash-chain | cc-idl seal (**manual only — NO auto caller**) | cc-idl verify (**manual only**) | none | mkdir-mutex | **never reset by rotation** | **OPEN — empirically BROKEN** (c#1) |
| **backlog.jsonl** | JSONL append-only fold | cc-backlog | cc-dispatch, operator-readout, cc-value, cc-discover | cc-backlog `reap` (stale-claim) | append-only fold (no explicit lock confirmed) | `compact` verb (terminal >30d) | reopen-thrash **CLOSED** (cc-backlog hdr "REOPEN GUARDS 2026-07-20") |
| **decisions/*.json** | per-file JSON | cc-decide:118/148 (atomic tmp+mv) | cc-blockers, operator-readout | cc-decide expire-sweep :199 | **atomic-rename only, NO lock** | **none** (68 files) | concurrent resolve/expire RMW=last-writer-wins (c#4) |
| **dod/*.md** | per-file md | dod-persist.sh | waiting-recycle, handoff-fire, operator-readout | none | atomic (unconfirmed) | **none** (5 files) | low (SID-keyed single-writer) |
| **cc-registry/<paneUUID>.json** | per-file JSON | session-register.sh (**write-once SessionStart**) + cc-reconcile (heal) | cc-sessions, cc-classify, cc-reaper, cc-notify | **cc-reconcile** (cc-reaper:119-129, :347) | none (per-pane single-writer) | cc-sessions age-sweep | write-once-miss **CLOSED** (cc-reconcile hdr, ad37447) |
| **wait-contracts/*.json** | per-file JSON | cc-wait (atomic mktemp+mv :160; **fail-closed** :88) | 9 readers: waiting-recycle(S3), never-stuck-gate, wait-safety-gate, exit-deadline, reaper-safety-gate, cc-classify, desk-invariant, lead-deathwatch | **liveness-filtered reads** | atomic rename | read-time liveness + close-rm | **none material** (best-designed store) |
| **mailbox/<uuid>.md + .seen/.acked** | md + int cursors | cc-notify, mailbox_append | mailbox-drain, cc-await-ping | cursor clamp (past-EOF→re-deliver) | **mkdir-lock** (mailbox-pending:69, 2s→giveup **lock-free dup-risk**) + atomic cursor :88 | (rotate) | lock-giveup dup, **bounded+documented** (c#6) |
| **pages/*.page+.notified** | 2-file pairs | cc-reaper, desk-invariant, cc-dispatch, supervisor | notify layer | page-damp.sh | none | **NONE — 359 files, oldest Jul 14** | dedup bounded; **unbounded growth** (c#3) |
| **push-records/*.json** | per-file JSON | push-send.sh | sweep-push-seen | none | none | **NONE (135)** | unbounded (c#3) |
| **comms-alarms/*(.handled)** | per-file JSON | cc-notify, cc-inbox-guard | — | .handled marker | none | **NONE (289)** | unbounded (c#3) |
| **inbox-guard/*.escalated** | 1-line marker | cc-inbox-guard:121 | cc-inbox-guard | damped | none | **NONE** | dedup bounded |
| **sweep-seen/ + sweep-push-seen/** | empty markers | autonomy-sweep:113 | autonomy-sweep | — | none | **✓ find -mtime +7 -delete (:110) — ONLY properly-GC'd marker dir** | dedup bounded |
| **waiting-recycle STATE_DIR** (fired-/arm-/disarm-/cooldown-/live-/brief-/busyforce-) | markers | waiting-recycle:231/251, boundary-handoff | waiting-recycle, desk-recycle-invariant | desk-recycle-invariant | mkdir-atomic acquire (Stage-3) | none | double-fire **mitigated** (mkdir); rm-disarm single-desk-per-cwd |
| **desk-invariant/ paged-*.marker** | empty/mtime | desk-invariant:192 (`: >`), desk-recycle-invariant:92 | invariant scripts | stale.marker | none | none | page-dedup bounded |
| **pending-activation/*.sh(.done)** | scripts+done | install/operator | activation scripts | .done gate | none | none | operator-paced, none |
| **session-index + .lock** (5297 sess) | index | session-index-helpers.sh | cc-sessions search | — | **flock + mkdir fallback**, 300s→**proceed unlocked** (:74) | ? | lock-timeout-proceed theoretical (c#5) |
| **accounts.json + /tmp/claude-accounts-cache.json** | JSON | claude-accounts (**fcntl.flock** :329/806/837) | cc-board, handoff-fire, cc-route, lr-* | last-good ledger | **proper flock** | 90s TTL cache | **none** (correctly locked) |

## (b) CONFIG / DRIFT MAP

| Layer | Live-vs-repo mechanism | Drift checked by | UNCHECKED drift |
|---|---|---|---|
| hooks/ bin/(cc-*) scripts/ commands/ | **per-file symlink → checkout** (verified `readlink`) | auto (symlink can't content-drift) | **brand-new tracked file never linked** (memory deploy-lag 2nd mechanism) |
| ~/bin/ launchers | **COPY** (install.sh) | **deploy-parity-assert.sh** (claude-accounts symlink+STRICT; rest content-only) | nothing (covered) |
| **skills/** | **REAL copies** (verified: all 20 dirs REAL, not symlinks) | **NOTHING** — deploy-parity covers only ~/bin | **entire skills/ layer** — repo skill edit silently undeployed |
| settings.json ×5 dirs | **real per-account files** (distinct inodes) | settings-drift-assert.sh (cross-dir asymmetry) + settings-dedup-stop.sh (intra-dir dup double-fire) | **a rule wrong/missing in ALL 5** (no SoT compare); template-vs-live semantic drift |
| **~/.claude/CLAUDE.md** | **real file, manual sync** | **NOTHING** (grep: only refs, no diff/assert) | **repo divergence** — currently in sync by luck (both 25235B, empirical `diff -q` clean) |
| per-account knowledge symlinks | config-mirror.zsh | config-mirror-assert.sh (SessionStart) | fires AFTER config load → fixes NEXT session only |

## (c) OPEN-RACE / ANOMALY LIST

1. **idl.jsonl.chain tamper-evidence is DECORATIVE — OPEN (empirical).** `cc-idl verify` → `TAMPER: idl.jsonl has 3477 line(s) but chain sealed 6910 — 3433 sealed record(s) DELETED/TRUNCATED`. Root: (i) no automated seal caller (grep hooks/bin/scripts/launchd/tests/nightly = **empty**); (ii) rotation truncates idl.jsonl but never rebases chain (rotate grep `chain`=0); (iii) 7 hot-path hooks direct-append, bypassing cc-idl mutex+seal. cc-idl:7 exists to make "lie-class T2 ledger-lie DETECTABLE" — now false-positives permanently. Chain last-sealed Jul 19; idl live Jul 23.
2. **idl multi-writer unlocked append — THEORETICAL corruption / REAL chain-desync.** cc-idl:174 locks; boundary-handoff:108 + 6 others raw `>> "$IDL"`. O_APPEND makes per-line interleave safe; real damage is the chain gap (#1).
3. **No unified retention across 6+ marker-dir stores — OPEN (empirical).** Only sweep-seen GC'd (autonomy-sweep:110). pages(359)/push-records(135)/comms-alarms(289)/inbox-guard/decisions(68)/dod grow unbounded (grep `-mtime`/prune on these = empty). Slow-burn inode growth + stale-marker false-signal risk. The systemic-fix pattern memory flags (desk-whack-a-mole).
4. **decisions/ concurrent resolve↔expire RMW — OPEN-minor.** cc-decide:118/148/199 atomic-rename, no lock → last-writer-wins on same id. Operator-paced, low freq.
5. **session-index lock-timeout-proceed — THEORETICAL.** session-index-helpers:74 proceeds unlocked after 300s. Benign in practice.
6. **mailbox lock-giveup dup — OPEN-bounded (documented).** mailbox-pending:71-76 gives up after 2s → lock-free (dup, never hang). By-design.
- **CLOSED (cite fix):** registry write-once → cc-reconcile (ad37447); reopen-thrash → cc-backlog reap+guards; cross-session git-index → worktree policy; Stage-2 double-fire → mkdir acquire; false-stall HEAD-diff → fixed-HEAD ref.

## (d) C-DSH-1 KERNEL-ABSORPTION MAP

**Record** = SID/cwd-keyed write-before-act {state:WATCHING|COORDINATING|FIRING, ts, DoD, lifecycle:fired→exited→relaunched→engaged}.

**ABSORBS / RETIRES:**
- **waiting-recycle STATE_DIR sprawl** (7 marker families) → one record's `lifecycle`+`state`.
- **wait-contracts S3/S5 desk-state INFERENCE** → watcher reads `state` directly (contracts store stays — it's inbound-wait coordination, not desk state).
- **desk-invariant HALF-ARMED + paged-markers** → `lifecycle` attests arm-live.
- **WHAT-not-WHY inference class** (cc-board STALL?, supervisor sweep target, cc-notify external-typer fence) → read `{state}` not mtime/HEAD/telemetry proxies.
- **dod/ partial** → the `DoD` field.

**DOES NOT ABSORB (honest sizing):** idl.jsonl+chain (history-integrity audit); backlog.jsonl (cross-session work items); decisions/pages/push-records/comms-alarms (queues/audit); settings.json/CLAUDE.md/skills (deploy layer); session-index/accounts.json; **the GC gap** (kernel needs its own retention). **Size:** C-DSH-1 dissolves the **desk-self-recycle lifecycle-inference spine** (~7 latch families + ~5 indirect-signal consumers) — NOT a universal state kernel. Its generalization (store-manifest + retention daemon for ALL stores) is a strictly larger, separate campaign (e#2).

## (e) CANDIDATE FRONTIER PROBLEMS

**F1 — IDL tamper-evidence chain is structurally defeatable by its own operating environment**
- Evidence: empirical `cc-idl verify`=TAMPER (3477 vs 6910); no auto seal/verify caller (grep empty); rotate never rebases chain (grep chain=0); cc-idl:174 lock bypassed by boundary-handoff:108 +6.
- Mechanism class: multi-writer append vs single-writer seal + unbounded-rotation vs immutable-prefix — three-way structural conflict.
- Mitigations+status: mkdir-mutex on ONE writer (bypassed); manual seal/verify (never run) — **effectively unmitigated**.
- Resists normal fixes: seal-on-every-append serializes 7 hot-path Stop/PreToolUse hooks behind one mutex (latency regression); rotation-rebase must atomically re-anchor genesis during truncation; any bypassable writer defeats tamper-evidence by definition.
- Cost: unmeasured — measure = `cc-idl verify` in nightly + days-since-valid (currently ≥4).
- Fix sketch: lock-free per-writer chain segments merged at verify (Merkle forest), OR rotation-aware genesis re-anchor sealing+rotating+re-genesis in one critical section.
- Confidence HIGH / stale-risk LOW.

**F2 — No store-manifest → no unified retention or deploy-parity across the state pool**
- Evidence: 6+ marker dirs unbounded (pages 359/push 135/comms 289 empirical; only sweep-seen:110 GC'd); skills/ real-copies + CLAUDE.md real-file have zero parity assert (deploy-parity only ~/bin).
- Mechanism class: absent registry — every store hand-rolls or omits GC + deploy semantics.
- Mitigations+status: per-store ad-hoc (sweep-seen mtime+7; idl rotation; cc-sessions age-sweep) — **partial, whack-a-mole**.
- Resists: per-store retrofit is the exact pattern memory flags as needing a systemic fix; unified retention/parity needs a store-registry the system lacks; skills can't symlink (breaks per-account mirror), CLAUDE.md intentionally real.
- Cost: unmeasured — measure = marker-file growth/week + inode count; parity = content-hash every live surface.
- Fix sketch: declarative store-manifest {path, format, writer, retention, deploy-mode} → ONE retention daemon + ONE content-hash parity gate over symlink/copy/real. C-DSH-1 generalized from desk-state to ALL state.
- Confidence HIGH / stale-risk LOW.

**F3 — Indirect-signal causal inference is systemic (the kernel's true raison d'être)**
- Evidence: recycle/page/stall/reap read mtime/HEAD-move/telemetry-freshness/last-message proxies; memory logs ≥3 wrong causal claims (desk-read-transcript-before-asserting-WHY); C-DSH-1 synthesis names 8 holes converging here.
- Mechanism class: no authoritative current-state record → every consumer re-derives WHY from a different WHAT proxy.
- Mitigations+status: FN-safe approximations (mailbox-mtime + contract-scan + latches) — **works, inelegant, drift-prone**.
- Resists: state genuinely distributed across processes; a poll loop can't see another session's intent without a written record; more proxies compound it.
- Cost: unmeasured — measure = causal-claim corrections/week in transcripts.
- Fix sketch: the C-DSH-1 record scoped as a WHY-substrate (write-before-act intent), not merely recycle-lifecycle. Generator-class.
- Confidence HIGH / stale-risk MEDIUM (C-DSH-1 already the campaign candidate; framing may shift).

**BLOCKERS/UNCERTAINTIES:** (1) cc-backlog append lock unconfirmed — likely unlocked O_APPEND fold like idl (append-only tolerates it). (2) dod/ atomic-write mechanism unconfirmed. (3) pages/ GC outside hooks/bin/scripts unchecked (grep there empty → high-confidence none). (4) 6910-sealed implies seal ran ≥once (~Jul 19) then rotation broke it — timeline not reconstructed. (5) settings.json ×5: only 3 dirs exist on this box (~/.claude,-next,-secondary); -tertiary/-quaternary in DEFAULT_DIRS may be absent → drift-assert may skip-on-missing (its own blind spot).