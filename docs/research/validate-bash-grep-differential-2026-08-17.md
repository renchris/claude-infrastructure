# The grep → bash-native differential for hooks/validate-bash.sh

**Date:** 2026-08-17 · **Row:** backlog `8942f3b1506d` · **Deliverable:** the corpus that row blocks
itself on · **Verdict: the row's remedy is RETIRED for two thirds of its own population.**

**10 of the 30 pattern sites are safe to convert. 20 are not — and on the path that actually costs
the forks the row is trying to save, exactly 1 of the 10 always-executed greps is convertible.**

The row proposes replacing `grep -qE` with bash-native `[[ =~ ]]` at ~30 sites in
`hooks/validate-bash.sh`, saving one fork per site on the hottest path in the fleet (this hook fires
on every Bash tool call). It blocks itself on its own terms: *"a differential corpus proving
identical verdicts on every DANGER pattern first."* That corpus now exists, is re-runnable, and its
answer is no.

## How to re-run it

```
bash scripts/validate-bash-differential.sh            # per-site verdict table + every counterexample
bash scripts/validate-bash-differential.sh --markdown # the table below, regenerated
bash scripts/validate-bash-differential-controls.sh   # 4 mutants + baseline — proves it can fail
bats tests/validate-bash-differential.bats            # all of the above as a suite
```

Fixtures: `tests/fixtures/validate-bash-sites.tsv` (the 31-row site inventory — 30 hook lines, site
114 instantiated twice because its pattern is built from an interpolated flag) and
`tests/fixtures/validate-bash-corpus.txt` (66 cases). The corpus file holds literal danger strings
by design and is read from disk; pasting a case body into a Bash tool call is denied by the live
hook, which is why nothing here is inlined.

## What was measured, and against which binaries

The hook is `#!/bin/bash` and calls **bare `grep`**. On this box that resolves to
**`/usr/bin/grep` — BSD grep 2.6.0-FreeBSD**, not GNU grep and not ugrep: there is no `grep` in
`/opt/homebrew/bin`, no `ggrep`, no `ugrep`, and `/usr/bin` precedes `/opt/homebrew/bin` on the
hook's PATH. (The `interactive-grep-is-ugrep` memory is about the *interactive* Bash-tool shell,
which is zsh with a rewrite; it does not reach this hook. The harness prints the binary it used and
takes `CC_DIFF_GREP` for a cross-check.) The bash side is **`/bin/bash` 3.2.57**, whose `=~` compiles
through the platform `regcomp`.

For each of 31 site rows × the applicable corpus cases — **1,672 scored pairs, 56 diverging** — the
harness runs the grep the hook actually executes (same invocation form, same feed: `printf '%s'`
vs `echo`, and for site 599 the same `sed|sed|tr|sed` pipeline) and the naive bash-native form a
converter would reach for (`[[ $x =~ $pat ]]`; `shopt -s nocasematch` for `-qiE`; `[[ $x == *lit* ]]`
for `-qF`; a match-and-advance loop for `-oE`). A case is scored against a site only when the site's
subject can actually receive it — a multi-line case is not charged against a pattern whose subject
is a single `grep -oE` occurrence, which is newline-free by construction. That narrows
*reachability*, never a verdict.

## Per-site verdict table

`subject`: **whole** = all of `$CMD`, can be multi-line · **line** = one occurrence extracted
upstream · **clause** = a `tr ';|' '\n'` fragment · **token** = one argv token · **stream** = the
multi-line stream site 599 greps.

