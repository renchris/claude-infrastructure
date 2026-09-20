# The resume regex expect refused — a locale pin that stopped one hop short

**Row:** cc-backlog `137f29a38c10` — post-land RED,
`tests/lr-resume-answer-width.bats::WIRING: with the source suppression FORCED OFF, the menu is
answered AS-IS at every width` @ `cde5cbfa0a08`.
**Verdict:** real defect, reproduced, cured, red-proven. Cure on this branch, not on trunk at the
time of writing.
**Run from:** an Anthropic cloud VM (Linux), not the desk. Every reading below states the env it
was taken under, because the env IS the variable.

## 1. What the row is not

It looks like a relapse of the 2026-08-12 byte-split (`03b7a50c7`, corrected by `4ed74ee9c`): same
suite, same 8-of-11 count, same `❯`. It is not. That cure pins the locale **bash** splits under and
**it is still working**. Measured — `lr_wrap_re`'s output is byte-identical under `LC_ALL=C` and
under a UTF-8 locale, for all 14 phrases the repo calls it with:

```
env -i PATH=… LC_ALL=C      bash -c 'eval "$(sed -n "/^lr_wrap_re() {/,/^}/p" FIRE)"; lr_wrap_re "❯1. Resume"' | od -An -tx1
env -i PATH=… LC_ALL=C.utf8 bash -c '…same…'                                                                  | od -An -tx1
→ identical; leading bytes `5c e2 9d af` = one backslash then the 3-byte ❯ in both
```

Counting the same 8 reds twice is what made a live second defect read as a cured first one.

## 2. The actual mechanism

`lr_wrap_re` builds a **Tcl** regex. `expect` is a **third program** `lr-fire-resume.sh` spawns, and
Tcl reads `LC_ALL` for itself to pick `encoding system`. That choice decides whether the bytes bash
emitted are one character or three, and the builder's backslash means opposite things in the two
readings:

| `encoding system` | the pattern's first token | Tcl ARE verdict |
|---|---|---|
| `utf-8` | `\❯` — ❯ is not alphanumeric | a literal-escape ⇒ **compiles** |
| `iso8859-1` | `\â` + 2 bare chars — â **is** alphanumeric in Latin-1 | unknown escape class ⇒ **REFUSED** |

Isolated directly (`expect -c`, iso8859-1): `\â` → `invalid escape \ sequence`; bare `â` → fine;
`\.` → fine. So the trigger is precisely *backslash before a non-ASCII character that the active
encoding calls alphanumeric*.

The refusal kills the expect program outright. The arm never runs, the keylog stays **empty**, and
`lr-fire-resume.sh` still exits **0** — fail-open and silent. That is why the wiring tests report
"selector never moved off option 1" rather than anything naming a regex.

## 3. Why it landed green and redded afterwards

| path | locale it runs under | outcome |
|---|---|---|
| `/ship` gate, a desk `bats` run | operator's ambient UTF-8 | compiles — **green** |
| `scripts/offbox-run.sh` | `env -i … LC_ALL=C` (`:151-158`) | refused — red |
| `scripts/postland-verify.sh` | launchd; the plist exports **PATH and nothing else** | refused — **the post-land RED** |

`launchd/com.claude.postland-verify.plist` has no `EnvironmentVariables` key. With no `LANG` and no
`LC_ALL`, libc falls back to C. This exact class is already on the record one layer over —
`hooks/anti-deference-nudge.sh:214` documents post-land RED `d6a4896406aa`, where a POSIX bracket
expression degraded to bytes under the same LANG-less launchd corpus run. There a character class
became a byte set; here a backslash changes meaning.

Reproduced under **both** shapes, trunk vs this branch:

```
### ENV: launchd (env -i PATH=…, no LANG, no LC_*)
 trunk:  encoding system = iso8859-1 · VERDICT: REFUSED — invalid escape \ sequence
 branch: encoding system = iso8859-1 · VERDICT: compiles
### ENV: env -i … LC_ALL=C          → same two verdicts
```

## 4. The cure

A backslash goes in front of **ASCII punctuation only**. Every Tcl ARE metacharacter is ASCII, so
nothing is lost; a non-ASCII character is always a literal and must be emitted bare, which matches
under either encoding because pattern and input then decode the same way.

Membership is tested against a literal set, not `[[:ascii:]]` and not a glob range: a range is
collation-dependent and a class table is interpreter-dependent, and this file runs under macOS
`/bin/bash` 3.2.57. `${set#*"$ch"}` is plain POSIX expansion needing neither, and is already proven
in desk-executed code — `hooks/validate-bash.sh:476`, `hooks/lib/dod-path.sh:127`,
`hooks/lib/placeholder.sh:108`. **`scripts/bash32-parse-lint.sh` returns NON-VERDICT off-box** (no
bash 3.x here, and ftp.gnu.org is blocked by the egress policy), so that precedent is the evidence
standing in for a 3.2 run — the desk's own gate still gets the real verdict.

## 5. Blast radius, measured rather than argued

My diff can reach sibling suites only through `lr_wrap_re`'s output, so that output was compared
directly, trunk vs branch, for all 14 phrases under both locales:

- **7 ASCII-only phrases — byte-identical.** Zero change.
- **7 phrases containing `❯` — differ by exactly one byte**, the `5c` backslash the fix drops.

And that byte is inert wherever things were already green. Compile-then-match verdicts against the
real captures, trunk vs branch:

| expect under | readback `❯2. Dark mode` (must MATCH) | negative `❯1. Auto` (must NOMATCH) |
|---|---|---|
| `LC_ALL=C.utf8`, w = 8/20/40/80 | trunk MATCH · branch MATCH — **identical** | trunk NOMATCH · branch NOMATCH — **identical** |
| `LC_ALL=C`, w = 8/20/40/80 | trunk **REFUSED** · branch MATCH | trunk **REFUSED** · branch NOMATCH |

So: no behavioural change on the UTF-8 path, correct behaviour on the C path, and the readback's
discrimination — the property that makes answering the menu safe at all — preserved at every width.

## 6. The suite could not see this, and now can

Under a UTF-8 runner a mutant reverting the cure left **all 11 original tests GREEN**. The suite
only redded off-box because `offbox-run.sh` happens to pin `LC_ALL=C` — which is exactly the trap
that file's own § COROLLARY names: *an axis supplied by the harness is an axis the suite is not
testing*. Two arms were added that set the hostile locale **themselves**, per its instruction that
a suite testing an env-coupled invariant must do so:

- `ENCODING PIN: every pattern compiles in expect under LC_ALL=C, not only under UTF-8` — five
  phrases × three locales, via a compile-only probe so a refusal is reported as a refusal rather
  than as a missed match.
- `ENCODING PIN: the readback still discriminates when expect decodes as iso8859-1` — compiling is
  necessary and not sufficient; a pattern can compile and match nothing.

**Red-proof.** Against that same mutant under a UTF-8 runner these two are the **only** tests that
fail, and both do. Against it under `LC_ALL=C`, 8 of 11 fail as the row reports.

Two latent weaknesses in the harness were fixed alongside: `match_in` did not truncate its verdict
file (a dead matcher could return the previous call's answer) and reported an empty file as a
missed match rather than as `DIED`.

## 7. Evidence index

| claim | command |
|---|---|
| suite red before, green after | `env -i HOME=… TMPDIR=… PATH=… TERM=dumb LC_ALL=C CC_OFFBOX=1 bats tests/lr-resume-answer-width.bats` → 8/11 red on `ab8c5c52`, 13/13 green here |
| the refusal itself | drive `lr-fire-resume.sh` under that env → `couldn't compile regular expression pattern: invalid escape \ sequence`, rc 0, empty keylog |
| postland runs LANG-less | `launchd/com.claude.postland-verify.plist` ProgramArguments — exports PATH only, no `EnvironmentVariables` |
| bash cure still working | byte-identical `lr_wrap_re` output under C and C.utf8 |
| lints | `shellcheck -S warning` clean (and clean on trunk's baseline) · `bats-shellcheck-lint` · `bats-kill-guard-lint` · `bats-testname-eval-lint` (711 suites) · `bats-assert-liveness.py` · `test-hermeticity-lint` (711 suites) — all clean |

## 8. A sibling cured a DIFFERENT defect in this same suite, in parallel

While this was in flight, trunk gained `f6ae93ba` — *"lr-resume-answer-width was ambient-dependent
on one env var"* — which adds `unset CLAUDE_CODE_RESUME_THRESHOLD_MINUTES` to `setup()`, because a
session launched with resume-suppression exports that variable into every shell it spawns and the
`--summary` arm then asserted `<unset>` against the desk rather than against the script.

**It is not this defect and neither supersedes the other.** Different arm, different mechanism, no
overlapping lines; the rebase applied cleanly and this branch now carries both. Two independent
confirmations that they are disjoint:

- Every reading in this document was taken under `env -i`, where that variable is absent — so it
  was never active in any of them, and the 8-of-11 here is the encoding defect alone.
- At `ab8c5c52` (before `f6ae93ba`), **this fix alone** takes the suite to 13/13. Nothing else in
  the tree was broken at that commit.

After rebasing onto trunk tip the suite is 13/13 in three env shapes, the third of which holds
**both** hostile conditions at once:

| shape | result |
|---|---|
| `env -i … LC_ALL=C` (offbox harness) | 13/13 |
| `env -i … LC_ALL=C.utf8` (desk-like) | 13/13 |
| `env -i …` no `LANG` **and** `CLAUDE_CODE_RESUME_THRESHOLD_MINUTES=999999999` | 13/13 |

That commit's own closing line — *"a corrected instrument delivers you into the next false
negative"* — is a fair description of this row too: it names a third `set -u` abort at `:381`,
cured before `ab8c5c52`, that produced the same empty-keylog symptom from a third cause. Three
distinct defects have now presented as *"the keylog is empty"* in this one suite. **The symptom is
not diagnostic here; read the drive's stderr before attributing it.**

## 9. Dispatcher vintage

`git rev-parse origin/main:bin/cc-dispatch` = `dc9130372d6332940388c2a17da7c65c1af3c3bd`, **EQUAL**
to the blob that composed the brief. The dispatcher that fired this work is trunk.

## 10. Left open, deliberately

- **No bash 3.2 run.** Off-box there is none and the source is unreachable through the egress
  policy. Argued from proven in-repo precedent instead (§4); the desk's `bash32-parse-lint` is the
  arm that can actually close it.
- **The fail-open silence is not cured, only tested.** A pattern expect refuses still exits 0 with
  an empty keylog. The new arms make the suite catch it; nothing makes the *script* announce it. A
  separate row, not widened into this one.
