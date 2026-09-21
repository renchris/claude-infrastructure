# W5-D — `bin/cc-lr`: one command for find / recover / status / repair

Worktree `wt-lr-w5d`, branch off `origin/main` at `ea5012b30`. File set, exclusively:
`bin/cc-lr` (new), `tests/cc-lr-front.bats` (new), `commands/limit-recover.md`. Nothing outside it
was written.

---

## 1. What changed, and why

### `bin/cc-lr` (new, 477 lines: 317 code, 135 comment) — a front end that COMPOSES, and three refusals that do not exist anywhere else

The parts were already correct and already fast. `cc-find` resolves a session in 0.18 s against the
30.4–41.0 s `cc-sessions` walk it replaces (U07 §0, §6b); `lr-fleet.sh --one … --detach` re-execs
its driver under `setsid` and returns in ≤3 s. What was missing was a surface that puts them in one
order — and **three refusals that are enforced NOWHERE downstream.** That is the load-bearing claim
of this wave and I verified it on the tree rather than taking it from the brief:

`lr-fleet.sh --one` checks exactly **one** precondition — "already TRANSPLANTED", at
`scripts/limit-recover/lr-fleet.sh:802` (registry/store path) and `:828` (census path). There is no
teammate guard, no ambiguity guard and no is-it-actually-limited guard on that path at all. So:

| rule | refusal | what it would cost |
|---|---|---|
| **RULE 0** | a **TEAMMATE** — `cc-find` classes it in column 7 and excludes it from every ranked result, but handed the sid directly `--one` will recover it | recovering a lead-owned session hands a driver someone else's pane |
| **RULE 1** | an **AMBIGUOUS** ref — `cc-find` already exits 2 with every candidate printed (`bin/cc-find:279`, `:309`, `:331`); cc-lr's job is to STOP on that, never to read row 1 | panes 122 and 124 rendered the byte-identical statusline (U07 §4); a silent pick is how the wrong pane gets recycled |
| **RULE 2** | a session that is **not LIMITED** | there is nothing to recover, and the actuator is a 115–658 s call |

All three refuse with **rc 2 and create no mutex**. A refusal that leaves a lock behind blocks the
next *correct* attempt, so refusal-before-mutex is ordering, not decoration — and it has its own
mutant (M12) which kills seven cases.

**The mutex reads its holder rather than assuming.** `mkdir` is the atomic primitive (the one
`lr_state_append` already uses for its event lock). A held mutex resolves three ways:

* holder pid **ALIVE** ⇒ REFUSE — a second driver on one pane is the split brain W10 exists for;
* holder pid **DEAD** ⇒ steal, loudly — the holder proved itself dead, and waiting out a TTL for a
  corpse is how a crashed driver silences every later attempt;
* **no holder file** ⇒ steal only past `CC_LR_MUTEX_TTL_S` (1800 s, ≈3× the 658 s worst measured
  `--one`, U14 §2.1) — an unlabelled lock may be a driver that has not written its holder yet.

After a successful fire the holder is **re-stamped with the DRIVER's pid**: this process exits
immediately, and a mutex naming a dead pid is stolen by the next caller, which for a live recovery
is exactly the split brain the mutex exists to prevent. On an `lr-fleet` refusal the mutex is
**released**, so a failed fire does not park the session forever.

The mutex path is `$STATE/runs/by-sid/<sid>.active` — deliberately the spelling the W5 spec gives
the poller's own claim (`PLAN_DRAFT.md` § W5, lr-reset-poller §0), so that when W5-A lands the two
interlock instead of racing. See § 5 residual R3.

### `status` — the state store's SECOND production reader

`lr_state_current` (`scripts/limit-recover/lr-lib.sh:439`) was present but inert: its only callers
were two bats cases. It is now called from production here — as the **per-file fallback**. The fast
path is **one bulk jq over every `events.jsonl` plus one `stat` for every mtime**, because one fork
per bundle blows the 0.1 s budget at 20 bundles; the ladder is the same shape `cc-find`'s `cf_bulk`
uses and for the same reason (jq aborts the whole invocation on one malformed document, and a
corrupt run must cost its own row, never every row).

