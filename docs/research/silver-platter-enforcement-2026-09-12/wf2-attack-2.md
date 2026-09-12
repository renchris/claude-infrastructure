## FALSE POSITIVES & BYPASS — 10 defects, each with the input that triggers it

Every claim below was executed against the real files or measured over the 8,465 transcripts in `~/.claude*/projects/`. Probes: `/tmp/spa_probe.py`, `/tmp/sigprobe.py`, `/tmp/cooc.py`, `/tmp/globtest.sh`.

---

### FP-1 — CRITICAL. R1's signature is argument-blind on multiplexers, so the gate orders a production deploy.

**Input.** A close carrying `▶ Run this:` / `` `aws amplify start-job --app-id d2wzxfgylxxfth --branch-name main --job-type RELEASE` `` (9 emissions) in a session that earlier ran `aws amplify list-jobs`.

**Wrong behaviour.** `hc_sig` is head+subcommand for the multiplexer family, so both resolve to `aws amplify`. `hc_self_ran` matches, R1 returns `REFUTED\tself-ran`, and the corrective reads *"this session already ran `aws amplify` … Run it, then close on the result."* The gate instructs a money-spending Amplify RELEASE — the exact act CLAUDE.md's ship-policy table reserves to the operator.

**Measured.** 118 `aws amplify` executions across 50 sessions. 30 sessions contain both this hand-off and a prior same-signature call, e.g. `~/.claude*/projects/**/agent-ac1b3b3d2ae3fa36b.jsonl` and `0f64011a-c0b7-4272-abca-350858c4bbb6.jsonl`, which ran `AWS_PAGER="" timeout 40 aws amplify list-jobs --app-id djnbdqpvc08g4 --branch-name main --region us-west-2`.

Same shape, two more classes:
- `gh auth refresh -h github.com -s user` (6 emissions — a **browser OAuth flow**, i.e. the genuinely-human 15% the gate exists to protect) is refuted by a prior `gh auth status`. Session `8c6364f9-1eb3-42f4-ba07-75d840efd17f.jsonl` ran `gh auth status` four times. 4 sessions co-occur.
- `git show <sha>` — which CLAUDE.md § *Where the dropped detail goes* **mandates** as the S5 read-back pointer — is refuted by any prior `git show` on any other commit. Measured 4,147 executions across 742 sessions, so this fires on essentially every compliant close that cites a sha on its own line.

**Severity: critical.** It is the largest claimed arm (389 emissions) failing in the one direction that converts a read into a write. Distinct from the causal runner-up's finding (they attacked *failed* prior attempts; this is a *successful* prior attempt of a **different, read-only** subcommand-level command).

**Minimal fix.** R1 may assert a receipt only on ARGV equality, never on signature: require the prior Bash command to contain the handed-over command's executable part with every non-flag argument intact (normalise whitespace; match at a segment head). `hc_sig` may be used to *rule out* a match, never to assert one.

---

### BYPASS-1 — CRITICAL. A3's slash-command glob swallows absolute paths → a universal one-token acquittal wrapper.

**Input.** `▶ Run this:` / `` `/usr/bin/env cc-blockers` `` — or any of the 11 corpus emissions that already start with a lowercase absolute path.

**Wrong behaviour.** The case pattern `/[a-z][a-z0-9_-]*|/[a-z][a-z0-9_-]*' '*` is a bash glob, where `[a-z0-9_-]*` is *one class char followed by `*`* — and `*` matches `/` and spaces. Executed (`/tmp/globtest.sh`):

```
MATCH slug=opt      <= /opt/homebrew/bin/python3 /tmp/discord-read-history.py   (9 emissions)
MATCH slug=tmp      <= /tmp/cc-read-twitter https://x.com/a --images            (2 emissions)
MATCH slug=usr      <= /usr/bin/env cc-blockers
MATCH slug=private  <= /private/tmp/x.sh
```

No `commands/opt.md` exists, so A3 returns `ADMITTED\ttui-builtin` and **short-circuits R1, R2 and R3 entirely**. Prefixing any refutable command with `/usr/bin/env` acquits it unconditionally.

**Severity: critical** — a live miss (11 emissions today) *and* the cheapest possible learned evasion.

**Minimal fix.** Reject paths before the slash arm: `case "$exec_part" in */*|*/*' '*) : ;; /[a-z]*) <A3> ;; esac` — the slug token must contain no further `/`.

---

### FP-2 — HIGH. R3's granularity is the binary; the operator-ness of the two largest `cc-*` rows is per-subcommand, and the design's own escape hatch cannot express it.

**Input.** `cc-decide list --open` (31) · `cc-decide list --open --class C` (9) · `cc-do --list` (13) · `cc-backlog list --blocked` (3).

