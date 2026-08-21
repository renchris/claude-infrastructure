# Permission prompts: what actually blocks us, and why the allowlist was the wrong lever

**2026-08-20.** Question asked: *investigate our history of permission prompts and improve our
allowlists with scalable patterns, so auto mode stops stopping.* This is the synthesis. The two
companion documents hold the evidence:

* `permission-matcher-truth-2026-08-20.md` — how CC 2.1.220 actually matches rules (binary +
  probes).
* `permission-settings-store-2026-08-20.md` — where settings live, what syncs them, what reloads.

---

## The answer, first

**The allowlist could not have fixed this, and the one hook that was supposed to was inverted —
auto-approving across eight of the operator's own fence rules while being structurally unable to
fire on the shape that actually prompts.** Both halves were proven by running the subject, not by
reading it. The fix is in `hooks/smart-bash-allowlist.sh` + `hooks/lib/smart-bash-allowlist.py`.

Three measurements carry it:

| | Measured | Source |
|---|---|---|
| Blocking Bash commands with full text | **1,759** over 2026-07-31 → 2026-08-20 | `~/.claude/autonomy/permission-archive` |
| Of those, **compound** (`&&`, `;`, `\|`, newline, `$( )`) | **90.4%**, mean 11.9 segments, 59.1% multi-line | corpus scan |
| Fence rules bypassable by prefixing `git commit -m x && ` | **8 of 36**, incl. 2 hard `deny` | executing the live hook |

---

## 1. Why the prompt history had to be mined, not guessed

`bin/cc-permission-audit` reports two populations and the gap between them is the whole story:
**21,618 Bash invocations matched no allow rule, but only 1,759 actually prompted.** Two mechanisms
that are *not* the allowlist close that gap, both verified in the matcher doc:

1. **A built-in read-only set.** With an *empty* allowlist, `date`, `uname`, `hostname`, `id`,
   `printf`, `git status`, `git rev-parse` all run with no prompt.
2. **The auto-mode classifier.** Every session on this box runs `--permission-mode auto`, and the
   classifier approves most unmatched commands on its own.

⇒ Writing patterns against the 21,618 would have been writing rules for commands that never
prompted. Only the 1,759 are addressable, and that is the corpus used throughout.

## 2. Why a settings.json rule could never have covered them

The harness parses each command with tree-sitter, splits on `&& || ; | |& &` and newlines, and
requires **every** sub-command to match independently (`any deny → deny; all allow → allow; else
ask`). So prefix rules *do* compose across compound commands — that was the open question, and the
answer is yes.

**But five constructs are gated *before* rule matching, and no allow rule of any form reaches
them:** `$( )` / backticks, `( … )` subshells, `{ …; }` groups, a trailing `&`, and **any output
redirection to a file**. `bash -c '…'` is not decomposed and is refused.

Those constructs are not a rare tail here — they are the house style. 543 of 1,759 blocking
commands (31%) contain a substitution. **Only a `PreToolUse` hook emitting `allow` can approve
them**, because that verdict bypasses the permission system entirely.

Two further findings make the settings route worse than useless for `allow`:

* **Auto mode DROPS a large class of allow rules** — anything keyed on `python|python3|node|npm
  run|bash|sh|env|xargs|sudo|curl|wget|…`. A `Bash(curl:*)` entry would be dead weight in the mode
  we actually run.
* **There is no sanctioned all-accounts path for `allow`.** `install.sh` unions `permissions.deny`
  and `permissions.ask` across the five config dirs and *pointedly does not union `allow`* — which
  is exactly why deny/ask sit at perfect parity while allow has forked. Adding allow rules means
  editing five real files by hand, with a mirror that may re-fork them.

⇒ **The hook is the lever. The allowlist is not.** No `permissions.allow` change was made this
session, and that is a decision, not an omission.

## 3. The defect that was actually there

