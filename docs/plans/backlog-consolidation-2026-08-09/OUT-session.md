# cluster-C-session + cluster-C-worktree — triage vs origin/main @ 51bdb524720aeb6c2fd49d14c1c584dce1456650

Measured 2026-08-09. Trunk head: `51bdb524` *"test(it2-kitty-operator-safety): the suite borrowed the
operator's kitty identity…"* (2026-08-09 16:51 -0700). Shared checkout sits at `c2ccbeb8` on `main`.

## Summary

counts: **PRUNE 3 / UPDATE 10 / KEEP 15 / MERGE 2** = 30 (slice = 15 session + 15 worktree)

### The measurement the lead asked for — stranded work, live

`git worktree list` = **425 registered worktrees**, 201 distinct HEAD shas. Classifying each head
against `origin/main` by **patch-id** (`git cherry`, not a raw commit count — three heads read
"455 commits ahead" but only 8–9 patches are genuinely unlanded, the rest already landed rebased):

| | |
|---|---|
| worktree heads that are ancestors of trunk (nothing stranded) | **168 / 201** |
| heads ahead of trunk | **33** |
| …of those, ahead but 0 unlanded patch-ids (fully landed, rebased) | 3 |
| **heads holding genuinely unlanded work** | **30** (spanning 32 worktrees, 31 branches) |
| **total unlanded patch-ids stranded on those branches** | **103** |
| orphan dirs: `~/Development/.worktrees` on disk vs git-registered | **553 vs 425 = 128 orphaned** |

Top strands (unlanded-patches · merge-base date · branch):

```
17  2026-08-07  deskless                          .worktrees/deskless
 9  2026-07-29  fix/accounts-eval-bin-resolver    .worktrees/wt-evalbin
 8  2026-07-25  wt-02ba4e52389a                   .worktrees/wt-02ba4e52389a
 8  2026-07-29  wt-dda10a298842 / wt-e06ba316a1aa (one sha, TWO worktrees)
 8  2026-07-31  terminal-arm-land                 wt-terminal-land
 7  2026-07-25  wt-63929c8d6072                   .worktrees/wt-63929c8d6072
 6  2026-07-31  terminal-iterm2-vs-kitty-arm      wt-terminal-arm
 6  2026-07-25  wt-6cab0ab3cb2f                   .worktrees/wt-6cab0ab3cb2f
 5  2026-08-09  fix/sigterm-forensics · 4 2026-08-09 cloud-g5-create · 3 fix/postland-kill-nonverdict
 …20 more branches at 1–2 patches each
```

Base-date distribution is the second half of the story: **24 of the 30 divergent heads were cut from
a base ≥9 days old** (2026-07-25 → 2026-08-01). These are not "in flight"; they are cut from a stale
base and stopped.

### The base-freshness guard — VERIFIED, and it is 2-of-3

The known open item ("never cut a branch from a stale shared checkout") is **partially built, and the
unguarded cutter is `hooks/worktree-setup.sh`**:

| cutter | fetches first? | base ref passed? | verdict |
|---|---|---|---|
| `bin/cc-dispatch:679,684` (new-branch arm) | ✅ `git fetch origin -q`, warns on failure | ✅ repo's own `origin/HEAD`, `origin/main` fallback | **guarded** |
| `bin/cc-dispatch:682` (branch-REUSE arm) | fetch yes | ❌ reuses `$br` at whatever sha it holds | **hole** |
| `scripts/handoff-fire.sh:5938-5939` | ✅ fetch + warn | ✅ `$BASE` (default `origin/main`) | **guarded** |
| `hooks/worktree-setup.sh:189` | ❌ **zero `fetch` in the whole file** | ❌ `git worktree add "$WT" -b "$BRANCH"` — **no base** | **UNGUARDED** |

`worktree-setup.sh:189` cuts from `$REPO`'s **current HEAD**. `$REPO` is the shared checkout, which
the project `CLAUDE.md` says "frequently sits on another session's feature branch". That is the exact
failure mode the open item names, live in the tree today, and it is the mechanism behind the 24
stale-base strands above. `docs/plans/GROUND_UP_REBUILD_MAP.md:56` independently ruled this
("**Worktree FRESHNESS AT HANDOUT**… no row's cell names this precondition") to row 11 — **open,
attempt #3** — naming `cc-dispatch:1258` and `cc-dispatch:680-684` but **not** `worktree-setup.sh:189`.

