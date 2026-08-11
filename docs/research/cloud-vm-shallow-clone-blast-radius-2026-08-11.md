# What a 50-commit shallow clone breaks in this repo's own scripts

**Date:** 2026-08-11 · **Measured on:** a cloud VM clone of `renchris/claude-infrastructure`,
branch `claude/fire-20260811T035034Z-93119-1`, HEAD `25aa774a`.

The damage is **not** in the land/close rails. `/ship`, `cc-teardown-safety-gate`, `cc-dispatch`,
`land-verify` and `cc-cloud` all survive, most of them because they were already written to
fail-closed or to answer by content rather than by history. The damage is concentrated in the
**evidence layer** — the four scripts that answer *"has this been done before / by whom / how long
ago"* — and in the **agent itself**, which reaches for `git blame` and `git log -S` on instinct and
gets a confident, complete-looking, wrong answer with no error anywhere.

The root cause is one measurement: across the 387 files in `scripts/ bin/ hooks/`, **nothing in this
repo has ever heard of a shallow clone.** Zero hits for `is-shallow-repository`, `--unshallow`,
`--depth`, or `.git/shallow`. The repo has a rich, deliberate vocabulary for *"I could not tell"* —
`cc-dispatch`'s three states, `session-writes`' rc 2, `cc-cloud`'s `return 2` — and no sensor that
can ever put a history read into it.

---

## 1 · The measurement

```
$ git rev-list --count HEAD
50
$ git rev-parse --is-shallow-repository
true
$ cat .git/shallow
e9f9c8797bcf7cb15f89a2bf2de8aabf0d7857f8
$ git log --format='%ad' --date=short | sed -n '1p;$p'
2026-08-10
2026-08-10
```

50 matches the brief, so the count itself is not the finding. Two properties behind the count are:

- **The graft is a single boundary commit**, `e9f9c879`, which git reports as a parentless root:
  `git rev-parse e9f9c879^` → `fatal: ambiguous argument … unknown revision`. Every walk terminates
  there and every walk terminates *successfully*.
- **All 50 commits are from one calendar day.** The visible history is not "the last 50 commits",
  it is "2026-08-10". Every `--since` window wider than about 36 hours is silently clamped to the
  graft, and this repo's evidence layer is built almost entirely out of `--since` windows.

There are also **zero tags** (`git tag` → 0 rows) — a shallow clone fetches none — so tag-distance
and `git describe` are dead here regardless of history depth.

## 2 · How git actually behaves at this boundary

Measured in this clone, because the failure *mode* is what decides whether a call site is a finding
or a footnote. The five real pre-graft SHAs cited in this repo's own `CLAUDE.md` and script headers
(`dfacccd`, `fb76c35bb`, `13bfa557db3a`, `3b22efbc2340`, `99b715f31a98`) behave identically:

| Invocation | Result at this boundary | Shape |
|---|---|---|
| `git rev-parse --verify --quiet <pre-graft-sha>` | empty, **rc 1** | loud |
| `git cat-file -e` / `-t <pre-graft-sha>` | `fatal: Not a valid object name`, **rc 128** | loud |
| `git rev-parse --disambiguate=<pre-graft-sha>` | **empty** | *silent* |
| `git merge-base --is-ancestor <pre-graft-sha> origin/main` | **rc 128** (not rc 1) | loud *if* rc is read |
| `git rev-list --count <pre-graft-sha>..HEAD` | `fatal: ambiguous argument`, rc 128 | loud |
| …the same, under this repo's `2>/dev/null \|\| echo 0` idiom | **`0`** | *silent* |
| `git merge-base HEAD <disconnected-commit>` | empty, rc 1 | loud |
| `git rev-list --count <disconnected>..HEAD` | **`50`** — no error | *silent* |
| `git rev-list --count --since=2020-01-01 HEAD` | **`50`** | *silent* |
| `git blame <file>` | **every line** attributed to `^e9f9c879` | *silent-ish* (`^` prefix) |
| `git log --follow -- CLAUDE.md` | **1 commit** | *silent* |
| `git log -S '<string>' -- CLAUDE.md` | **1 commit** | *silent* |
| `git describe --tags` | `fatal: No names found` | loud |

Two rows carry most of the weight. **`merge-base --is-ancestor` returns 128, not 1** — git *is*
distinguishing "no" from "cannot evaluate", and every call site that writes `2>/dev/null && …`
throws that distinction away. And **the `|| echo 0` idiom converts every loud rc-128 into a silent
`0`** — this repo uses that idiom at eight sites, and at most of them `0` is the *safe-looking*
answer ("nothing ahead", "not behind", "already landed").

