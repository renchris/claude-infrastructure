# W2-B5 — the coverage and the false convictions live in the SAME idiom, and the cause is an in-command `cd`

**The false-conviction rate of the proposed Bash-write extraction is 5.6 % overall (12 of 214
in-repo hits), and it partitions: `heredoc` 9.3 % (11/118) · `sed -i` 2.7 % (1/37) · `>`/`>>`
0.0 % (0/59) · `tee` n/a (0 hits, zero coverage). The tightest subset under 2 % is
`{>/>>, sed -i}` at 1.0 % (1/96) — and it covers 17.9 % of the Bash-mediated write population,
not the 80 % the decision rule requires. `heredoc` carries 79.2 % of the coverage and 92 % of
the error. No subset of the four idioms as proposed meets both bars.**

**Every one of the 12 has a single cause, and it is not the idiom set: the extractor resolves a
relative target against the session's launch `cwd` while the command has already `cd`'d
somewhere else.** 11 of the 12 land in a path that exists in the session's own tree, and 11 of
the 41 wrong-repo resolutions land in `~/Development/claude-infrastructure` — the shared
checkout, which is exactly the #105 venue where a sibling's dirt lives and where the convicted
session cannot clear the 🔧 because it does not own the file. Track the `cd` and the measured
rate is **0 of 214** (95 % upper bound 1.43 % by the rule of three) with `heredoc` retained.

Row: SYNTHESIS §2B B5 · A07 R2 (conviction 88) · A09 R3 (conviction 75) · backlog `ed54373d639b`.
Subject: `hooks/lib/session-writes.sh` — the **extraction half only**; the three-state rc contract
is untouched. Nothing in the repo was edited by this census.

---

## 1 · The number, per idiom

Denominator is **in-repo hits**, not tracked hits, and that correction matters: `session_dirty_mine`
reads `git status --porcelain -z -uall` (`session-writes.sh:282`), and `-uall` lists **untracked**
files as `?? path`. A heredoc creating a brand-new `docs/…md` therefore reaches the intersection
just as a `sed -i` on a committed file does. Scoping the census to `git ls-files` membership would
have discarded 87 of 214 hits — 41 % of the population — and every one of them can convict.

A hit counts as a **false conviction** when the path the extraction names is not the path the
session wrote **and** that named path exists on disk (a path that does not exist is never listed by
`git status`, so it can convict nobody).

| idiom | in-repo hits | tracked | untracked | false convictions | rate | of which → shared checkout |
|---|---|---|---|---|---|---|
| `heredoc` (`cat > path <<EOF`) | 118 | 93 | 25 | 11 | **9.3 %** | 10 |
| `sed -i` | 37 | 24 | 13 | 1 | **2.7 %** | 1 |
| `>` / `>>` to a path | 59 | 10 | 49 | 0 | **0.0 %** | 0 |
| `tee` without `-a` | 0 | 0 | 0 | 0 | — | 0 |
| **all four** | **214** | 127 | 87 | **12** | **5.6 %** | 11 |

**Subset search against the decision rule** (≥ 80 % coverage at < 2 % false conviction). Coverage is
measured over distinct `(session, in-repo path)` write pairs: 106 pairs are Bash-mediated and
invisible to the oracle today, against 61 pairs the Edit/Write tools already expose — so **63.4 % of
this fleet's real in-repo writes are currently unattributable**, and 33 of 57 writing sessions have
zero Edit-tool writes to a repo while having at least one Bash write.

| subset | false-conviction rate | coverage of the Bash population | meets both bars |
|---|---|---|---|
| `tee` | 0 % | 0.0 % | no — earns nothing |
| `>`/`>>` | 0.0 % (0/59) | 7.5 % | no |
| `>`/`>>` + `sed -i` | **1.0 % (1/96)** ← tightest under 2 % | 17.9 % | no |
| + `heredoc` (all four) | 5.6 % (12/214) | 100 % | no — rate |

The two bars are satisfied by disjoint subsets. That is the finding, not an artifact: `heredoc` is
both the only idiom this fleet uses at scale for authoring files and the only one above 2 %.

## 2 · The automated "not-authored" rate is 73–90 % and reading it as the answer inverts the verdict

The brief's mechanical proxy — *does the path also appear in the same session's Edit/Write records
or an earlier Bash write?* — returns **NOT-authored for 162 of 214 in-repo hits (75.7 %)**. Taken at
face value that reads as a catastrophic REFUTED. It is the opposite.