## Verdicts

### cluster-C-session (15)

```
11c25d8f7c55 | UPDATE | root cause is now ESTABLISHED, contradicting the item's own "NOT ESTABLISHED":
                        hooks/goal-inert-watch.sh (on trunk, symlinked live at ~/.claude/hooks/,
                        Aug 9 14:45) carries the decompiled CC Stop handler — `_We(B)||Tio(B)` removes
                        the goal hook whenever a non-terminal local_bash task exists, and restores it in
                        `finally`, so the registry reads correct before and after and is wrong only
                        DURING. `cc-await-ping --timeout 14400` makes that true by default on this box.
                        Item should now say: cause known, remedy = register the compensating Stop hook
                        (see 0db2c692efb7); the "untested hypothesis" paragraph is dead.
9f684129d020 | MERGE  | canonical = 1dca461d4b90. Same ask (install Claude GitHub App on
                        renchris/claude-infrastructure via claude.ai/code), same root
                        (bundle-mode create → no authenticated remote), same doc family.
d74191a99b5f | KEEP   | verified live: `launchctl list` shows com.claude.compressor-sentinel PID 48326
                        still loaded; cb21783b IS an ancestor of origin/main; scripts/install.sh:696
                        carries `if $loaded && ! $plist_changed; then continue` verbatim, plus a second
                        live-PID skip at :700. A script-only land still cannot reach the running process.
ed6d0716caa7 | KEEP   | scripts/lead-deathwatch.sh:13 states the watch-list is fed "by the P8 registry
                        (spawn-instant registration)"; scripts/wait-safety-gate.sh:70 still prints
                        `todo L1-e "NOT BUILT"`. No producer found. Premise intact.
9bc82b51843e | UPDATE | both track branches are FULLY LANDED — refs/heads/feat/readme-timeline-banner
                        (1c4813ab) and refs/heads/fix/idle-recycle-not-proactive (21ac6186) are both
                        ancestors of origin/main, 0 unlanded patches. Not PRUNEd because "plan advanced"
                        ≠ "plan complete": re-scope the item to whatever the plan doc still lists open,
                        or close it. The two worktrees are now pure GC candidates (feeds 475b43aacbf2).
fc775c86145b | MERGE  | canonical = 11c25d8f7c55. Same subject (why /handoff stopped using /goal); its
                        answer is the file 11c25d8f7c55's UPDATE cites, docs/research/
                        goal-in-handoff-2026-08-08.md (on trunk) + hooks/goal-inert-watch.sh.
635eb82ef810 | KEEP   | live process is `/Users/chrisren/.claude-220/...claude.exe` (read from $PPID
                        argv, not a launcher's --version); installs on disk are .claude-219 and
                        .claude-220 only — no .claude-224. The audit has not been run.
0db2c692efb7 | UPDATE | HALF DONE. The converge half is complete — ~/.claude/hooks/goal-inert-watch.sh
                        is a live symlink into the checkout (Aug 9 14:45). The registration half is NOT:
                        parsing ~/.claude/settings.json for any hook matching "goal" returns `[]`, and
                        migrations/0005-goal-inert-watch-registration.sh sits unrun in the tree. Item
                        should now read: run migration 0005 only.
49cfd01dd5eb | PRUNE  | FIXED, and it landed the day BEFORE the item was filed. 09aca05b (2026-08-08
                        22:52) "fix(handoff-fire): an absent it2 shim aborted the fire under pipefail,
                        so its own fallback was dead code". Both named sites now carry the guard INSIDE
                        the substitution: :6073 `REAL_IT2="$(sed … 2>/dev/null | head -1 || true)"` and
                        :6106 the same for PYTHON_BIN, with the comment "`|| true` is LOAD-BEARING".
                        The cited lines :5237/:5247 no longer hold that code (file grew to 7461 lines).
                        A wider sweep for `VAR="$(… 2>/dev/null | …)"` without a fallback returns no
                        unguarded remainder — every hit has `|| true` / `|| return` / `|| ""`.
1dca461d4b90 | KEEP   | canonical GitHub-App item. Operator-only (GUI + GitHub credentials); nothing in
                        the tree can close it. docs/plans/CLOUD_OBSERVABILITY.md is on trunk.
f76e7d78aaac | UPDATE | premise half-refuted: `scripts/lr-fire-resume.sh` does not exist — the file is
                        `scripts/limit-recover/lr-fire-resume.sh`. The oracle IS landed (735c3c79 is an
                        ancestor of origin/main; hooks/lib/engagement.sh present). Both consumers still
                        have ZERO references to it (grep -c engagement = 0 on both). Item stands with
                        the corrected path.
8ad4b02602dc | KEEP   | not refuted by any cheap check — no `scripts/cc-await-ping*` to inspect and the
                        premise is a design gap in CONCURRENCY_PROGRAM §S6.7 Phase E, not a code
                        assertion. Per the contract, an unread premise is KEEP-with-note, not PRUNE.
7176bda11a8d | KEEP   | CONFIRMED live at scripts/handoff-fire.sh:2322 inside recycle_engaged() (defined
                        :2294): `[ -f "$pdir/$newsid.jsonl" ] && assistant_turn_in …` — the exact
                        root-level resolve. Path (a) at :2313 and the sibling at :3358 both already use
                        `find "$pdir" -name "$sid.jsonl"`, and :3343 carries the comment "`find`, NOT
                        \"$pdir/$sid.jsonl\". A CC_PROJECTS_DIRS entry is the projects ROOT". Path (b)
                        is the one site that never got the fix.
22a597979284 | UPDATE | facts confirmed — b9896b4e is on trunk, `--stat` shows all 4 named files
                        (assets/banner/recycle-bmo.svg, assets/demo/recycle-bmo.mp4, docs/research/
                        recycle-banner-source-fidelity-2026-07-30.md, tools/banner/recycle.py) riding
                        under "fix(qos-chokepoint): a vacuous recursion test hid a live two-shim
                        fork-storm". But the DECISION it asks for has only one safe answer: re-attributing
                        means rewriting landed trunk history, which Git Safety forbids. Recast as: accept
                        the mis-attribution, record the provenance where the files live, and close.
d4c091a86fb8 | UPDATE | re-verified as the item itself demands. 12 `_cc_sync_account` call sites in
                        ~/.zshrc; the SILENT ones (stderr discarded) are lines
                        179,180,181,235,251,252,264,265,327,517 — that is still 10, but the tenth moved
                        from 488 to 517, and the LOUD exemplar moved from 450 to 479. Line 327 is silent
                        (item listed it correctly); the item's "488" is now 517. Remedy unchanged.
```