---

## 3 · Silent wrong answers

Ranked by blast radius under a backlog dispatched at scale.

### S1 — `git blame` / `log --follow` / `log -S`: the agent's own investigation

No call site in `scripts/ bin/ hooks/` runs these. That understates the exposure rather than
removing it: a dispatched brief that says *"read the working tree and find out why this rule
exists"* is answered by exactly these three commands, and here they are unanimous and wrong.

```
$ git blame -l CLAUDE.md | awk '{print $1}' | sort -u
^e9f9c8797bcf7cb15f89a2bf2de8aabf0d7857f
```

**One value, for all 752 lines.** Same for `scripts/ship-land.sh` (2617 lines) and
`scripts/deploy-live.sh` (1440). `git log --follow -- CLAUDE.md` returns one commit; `git log -S
'Session Close Protocol' -- CLAUDE.md` returns one commit — the graft, which "introduced" a section
it did not write.

This is the single most dangerous item in the document, because the answer is *shaped exactly like a
correct answer*. An agent asked when a rule changed gets a real SHA, a real author, a real date, and
a complete-looking history of length 1. `CLAUDE.md` is dense with claims of the form *"corrected
2026-08-08, measured on 2.1.220"* and *"revised 2026-07-31 from …"* — provenance an agent will
naturally verify with `blame`, and cannot.

The one mitigation git offers is the `^` prefix marking a boundary commit (`boundary` in
`--porcelain`). It is a single character, it is absent from `--line-porcelain`'s author fields, and
the standard parse — `awk '{print $1}'`, or a `[0-9a-f]{7,}` regex — drops it.

### S2 — `bin/cc-premise:490` — every historical SHA in the backlog reads `absent`

```python
typ = _git(["cat-file", "-t", sha])
if typ is None:
    return "ambiguous" if _git(["rev-parse", "--disambiguate=" + sha]) else "absent"
...
if _git(["merge-base", "--is-ancestor", sha, "origin/main"]) is not None:
    return "landed"
return "on-branch"
```

For a pre-graft SHA: `cat-file -t` → rc 128 → `None`; `--disambiguate=` → empty (measured); result
**`absent`**. On a full clone the same SHA returns **`landed`**. `resolve_sha`'s own docstring
defines `absent` as *"this pointer is dead"* — a claim about the SHA, not about the clone.

This is the finding with the widest reach, because `cc-premise` is the thing that reads the backlog,
and the backlog is what is about to be dispatched. Its measured base rate — *"5 of 10 SHAs that
resolve to no object at all describe changes that are demonstrably live on trunk"* — goes to 100%
for anything committed before 2026-08-10.

The prose hedging in the docstring is real and it is why nothing auto-closes on this. It is not a
guard: the *value* still flips, and the contract prose a human reads is generated from the value.

### S3 — `bin/cc-premise:617` — the EVIDENCE-AGE count, clamped by the graft

```python
total = _git(["rev-list", "--count", "--since=" + ts, "origin/main", "--"] + present_paths)
if not total or not total.isdigit() or total == "0":
    return []
```

`ts` is the backlog item's `first_ts`, and the arm only runs on items older than `STALE_AFTER_S`.
Since the visible history is one day wide, **the window is bounded by the graft rather than by
`ts`** — measured: `--since=2020-01-01` returns 50. Two silent outcomes:

- a headline that under-counts (`"N commit(s) have landed on the file(s) it cites"`), against a
  comment two lines above it that reads *"the COUNT is the headline number, so it has to be exact"*;