**Wrong behaviour.** CLAUDE.md § *Where the dropped detail goes* names exactly these three binaries as the commands **the operator** runs to expand the counted `◆` block. R3 refutes them as *"a CLI you run yourself"*. The `# cc-class: operator` header cannot fix it: `cc-decide open` and `cc-backlog add` are **agent-mandatory** under the F2 conviction rule, so the binary is not operator-class — only the `list`/`show` signatures are. The corrective asks the model to run a listing whose only consumer is the human, produces nothing, and the message-hash latch does not prevent a reworded re-close from burning the second of two fires.

**Severity: high** — 43+ emissions, structural rather than an omission.

**Minimal fix.** Key the declaration on `hc_sig`, which the design already computes: `# cc-class: operator list|show|--list`, parsed as a subcommand set; R3 acquits when the handed-over signature is in it.

---

### FP-3 — HIGH. R3 has no exemption for the `bin/` tools whose own headers declare them unrunnable by an agent.

**Input.** `▶ Run this:` / `` `cc-signoff <row>` `` — the mission board's own mandated hand-off (*"An agent may advance a row to `awaiting-signoff` and NO further — only the operator, running `cc-signoff`, can call a floor plan or a bottle menu done"*).

**Wrong behaviour.** `bin/cc-signoff:2` reads *"Operator only … this command exists to be UNRUNNABLE BY AN AGENT"*, and ARM 1 walks the parent chain to refuse a claude child. R3 sees `-x bin/cc-signoff` and refutes. Same for `bin/cc-relogin` (browser OAuth; `cc-relogin next` is in the corpus) and `bin/cc-authbrowser`. Only `cc-do` gets the declaration in the design. 0 emissions today, so it is latent — but it fires on the *compliant* behaviour the customer-deliverable board demands.

**Severity: high** (latent, on the deliverable path).

**Minimal fix.** Same declaration, applied at land time, plus a checked-in test that greps `bin/` for `operator only|UNRUNNABLE BY AN AGENT|Operator ONE-GLANCE` and fails when such a tool lacks `# cc-class: operator`. A spot-list of names is the thing the design correctly refuses elsewhere; make it derived.

---

### SPEC-1 — HIGH. Six load-bearing primitives are never defined, and the two plausible readings of one of them differ by 28 false convictions.

`hc_head`, `hc_sig`, `hc_paths`, `hc_scripts`, `hc_repo_bin`, `_hc_grep` and four of the five `HC_*_RE` constants appear only as call sites. Every arm's verdict is a function of them.

**Concretely, `hc_paths`.** R4a fires when `hd ∈ {cursor,code,subl}` **and** `[ -n "$p" ]`. If `hc_paths` returns any path, all **34** `cursor` emissions are refuted — including ~28 pointing at `.md`/`.yaml` documents (`cursor docs/OWNER_BRIEF.md` ×7, `cursor ~/.claude/model-config.yaml`, `cursor …/NONLIMIT_RESUME_LADDER.md`) — with the corrective *"run it"*. CLAUDE.md § Manual-Command-Delivery records that exact act as a measured defect: a bare `.md` path under a run marker returns `permission denied` and cost a round trip. The scorer's `worksheet 6/2` implies script-only (it matches `cursor /tmp/wifi-cutover-runbook.sh` ×4 + `cursor /tmp/sevenrooms-close-the-loop.sh` ×2 exactly) — but that is inferred from a number, not stated anywhere in the design.

**Minimal fix.** Define it, in the file: `hc_paths` := tokens matching `\.(sh|py|ts|js|mjs)$` or resolving to an `-x` file. Anything else is not a worksheet target.

**Corollary asymmetry, one token wide.** `cursor /tmp/x.sh` → `REFUTED worksheet`; `open /tmp/x.sh` → falls past R4a (which only knows three editor verbs) to A8 → `ADMITTED eyes`. On macOS both hand the operator a file in an editor. Fold `open <script-path>` (without `-a Terminal`) into R4a, or A8 is the worksheet arm's bypass.

---

### BYPASS-2 — HIGH. Welding the command onto the marker line escapes every lookup, and it is a shape the neighbouring hook blesses.

**Input.** ``▶ Run this: `cc-blockers` `` on one line.

**Wrong behaviour.** The parser's inline branch takes `rest` = ``Run this: `cc-blockers` ``, which does not end in `:`, strips backticks, and emits the candidate **`Run this: cc-blockers`**. `hc_head` = `Run`; no arm matches; `UNRESOLVED`; silence. Measured: **60** marker lines in the live transcripts already carry an inline span on the marker line itself. Worse, `close_act_missing` accepts it (`index(t,"▶") > 0`), so the model can satisfy D7 and be invisible to this gate in the same line — enforcement anti-correlated with the scannability rule it sits beside, whose own measurement says the welded form is the *worst* shape for the operator (ACTED 9.4% vs 35.4%).