It honours the **terminal-stickiness contract lr-lib.sh states at `:393`** — "readers compute the
state as the LAST line; a terminal line is sticky against a later non-terminal one" — so a
crashed-then-restarted writer's `probed` cannot erase a `FAILED:submit` verdict. A later *terminal*
line still replaces an earlier one: a run that failed and then recovered has recovered.

`CAUSE` is the last relevant row's `detail`; `NEXT` is the ONE command, and for a failed or parked
run it is always `cc-lr repair <bundle>`.

### `repair` — writes a request, kicks the daemon, **never types**

Schema fixed by its consumer, read at `scripts/limit-recover/lr-reset-poller.sh:674-677`:

* `.sid` is **REQUIRED** — absent, the poller renames the file `<name>.malformed.json` into
  `results/` and it is **LOST, not retried** (`:675`). So a bundle whose parent directory is not a
  session uuid is REFUSED here, rather than queued into a discard.
* `.target` (default `auto`), `.source_pane`, `.requested_by` (default `?`) — all at `:677`.
* `.mode` — **not read by the poller on this tree.** W5-A is adding the consumer this wave; at the
  time of writing it has not landed (`git show origin/main:…/lr-reset-poller.sh | grep -c "'.mode'"`
  ⇒ 0, and `reports/W5A.md` does not exist). The field is written per the W5 spec so it is there
  when the reader lands; an unread extra key is inert to `jq`. See § 5 residual R1.

`requested_by` is **`CC_PANE_ID` first, `ITERM_SESSION_ID` only as the fallback, `##*:` stripped** —
copied exactly from `lr-fleet.sh:753-759`, whose class-B cases name the failure: a stale
`ITERM_SESSION_ID` can sit beside a live `CC_PANE_ID` after a transplant, and preferring the stale
one addresses the wrong pane.

The write is **write-then-rename** into a dotfile with a `.tmp` suffix — the poller's drain globs
`$REQUESTS/*.json`, which cannot match on either axis. The kick is
`launchctl kickstart gui/$(id -u)/com.reso.lr-reset-poller`, **no `-k`** (`-k` kills a running
poller first, and a tick that is mid-transplant is exactly the one a caller just enqueued work for —
`lr-fleet.sh:893-896` makes the same argument and only ECHOES the command), and it is **non-fatal**:
the request is already on disk and the poller's own interval drains it, so a failed kick delays the
work, it does not lose it. `hooks/validate-bash.sh` has no `launchctl` rule at all (grep: 0 hits),
so nothing refused the call; the guard is cc-lr's own ratchet, which allows `kickstart` and no other
verb.

### `find` — a passthrough, `exec bash "$FIND_BIN" "$@"`

Resolved through the **readlink-first ladder** `bin/cc-find:60-61` uses, because `~/.claude/bin` is a
per-file symlink farm and a `$0`-relative path resolves against the LINK's directory.

### `commands/limit-recover.md`

§ The fast path rewritten around `cc-lr`: `/limit-recover <ref>` ⇒ `cc-lr recover <ref>` **and END
THE TURN**, with the three refusals tabulated so a reader who routes around `cc-lr` knows what they
are losing. `<ref>` added to `argument-hint` (line 5). The banned-transport table and the U11
measurement that motivates ending the turn are kept verbatim. DoD metric
`grep -c 'until \[' commands/limit-recover.md` was 0 before and is **0** after.

---

## 2. Verified anchors

Every line below was read in this worktree at `ea5012b30`, not taken from the spec.

