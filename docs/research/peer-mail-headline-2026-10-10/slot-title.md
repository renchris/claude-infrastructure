# Slot: how a peer-mail TITLE should be produced

Question: should the title be (a) derived from the body, (b) derived with an optional `--subject`
override, or (c) a required subject? Measured on the real 7-day mailbox corpus, read-only.

## Answer

**(b): derive by default with the algorithm A4.1 below, and add an OPTIONAL `cc-notify --subject`.**
Do not require a subject (c).

- On a 160-line hand-judged sample, A4.1 gave a usable title for **90%** of lines: 95% of
  automated lines and 87% of agent-written ones. On a separate 70-line holdout, the frozen A4 scored
  **80%** (82% for agent lines). A4.1 scored 87% there, but its two tweaks were made after I had seen
  the holdout. See §4.
- The split the brief suggested (cut at the first `. `, `; `, ` — ` or `:`) is **the wrong boundary
  for this corpus**: 8% usable as-is, 18% with tags stripped. Mail here is written
  `TAG: answer` or `TAG — answer` (`LEAD RULING (92%): YES — …`, `HANDOFF-PING slug: DONE — …`,
  `SESSION DEATH — 0dfa9f2e died abruptly`). Cutting at the first colon or dash keeps the label and
  drops the answer. Two things make derivation work: keep the label, and keep extending until the
  clause carries content.
- What derivation still gets wrong on agent mail (about 13-16%) is almost all **buried-lede** mail.
  The sender wrote context first and the verdict later, e.g. `DONE — E1k landed + converged …`
  followed many characters later by `Verdict FAIL`. No derivation can recover that. An opt-in
  `--subject` lets a sender fix it, and a required one is not needed for that.
- `--subject` cannot reach **28%** of 7-day mail (982 of 6,187 unique lines are WAKE-PATH-DOWN or
  WAKE-PATH-CLASS). `bin/cc-await-ping` appends those lines straight into the box at
  `bin/cc-await-ping:1014-1016` and `:1057-1060`, so they never pass through cc-notify. Derivation
  already gives 100% usable titles on those classes in the sample.

## 1. Corpus (measured)

All measured with python3 scripts over `$HOME/.claude/mailbox/*.md` with mtime under 7 days. The
scripts were kept outside the repo in `/tmp/slot-title/scripts/` (load.py, algos.py, sample.py,
holdout.py) and are transient.

| quantity | value |
|---|---|
| mailbox files total / modified in last 7 d | 2,643 / 360 |
| non-empty lines in those 360 files | 6,917 (6,916 parse as `<ISO> [from] body`, 1 does not) |
| forwarded copies (`[forwarded:N]` wrapper) | 732; max forward depth 2 |
| unique messages after unwrapping forwards and de-duplicating (ts, origin-from, body) | **6,187** |
| … automated status/lifecycle (tag-classified, §5) | 5,241 (85%) |
| … agent-written | 946 (15%) |
| distinct `[from]` values | 420 |
| working set (most recent ≤60 per (origin sender, class), newest first) | 1,842 (1,000 automated, 842 agent) |
| agent body length, working set | median 507 chars, p90 1,505 |
| agent lines with a double space (a newline collapsed by `bin/cc-notify:1095`) | 41 / 842 |
| agent lines that start with `HANDOFF-PING <slug>:` | 478 / 842. First status token: DONE 174, progress 101, decision 15, LANDED 10, BLOCKER 8, … |

**Classify by the body tag, not by `[from]`.** Automated mail often carries an agent's name. For
example, `SESSION DEATH` arrives from `[wt-pool-7-83]` and `[wt-ptuf2-269]`, and
`HANDOFF-PING (auto, durability)` arrives from `[tm2-plan-NNN]`. The largest automated classes come
from a generic `[claude]` (SUPERVISOR PAGE, all 2,742 lines). That is an issue for the sender slot,
noted here only because it rules out using `[from]` to classify.