### cluster-C-worktree (15)

```
b03eb3f28845 | KEEP   | scripts/lib/worker-claim-gate.sh exists and gates the WRITE only — and its own
                        header (:28-32) records that the obvious remedy is already refuted in this repo:
                        "tell the duplicate to stand down … is ALREADY REFUTED … It has not drained the
                        stand-down". So nothing stops the SESSION, and the cheap fix is closed off. This
                        is the direct producer of "15 clones alive in one worktree" and of the
                        two-worktrees-on-one-sha rows in the measurement above.
91a29f4806fe | PRUNE  | the CONTENT landed. 7edc3b5b is not an ancestor of origin/main, but
                        `git grep origin/main -- bin/claude-accounts` finds the fix's own docstring at
                        :510 and :515 ("reading of 17691 rendered as \"$176.91 spent\"" / "the same
                        2026-07-26 account read false while $176.91 sat on the meter. Spend is …") —
                        i.e. verified by CONTENT, the standard this repo's CLAUDE.md mandates. The sha
                        is preserved on refs/heads/save/accounts-cents-7edc3b5b. The named rescue branch
                        `rescue/shared-checkout-accounts-7edc3b5b` is gone (renamed to save/*); only
                        rescue/concurrency-census-2026-08-07 remains under rescue/.
417fbab3c317 | KEEP   | verbatim true TODAY, measured on the live shared checkout:
                        `git config --get branch.main.merge` → `refs/heads/up`; `branch.main.remote` →
                        `origin` (the repair that DID land); `git rev-parse --abbrev-ref main@{u}` →
                        `fatal: ambiguous argument 'main@{u}'`; `git branch --list up` → `up` still
                        exists. Both the one-command fix and the cosmetic `-D up` are still open. This
                        is the single highest-leverage row in my slice — see M-1.
6cab0ab3cb2f | UPDATE | the GC franchise is live but its headline number is dead: `/tmp/claude-*` is now
                        18 entries at KB scale (`du -sh` tops out at 4.0K), not 21GB — that TMPDIR pile
                        was wiped, almost certainly by one of the 4 kernel panics. The DURABLE half is
                        worse than filed: 553 dirs vs 425 registered = 128 orphans (see 475b43aacbf2).
                        Re-scope to the worktree/mailbox/pidfile/transcript arms and drop the /tmp figure.
8f4eae55a0c7 | UPDATE | core intact (no local mechanism can close the `git push --no-verify`-from-a-file
                        bypass; a GitHub server-side ruleset is the only closure) but the cited anchors
                        moved: scripts/ship-land.sh is now 2332 lines and the two plain pushes are at
                        :2100 and :2145, not :1858/:1903. Operator-only (GitHub web UI).
a615d309c182 | KEEP   | docs/plans/MACHINE_CAPACITY_V2.md is on trunk; grep for "rung 6" / "Rung 6" /
                        "coalition" returns nothing. The record was never written. The deferral reason
                        (a concurrent session holds live edits) is exactly the shared-checkout
                        contention M-1 addresses — this item unblocks when M-1 lands.
216f429128a2 | KEEP   | premise not refuted from this repo; reso's `.eslintcache` is absent at the reso
                        root, which is consistent with "worktree-local, never amortises". CROSS-CLUSTER:
                        this is a reso item and belongs in cluster-P-reso — see Notes for the lead.
85bb7476f57f | KEEP   | MEASURED: both named refs resolve to nothing, local or remote —
                        `git rev-parse --verify refs/heads/feat/codex-security-port` and
                        `refs/remotes/origin/...` both fail, same for `infra-currentstate`. Per the
                        repo's own rule (a gone ref is a lookup miss, not proof of landing) these two
                        escalations are unresolved. Recover from the graveyard
                        (`git log --all --diff-filter=A` + reflog) or close them explicitly.
475b43aacbf2 | UPDATE | RE-MEASURED TODAY and both halves roughly doubled: 553 dirs on disk in
                        ~/Development/.worktrees vs 425 git-registered = 128 orphaned (item says
                        273 / 151 / 122). Registration itself nearly TRIPLED (151 → 425), which is the
                        newer and more alarming number — the registry is growing faster than the
                        orphan pile. Destructive rm remains an operator call; the growth rate is not.
dc426ee8df11 | KEEP   | row 11 ("Worktree management") in docs/plans/GROUND_UP_REBUILD_MAP.md is OPEN and
                        explicitly "mid-flight on attempt #3". Its bound scope, read from the map today,
                        covers: freshness-at-handout (:56), AC-7's missing kill switch, the
                        KEEP-vs-STALE adjudication in worktree-gc.sh:726 ("dirty-because-abandoned must
                        be separable from dirty-because-unlanded — the current rule cannot tell them
                        apart"), and the `scripts/worktree-pool.sh` PHANTOM (:57 — referenced by 15
                        files, `git log --all` on it is EMPTY, so handoff-fire.sh:5508's `[ -x "$POOL" ]`
                        gate is permanently false and :5509-5566 is dead code). This is M-1's spine.
55065a61b31c | KEEP   | no refusal exists. `bin/cc-cloud` parses `--branch` with no default-branch check;
                        its own comments confirm the hazard is known and unfixed — :23 "against the
                        default branch instead", :520 "silently runs against the default branch", :768
                        "measured 2026-08-07, origin held 1 head against 286 local branches".
641c1802d75b | KEEP   | CONFIRMED in bin/cc-cloud: `paths=""` initialised at :377, `--paths` optional at
                        :385, written verbatim at :428 (`printf 'paths=%s\n' "$paths"`), read back at
                        :258 (`paths="$(dfield "$f" paths)"`) and consumed at :222. Nothing supplies a
                        default, so a declaration made without --paths files empty and stays ELIGIBLE.
87822050d5e5 | KEEP   | BOTH defects still present and unchanged. commands/compact-memory.md:112 is
                        verbatim `grep -rqF "${f%.md}" "$P/CLAUDE.md" "$P/.claude/CLAUDE.md"
                        "$P/.claude/rules" 2>/dev/null || echo "ORPHAN $f"` — no per-candidate existence
                        test, no `/dev/null` sentinel. The `shopt -s nullglob` prescription is still at
                        :101-102. One commit since the item was filed (98d92d34, "the trigger named a
                        unit that does not truncate") fixed a DIFFERENT defect in the same file.
28ad16b4f9fa | PRUNE  | LANDED. hooks/lib/session-writes.sh exists on trunk, and hooks/completion-assert.sh
                        consumes it: :214 "is any of this MINE? hooks/lib/session-writes.sh answers it
                        from the transcript's own edit …", resolver chain at :259-265, and two calls to
                        `session_writes_paths "$TP"` at :299 and :312. The global CLAUDE.md documents
                        the same mechanism ("attribution via hooks/lib/session-writes.sh … so a sibling's
                        dirt in a shared checkout can never convict you").
d605fd2f4635 | UPDATE | PARTIALLY refuted. A disable switch DOES exist for the cron —
                        scripts/worktree-gc-infra-run.sh:28 `DISABLED="$STATE/worktree-gc-infra.disabled"`
                        and :77-78 `[ -f "$DISABLED" ] && verdict disabled 0` — landed in dae60868, the
                        very commit the item credits with building the cron. But it is a FILE switch, not
                        the env var the standing rule requires, and scripts/worktree-gc.sh (the actual
                        destructive actor) has NO disable of any kind — only `--dry-run` (:128,:149).
                        None of its 16 CC_WTGC_* vars disables it. Re-word to: the ENGINE has no kill
                        switch; the CRON's is a file, not an env var. Corroborating observation from the
                        rebuild map: com.claude.worktree-gc-infra last-exited -9 (SIGKILL).
```

