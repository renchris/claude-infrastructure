# Refutation pass: K06 "Record what a blocked session asked for, then pre-answer it"

Date: 2026-10-06 (local, UTC-5). Repo read-only at `/Users/chrisren/Development/.worktrees/wt-cc-205652-27362` (HEAD `593a21fc3`). No session started, no row dispatched, no state changed.

## Verdict

| field | value |
|---|---|
| proposed | trial, conviction 50, effort S |
| refuted | **false** (the verdict survives, narrowed) |
| corrected verdict | **trial**, record half only |
| my conviction | **45%** |

The row's facts check out and its riskiest assumption is mostly supported by a log the proposer did not cite. The pre-answer half is not supported: it rests on asks whose input nobody has ever seen, and it moves no landed rows at today's volume.

## 1. Cited facts, checked against the primary source

| claim in the row | result | evidence |
|---|---|---|
| control-plane read fetches `requires_action_details_list` | TRUE today | `scripts/cloud-create-api.py:604-607` |
| `.cp` sidecar keeps only four status fields | TRUE (5 lines: `probed_at` plus `status_bucket`, `worker_status`, `status_category`, `ran`) | `cat ~/.claude/autonomy/cloud/session_01Gpfq9aE3qegTwaxLmLizL5.cp`; writer `scripts/cloud-inbox.py:198-227` |
| answer pass files a needs-human row with no `run` | TRUE | `scripts/cloud-answer.py:164-165, 185-190` |
| the create sets no permission mode | TRUE: body carries `"events": []`, no mode anywhere | `scripts/cloud-create-api.py:430`; `grep -n -i permission` over the create files returns one comment |
| repo permission rules load in one-repository cloud sessions | TRUE as documented | `doc-settings.md:752`; `doc-cloud-environments.md:272` |
| cloud approvals are "Auto, Accept edits or Plan" | TRUE | `b1-text.md:107`; `doc-web-quickstart.md:142-149` ("Cloud sessions don't offer Manual or Bypass permissions") |
| 6 "blocked on a permission grant" rows, 3 since 09-22 | TRUE (measured: grep of `~/.claude/autonomy/backlog.jsonl`, grouped by id): 09-13, 09-20, 09-21, 09-28, 09-28, 10-04 | ids `9a83be41311c cd0ba52ad33e d6416dde4c08 6869258e9036 3e340af1706b 36081c20be23` |
| the 10-04 one re-blocked for 7 h | IMPRECISE: 22 block events span 13:12:17Z to 18:53:09Z = 5 h 41 min; the row stayed open 7 h 21 min (closed 20:33:26Z) | same grep |
| pain cited at audit README:113-118 | TRUE ("65 block events in September alone, naming 8 distinct cloud sessions") | `docs/research/backlog-drain-audit-2026-09-22/README.md:113-118` |

## 2. New evidence the row did not use

### 2a. The tool name is already recorded (partial already-have)

`scripts/cloud-return-lane.sh:301-306` copies the answer pass's per-row detail, including the VM's own status text, into `~/.claude/logs/cloud-return-lane.log`, retained since 2026-09-07. Measured (grep of `PERMISSION session_` rows and their `asked (UNTRUSTED...)` line, 175 rows):

| session | date | VM's own text | ticks | pushed work? | outcome |
|---|---|---|---|---|---|
| `session_01KoH4...` | 09-13 | Approve or deny Bash | 60 | yes, commit 04:15Z before the ask | landed (`a16b9a289`) |
| `session_013Kd6...` | 09-20 | Approve or deny Bash | 18 | yes, 3 commits | land refused rc=6; item done by next session |
| `session_017f7V...` | 09-21 | Approve or deny Edit | 1 | yes, commit 04:20Z before the ask at 04:23Z | returned, goal=MET |
| `session_01AMUi...` | 09-28 | "#4, #12, #14 pushed; waiting on #9 & #13 agents" | 36 | yes, 4 commits | retired `conflict` |
| `session_01Gpfq...` | 09-28 | Approve or deny Edit | 37 | no (`.seen` sha `ba8e5c24a` is the trunk base from the boot ping) | item closed premise-retracted the same day |
| `session_01C8Gu...` | 10-04 | Approve or deny Bash | 22 | no (`.seen` sha `533c539d9` is the trunk base) | re-fired 21:01Z as `session_01Be1LHu...`, which parked the row on an operator-only step (`d7917435e`) |

So the proposer's riskiest assumption holds for 5 of 6: 3 Bash asks, 2 Edit asks, 0 connector approvals, 0 prose questions, 1 unknown (a sub-agent's ask). What is missing is the input (`raw_command`, `file_path`), not the tool name.

### 2b. `requires_action` is wider than "permission grant" (2.1.284 binary)

`strings-284.txt` shows the details builder labels `AskUserQuestion` as "Question", `ExitPlanMode` as "Plan", and `ConnectGitHub` as its own card, in the same `requires_action_details` object as Bash asks (`Vs="AskUserQuestion"`, `Gb="ExitPlanMode"`, `A4e="ConnectGitHub"`; shape `{tool_name, display_tool_name, action_description, raw_command, tool_use_id, request_id, input}`). `scripts/cloud-answer.py:164` and `scripts/cloud-inbox.py:238` label any non-empty list PERMISSION. None of the six was a question card, but the label is an assumption the record would also correct. Caveat: the VM runs Anthropic's build, so the local 2.1.284 binary is a proxy.