| anchor | verified | what it gave me |
|---|---|---|
| `bin/cc-find:60-61` | ✅ exact | the readlink-first `$0` ladder cc-lr copies |
| `bin/cc-find:150-152` | ✅ | `cf_class` → `TEAMMATE` \| `LIMITED` \| `SESSION` \| `UNKNOWN` (column 7) |
| `bin/cc-find:279`, `:309`, `:331` | ✅ | the three `return 2` (AMBIGUOUS) sites; candidates printed, never one row |
| `bin/cc-find:44-46` (header) | ✅ | the rc contract: 0 resolved · 1 no match · 2 ambiguous · 3 usage |
| `scripts/limit-recover/lr-fleet.sh:69` | ✅ exact | `STATE="${LR_STATE_DIR:-$HOME/.reso/limit-recover}"` |
| `…/lr-fleet.sh:740-768` | ✅ | the `--detach` block; `:748` is the refusal when `detach.sh` is unreachable |
| `…/lr-fleet.sh:765` | ✅ | `echo "run=$FLEET_DIR/$RUN log=$_lf_log"` — the FLEET run dir, not the bundle |
| `…/lr-fleet.sh:753-759` | ✅ | the `CC_PANE_ID`-first requester ratchet cc-lr copies |
| `…/lr-fleet.sh:802`, `:828` | ✅ | `--one`'s ONLY precondition, "already TRANSPLANTED" — no teammate guard |
| `…/lr-fleet.sh:896` | ✅ | the kickstart command, ECHOED and never run |
| `…/lr-lib.sh:393-394` | ✅ | the terminal-stickiness contract `status` implements |
| `…/lr-lib.sh:409` / `:439` | ✅ exact | `lr_state_append` / `lr_state_current` |
| `…/lr-lib.sh:511` | ✅ | `LR_STATE_DIR` honoured |
| `…/lr-handoff.sh:479` | ✅ exact | `BUNDLE="$HOME/.reso/limit-recover/$SID/bundle-$TS"` — hardcoded |
| `…/lr-reset-poller.sh:674-677` | ✅ | the request schema; `:675` is the sid-absent ⇒ `.malformed.json` LOSS |
| `…/lr-reset-poller.sh:127` | ✅ | `STATE="$HOME/.reso/limit-recover"` — **also hardcoded** (see § 3) |
| `bin/cc-limited:852` | ✅ | `render_screen` — read for the column idiom only; never called |
| `install.sh:995` | ✅ | `for tool in "$REPO_DIR"/bin/cc-* …` — a new `bin/cc-lr` needs no install.sh edit |
| `tests/cc-lr.bats:15`, `:270-276` | ✅ | the naming trap and the `$FIND`-scoped iron rule this suite's own ratchet is modelled on |
| `hooks/validate-bash.sh` | ✅ | **0** `launchctl` hits — nothing refuses the kick |

---

## 3. Where the spec disagreed with the tree

1. **Every `scripts/lr-*.sh` path in the brief and in `PLAN_DRAFT.md` § W5 is wrong.** The files
   live under **`scripts/limit-recover/`**. `scripts/lr-predicate-lint.sh` is the only `lr-` script
   at `scripts/` top level.
2. **The store divergence is TWO consumers, not one.** The brief says "every lr consumer honours
   `LR_STATE_DIR` … but `lr-handoff.sh:479` hardcodes". `scripts/limit-recover/lr-reset-poller.sh:127`
   **also** hardcodes `STATE="$HOME/.reso/limit-recover"`, and that is the more consequential one
   for this wave: it is the **request lane** `cc-lr repair` writes into. Under a non-default
   `LR_STATE_DIR`, cc-lr queues a request the daemon will never look at. cc-lr honours
   `LR_STATE_DIR` (the `lr-fleet.sh:69` spelling) and names the divergence in its own header rather
   than silently scanning two roots, which would hide a split store. Neither file is in my set.