**Minimal fix.** In the inline branch, take the **last** inline-code span on the line when one exists; else the text after the last colon.

---

### BYPASS-3 — MEDIUM-HIGH. The `ACT:` shape is a sanctioned hand-off form the gate structurally cannot see.

**Input.** `ACT: run bash /tmp/fsev-remediation.sh in your terminal.`

**Wrong behaviour.** `hooks/lib/close-shape.sh:_CS_ACT_LABEL` makes `ACT:` the **second legal act shape**. It carries no `▶`; written without backticks it fails the hot-path `case` and the hook abstains `no-marker`. Two house contracts disagree about what a hand-off is.

**Minimal fix.** Source `close-shape.sh` and arm `hc_commands` on `_CS_ACT_LABEL` as well as `HC_MARKER`. Reuse the constant — do not re-spell it.

---

### BYPASS-4 — MEDIUM. A list marker or `$` prefix on the payload line.

**Input.** `▶ Run this:` then `` - `bash /tmp/x.sh` ``.

**Wrong behaviour.** The armed branch strips only backticks: candidate becomes `- bash /tmp/x.sh`, head `-`, `UNRESOLVED`. Identical for `$ bash …` and `1. bash …`. Measured 2 live occurrences — near-zero adoption cost, and the bullet is a natural formatting habit.

**Minimal fix.** In the armed branch, strip a leading `[-*+•>]\s+`, `[0-9]+\.\s+`, `\$\s+` before printing.

---

### BYPASS-5 — MEDIUM (unexploited today). Fencing the payload both hides it and mis-attributes the next line.

**Input.** `▶ Run this:` then a ```` ```bash ```` fence containing `bash …/deploy-live.sh`.

**Wrong behaviour.** The awk toggles `fence` and `next`s **before** the `armed` test, so the command is never evaluated; `armed` stays 1, so the first non-fenced line *after* the block — prose — is emitted as the candidate. Measured `payload_fenced = 0` today (CLAUDE.md bans the fence), so this is a latent one-character evasion, not a live miss. The 180 marker lines found inside fences are all the rendered `OPERATOR ▸` block (`▶ cc-do [12 runnable]` ×58, etc.) and are correctly skipped.

**Minimal fix.** When armed and a fence opens, consume the fence's first content line as the payload; reset `armed=0` on any fence toggle.

---

### PERF — MEDIUM, and it silently disables the gate on the longest sessions. The hot-path claim is wrong by 27×.

**Measured** over 614 real last-assistant-text records: **55.2% contain a backtick; 2.0% contain `▶`.** So more than half of every Stop in the fleet pays the awk fork, the candidate loop, and — whenever any line is a lone span — a **full-transcript `jq` per candidate** inside `hc_self_ran`, which is called inside the loop with no memoisation. Transcript sizes: p50 0.5MB, p99 **15.7MB**, max **241MB**; one jq pass over the 241MB file measured **1.20s**. Five candidates ≈ 6s against the registered `timeout: 5` → the hook is killed, silently, on exactly the sessions that emit the most hand-offs. (13 Stop hooks are already registered; 4 of them can block.)

**Minimal fix.** Hot-path on `▶` / `ACT:` only — the mandated lone-span form always has a marker above it, so the backtick arm buys nothing. Hoist the Bash-command extraction to one `jq` call before the loop.

---

### BYPASS-6 — STRUCTURAL. The gate's gradient points at "hand over without trying", and the design understates the unreachable surface.

R1 is the only arm with real reach, and it fires **precisely when the session attempted the command**. Never attempting is silent; attempting and failing for a human-only reason is convicted. Add the two measured escapes that need no cleverness: **244 of 1,855 marker-bearing assistant records (13.2%) are not the last assistant text of their turn** and are unreachable by any Stop hook (confirming the design's 13.5%), and `SPA_MAX=2` caps enforcement at two fires per `CFG|SID|CWD` key — a `cd` to a worktree mints a fresh key, and everything after the cap is admitted in silence. Combined with BYPASS-1..5, an agent needs no intent to evade; the natural formatting variants already escape.

State this in § *What it cannot see* as a **gradient** defect, not only a coverage one, and treat the deferred `PreToolUse/Write` companion as the load-bearing half rather than a nice-to-have.

---

### Confirmations (not new)

`cc-owner` mention-vs-use is real; executed just now: `cc-owner "cd ~/Development/claude-infrastructure && git diff hooks/session-start.sh"` → `OWNED — hook:SessionStart — names session-start.sh`, rc 0. R2 would refute a pure read. The `minimal` runner-up's segmentation fix is the right shape and also repairs R1's basename match.