## Master item(s)

### M-session-1 — a worktree can only be cut from a verified-fresh base, and no worktree can be retired while it still holds unlanded work

**Encompasses:** `dc426ee8df11` (spine, row 11) · `417fbab3c317` · `475b43aacbf2` · `6cab0ab3cb2f` ·
`d605fd2f4635` · `85bb7476f57f` · `b03eb3f28845` · `a615d309c182` · `216f429128a2` · `8f4eae55a0c7`
· `9bc82b51843e` (its two landed worktrees become GC input)

**Why this is one effort.** One shared surface: **the shared checkout is the base of every worktree,
and it currently cannot answer "am I current?"** — `branch.main.merge` is the leaked fixture value
`refs/heads/up`, so `main@{u}` is a hard error (`417fbab3c317`, measured live today). Every downstream
symptom in this group is that one fact propagating through the handout path and back:

- **Handout** — `hooks/worktree-setup.sh:189` does `git worktree add -b "$BRANCH"` with **no base ref
  and no fetch anywhere in the file**, so it inherits whatever branch the shared checkout is parked on.
  `cc-dispatch`'s reuse arm (:682) has the same hole. That is the mechanism, and the damage is
  measured: **24 of 30 divergent heads sit on a base ≥9 days old**.
- **Retirement** — `worktree-gc.sh:726` cannot separate *dirty-because-abandoned* from
  *dirty-because-unlanded* (row 11's own words), so the janitor is either too timid (128 orphans,
  553-vs-425) or too dangerous to arm — and it has **no kill switch** at all (`d605fd2f4635`), while
  its cron already died on a SIGKILL.