3. **The line anchors are off by 2–6 throughout** but all resolve within a few lines: `--one`'s
   TRANSPLANTED check is `:802` not `:801-803`; the detach print is `:765` not `:766`; the requester
   ratchet is `:753-759` not `:757-762`; the poller schema is `:674-677` not `:675-679`;
   `lr-lib.sh`'s `LR_STATE_DIR` is `:511` not `:506`; `bin/cc-limited`'s `render_screen` runs to
   `:899`, not `:884`.
4. **`PLAN_DRAFT.md` § W5 acceptance names `tests/cc-lr.bats (new)`.** That file already exists and
   is **bin/cc-find's** suite (276 lines, `FIND="$REPO/bin/cc-find"` at `:15`). This wave's suite is
   `tests/cc-lr-front.bats`; `tests/cc-lr.bats` was not touched, including its re-tuned walltime
   case at `:60-71`/`:102`.
5. **The D2 §4 C1 design describes a `cc-lr` that drives its own chain** (`lr-resolve.sh`,
   `lr-drive.sh`, `runs/<id>/state.json`, `index.jsonl`, tracking ids of the form
   `lr-<sid8>-<stamp>`). None of that exists on the tree and none of it is in this wave's file set.
   What is built is the § W5 line-item version: a front end that composes `cc-find` + `lr-fleet
   --one --detach` + the bundles those already write. `status`'s columns are therefore what the
   store actually holds (`ts`/`state`/`stage`/`detail`), not D2's `PANE / ACCT→ACCT` — no field on
   `events.jsonl` carries a pane or an account.
6. **The bundle path CANNOT be known at fire time, and this is a fact about the tree, not a
   shortcut.** The brief asks for the bundle path as line 3's id. `lr-handoff.sh:479` mints
   `bundle-$TS` with **its own** timestamp, **inside the detached driver**, *after* the precheck and
   the capacity park — which on a parked run is minutes later and on a refused run never. A path
   invented by the firing process is a guess no store confirms. Line 3 therefore prints what IS
   known — the bundle ROOT, which is keyed on the sid alone, plus any bundle a previous attempt
   already left — and hands over `cc-lr status <sid8>`, which resolves the newest bundle at READ
   time. `cc-lr repair` accepts either the bundle path or the sid8 for the same reason (D2 §1.3: an
   identifier a tool prints must be one it accepts).

---

## 4. Mutation score

**36 mutants built · 36 killed · 0 survived at close.** Four survived the first pass and are
recorded as survivors below with the case that then killed each; that is the whole point of the
exercise and the four are the most informative rows in the table.

Method: `bin/cc-lr` or `tests/cc-lr-front.bats` is patched by one mutation, the suite runs, the
subject is restored from a copy and the restore is **verified by sha256** before the next mutant.
A run that produced no `1..N` plan line is recorded `NO-VERDICT`, never `pass` — a bats suite that
REFUSES (rc 75, machine-wide admission shed) emits no `not ok` and exits 0. Every verdict below was
re-taken against the tree **as committed**, so the score is not a fact about an earlier draft.

### Recover — the three refusals and their ordering

| # | mutation | verdict | case that died |
|---|---|---|---|
| M01 | RULE 0 (teammate) deleted | **SURVIVED → killed** | see § survivors |
| M02 | RULE 2 (`class != LIMITED`) deleted | KILLED | `recover REFUSES a session that is not LIMITED` |
| M03 | cc-find rc 2 falls through instead of refusing | KILLED | `recover REFUSES an ambiguous ref` |
| M04 | the "exactly one row at rc 0" belt deleted | KILLED | `recover REFUSES two rows at rc 0` |
| M05 | cc-find rc 1 collapsed into rc 2 | KILLED | `recover relays cc-find's rc 1` |
| M12 | the mutex is taken BEFORE the three refusals | KILLED (13 cases) | `recover REFUSES a teammate …` + 12 more |
| M11 | `--source-pane` passed even when no pane is known | KILLED | `recover omits --source-pane when no pane is known` |
| M29 | a bare ref silently recovers instead of rc 3 | KILLED | `an unknown subcommand and a bare ref are rc 3 usage` |
| M28 | `find` drops its argv | KILLED | `find execs cc-find with verbatim argv` |