- `total == "0"` → `return []` → **the warning never fires at all**, indistinguishable from the
  designed silence the docstring enumerates (*"nothing landed in the window — all return [], never a
  fabricated finding"*).

The arm goes to deliberate trouble to avoid a cap that hides itself — `CHURN_COMMITS_MAX` prints
`showing X of N` rather than lying — and the graft imposes precisely such a hidden cap one layer
below it.

### S4 — `scripts/never-stuck-gate.sh:191` — a machine-health verdict from 50 commits

```bash
ts="$(git -C "$REPO" log --all -1 --format=%ct --grep='^Acked-Ruling:' 2>/dev/null)" || ts=""
[ -n "$ts" ] || return 0
```

Empty output renders `NEVER — no artifact at Acked-Ruling: trailers in git history (never invoked,
or episodic and still idle)`. On a shallow clone that verdict is reached whenever no ack trailer
happens to fall inside the 50, i.e. almost always. `--all` compounds it: a shallow clone has fetched
two refs, so "all" is `main` plus the working branch.

The comment above the function — *"Empty = the ruling channel has never been exercised in this
history"* — becomes accidentally true of the clone while being false of the repo, which is the exact
shape that makes this class hard to notice.

### S5 — `scripts/git-identity-assert.sh:268,281` — the attribution sweep loses its subject

```bash
sha="$(git -C "$repo" log "$base" --format='%H %ae' | awk -v e="$em" '$2==e{print $1; exit}')"
...
$(git -C "$repo" log "$base" --format='%ae' | sort -u)
```

`verify-attribution` re-derives the email→account map by enumerating **every author email in trunk
history**. Here that enumeration covers one day. An identity that appears only before the graft is
absent from the set, and the sweep reports a clean map.

The irony is load-bearing: this script exists because a bad identity *"sat in `.git/config` from
2026-08-05 to 2026-08-08 and produced 710 unattributable commits while every sensor on the machine
read green"*, and its header names the failure class — *"a defence with no state sensor is a defence
with a blind spot the exact width of its own deployment date"*. On a cloud VM the blind spot is the
width of the graft, and all 710 of those commits are on the far side of it. This matters more here
than anywhere else in the document: a cloud VM authors as `noreply@anthropic.com`
(`scripts/cloud-reconcile.sh` header), so the identity question is *specifically* a cloud-VM
question, asked on the one clone that cannot answer it.

### S6 — `bin/cc-value:159` — the value metric under-reports

```bash
git -C "$repo" log "$REF" --since="$iso" --no-merges --format='%ct…'
```

Landed-commits-in-window, over a 7- or 30-day window, capped at the 50 visible. The `[ "$ct" -ge
"$since_epoch" ]` re-filter below it makes the window *exact on the late side* — `--since` is fuzzy —
while the early side is silently truncated, so the code looks more rigorous than it is.

### S7 — `scripts/wrap-ledger.sh:196-199` — every failure mode of the close ledger points at ✅

```bash
AHEAD="$(git rev-list --count "$TRUNK"..HEAD 2>/dev/null || echo 0)"; …
if git cherry "$TRUNK" HEAD 2>/dev/null | grep '^+ ' >/dev/null; then CHERRY=1; fi
…
UNLANDED=0; { [ "$AHEAD" -gt 0 ] || [ "$CHERRY" -eq 1 ]; } && UNLANDED=1
```

Ranked last among the silent findings because **it is not reachable on an ordinary cloud clone** —
`origin/main` is present and its merge-base with HEAD is visible (measured: `merge-base origin/main
HEAD` → `25aa774a`, rc 0), so both reads answer correctly today. It is listed because the asymmetry
is worth naming: `git cherry` needs a merge-base, an unreachable base makes `AHEAD` read `0` via the
`|| echo 0` idiom and `CHERRY` read `0` via `2>/dev/null`, and **both point at `UNLANDED=0`, i.e. at
`✅ Complete & live on trunk`**. `CLAUDE.md` already warns that *"a count reads 0 after a sibling
rebase and proves nothing"*; a truncated history is a second, independent way to read that same `0`,
and the ledger has no third state to fall into.

---

## 4 · Loud failures (footnotes)

- **`scripts/ship-land.sh:2520-2523`** — `BASE="$(git merge-base "origin/$TRUNK" HEAD …)"`; empty →
  `exit 2`, *"cannot find a merge-base with origin/main — is 'main' the right trunk? (use
  --trunk)"*. Loud and rolls back cleanly, but the message names the wrong cause and sends the
  operator to a `--trunk` flag that cannot help. Not reachable on the ordinary path: a VM branches
  from the fetched tip, so the base is always inside the window.
- **`git describe`** — no call sites in `scripts/ bin/ hooks/`, and moot anyway: the clone has zero
  tags, so any ad-hoc use fails loudly rather than truncating.
- **`git rev-list --count <pre-graft>..HEAD`** — rc 128 with a clear message, *except* at the eight
  sites that wrap it in `|| echo 0`. The idiom, not the command, is what converts loud to silent.
- **Abbreviation width.** 2034 objects here, so `%h` and `rev-parse --short` yield 7 characters
  (`25aa774`). Short SHAs minted on a VM and written into the backlog, decision packets or a commit
  message may be ambiguous when resolved later against the operator's full clone. Cosmetic against
  the rest of this document; real if a 7-char SHA becomes a lookup key.

---