- **Loss** — 103 unlanded patch-ids on 31 branches, plus two class-B escalations pointing at refs that
  no longer resolve (`85bb7476f57f`). A refused-but-still-running worker (`b03eb3f28845`) keeps
  minting more of them.
- **Contention** — `a615d309c182` was deferred purely because a concurrent session holds live edits in
  the shared checkout; `216f429128a2` is the per-worktree cost of the same sprawl.

Close the base/retirement contract and all of these resolve or become cheap. Keep it open and every
new dispatch adds to the 103.

**Impact.** Highest in my slice, argued from three measurements: (1) **103 unlanded patch-ids are real
completed work that is one `git worktree prune`/`rm -rf` away from loss** — pure downside, no upside;
(2) it touches enforcing stores — `hooks/`, `bin/cc-dispatch`, `launchd/com.claude.worktree-gc-infra`,
and live `git config` — so it is not advisory; (3) it retires 11 items and unblocks a 12th
(`a615d309c182` explicitly names the contention as its blocker). Row 11 is on **attempt #3**, which is
itself evidence that a partial pass does not hold.

**DoD.** (a) `branch.main.merge` on the shared checkout is `refs/heads/main`, `main@{u}` resolves, and
the orphan `up` branch is gone. (b) Every worktree cutter — `hooks/worktree-setup.sh`,
`bin/cc-dispatch` **both arms**, `scripts/handoff-fire.sh` — fetches and asserts its base is at
`origin/<default>` before `worktree add`, and refuses (loudly, with the measured lag) otherwise; a bats
case per cutter, each red on mutation of that cutter alone. (c) `worktree-gc.sh` distinguishes
abandoned-dirty from unlanded-dirty and refuses to dispose of anything with `git cherry origin/main`
output, and both it and its cron carry an env kill switch. (d) A one-command stranded-work report
exists (the `git cherry` sweep in this triage, promoted to `bin/`) and its output is 0, or every
non-zero row is either landed or explicitly warranted. (e) `feat/codex-security-port` and
`infra-currentstate` are recovered from the graveyard or closed with evidence. (f)
`scripts/worktree-pool.sh` is built or its 15 references (incl. the dead `handoff-fire.sh:5509-5566`)
are deleted and `docs/WORKTREE_WORKFLOW.md:162` corrected. All landed on trunk.