**A hand-read of 20, drawn at random (seed 5) from the 93 tracked NOT-authored hits, classified:**

| class | n | example |
|---|---|---|
| genuine own write, correctly resolved — the session authored the file by heredoc/`sed -i` and never touched it with an Edit tool | **18** | `cd …/lr100p; cat > tests/lr-reset-poller-inplace.bats <<'BATS'` |
| genuine own write, **mis-resolved into another tree** by an untracked in-command `cd` | **2** | `cd ~/Development/.worktrees/wt-pane-verdict && cat > tests/lead-crash-pane-verdict.bats` → named as `claude-infrastructure/tests/lead-crash-pane-verdict.bats` |
| sibling's file (the `git checkout -- <path>` / shared-store class the brief named) | **0** | — |
| shared-store append (`tee -a`, `>>` into a log) | **0** | — |
| scratch / `/tmp` | **0** in this stratum (818 of 1,032 resolved hits sit outside any repo and are discarded before it) | — |
| fixture text inside a heredoc that is not an execution | **0** in this stratum — **686 such hits were stripped upstream** (see §3) | — |

18 of 20 NOT-authored hits are the session's own write that the current oracle simply cannot see.
**The NOT-authored bucket is the coverage the change exists to add, and its rate is not the error
rate.** The hand-read's 2/20 mis-resolutions (10 %) agrees with the mechanical wrong-repo count over
the full population (10/93 tracked = 10.8 %), so the sample surfaced no mechanism the scan missed —
which is the precision check the unsampled matcher required.

A cross-check for the sibling class specifically: of the 93 tracked NOT-authored hits, **7** name a
path some *other* session in the window also wrote. All 7 are legitimate multi-session files
(`.claude/rules/agent-operating-lessons.md`, `docs/plans/LIMIT_RECOVER_100P.md`, `tests/lr-lib.bats`)
where each session's own append is its own write. None is a session being named over a write it did
not make.

## 3 · The 686 fixture hits, and why a naive matcher must strip heredoc bodies first

A command of the shape

```
cat > /tmp/f.sh <<'EOF'
sed -i '' 's/x/y/' inner.sh
echo z > inner2
EOF
```

contains three idiom matches, and **two of them are data**. Across the corpus, matching the raw
command string rather than its executable part mints **686 extra hits** — a 5.4 % inflation over the
12,770 raw hits, concentrated in exactly the sessions that write scripts and tests, i.e. the ones the
extension is for. The matcher used here consumes heredoc bodies by delimiter before tokenizing.

Two smaller precision traps, both real in this corpus and both fixed before the counts above were
taken:

- **A quoted `>` is not a redirect.** `grep -n '>' file.txt` reads as a redirect to `file.txt` under
  a POSIX-mode tokenizer, which strips the quotes. The matcher runs `shlex(posix=False)` so quoting
  survives and a quoted operator is skipped.
- **`sed -i ''` on BSD takes the suffix as a separate argument.** Treating it as an operand names
  the empty string; treating the script as an operand names the substitution expression as a file.

## 4 · Method — re-runnable