## 2. Unwrapping (what every algorithm runs on)

```
ISO = \d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:[+-]\d{4}|Z)?
HEAD = ^(ISO) \[([^\]]*)\] ?
m = HEAD.match(line); ts, from, body = …
while from startswith "forwarded:":          # forward chain: "<ISO> [forwarded:P] <ISO> [orig] body"
    chain.append(pane); m2 = HEAD.match(body); if not m2: break
    ts, from, body = m2 groups                # origin ts/from survive the forward
```

The title is computed on the innermost `body`, so it survives forwards by construction.

## 3. Candidate algorithms

| id | definition |
|---|---|
| A0 head72 | collapse whitespace, cap 72 at a word boundary, add `…` (the baseline; no logic) |
| A1 naive-sentence | cut at the first `. ` / `; ` / ` — ` / `:` with no tag strip, cap 72 |
| A2 strip+sentence(colon) | strip leading `[…]` tags, emoji and `HANDOFF-PING slug:`, then A1's cut (the brief's suggestion) |
| A3 label-keep | A2's strip; shorten UUIDs to 8 hex; keep a short `Label:` (≤4 words, ≤28 chars) as a prefix; cut at a sentence end that does NOT include `:`; if the clause is under 24 chars or tag-only, append the next clause with ` — `; cap 72 (A3-60: cap 60) |
| A4 | A3, plus: strip only routing brackets (`[for:…]`, `[restart]`, `[lead]`, `[restore]`) so `[desk-sweep]` keeps its meaning; strip attribution preambles (`From the lead (pane N):`, `Relay from …:`, `Coordination from …:`), since the headline already names the sender; do not split inside `()[]{}` or quotes |
| **A4.1** | A4, plus: strip sender self-label brackets (`[pane-223 lr-research]`, `[husk-forensics, pane 72]`) and a bare leading `HANDOFF-PING ` (e.g. `HANDOFF-PING recycle #311 — closed=…`) |

## 4. Hand classification (by me, one judge)

**USABLE** means the title alone tells the reader the point or answer. **NOT** means it is only a
tag or a status token (`DONE`, `progress`, `REAPER SURFACE`), only boilerplate or preamble, or cut
before the state or verdict. The same rule was applied to every algorithm. Templated automated lines
were judged per line but are effectively per template.

### 4a. Main sample: 160 lines (60 automated, stratified at 2 per class plus random fill; 100 agent, ≤3 per sender)