**Falsifier** — exit 0 means the whole effort is unnecessary:

```sh
git -C ~/Development/claude-infrastructure rev-parse --abbrev-ref main@{u} >/dev/null 2>&1 \
  && grep -q 'fetch' ~/Development/claude-infrastructure/hooks/worktree-setup.sh \
  && [ "$(git -C ~/Development/claude-infrastructure worktree list --porcelain | awk '/^HEAD /{print substr($0,6)}' | sort -u | while read s; do git -C ~/Development/claude-infrastructure cherry origin/main "$s" 2>/dev/null | grep -c '^+'; done | paste -sd+ - | bc)" -eq 0 ]
```

**First move.** Run the one config write that `417fbab3c317` has been blocked on for 4 days —
`git -C ~/Development/claude-infrastructure config branch.main.merge refs/heads/main` — then confirm
`main@{u}` resolves. It is one command, it un-breaks the deploy-lag sensor (which read 2 against a
true 6), and it is the precondition for every freshness assertion the rest of the effort adds. Note the
auto-mode classifier has refused this write twice in two canonical forms; if it refuses again, that
refusal is the `⛔` to file, not a thing to retry.

**Order.** 1. `417fbab3c317` (config; unblocks measurement) → 2. `dc426ee8df11` row-11 Phase 1, but
**add `hooks/worktree-setup.sh:189` to its scope** — the map's freshness cell at :56 names
`cc-dispatch` only and misses the actually-unguarded cutter → 3. `b03eb3f28845` (stop minting new
strands before draining the old ones) → 4. `85bb7476f57f` graveyard recovery + the 103-patch sweep →
5. `d605fd2f4635` kill switch (must precede arming GC) → 6. `475b43aacbf2` + `6cab0ab3cb2f` disposal →
7. `a615d309c182` (now editable) · `9bc82b51843e` worktrees to GC · `216f429128a2` · `8f4eae55a0c7`
(operator, fire-and-forget in parallel).

---

### M-session-2 — every armed session-lifecycle control is observed by the thing it governs, or says so out loud

**Encompasses:** `11c25d8f7c55` · `0db2c692efb7` · `fc775c86145b` (merged) · `f76e7d78aaac` ·
`7176bda11a8d` · `ed6d0716caa7` · `8ad4b02602dc` · `d74191a99b5f` · `d4c091a86fb8` · `22a597979284`

**Why this is one effort.** Every item here is the same defect at a different station: **a control
reports "armed / landed / set", and the consumer never observes it — silently.** Not a theme, a shape,
and each item is a named instance of it:

| control | reports | actually observed by |
|---|---|---|
| `/goal` | `goal-arm verdict=set` | nothing — CC deletes the hook whenever a non-terminal `local_bash` task exists, and `cc-await-ping --timeout 14400` guarantees one (`11c25d8f7c55`) |
| `hooks/goal-inert-watch.sh` | symlinked live | no Stop registration in `settings.json` — migration 0005 unrun (`0db2c692efb7`) |
| `hooks/lib/engagement.sh` | landed at 735c3c79 | 0 references in either spawn path (`f76e7d78aaac`) |
| `recycle_engaged` path (b) | pane engaged / not | resolves `$pdir/$sid.jsonl` at the projects ROOT; CC nests one level down (`7176bda11a8d`) |
| L1 death-watch | armed watch-list | watch-file has no producer (`ed6d0716caa7`) |
| idle headless session | waiting | no wake path — watcher-exit only (`8ad4b02602dc`) |
| landed daemon script | on trunk | `install.sh:696` skips reload on an unchanged plist ⇒ the running process keeps pre-land bytes (`d74191a99b5f`) |
| `_cc_sync_account` | mirror synced | 10 launcher sites discard stderr ⇒ a missing lib degrades silently (`d4c091a86fb8`) |