### 2c. What an allow rule can and cannot pre-answer (docs, fetched 2026-10-06)

Source: https://code.claude.com/docs/en/permission-modes.md

- Cloud "Accept edits corresponds to `default` mode: cloud sessions pre-approve file edits regardless of mode" (line 232). So an Edit ask in a cloud session is not an ordinary in-tree edit.
- "`permissions.allow` rules in settings files do not pre-approve protected-path writes. The safety check runs before Claude Code evaluates allow rules" (Protected paths section). Protected directories include `.claude`, `.git`, `.husky`. This repo tracks 5 files under `.claude/` (measured: `git ls-files .claude`).
- `defaultMode: "auto"` in `.claude/settings.json` "doesn't take effect"; cloud sessions ignore `dontAsk` and `bypassPermissions` from settings files (lines 568, 620).
- Ordinary Bash does not prompt in our cloud sessions: every session runs `git push -u origin HEAD` as its boot ping, and no `git push` rule exists in the 37-entry allow list (`.claude/settings.json`). The Bash asks therefore belong to an exceptional class whose content is unknown.

Inference (theoretical, not measured): the two Edit asks were protected-path or outside-working-directory writes. If protected, no allow rule reaches them. Counter-evidence against the protected-path reading: two cloud-authored commits landed edits under `.claude/rules/` with no PERMISSION row (`23974cc92`, `653afd00f`), by a route I could not determine. The paths are unknown either way.

## 3. Does it move landed rows per unit of quota?

No, at today's volume. Measured from sidecars, backlog events and `git log`:

- 4 of 6 flagged sessions had already pushed their work; their outcomes were set by the land arm (landed, goal=MET, gate refusal, conflict). `session_017f7V...` was landed 52 min after its ask with the ask still pending.
- 2 of 6 produced nothing. One served an item retracted as already complete; the other was re-fired 8 h later and ended in a park. Landed rows lost to permission asks since 09-13: 0.
- Quota lost: 2 fires of 31 since 09-22 (measured: `declared_at` count over `~/.claude/autonomy/cloud/*.decl`), about 0.29 weekly-pp (estimated: 2 x 0.143 pp per fire from C1).
- Rate: 3 of 31 fires flagged (9.7%), 2 of 31 with no output (6.5%). This would matter if volume returned.

The 22 to 37 block events per row are our own answer pass re-filing every lane tick (`scripts/cloud-answer.py:207-243`), which K06 does not change.

## 4. Why the pre-answer half does not survive as written

- The trigger "after three events add matching allow rules" needs three asks with the same command. Three Bash asks exist across 09-13 to 10-04 with unknown and probably different commands; at 1.9 fires/day and 0 dispatchable cloud rows today, the trigger is weeks or months away.
- Turning VM-authored `input` into allow rules is the remote composing its own authorization. `scripts/cloud-answer.py:28-49, 61-63` forbids it ("NEVER script your own authorization"; no remote-composed byte reaches a command), and the brief rail says never edit `settings.json` in place (`bin/cc-dispatch:3084`). A rule would have to be written by the operator after reading the record.
- The 10-04 ask may have been a prompt doing its job: that row's only open step was operator-only (migration 0053, `docs/plans/INSTRUCTION_BUDGET.md:175`), and the second session finished the same task without any prompt.

## 5. Corrections to the row

1. Write the record to the lane log, not the `.cp` sidecar. `cc-cloud classify()` reads `.cp` on every board render, and `scripts/cloud-return-lane.sh:301-303` already names the lane log as the only place remote-authored text goes. The data is already in the pipeline (`scripts/cloud-inbox.py:194`); `scripts/cloud-answer.py:346` drops it. Estimated size: under 10 lines plus one bats case.
2. Record `tool_name`, `raw_command` and `input.file_path`; the tool name alone is already logged.
3. "7 h" is the row's open time; block events span 5 h 41 min.
4. Drop "after three events add allow rules". Replace with: after the first recorded Bash and Edit input, the operator decides whether any rule can match.

## 6. Alternatives considered

| alternative | why not chosen here |
|---|---|
| Skip outright | Defensible on value (0 landed rows lost). Rejected because the record is nearly free and is the precondition for every other cure of F49. |
| Set the mode at create | The CLI builds an initial `set_permission_mode` control-request event for session creates (`strings-284.txt`, function `V2n`), and our body sends `"events": []`. Auto mode would send asks to a classifier instead of a human. Unverified: whether the private `/v1/sessions` create accepts it, and whether Max accounts get Auto in cloud. Testing needs a live create, which is out of scope. |
| Brief rail "never ask" | A worker cannot know in advance which call will prompt; none of the six was a question card. |
| Park-on-prompt | The prompt blocks the turn, so the worker cannot act on it. |

## 7. Uncertainties

- The input of all six asks is unknown; nothing local holds it.
- Whether repo allow rules load on API-created sessions is unverified (same open fact as K03).
- Who or what cleared the one-tick Edit ask on 09-21 is unknown.