### Recover — the mutex

| # | mutation | verdict | case that died |
|---|---|---|---|
| M06 | a LIVE holder no longer refuses | KILLED | `recover REFUSES when the mutex is held by a LIVE pid` |
| M07 | a DEAD holder is not stolen | KILLED | `recover STEALS a mutex whose holder pid is dead` |
| M08 | the TTL comparison inverted (`-lt` → `-gt`) | KILLED | `recover REFUSES an unlabelled mutex under the TTL` |
| M09 | the mutex is not released when lr-fleet refuses | KILLED | `recover RELEASES the mutex when lr-fleet refuses` |
| M10 | the holder is not re-stamped with the DRIVER's pid | KILLED | `recover … takes the mutex, fires --one … --detach` |
| M35 | the unreachable-lr-fleet guard deleted | KILLED | `… RELEASES nothing when lr-fleet is unreachable` |
| M36 | that guard keeps the mutex instead of releasing it | KILLED | same case |

### Status — the state store's reader

| # | mutation | verdict | case that died |
|---|---|---|---|
| M13 | terminal stickiness removed | KILLED | `a terminal state is STICKY against a later non-terminal line` |
| M14 | the FIRST terminal sticks, not the last | **SURVIVED → killed** | see § survivors |
| M15 | the NEXT column is unconditional | KILLED | `NEXT names cc-lr repair for a failed or parked run` |
| M16 | an empty store returns 0 instead of 1 | KILLED | `status is rc 1 and prints no table` |
| M17 | jq forked per bundle | KILLED | `status forks jq ONCE and stat ONCE over 20 bundles` |
| M18 | stat forked per bundle | KILLED | same case |
| M19 | newest run rendered LAST | KILLED | `status renders the LAST state per run, newest run first` |

### Repair — the request lane

| # | mutation | verdict | case that died |
|---|---|---|---|
| M20 | the sid-uuid validation removed | KILLED | `repair REFUSES a bundle with no derivable sid` |
| M21 | the `--mode` validation removed | KILLED | `repair REFUSES an unknown mode` |
| M22 | writes straight to the destination | **SURVIVED → killed** | see § survivors |
| M27 | the unresolvable-ref refusal removed | **SURVIVED → killed** | see § survivors |
| M23 | `ITERM_SESSION_ID` preferred over `CC_PANE_ID` | KILLED | `repair's requested_by is CC_PANE_ID FIRST` |
| M24 | the `##*:` strip removed | KILLED | same case |
| M25 | a failed kick made fatal | KILLED | `repair kicks with kickstart and NO -k` |
| M26 | `kickstart` gains `-k` | KILLED (3 cases) | same case + both iron-rule cases |

### The ratchet itself — five arms, each proved load-bearing

Every arm of `iron_rule()` was blanked in turn (its pattern replaced with a token absent from the
file). All five died on `iron rule POSITIVE CONTROL`, which is the case that builds one mutant per
banned verb and requires the ratchet to trip on each.

| # | arm blanked | verdict |
|---|---|---|
| M30 | git-mutation arm | KILLED |
| M31 | typing arm (`send-text`/`osascript`/`it2 session send`/`tui-submit`/`expect`) | KILLED |
| M32 | kill arm (`pkill`/`killall`, and any `kill` other than `kill -0`) | KILLED |
| M33 | launchctl arm (verb must be `kickstart`; never `-k`) | KILLED |
| M34 | ship/deploy arm | KILLED |

### The four survivors, and what each taught