The unifying remedy is one rule, not eight patches: **an arm returns a verdict its consumer can parse,
and absence of observation is LOUD** — this repo's own `claimed-outcome-vs-checked-outcome` and
`conclusion-must-reach-the-enforcing-store` memories, applied to the session lifecycle. `22a597979284`
rides here as the same class one level up: a pathspec-less commit reported success over content nobody
observed.

**Impact.** This is the class that makes *every other* effort's completion claim unreliable — a session
that cannot tell "armed" from "live" cannot tell "landed" from "running", which is literally
`d74191a99b5f` (a live daemon executing pre-land bytes for 12 hours). It touches enforcing stores
(`~/.claude/settings.json` via migration 0005, `~/.zshrc`, launchd reload policy). Closing it retires 9
items and removes the reason `/goal` cannot be trusted as a completion mechanism at all. Cheapest
high-value entry point in either master: `0db2c692efb7` is one migration run.

**DoD.** Migration 0005 run and a `goal-inert-watch` Stop hook readable in `~/.claude/settings.json`;
both spawn paths in `scripts/limit-recover/lr-fire-resume.sh` and `scripts/cc-upgrade-gate.sh`
consuming `hooks/lib/engagement.sh`; `recycle_engaged` path (b) using `find` like paths (a)/:3358, with
a bats case red on reverting that one line; `install.sh` reloading on a changed SCRIPT mtime (not only
a changed plist) **plus** a one-shot `launchctl kickstart -k gui/$(id -u)/com.claude.compressor-sentinel`
for the live PID 48326; the 10 `~/.zshrc` sites routed through the loud `_cc_lib` form already
established in-file at :479; L1's watch-file producer built or L1 declared unbuilt in
`wait-safety-gate.sh` output; a wake path for idle headless sessions, or `8ad4b02602dc` re-filed as a
blocked design decision. Landed on trunk **and converged to the live layer** — this effort is precisely
about the difference.

**Falsifier:**

```sh
python3 -c "import json,sys;d=json.load(open('$HOME/.claude/settings.json'));sys.exit(0 if [h for k,v in d.get('hooks',{}).items() for m in v for h in m.get('hooks',[]) if 'goal' in str(h)] else 1)" \
  && grep -q engagement ~/Development/claude-infrastructure/scripts/limit-recover/lr-fire-resume.sh \
  && grep -q 'find "$pdir"' <(sed -n '2318,2326p' ~/Development/claude-infrastructure/scripts/handoff-fire.sh)
```

**First move.** Run `migrations/0005-goal-inert-watch-registration.sh`. The hook is already live on
disk; the migration is the only thing between it and a registered Stop hook, and it converts the
biggest unknown in the slice (`/goal` is inert and nothing says so) into a loud signal on the very next
session Stop. Verify by re-parsing `settings.json` for a `goal` hook, then by counting `goal_status`
attachments over the following hour — the item's own stated verification method.

**Order.** 1. `0db2c692efb7` (migration; makes the rest observable) → 2. `11c25d8f7c55` (re-verify with
the now-loud signal; rewrite its "NOT ESTABLISHED" paragraph) → 3. `7176bda11a8d` (one-line,
self-verifiable) → 4. `f76e7d78aaac` (two spawn paths, corrected file path) → 5. `d74191a99b5f`
(kickstart the live sentinel first, then the install.sh mtime rule) → 6. `d4c091a86fb8` (10 zshrc sites;
re-grep line numbers immediately before editing — they moved twice already) → 7. `ed6d0716caa7` +
`8ad4b02602dc` (build or explicitly declare unbuilt) → 8. `22a597979284` (record provenance, close).

---

### M-session-3 — the three items no agent can drive

**Encompasses:** `1dca461d4b90` (+ merged `9f684129d020`) · `635eb82ef810`