| site | line | form | subject | cases | diverging | verdict | first counterexample |
|---|---|---|---|---|---|---|---|
| S01a | 114 | `qE` | whole | 60 | 0 | **EQUIVALENT** | — |
| S01b | 114 | `qE` | whole | 60 | 0 | **EQUIVALENT** | — |
| S02 | 472 | `qE` | whole | 60 | 1 | **DIVERGENT** | ml-body-sudo-rm |
| S03 | 503 | `qE` | whole | 60 | 0 | **EQUIVALENT** | — |
| S04 | 542 | `oE` | whole | 60 | 5 | **DIVERGENT** | ml-rm-second-line |
| S05 | 545 | `qE` | line | 47 | 0 | **EQUIVALENT** | — |
| S06 | 546 | `qE` | line | 47 | 0 | **EQUIVALENT** | — |
| S07 | 599 | `qE` | stream | 57 | 2 | **DIVERGENT** | ml-pkill-second-line |
| S08 | 600 | `oE` | whole | 60 | 1 | **DIVERGENT** | ml-pkill-then-more |
| S09 | 604 | `qE` | line | 47 | 0 | **EQUIVALENT** | — |
| S10 | 608 | `qE` | line | 47 | 0 | **EQUIVALENT** | — |
| S11 | 612 | `qF` | line | 47 | 0 | **EQUIVALENT** | — |
| S12 | 624 | `qiE` | whole | 60 | 4 | **DIVERGENT** | tp-ddl-turso |
| S13 | 625 | `qiE` | whole | 60 | 4 | **DIVERGENT** | tp-ddl-turso |
| S14 | 630 | `qE` | whole | 60 | 1 | **DIVERGENT** | ml-body-drizzle-push |
| S15 | 635 | `qE` | whole | 60 | 5 | **DIVERGENT** | tp-git-add-force |
| S16 | 638 | `qE` | whole | 60 | 5 | **DIVERGENT** | tp-git-add-force |
| S17 | 657 | `qE` | whole | 60 | 2 | **DIVERGENT** | tp-commit-dash-n |
| S18 | 676 | `qE` | whole | 60 | 1 | **DIVERGENT** | tp-cc-git-identity |
| S19 | 684 | `qE` | whole | 60 | 7 | **DIVERGENT** | tp-exempt-write |
| S20 | 685 | `qE` | whole | 60 | 2 | **DIVERGENT** | nm-exempt-read |
| S21 | 686 | `qE` | whole | 60 | 1 | **DIVERGENT** | tp-exempt-write |
| S22 | 776 | `qE` | clause | 46 | 4 | **DIVERGENT** | tp-gid-write-bare |
| S23 | 778 | `qE` | clause | 46 | 3 | **DIVERGENT** | nm-exempt-read |
| S24 | 779 | `qE` | clause | 46 | 0 | **EQUIVALENT** | — |
| S25 | 781 | `qE` | clause | 46 | 3 | **DIVERGENT** | tp-gid-write-bare |
| S26 | 950 | `qE` | whole | 60 | 3 | **DIVERGENT** | tp-reset-hard |
| S27 | 956 | `qE` | whole | 60 | 1 | **DIVERGENT** | ml-body-git-clean |
| S28 | 971 | `qE` | token | 9 | 0 | **EQUIVALENT** | — |
| S29 | 986 | `oE` | whole | 60 | 1 | **DIVERGENT** | ml-body-rm-flags |
| S30 | 989 | `qE` | line | 47 | 0 | **EQUIVALENT** | — |

**EQUIVALENT (safe to convert), 10 hook lines:** 114, 503, 545, 546, 604, 608, 612, 779, 971, 989.
**DIVERGENT (must not convert), 20 hook lines:** 472, 542, 599, 600, 624, 625, 630, 635, 638, 657,
676, 684, 685, 686, 776, 778, 781, 950, 956, 986. **UNTESTED: none** — the harness enumerates the
hook's own code-level `grep -` lines and fails if any is missing from the inventory, so a site added
later is a red, not a silent pass.

## The four causes, attributed — not guessed

Each was isolated with the other axes held out, because a divergence beside a true-but-irrelevant
difference reads as diagnosed when it is not.

### 1. `\b` is a word boundary in BSD grep and a **literal `b`** in bash — 13 sites

The single largest cause. `/usr/bin/grep -E` honours `\b`; bash's `=~` compiles it through
`regcomp`, which has no `\b`, and the backslash is dropped — so `\bconfig\b` becomes the literal
`bconfigb`. Measured with everything else held constant:

```
pattern '\bconfig\b'   input 'git config --get x'    grep=MATCH   bash=no       ← guard goes SILENT
pattern '\bconfig\b'   input 'git bconfigb --get x'  grep=no      bash=MATCH    ← guard FIRES on noise
pattern 'config'       input 'git config --get x'    grep=MATCH   bash=MATCH    (control: no \b, agrees)
```

This is not a style difference, it is **a security hole in the under-blocking direction and a false
deny in the over-blocking one**, at the same site, from the same edit. Live consequences from the
corpus, verbatim:

```
S15/S16 (git add -f/--force guard, lines 635/638)
  git add --force .env.secret        grep=MATCH  bash=no       ← force-add of a gitignored file ALLOWED
  git add -f .env.secret             grep=MATCH  bash=no
  git addb notes.txt                 grep=no     bash=MATCH    ← an innocent command DENIED
S18 (identity-gate escape hatch, line 676)
  CC_GIT_IDENTITY_OWNER=x git commit -m "wip"    grep=MATCH  bash=no  ← the sealed bypass reopens
S19 (git config detection, line 684)
  every one of the 7 config cases   grep=MATCH  bash=no       ← the whole cc.identity.exempt clause dies
S22/S25 (git identity write, lines 776/781)
  git config user.email t@t          grep=MATCH  bash=no       ← the 2026-08-05 leak guard goes inert
S26 (git reset --hard warn, line 950)
  git reset --hard origin/main       grep=MATCH  bash=no
  git reset --hardball origin/main   grep=no     bash=MATCH    ← and --hardb, the literal-b reading
S12/S13 (DDL guard, lines 624/625)
  turso db shell mydb "DROP TABLE users"        grep=MATCH  bash=no
  echo "TRUNCATE TABLE audit" | sqlite3 app.db  grep=MATCH  bash=no
```

Note what S19's row means concretely: `\bconfig\b` is the *entry condition* for the
`cc.identity.exempt` write guard. Converted, it never matches a real `git config` line, so the two
sites beneath it (685, 686) are unreachable regardless of their own verdicts. A converted `\b` site
does not degrade — it disappears.

### 2. `^` anchors per LINE in grep and to the WHOLE STRING in bash — site 599

The highest-risk axis the brief named, and it lands on the one site whose subject is *deliberately*
multi-line. Line 599 pipes `$CMD` through `sed | sed | tr ';' '\n' | sed` precisely to split a
compound command into one clause per line, then anchors `^(sudo[[:space:]]+)?(pkill|killall)` to the
start of each. In bash there is one string and one `^`:

```
input 'echo one\npkill -f bats'    grep=MATCH  bash=no
input 'echo x && pkill -f bats'    grep=MATCH  bash=no    ← && is turned into a newline by the pipeline
```

The second case is not exotic: `&&`-chaining is the ordinary shape of an agent tool call, and the
splitter exists so a sibling clause cannot exonerate a dangerous one. Converting this site restores
exactly the compound-command escape hatch the pipeline was written to close — the machine-wide
`pkill -f bats` that caused the 2026-07-26 false-RED epidemic (backlog `a0718a5d78b3`).

### 3. `[[:space:]]` cannot cross a line in grep and **includes `\n`** in bash — 3 sites

`sudo[[:space:]]+rm` (472), `drizzle-kit[[:space:]]+push` (630) and
`git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]` (956) look anchor-free and therefore safe. They are
not: in bash the class matches a newline, welding the end of one line to the start of the next. The
realistic carrier is a multi-line `-m` message body, where the words are prose:

```
git commit -m "refuse to sudo
rm anything under /, ever"                       grep=no  bash=MATCH  ← commit DENIED as a fork-bomb/sudo-rm
git commit -m "docs: never use drizzle-kit
push against production"                         grep=no  bash=MATCH
git commit -m "chore: stop recommending git clean
-fdx in the runbook"                             grep=no  bash=MATCH
```

Direction is over-block, which is the survivable direction — but this is precisely the defect class
line 472's own comment block records the hook already fixing once (*"text is not execution:
`git commit -m "fix: guard rm -rf / properly"` used to be DENIED, so the guard blocked its own
fix"*). Converting these three re-introduces it in a new spelling.

### 4. `grep -oE` extracts per line; a bash loop extracts across the whole string — 3 sites

Sites 542, 600 and 986 do not return a boolean, they return an *occurrence list* that a `while read`
loop then adjudicates per occurrence. `[^;&|]*` and `[[:space:]]+` stop at a line end under grep and
do not under bash, so the occurrences themselves change shape:

```
S08 (line 600)  input 'pkill -f bats\necho done'
                grep -oE → 'pkill -f bats'
                bash     → 'pkill -f bats\necho done'      ← one glued occurrence, not one clean one
S04 (line 542)  input 'echo "cleaning up"\nrm -rf /tmp/x'
                grep -oE → 'rm -rf /tmp/x'
                bash     → '\nrm -rf /tmp/x'                ← leading newline captured by (^|[^a-zA-Z0-9_-])
S29 (line 986)  input 'git commit -m "warn: rm -rf\n/etc is unrecoverable"'
                grep -oE → (no occurrence)
                bash     → 'rm -rf\n/etc'                   ← invents a target that is on another line
```