**M01 — deleting RULE 0 (teammate) left the suite green.** Because a teammate is *also* not
LIMITED, RULE 2 refused the same ref with the same rc, and the original assertion
`[[ "$output" == *TEAMMATE* ]]` matched RULE 2's message too (it names the class). The refusals are
**behaviourally redundant on cc-find's current contract** — `cf_class` returns `TEAMMATE` before it
ever tests for a limit (`bin/cc-find:150-156`), so a teammate can never reach RULE 2 as `LIMITED`.
That is not a reason to leave the arm untested: the two refusals say different things to an
operator, and RULE 0 is the one that must survive if cc-find's class vocabulary ever changes.
**Case written:** the teammate case now asserts RULE 0's own words (`lead-owned`) and the ABSENCE
of RULE 2's (`not LIMITED`). M01 now dies on it.

**M14 — "the FIRST terminal sticks" left the suite green.** The existing case fed
`FAILED:submit → RECOVERED`, whose LAST line is itself terminal, so the stickiness branch never
ran and could not choose wrongly. **Case written:** a third fixture,
`FAILED:submit → RECOVERED → probed`, which is the only shape that forces the branch to pick
between two terminals. M14 now dies on it.

**M22 — writing straight to the destination left the suite green.** Not an equivalence, but
unobservable from outside: the error path's own `rm -f "$tmp"` deletes the destination too when
`$tmp == $dest`, so the "a failed write leaves no request" case passes either way. The real
property is about an INTERVAL — that no partially written file ever matches the poller's
`$REQUESTS/*.json` glob — and no external test can sample it. **Case written:** a structural arm
asserting the temp is a dotfile with a `.tmp` suffix and that `mv -f "$tmp" "$dest"` places the
destination. It is anchored on source text and its residual is stated (R5). M22 now dies on it.

**M27 — deleting the unresolvable-ref refusal left the suite green.** It fell through to the
sid-uuid guard one line below (`basename "$(dirname ffffffff)"` → `.`), which refused it with the
same rc. **Case written:** assert the arm's own message. M27 now dies on it.

### Arms I did NOT mutate, and why

Three guards are genuine equivalence guards against the mutations available to me, and I state the
mutation each DOES die on rather than pad the table:

* `[ -x "$FIND_BIN" ] || [ -f "$FIND_BIN" ]` in `cl_resolve` — deleting it leaves
  `bash "$FIND_BIN"` exiting 127, which the `*)` arm turns into the same rc 2. It dies on a mutation
  that also removes the `*)` arm, i.e. it is the *message*, not the refusal.
* `command -v jq` in `cmd_repair` — without jq nothing is written either way; the guard converts a
  silent empty file into a named refusal. Dies on a mutant that also drops the `> "$tmp" || …`
  failure branch.
* the `[ $# -ge 2 ]` option-value guards — bash's own `"$2"` under `set -u` aborts anyway; the guard
  turns an unbound-variable trace into rc 3 usage. Dies on a mutant that also removes `set -u`.


---

## 5. Residuals

Each carries the command that re-measures it.

**R1 — `.mode` has no consumer on this tree.** W5-A is adding the poller's reader this wave; it had
not landed when this was written, so `cc-lr repair` writes a field nothing reads. It is inert to
`jq`, and the alternative — omitting it — would need a second edit the day W5-A lands.
`git fetch -q origin && git show origin/main:scripts/limit-recover/lr-reset-poller.sh | grep -c "'\.mode'"`

**R2 — the store is split under a non-default `LR_STATE_DIR`, and TWO files cause it.**
`lr-handoff.sh:479` writes bundles to a hardcoded `$HOME/.reso/limit-recover/$SID/bundle-$TS`, and
`lr-reset-poller.sh:127` reads its request lane from a hardcoded `$HOME/.reso/limit-recover`. So
with `LR_STATE_DIR` set, `cc-lr status` looks where no bundle is written and `cc-lr repair` queues
where no daemon looks. Both files are outside this wave's set; cc-lr honours `LR_STATE_DIR` (the
`lr-fleet.sh:69` spelling) and says so in its header rather than scanning two roots, which would
hide the split.
`grep -n 'reso/limit-recover' scripts/limit-recover/*.sh bin/cc-limited | grep -v LR_STATE_DIR`