| algorithm | automated (60) | agent (100) | all (160) |
|---|---|---|---|
| A0 head72 | 54 (90%) | 80 (80%) | 134 (84%) |
| A1 naive-sentence | 10 (17%) | 3 (3%) | 13 (8%) |
| A2 strip+sentence (brief's suggestion) | 12 (20%) | 16 (16%) | 28 (18%) |
| A3 label-keep, cap 72 | 52 (87%) | 84 (84%) | 136 (85%) |
| A3 label-keep, cap 60 | 50 (83%) | 83 (83%) | 133 (83%) |
| A4 | 55 (92%) | 87 (87%) | 142 (89%) |
| **A4.1** | **57 (95%)** | **87 (87%)** | **144 (90%)** |

A4 and A4.1 were tuned after looking at this sample, so these rows are optimistic.

### 4b. Holdout: 70 fresh lines (50 agent, ≤2 per sender; 20 automated random), none in 4a

| algorithm | automated (20) | agent (50) | all (70) |
|---|---|---|---|
| A0 head72 | 18 (90%) | 37 (74%) | 55 (79%) |
| A3 label-keep 72 | 15 (75%) | 41 (82%) | 56 (80%) |
| A4 (frozen before holdout) | 15 (75%) | 41 (82%) | 56 (80%) |
| A4.1 (tweaked after seeing holdout) | 19 (95%) | 42 (84%) | 61 (87%) |

- **Paired test on all 150 agent lines (4a and 4b), A0 vs A4.1** (counted from the judgment files):
  15 lines usable only under A4.1 and 3 usable only under A0. An exact two-sided binomial test on
  those 18 discordant pairs gives p ≈ 0.008 (estimated by hand from the binomial formula). The gain
  over A0 is real but modest.
- **Precision:** the agent rate has a 95% interval of about ±7 pp at n=100 and ±11 pp at n=50
  (estimated, normal approximation).
- **Caveats:** a single judge, not blind to which algorithm produced each title.
- **Weighted by corpus share** (85% automated, 15% agent), A4.1 comes to about **93%** usable. This
  is an estimate: automated class rates applied to the corpus mix, without per-class reweighting.

### 4c. Mechanical metrics on the 1,842-line working set (measured, no judgment)

| | median len | p90 len | ends in `…` | tag-only | under 16 chars |
|---|---|---|---|---|---|
| A0 agent / auto | 68 / 67 | 71 / 71 | 97% / 100% | 2% / 6% | 0% / 0% |
| A2 agent / auto | 13 / 15 | 60 / 32 | 8% / 2% | **32% / 63%** | **53% / 50%** |
| A4.1 agent / auto | 66 / 67 | 71 / 71 | 66% / 79% | 1% / 6% | 0% / 0% |

A2's 32-63% tag-only rate is the failure mode in numbers. A4.1 costs **0.32 ms per line** in
python3 (measured over the 1,842 lines under load ~800, interpreter start-up excluded).

### 4d. What A4.1 still gets wrong (all 25 NOT lines across 4a and 4b)

- **Buried lede, the sender's fault (15 of 21 agent NOTs).** Examples:
  - `DONE — E1j landed + converged (trunk ba1fdc86c)`: the real answer, "no arm passed RULE E1j", is
    in sentence 3.
  - `storyboard: STORYBOARD.md + board.jpg + refs/ in…`: the real answer, `Operator: "Approve all"`,
    comes later.
  - `decision gate — step 1 pre-registration committed…`: the question being asked is never reached.
  - `from drain recycle #291 (pane 27)`: the point, `METHOD 263 — …`, comes after.
  - `Address update after the reboot: the origin pane is now…`: the new address is cut off.
- **Cap cuts the predicate (3).** `Panes 113 (58d3640a), 124 (e582464c) and 134 (6defb493) are all…`
- **Boilerplate first clause (3).** `progress after the reboot`, `E1M-CHAIN E1k re-run done rc=0:`,
  `fire-austin-move (final): 11 commits …`
- **Automated, cut before the state (4).**
  - REAPER SURFACE with a long session name: `REAPER SURFACE — session claude-infrastructure-248 is…`.
    Measured: 162 of 563 REAPER lines in 7 days (29%) end in `is…`.
  - `cc-lr move 20261010T012444Z-next-next2-98959 (next -> next2) done…`: the 33-char batch id
    pushes the `FAILED=1 NOTMOVED=7` result past the cap.

## 5. Automated prefixes and whether they need a canned title

Unique 7-day lines by class, the emitter (from a grep of bin/hooks/scripts), and an example A4.1
title:

| n (7 d) | class | emitter | A4.1 title example | canned title? |
|---|---|---|---|---|
| 2,742 | SUPERVISOR PAGE | `scripts/lead-supervisor.sh:518` (and supervisor-e2e.sh) | `SUPERVISOR PAGE — session 213c421b is DEAD: owning pid 33946 gone` | no; UUID-shortening fixes it |
| 628 | WAKE-PATH-DOWN | `bin/cc-await-ping:1057-1060` (**direct append, bypasses cc-notify**) | `WAKE-PATH-DOWN: the watcher armed for [283] was TERMINATED from…` | no |
| 563 | REAPER (SURFACE 527, SELF-CHECK 36) | `bin/cc-reaper` | `REAPER SURFACE — session claude-infrastructure-248 is…` (29% cut before state) | **yes**: emitter passes `--subject "reaper: <session> <state>"` |
| 354 | WAKE-PATH-CLASS | `bin/cc-await-ping:1014-1016` (**direct append**) | `WAKE-PATH-CLASS: verdict=B-BENIGN reason=sender-session-exited-beat-fro…` | no; verdict is visible |
| 184 | PERMISSION-PENDING | `bin/cc-blockers`, `scripts/lead-supervisor.sh` | `PERMISSION-PENDING — session d0630e1c blocked 129s on a permission…` | no |
| 173 | HANDOFF-PING recycle #N — closed=… | drain brief template `scripts/drain-brief.template.md` (agent-typed to a template) | `recycle #3 — closed=10 closed_pre=8 closed_other=6 filed=0(by me)…` | no (A4.1) |
| 167 | SESSION DEATH | `hooks/lead-crash-watchdog.sh` | `SESSION DEATH — 84f8c585 died abruptly (cause: abrupt-unknown)` | no |
| 63 | SUPERVISOR SELF-CHECK | `scripts/lead-supervisor.sh` | `SUPERVISOR SELF-CHECK — 12 live Claude pane(s) but only 8 in telemetry` | no |
| 58 | lr-handoff | `scripts/limit-recover/lr-handoff.sh` | `lr-handoff 762a6daa: verdict=SWITCHED-UNPROVEN from=next3 to=next4…` | no |
| 50 | [desk-sweep] NEW | `scripts/autonomy-sweep.sh` | `[desk-sweep] NEW: 15 page(s), 5 alarm(s), 5 push-failed, 28 open…` | no (A4 keeps the bracket) |
| 48 | HANDOFF-PING (auto, durability) | `scripts/handoff-fire.sh`, `hooks/mailbox-drain.sh` | `HANDOFF-PING (auto, durability): peer 93 pinged you and is retiring…` | optional (the `COMMITTED ≠ LANDED` warning is past the cap) |
| 46 | CC-LR-SWITCH | `scripts/limit-recover/lr-upgrade.sh` | `CC-LR-SWITCH pane 150 (6ebd9a1c): verdict=NOTMOVED from=next3 to=next4…` | no |
| 28 | lr-fleet --one | `bin/cc-lr`, `scripts/limit-recover/*` | `lr-fleet --one 3a06361f: verdict=PARKED rc=1 pane=13 acct=next4…` | no |
| 24 | RECYCLE-HELD / RETRY / DEFERRED | `scripts/handoff-fire.sh`, `scripts/pane-close-retry.sh` | `RECYCLE DEFERRED: the draft in this pane's composer ('/exit') was not…` | no |
| 19 | teammate-auto-shutdown | `bin/cc-teardown-safety-gate.sh`, `hooks/teammate-checkpoint.sh` | `teammate-auto-shutdown: pane 93 (W4c) could NOT be closed (rc=124)…` | no |
| 17 / 12 / 9 / 9 / 9 / 9 / 7 / 5 / 5 / 4 / 4 / 4 | SHADOW, GOAL-ARM, reconciler RESTARTED, lr-fire-resume, [restore], fired-peer DARK, CONTEXT n% FULL, cc-lr move, HANDOFF-SUCCESSION, limit-recover resume, SELF-CLOSE RETRY, STRANDED WORK | various | all usable except **cc-lr move** (`… done…`, result past the cap) | **cc-lr move: yes** (emitter `--subject`) |

**Recommendation for automated mail.** Do **not** build a reader-side table of canned titles.
- Derivation already reaches 95% on automated mail.
- A reader-side regex table duplicates every emitter's wording and silently goes stale when an
  emitter rewords a message.
- The two classes that fail (REAPER SURFACE and cc-lr move) should be fixed **at the emitter**:
  pass `--subject` from `bin/cc-reaper` and from the cc-lr move reporter.
- Shortening their variable fields (session name, batch id) would also work.
- cc-await-ping needs no change, because both of its classes derive well.

## 6. Recommended derivation: A4.1 (precise)

Python 3, one shared reader-side function. `hooks/mailbox-drain.sh` already shells out to python3 at
`:775` and `:831`, so there is precedent. awk/sed cannot do the quote/paren-depth check or the
lookbehinds. Every reader calls this one function rather than re-implementing it: the drain digest
(`hooks/mailbox-drain.sh:851-866`), the wake-arm stderr body (`hooks/mailbox-wake-arm.sh:211`), the
cc-wake frame and cc-mail.

```python
UUID   = r"\b([0-9a-f]{8})-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"   # -> \1
ROUTE  = r"^(?:\[(?:for:[^\]]*|restart|lead|restore)\]\s*)+"            # routing tags (cc-notify:1514 adds [for:X])
SYM    = r"^[\s⚠️⛔✗✓✔❌📬🔴🟢]+"                                          # leading status glyphs
SELF   = r"^\[[^\]]*\bpane[- ]?\d+[^\]]*\]\s*"                          # sender self-label: [pane-223 x] / [x, pane 72]
HP     = r"^HANDOFF-PING [A-Za-z0-9][A-Za-z0-9._/-]*:\s*"               # SAME slug charset as mailbox-drain.sh:716
HPBARE = r"^HANDOFF-PING\s+(?=[^(:\s])"                                 # 'HANDOFF-PING recycle #311 — …'
ATTR   = r"^(?:From|Relay from|Relayed from|Coordination from)\b[^:]{0,60}:\s+"   # headline already names sender
LABEL  = r"^([^:\s][^:]{0,27}?):\s+(?=\S)"                              # kept as prefix iff <= 4 words
SPLIT  = r"(?<!\be\.g)(?<!\bi\.e)(?<!\bvs)(?<!\.)[.!?](?=\s+[A-Z0-9(\[\"'`])|; | — | -- | {2,}"
          # sentence end (not '..', not e.g./i.e./vs) | '; ' | ' — ' | ' -- ' | 2+ spaces (= a collapsed newline)