## 5 · Already guarded — not counted

Listed so a reader does not re-derive them, and because two of them are the fix.

- **`bin/cc-dispatch:824-838`** — pre-verifies both refs with `rev-parse --verify --quiet` and emits
  `unknown`, with a header that states the principle outright: *"`--is-ancestor` exits 0 for yes, 1
  for no, and something else for 'I could not evaluate that' … collapsing the third into `no` is
  exactly the failure `cc-premise` measured."* Correct as written; the rc-128 boundary is the third
  state it already models.
- **`scripts/land-verify.sh`** and **`bin/cc-cloud:219-234`** — landedness decided by
  `git ls-tree` + `git diff` per path. **Structurally immune to truncation**: no walk, no ancestry,
  no window. This is the pattern the rest of the repo should be measured against.
- **`bin/cc-teardown-safety-gate.sh:103`** — `if ! ahead=…` → `DEFER no-remote-trunk … fail-closed`.
- **`bin/cc-classify:337`**, **`bin/cc-reaper:598`**, **`scripts/lead-supervisor.sh:528`** —
  `… || return 1`, so an unreadable count is "not proven landed", never "landed".
- **`bin/cc-bind:98-101`** — empty base → `gate_fail "indeterminate: cannot resolve a default base"`;
  and `git rev-list "$range" || gate_fail "indeterminate: unresolvable range"`.
- **`scripts/postland-verify.sh:1984`** and **`scripts/ship-backup-reap.sh:101-105`** — both fail
  closed on an unusable merge-base, with a named reason in the log.
- **`hooks/boundary-handoff.sh:331`** — a `log -1 -- <file>` that returns empty (the file was not
  touched inside the window) falls to `abstain "log-head-lags"`, which is the safe direction.
- **`bin/desk-assert:90`** — pre-verifies the ref and records `head(rev-list failed …)` as missing.

---

## 6 · What would make this safe

The smallest change is **not** deepening the clone. `git fetch --unshallow` on every VM costs the
full history per dispatch, and it does not help the scripts at all when the fetch is skipped, fails,
or runs after they do — which is the failure mode this whole document is about.

The smallest change is **one sensor and one rule**, because the repo already has the vocabulary to
absorb the answer.

**A shared helper, `hooks/lib/history-horizon.sh`, alongside the existing `session-writes.sh` /
`peer-owned.sh` / `dod-path.sh`:**

```bash
history_truncated()   # rc 0 iff `git rev-parse --is-shallow-repository` = true
history_floor_sha()   # the graft commit (`git rev-list --max-parents=0 HEAD`)
history_floor_epoch() # committer time of the oldest visible commit
history_covers()      # <sha-or-epoch> → rc 0 visible · 1 below the floor · 2 cannot tell
```

Roughly thirty lines, no network, and a **strict no-op on a full clone** — `history_truncated`
returns 1 and every caller keeps today's behavior byte for byte.

**The rule, applied at the five call sites in §3:** an answer whose input predates the floor returns
the caller's *existing* cannot-tell state, never its false-negative one. Every one of them already
has that state and already routes it correctly:

| Site | Today, on a shallow clone | With the floor |
|---|---|---|
| `cc-premise:490` `resolve_sha` | `absent` | `unknown` — already a returned value |
| `cc-premise:617` churn | a low count, or silence | say `below the horizon`, or stay silent *and say why* |
| `never-stuck-gate.sh:191` | `NEVER` | a fourth verdict beside `NEVER`/`USED`/`DORMANT` |
| `git-identity-assert.sh:268` | a clean map | `UNPROTECTED`-style finding — the header's own polarity |
| `cc-value:159` | an under-count | annotate the window as clamped |

The two content-based checks in §5 need nothing. That is the general lesson worth carrying out of
this: **`land-verify.sh` and `cc-cloud`'s `landed()` are correct here by accident of being correct
in general** — they ask the tree what it contains instead of asking the graph what happened. Where a
question *can* be asked of a tree, asking it of history is the bug, shallow clone or not.

**What this deliberately does not fix:** §3's S1. No library helps an agent that types `git blame`.
The only defence there is that the fact be *written down where the agent reads* — one line in the
dispatch brief, or in `.claude/CLAUDE.md`, saying that on a cloud VM the history is grafted, `blame`
and `log -S` and `--follow` will answer from a single boundary commit, and provenance questions must
be answered from the working tree and the plan docs instead. That line does not exist anywhere in
this repo today, which is the same root cause as everything above: nothing here knows it can be
running on a clone that cannot see its own past.