**R3 — the mutex and the poller's claim share a path but have never met.** cc-lr takes
`$STATE/runs/by-sid/<sid>.active`, which is the spelling `PLAN_DRAFT.md` § W5 gives the poller's own
claim, deliberately so that the two interlock. Nothing on the tree writes that path yet, so *who
releases it* is untested across the two actuators. cc-lr's own release paths are the lr-fleet
refusal (M09) and the dead/stale steal (M07, M08); a poller that took the mutex and died leaves a
lock cc-lr steals only once its holder pid reads dead.
`grep -rn 'runs/by-sid' scripts/ bin/`

**R4 — line 3's id is a bundle ROOT, not a bundle.** See § 3.6: `lr-handoff.sh:479` mints the
directory inside the detached driver, minutes later on a parked run. `cc-lr status <sid8>` resolves
the real one at read time and is what line 3 hands over.
`grep -n '^BUNDLE=' scripts/limit-recover/lr-handoff.sh`

**R5 — one test arm is anchored on source text.** "repair's destination is placed ONLY by a rename
from a dotfile temp" greps `bin/cc-lr` for `tmp="$REQ_DIR/.cc-lr-repair-` and `mv -f "$tmp" "$dest"`,
because the property is about an interval no external test can sample (§ 4, M22). A behaviour-
preserving rename of those two variables disarms it silently — the shape the repo lesson
*a-mutation-control-anchors-on-the-subjects-source-text* names.
`bats tests/cc-lr-front.bats -f 'placed ONLY by a rename'`

**R6 — `cc-lr recover` takes a BARE ref only.** A pane id (`117`, `⌗117`, `#117`), a sid or a sid8.
`--tuple` and `--kw` are two-token forms and are reachable through `cc-lr find` alone; passing one
to `recover` is rc 3 usage, not a silent mis-parse.
`bash bin/cc-lr recover --tuple 'x'; echo $?`

**R7 — `status`'s columns are what the store holds.** D2 §4 C1 renders `PANE` and `ACCT→ACCT`; no
field on `events.jsonl` carries either (`ts`, `run`, `state`, `stage`, `detail`, `writer`,
`attempt`). Adding them would mean a second store or a registry join per row, which is the fork
budget this reader exists to avoid.
`jq -r 'keys_unsorted | @csv' "$(ls -d ~/.reso/limit-recover/*/bundle-*/ | head -1)events.jsonl" | head -1`

**R8 — nothing here has been run end-to-end against the real actuator.** Every case stubs `cc-find`,
`lr-fleet.sh` and `launchctl`, deliberately: a case that reached the real `lr-fleet` would RECOVER A
PANE from a test run. So the composition against a live `--detach` — in particular whether the
`driver pid N` and `run=` lines keep the shapes `lr-fleet.sh:764-765` prints — is pinned by a stub
and not by the tree. It is an operator-owned check because it moves a real session.
`bash bin/cc-lr recover <a pane id that is genuinely limited>`

**R9 — the 0.1 s figure was PRINTED, not judged, in this session.** The box ran at load/core 2.1–3.6
throughout (10 cores, `uptime` 21–36), above the case's 1.0 judged band, so the walltime arm
abstained by design and the fork-count arm carried the claim. Re-take on a quiet box:
`CC_LR_JUDGE_MAX_LPC=99 bats tests/cc-lr-front.bats -f 'inside its budget'`

---

## 6. Suites run, with their plan lines

Asserted as plan lines, not as "no failures" — a suite that REFUSES emits no `not ok` and exits 0.