**Why separate, not padding.** Both masters above are agent-drivable to a landed state. These two are
not, and folding them in would make an otherwise completable effort permanently un-completable —
exactly the `👤`-vs-`✅` distinction the close protocol exists to keep separate.
`1dca461d4b90` needs the operator's GitHub credentials in a web GUI (claude.ai/code → install the
Claude GitHub App on renchris/claude-infrastructure); `635eb82ef810` is a vendor-track judgment about
whether to advance the eval binary to 2.1.224, and the contract forbids me running the gate that would
answer it. `8f4eae55a0c7` is also operator-GUI but I folded it into M-1 because it shares the land-rail
push surface; these two share nothing with either master.

**Impact.** `1dca461d4b90` is the single named blocker on the cloud round trip — with the app installed,
`cc-cloud` create uses a `git_repository` source and stops bundling ~95 MiB, which removed one refused
create and is the leading explanation for the first fired cloud session pushing no `claude/*` branch in
15 minutes. It gates the entire cloud cluster, not just my slice.

**DoD.** GitHub App installed and a cloud create verified to use a `git_repository` source; 2.1.224
audited to an ADVANCE-or-HOLD verdict recorded in MANIFEST.jsonl.

**Falsifier:** `gh api /repos/renchris/claude-infrastructure/installation >/dev/null 2>&1`

**First move.** File both with `cc-backlog needs` so they render in the `OPERATOR ▸` block rather than
living in prose — `1dca461d4b90` has no runnable command (GUI only), `635eb82ef810` does.

**Order.** 1. `1dca461d4b90` (gates the cloud cluster) → 2. `635eb82ef810` (independent).

## Notes for the lead

1. **The 103-patch stranded-work sweep is the deliverable most likely to be wanted outside my slice.**
   The exact command is in M-1's falsifier. It should be promoted to `bin/` — `git worktree list` +
   `git cherry` is the only pairing that gets the right answer; a raw `rev-list --count` reports 455
   for a branch holding 8 real patches and will make anyone reading it despair for no reason.

2. **`216f429128a2` (reso `.eslintcache` is worktree-local) is a reso item** and should move to
   cluster-P-reso. I kept it KEEP rather than dropping it so your completeness check still balances,
   but whoever owns reso is better placed to verify it than I am from this repo.

3. **Cross-cluster duplicate, flagged:** `1dca461d4b90` / `9f684129d020` (Claude GitHub App) will almost
   certainly appear again in **cluster-C-dispatch** or a cloud slice — both cite
   `docs/plans/CLOUD_OBSERVABILITY.md`. I made `1dca461d4b90` canonical (earlier ts, richer body); if a
   cloud slice claims it, let the cloud slice own it — its impact is cloud-side, not session-side.
   Similarly `55065a61b31c` and `641c1802d75b` are `bin/cc-cloud` items that landed in my *worktree*
   file only because they mention branches; if a cloud master exists, they belong there and I would
   drop them from M-1 (I deliberately did NOT fold them into either master for that reason — they
   appear in Verdicts as KEEP and are unassigned).

4. **Landmine — `scripts/worktree-pool.sh` is a phantom referenced by 15 files.**
   `git log --all -- scripts/worktree-pool.sh` is empty; it has never existed in this repo. But
   `docs/WORKTREE_WORKFLOW.md:162` asserts it as shipped, `handoff-fire.sh:5508` branches on `[ -x
   "$POOL" ]` (permanently false ⇒ :5509-5566 is dead code), and `hooks/worktree-setup.sh:154`
   references it. Any agent doing worktree work will burn time rediscovering this. It is inside M-1's
   DoD via row 11's scope bound, but call it out in the brief explicitly.

5. **Two items were filed AFTER their own fix landed** — `49cfd01dd5eb` (filed 2026-08-09T18:26, fixed
   by 09aca05b on 2026-08-08 22:52) and half of `0db2c692efb7`. If other clusters show the same
   pattern, the filing path is reading a stale checkout, which is itself an M-1 symptom (an agent
   working from a worktree cut off a stale base files defects that trunk already fixed). Worth a
   cross-cluster count.

6. **Do not let anyone "clean up" worktrees before M-1 step 4.** 128 orphan dirs is tempting to `rm`,
   but 30 registered worktrees hold 103 unlanded patches and the current `worktree-gc.sh` cannot tell
   the two populations apart (`worktree-gc.sh:726`). Ordering here is load-bearing, not stylistic.