S04 and S29 are the *legacy* rm paths — the ones that run when `python3` is absent or
`VALIDATE_BASH_LEGACY=1`, i.e. the fallback that exists to be correct when the tokenizer is
unavailable. S29's row is the worst of the three: bash manufactures the target `/etc` out of a
two-line message body and the `rm -r on non-safe target` warn fires on prose.

### Axes that were tested and did **not** diverge

Stated because a corpus that only reports hits cannot be told from one that only tested hits.

| axis | result |
|---|---|
| `\-` escaped hyphen (`\-\-(get\|list)`, lines 685/778) | **AGREE**. The escape exists so grep does not parse `--…` as an option; it is not a divergence source. Those sites are DIVERGENT for `\b` alone. |
| `\.` escaped dot, `\$` escaped dollar, literal backtick (lines 608, 686) | **AGREE** in both engines |
| case folding: `grep -qiE` vs `shopt -s nocasematch` (624, 625) | **AGREE** on the folding itself; those sites diverge on `\b`, and the `nocasematch` conversion is otherwise faithful |
| locale: `LC_ALL=C` vs ambient, multi-byte input (`"Chrïs Ren — café"`) | **AGREE** on both engines, both locales. No locale-attributable divergence observed. |
| empty and whitespace-only input | **AGREE** at every site |
| TAB as the separator, trailing CR (CRLF paste) | **AGREE** except where `\b` is already the cause |
| interval `{n,m}` and back-references | **not applicable** — no site uses either |

## What the optimisation would actually buy

The row's value is forks avoided on the hot path, so the population that matters is the greps that
run on **every** Bash tool call, not the 30 that exist. Ten do: lines **472, 503, 599** (plus its
four-process `sed|sed|tr|sed` pipeline), **624, 630, 657, 676, 684, 950, 956**. The rest are behind a
gate — `RM_PRESENT`, the pkill branch, `check_real_flag` returning true, the `*user.email*`
fast-path, or a short-circuited `&&`.

**Of those ten unconditional forks, exactly one — line 503 — is safe to convert.** The nine that
carry the cost are the nine the corpus refuses. The remaining nine EQUIVALENT sites are all inside
branches that only execute when a dangerous token is already present, i.e. the cold path.

## Conclusion

The conversion is **not** authorised for 20 of 30 sites, and the 10 it is authorised for are almost
entirely off the hot path. A safe conversion is still *possible* — it would mean rewriting `\b` as
an explicit `(^|[^a-zA-Z0-9_-])…([^a-zA-Z0-9_-]|$)` bracket, replacing `[[:space:]]` with `[ \t]`
wherever a newline must not be crossed, splitting on newlines by hand where `^` is per-line, and
keeping `grep -oE` for the three extraction sites. But that is a **rewrite of 20 danger patterns**,
not a mechanical `grep`→`[[ =~ ]]` substitution, and every one of the 20 is a guard whose failure
mode was measured above to be silence. Weighed against ~9 forks per tool call, the trade is not
close. (Order of magnitude only: the hook's own header measures a *different* fork — the `$(cat)`
it removed — at ~6 ms and ~18% of a 163 ms PreToolUse/Bash chain. A grep fork is not that
measurement and no per-grep figure was taken here; if the saving is the case for the row, measure
it rather than inherit the number.)

Recommended disposition for row `8942f3b1506d`: **close as REFUTED-BY-MEASUREMENT**, citing this
document. If the fork cost is worth attacking, the lever is the *number of unconditional greps*
(several sites re-scan the same `$CMD` for overlapping tokens behind no fast path at all — line 684's
`\bconfig\b` and line 624's DDL scan are both unconditional full-string scans), not the engine each
one uses. That is a different row, and it does not require any pattern to change semantics.

## Durability of this result

The verdicts are pinned per site in `validate-bash-sites.tsv` and re-checked on every run, in both
directions: a site that starts diverging fails, and a site that *stops* diverging fails too — the
second because a counterexample silently disappearing is how a control goes vacuous. The harness
additionally fails if the hook gains, loses or moves a `grep` site (coverage) or if a pinned pattern
no longer appears on its line (drift). `scripts/validate-bash-differential-controls.sh` mutates four
pinnings and asserts the harness reds on each with **exit 1 specifically** — not merely non-zero,
which would also be satisfied by a broken path.

Everything above is a measurement of *this box*: BSD grep 2.6.0-FreeBSD and bash 3.2.57. On a host
where the hook resolved GNU grep the `\b` sites would still diverge (GNU grep also honours `\b`;
bash still does not), but the numbers should be re-derived rather than quoted — run the harness.