MINLEN, CAP = 24, 72

def title(body):                      # body = innermost body after unwrapping forwards (§2)
    if (k := body.find(" ¶ ")) != -1 and k <= 120:      # explicit --subject (see §7)
        return cap(body[:k].strip(), CAP)
    s = re.sub(UUID, r"\1", body.replace("\r", " ").replace("\n", "  "))
    s = re.sub(r"[ \t]{3,}", "  ", s).strip()
    repeat up to 5x until unchanged:
        s = sub(ROUTE); sub(SYM); sub(SELF); sub(HP); sub(HPBARE); sub(ATTR)
    label = ""
    if m := LABEL.match(s) and len(m[1].split()) <= 4:
        label, s = m[1], s[m.end():]
    out = ""
    loop:
        m = first SPLIT match in s whose position is at bracket depth 0 and outside "…", `…`, “…”,
            and '…' (a ' opens only after a space, '(', ':', '=', or '[', and closes only when not followed by an alnum)
        piece = s[:m.start()] if m else s
        out = out + " — " + piece if out else piece
        tagonly = not re.search(r"[a-z]{3,}", re.sub(r"\b[\w.-]*[0-9#=][\w.=#-]*\b", "", out))
        if (len(out) >= MINLEN and not tagonly) or not m: break
        s = s[m.end():]
    t = f"{label}: {out}" if label else out
    return cap(re.sub(r"\s+", " ", t), CAP)

def cap(s, n):  # word-boundary cut with ellipsis
    if len(s) <= n: return s
    cut = s[:n-1]; sp = cut.rfind(" ")
    if sp >= n*0.5: cut = cut[:sp]
    return cut.rstrip(" ,;:—-(") + "…"
```

Notes:
- **Cap.** Use 72. Capping at 60 cost about 2 pp, measured on A3 (85% vs 83%). If the format slot
  needs the width, 60 is acceptable.
- **The HANDOFF-PING slug is dropped from the title.** The sender's session title (headline item 1)
  carries the task identity, and the custody parser (`hooks/mailbox-drain.sh:709-726`) still reads
  the slug from the body. The status token (`DONE`, `progress`, `BLOCKER`) stays as the title's
  first word. It is answer-first, and `hooks/lib/handoff-ping-terminal.sh:23` already treats these
  words as meaningful.
- **Never empty.** If everything is stripped, fall back to A0 (the raw head, cap 72), so the title
  is never empty.

## 7. The optional `--subject` override

- **Why optional, not required.**
  - Derivation already produces usable titles for about 87% of agent mail and about 95% of
    automated mail.
  - A required flag would touch every send site. A grep counted 349 non-comment lines mentioning
    cc-notify across 106 non-test files in bin/hooks/scripts (estimated: a rough grep that includes
    some non-call mentions).
  - The flag would also break every existing caller at once, since unknown options exit 2 at
    `bin/cc-notify:569`.
  - The failure it targets, a buried lede, needs a sender who chooses to state the answer. Making the
    field required invites formulaic subjects instead. This is an estimate: 174 of 478 HANDOFF-PING
    agent lines already open with the bare token `DONE`, the likely value of a forced subject.
- **Where it pays off.**
  1. Automated emitters whose variable fields push the state past the cap: `bin/cc-reaper` REAPER
     SURFACE, cc-lr move.
  2. Experiment, decision-gate and relay mail, where the verdict is not the first clause.
  3. Optionally, brief templates (`scripts/drain-brief.template.md`, the fire brief) can tell fired
     sessions to open with the answer, or to pass `--subject` when the first clause is not the
     answer.
- **On-disk form (a proposal for the format slot to confirm).**
  - Keep one message per line; the `.seen` cursor counts lines (`bin/cc-notify:1092-1095`).
  - Write the line as `<ISO> [from] <subject> ¶ <body>`.
  - The delimiter ` ¶ ` occurs **0 times** in the 6,917-line corpus (measured; ` || ` occurs 20
    times, so it is unsafe).
  - Old readers show `subject ¶ body`, which still reads correctly.
  - The custody awk still finds the last `HANDOFF-PING <slug>:` anywhere in the line
    (`hooks/mailbox-drain.sh:714`).
  - The drain's noise grep is substring-based (`:851-853`).
  - Forwards only prepend, so the subject survives forwarding.
  - At write time, cc-notify should strip newlines and any ` ¶ ` from the subject and cap it at 72.
- **What `--subject` cannot reach.** `bin/cc-await-ping` appends directly, so it would need to emit
  the ` ¶ ` form itself. It does not need to, since both of its classes derive well.

## 8. Risks and caveats

- **Judging.** I was the only judge and saw the algorithms' titles side by side, not blind. A4 and
  A4.1 were tuned on the 4a sample, so the frozen-A4 holdout figure (80% overall, 82% agent) is the
  honest out-of-sample number. A4.1's holdout gain on automated mail (75% to 95%) comes from a tweak
  made after seeing the holdout.
- **Small subgroups.** Automated classes with 4-17 lines in 7 days have only 2 sampled lines each.
- **Silent wrong titles.**
  - The colon-label rule can promote a non-label (`references: picked 1 Even Realities…` works;
    `Panes 113 (…), 124 (…) and 134 (…) are all…` does not).
  - Splitting at `!` or `?` followed by a capital can cut inside an unquoted code fragment.
- **Wording drift.** Derivation depends on emitter wording; a reworded emitter changes its title
  silently. Pin the shared title function with a bats fixture built from real lines of each class
  in §5.
- **Session IDs.** UUID shortening to 8 hex matches the shortening used elsewhere (`(4982cee2)` in
  CC-LR-SWITCH), but it could collide in a title. It is display-only, never a key.
- **A possible fixture leak.** The corpus contains `SESSION DEATH — 33333333-…`, which looks like a
  test fixture in the live store. Not in scope for this slot; noted only.