The prototype is a scratch file (`extract.py` in this session's scratchpad) and is **not committed**;
it is a throwaway per the wave contract, and its decisive logic is reproduced here so the census can
be re-derived. Population enumeration:

```
find ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary \
     -path '*/projects/*' -name '*.jsonl' -newermt '2026-09-08 00:00:00' ! -name 'agent-*' -print0
```

Then, streaming each file line-by-line with `json.loads` inside `try/except` (**never `jq -s`, and
never a single `jq` pass** — §1b of SYNTHESIS: one oversized record aborts jq mid-file and silently
truncates the census; here `json_parse_failures` was **0 of 141,688 records**, so the store is clean
on this axis and the tolerant reader cost nothing):

1. For each `assistant` record, for each `tool_use`: `Write|Edit|MultiEdit|NotebookEdit` →
   `.input.file_path` joins the session's authored set; `Bash` → `.input.command` enters the matcher.
2. Split the command into **executable text** and **heredoc bodies** by scanning `<<-?\s*(["']?)(\w+)\1`
   per line and consuming until the delimiter line. Bodies are counted separately and never mint hits.
3. Tokenize each executable line with `shlex(posix=False, punctuation_chars=True)`, split on
   `; && || | &`, and per segment: emit `>`/`>>` targets (attached or spaced, skipping quoted
   operators, `&…` and `/dev/*`); emit `sed` operands when an unquoted `-i` flag is present, skipping
   `-e`/`-f` arguments and the BSD suffix; emit `tee` operands when no `-a`/`--append` is present and
   `tee` heads its segment or follows a wrapper (`sudo`, `env`, `nohup`, …). A segment whose first
   word is `cd`/`pushd` updates the effective directory; `cd -` and `cd "$SOMEVAR"` set it to
   *unknown*.
4. Resolve each target twice — once against the record's `cwd` (**naive**) and once against the
   effective directory (**cd-aware**) — then `os.path.realpath` the parent and re-append the
   basename, which is `_sw_canon`'s algorithm verbatim (`session-writes.sh:175-181`).
5. Walk up to the nearest `.git` for the repo top; membership via one cached `git ls-files -z` per
   repo; existence via `os.path.exists`.

The matcher carries a 28-case fixture selftest (redirect forms, quoted operators, `awk '{print > "x"}'`,
`python3 - <<'PY'`, `sudo tee`, `tee -a`, BSD and GNU `sed -i`, `cd`-tracking, heredoc bodies); it
passes 28/28. **A W3 implementation must ship that selftest as bats before the idiom set lands** —
the census's whole precision claim rests on it.

## 5 · Population, denominator, and every excluded stratum

| stratum | n | disposition |
|---|---|---|
| `*.jsonl` under the four `projects/` roots, mtime ≥ 2026-09-08 | 355 files | population frame |
| `agent-*.jsonl` under `*/subagents/**` | **176 files — EXCLUDED** | the Stop hook's `transcript_path` never names one; a subagent generates no Stop |
| main session transcripts scanned | **179 files · 141,688 records · 311 MiB** | the census |
| `Bash` tool_use records | 19,348 | |
| — commands the tokenizer could not parse | **1,027 (5.3 %) — EXCLUDED, fail-safe** | see §6 |
| raw idiom hits on executable text | 12,770 | |
| — hits inside heredoc **bodies** (fixture text) | 686 — excluded by construction | §3 |
| — targets unresolvable (`/dev/null`, `&1`, unexpanded `$VAR`, globs) | 11,738 (91.9 %) | dominated by `2>/dev/null`; A07 R2's contract makes these **rc 2**, never rc 1 |
| resolved targets | 1,032 | |
| — outside any git repo (`/tmp`, scratchpads) | **818 — EXCLUDED** | cannot reach the `git status` intersection |
| **in-repo hits — the census denominator** | **214** across 44 transcripts, 100 distinct paths | |

**The one term that cannot be measured, and it bounds every rate here upward.** A false conviction
requires the mis-named path to be **dirty at the moment the session closed**. That state is not
replayable: re-reading `git status` now returns 0 of the 12 dirty, but the sessions that produced
them closed and landed hours earlier, so the reading neither confirms nor refutes. Every rate in §1
is therefore an **upper bound** on live conviction, and the same factor divides both the as-proposed
and the corrected variant, so the comparison between them is unaffected.

## 6 · Adversarial pass — three things this census nearly assumed away

**(a) 1,027 Bash commands (5.3 %) do not parse, and 83 % of them contain a write token.** They are
`bash -c '…'` wrappers, `python3 - <<'PY'` bodies that write files through Python, and multi-line
`for` loops. Under the proposal a command that fails to parse yields **no detection at all**, so the
session's rc stays where it is — a coverage miss in the safe direction, not a conviction. But it
caps what B5 can ever deliver: `python3 - <<'PY' … open(p,'w') …` is a real, common write to a
tracked file that **no idiom set reaches**, and one such case in this corpus rewrote a tracked
`personal/*.md`. B5's ceiling is well below "sees every Bash write".

**(b) `tee` earns nothing and should be dropped from the idiom set.** 11 raw hits, 8 resolved,
**0 in any repo**. It contributes zero coverage and zero risk, so it is pure surface: one more
selector, one more mutant to maintain, one more thing to get wrong. The proposal's own framing —
*`tee` without `-a`* — implies the danger is `tee -a` into a shared store, and this corpus contains
no repo-path `tee` of either form.

**(c) `session-writes.sh`'s sidechain invariant is vacuous on this build, and B5 cannot fix it.**
The header states *"Sidechain (subagent) records are DELIBERATELY INCLUDED: a subagent's edit is this
session's write, and excluding it would attribute the session's own dirt to nobody"*
(`session-writes.sh:64-66`), and `_sw_paths` carries `$r.isSidechain != true` in its turn-boundary
guard (`:136`). **Across all 179 main transcripts and 141,688 records, exactly 0 carry
`isSidechain:true`.** The subagent records live in separate `subagents/**/agent-*.jsonl` files — 176
of them in this two-day window — which the Stop payload's `transcript_path` never names. So the
guard never fires, and **a subagent's writes are invisible to the oracle by any idiom, Bash or
otherwise**. This is a coverage hole strictly larger than the one B5 addresses, it fails in the safe
direction, and it is out of B5's scope; it wants its own row. Scope note: this measures *these* 179
transcripts on the current build, not a claim about every harness version.

## 7 · Verdict for W3

**STAYS BELOW 90 as proposed — conviction 35 %** that adding the four idioms with straightforward
path resolution is net-positive. No subset satisfies the decision rule: the tightest subset under
2 % (`{>/>>, sed -i}`, 1.0 %) covers 17.9 % of the Bash write population against the required 80 %,
and the subset that reaches 80 % coverage must include `heredoc`, which runs at 9.3 %. Worse, the
error concentrates in the shared checkout: 11 of 12 false convictions name a path in a tree the
session was not writing to, and the shared checkout is precisely where a sibling's dirt lives and
where the innocent session cannot clear the block — the failure `session-writes.sh:56-62` rejects
the whole extension over, reproduced empirically in a two-day window.

**CROSSES 90 for a narrower, corrected variant — conviction 88 %**, which is the number W3 should
carry, not a green light:

> Three idioms — `heredoc`, `sed -i`, `>`/`>>` (**drop `tee`**) — with the target resolved against
> an effective directory that tracks in-command `cd`, and **rc 2 (cannot-tell) whenever the
> effective directory is unknown** (`cd -`, `cd "$VAR"`) or the target is unresolvable.

Measured on that variant: **0 false convictions in 214 in-repo hits**, 95 % upper bound **1.43 %** by
the rule of three — under the 2 % bar — while retaining 100 % of the measured Bash-write coverage
(106 of 106 pairs) and 63.4 % of all real in-repo writes this fleet makes.

**Why 88 and not above 90.** The cd-tracker is itself shell parsing, which is the
*prescribed-remedy-worse-than-the-bug* class `session-writes.sh:40-44` names by name; a cd-tracker
with a bug is worse than no extraction, because it would mint exactly the wrong-tree convictions
this census found. The evidence that would take it over 90 is a W3 deliverable, not more research:
**one bats mutant per idiom plus a cd-tracker red-proof** — a fixture whose command `cd`s to a
second tree, asserted to name the second tree's path and to arm nothing in the first. That fixture
must not be a copy of an existing one: the whole census turns on the two trees having **different**
paths for the same relative file, and a single-tree fixture holds the one axis the bug lives on
constant (memory `fixture-identifier-shape-collapses-two-spaces`).

## 8 · The fail direction — what a wrong reading looks like

1. **Stopping at the automated rate kills the right change for the wrong reason.** "NOT-authored /
   hits = 75.7 %" reads as REFUTED. 18 of 20 hand-read cases are the session's own write, so that
   number measures the *coverage gap*, not the error. The proxy's polarity is inverted for the
   dominant bucket, and only a hand-read separates them. If a future re-run reports a rate near 75 %
   and concludes "too dangerous", it has re-derived the coverage.
2. **Running this census on a fleet that does not `cd` returns 0 and reads as safe.** All 12 false
   convictions come from a session working outside its launch `cwd` — a property of *this* fleet's
   wave discipline (worktree-per-wave, `cd` into a peer's tree to inspect or patch), not of the
   idioms. 10.4 % of in-repo hits carry an effective directory different from the record `cwd`
   today. The mechanism would be dormant, not absent, in a single-worktree corpus; key the re-check
   on the `cd`-divergence rate, not on the conviction count.
3. **Treating "names a repo path" as "will convict" overstates every rate here** (the dirty-at-close
   term of §5), and treating `git ls-files` membership as the population **understates** it by 41 %
   (the `-uall` untracked term of §1). The two errors point in opposite directions and do not cancel.