| suite | plan line | result |
|---|---|---|
| `tests/cc-lr-front.bats` (new, this wave) | `1..32` | **32/32** |
| `tests/cc-lr.bats` (the sibling; untouched, run as a control) | `1..15` | **15/15** |
| `tests/cc-pane.bats` (whole-tree ITERM ratchet) | `1..34` | **33/34 — the red is TRUNK's, see § 7** |
| `tests/deploy-parity.bats` (a new `bin/cc-*` file) | `1..107` | **107/107** |
| `tests/deploy-link-parity.bats` | `1..67` | **67/67** |
| `tests/cc-unattended-ask-guard.bats` (reads `commands/`) | `1..14` | **14/14** |

Static gates, all clean on `bin/cc-lr`, `tests/cc-lr-front.bats` and `commands/limit-recover.md`:
`shellcheck -S warning -x` (the `.bats` file too — SC2010 and SC2034 were both real and both
fixed), `bash -n` **and** `/bin/bash -n` (bash 3.2, which is what launchd runs),
`scripts/pipefail-sigpipe-lint.sh`, `scripts/bats-assert-liveness.py` (30 `[[ … ]]` assertions were
DEAD under bash 3.2 as first written and now carry `|| false`).

**One admission waiver was taken and it is recorded.** The box sat at load/core 2.1–4.0 for the
whole session (10 cores; `uptime` 21–39, five sibling worktrees gating concurrently), and
`cc-bats`'s ceiling refused 12 of the first 34 mutant runs outright. The second and third mutation
passes and the three close-out suites ran under `CC_BATS_MAX_ROOTS=0` — the documented
admission-only switch — with `CC_BATS_WAIVER_REASON` stated, which appends an attributed line to
`~/.claude/state/bats-waivers.jsonl`. Each waived run was a single filtered case, sequential, never
a parallel batch. Read them back: `tail -n 20 ~/.claude/state/bats-waivers.jsonl`.

---

## 7. STOP-ON-ISSUE: `tests/cc-pane.bats:352` is RED on trunk, and it is not this diff

`tests/cc-pane.bats` case 27 — *"ratchet: no production file reads a BARE `$ITERM_SESSION_ID`
without the CC_PANE_ID fallback"* — fails. **It is trunk's, it predates this branch, and the file
is outside this wave's set, so I did not touch it.** The A/B, run with the ratchet's own predicate:

```
git grep -n -F '${ITERM_SESSION_ID:-}' ea5012b30 -- bin scripts hooks \
  | grep -v CC_PANE_ID | grep -v cc-pane-id-lint:allow \
  | grep -vE 'handoff-fire\.sh|handoff-selfclose-e2e\.sh|lr-handoff\.sh'
⇒ ea5012b30:scripts/limit-recover/lr-fire-resume.sh:594:LR_PANE="${ITERM_SESSION_ID:-}"; LR_PANE="${LR_PANE##*:}"
```

The same hit is present at `origin/main`, and it is the **only** hit — `bin/cc-lr` does not appear,
because its one read is `p="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"`, which carries the fallback on
the same line and is filtered out by the ratchet's own `grep -v CC_PANE_ID`.

The line landed in `ba5e3c1e1` (2026-09-19, *"a quiet pty is read before it is typed into"*) and
was last touched by `bdf38553c`. It is a genuine class-A site: a bare `$ITERM_SESSION_ID` read with
no `CC_PANE_ID` preference, in a limit-recovery script — i.e. exactly the population the ratchet
was written for, and exactly the failure its class-B commentary describes (a stale
`ITERM_SESSION_ID` beside a live `CC_PANE_ID` after a transplant addresses the wrong pane).
`scripts/limit-recover/lr-fire-resume.sh` is another wave's file; **the one-line fix is the same
shape `lr-fleet.sh:758` already uses** and belongs to whoever owns that file:

```
LR_PANE="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; LR_PANE="${LR_PANE##*:}"
```

Re-measure: `bats tests/cc-pane.bats` (case 27), or the `git grep` above against `origin/main`.