`hooks/smart-bash-allowlist.sh` was wired in **5 of 5** config dirs (its own test header still
claimed "0 of 5" — stale by the time it mattered). It decided on the **raw command string**:

* **Rule 1 (`git commit`) was anchored only at the START.** It fired on anything beginning with
  `git commit` and carried whatever followed. Because a PreToolUse `allow` bypasses everything,
  `git commit -m x && <tail>` auto-approved `git push`, `git push --force`, `git reset --hard`,
  `git restore`, `fly deploy`, `git clean -xdf`, `rm -rf .git` and `wget` — eight of the operator's
  36 Bash fence rules, two of them hard `deny`.
* **Rules 3/5/6 were whole-command-anchored** (`[^;&|]+$`), so the *safe* read-only rules could not
  fire on a compound command at all.

Simultaneously too permissive where it fired, and inert where it didn't. Its header asserted the
opposite — *"rules 1/3/5/6 cover those [compound commands]"* — and the suites guarding it varied
only the command's CONTENT, never its SHAPE, so `git push origin main` alone was correctly refused
and nobody ever asked the question that mattered.

**Generalisable lesson.** A guard anchored at one end of its input is a guard against one end of its
input. And a test suite that never varies the structural axis will certify a file that is broken
along exactly that axis — the defect lived where no test looked, not where the tests were weak.

## 4. What was built

`allow(C)` **iff** C decomposes confidently into segments, **and** no segment matches the operator's
**live** `permissions.ask`/`deny` fence, **and** no danger pattern matches, **and** every segment
independently matches a positive whitelist. Any doubt anywhere ⇒ no decision. `deny` stays
unreachable — a wrong `deny` wedges a session with no human in the loop; a wrong silence costs one
prompt.

Load-bearing properties:

* **The fence is read live from settings.json.** A rule the operator adds arms the hook with no code
  change here; an unreadable fence refuses to decide rather than deciding blind.
* **Substitutions are judged, not refused.** Recursively, against the same fence — so `$( )` cannot
  launder a gated command, while a substitution in *verb* position still defers.
* **`rm` is delegated to `rm-safe-allowlist.sh`**, never re-implemented, and only for the compound
  case that hook cannot reach. No second deletion policy exists to drift.

**Result, replaying all 1,759 archived blocking commands through both deciders: 111 allow (6.3%) vs
the pre-fix 89 (5.1%) — with zero fenced segments inside any allowed command, where the pre-fix 89
were largely the bypass itself.** 111 is a floor: 749 rows' original working directories no longer
exist and containment is cwd-relative.

## 5. The honest ceiling, and what is next

93.7% still defers, and most of it *should*: interpreters taking a command as data (`python3`,
`bash -c`), deletions outside a regenerable tree, git mutations, and 122 commands sitting behind the
operator's own gates. Some buckets carry `classifierApprovable: false` and **cannot be fixed by any
rule or hook at all**.

A deterministic whitelist is near its limit. The designed next step already exists in this repo and
is **unwired**: `hooks/model-permission-decider.py` — route the residue to a model that has the
session and repository context, with the same live fence applied to decomposed segments, emitting
only `allow` or `ask`. Its own header records the measured harness behaviour it depends on. Wiring
it is a separate decision, because a model in the permission path is a different risk posture than a
regex, and it should be taken deliberately rather than as a side effect of a prompt-reduction pass.

Two smaller follow-ons, both filed rather than done here:

* `install.sh` unions `deny`/`ask` but not `allow` — the reason allow has forked across five config
  dirs. Fixing that is the prerequisite to *any* future allowlist work being durable.
* The 339 existing allow entries have never been audited against the auto-mode drop list;
  `cc-permission-audit --prune` already exists to find provably-dead ones.

## Deployment note

Hooks reach all five accounts by per-file symlink into this checkout, and CC 2.1.220 ships a
settings watcher, so a landed hook change is live for every running session without a recycle. The
`allow` array is the one thing that does *not* travel that way — which is the point of §2.
