# Cloud post evaluation — 2026-10-06

Question: does "Claude Code in the Cloud: A Field Guide to Cloud Sessions"
(https://claude.dev/blog/claude-code-in-the-cloud/, 2026-10-06), plus Claude Code releases up to and
past 2.1.284, improve the cc-backlog cloud lane?

**Answer: mostly no.** Nothing in the post or in 2.1.285–2.1.292 moves the lane's three limits:
supply (1 open row of 4,241; all 10 cloud-eligible rows blocked), the shared Max quota pool, and the
desk-side land gate. The lane already uses the one verb that applies (`-p … --cloud <id>`); its
create path is a private API the post does not replace.

Method: 8 parallel readers (`a1`–`a4` on our pipeline, `b1`–`b3` on the post, docs and changelog,
`c1` hostile review), one proposer (`candidates.md`, 29 rows), one refuter for each of the 8
strongest rows (`refute-K01`–`K08`). The other 21 rows were all skip or already-have and were not
independently checked. Paths of the form `/tmp/cloud-blog-eval/…` inside these files are the
readers' scratch copies of vendor docs and were not kept.

| Row | After refutation | Disposition |
|---|---|---|
| K01 guard so a VM cannot `/ship` | adopt, 62% | decision `fc5d34097c6e`, open |
| K02 ruleset on `main` with a deploy-key bypass | trial, 45% | same decision |
| K03 cloud-only SessionStart provisioner | refuted, skip 70% | dropped |
| K04 send a conflicted branch back to its VM | refuted, skip 65% | dropped |
| K05 cloud-only Stop hook gate | refuted, skip 72% | dropped |
| K06 record what a blocked session asked for | trial, 45%, record half only | dropped |
| K07 cc-upgrade target and cloud coverage | adopt narrowed, 65% | holds note corrected, `8e2c8d61a` |
| K08 version glob in `cc-offload setup` | adopt, 85% | fixed, `cecc3f6b8` |

## Decision research (same day, second pass)

Three researchers per decision, one adversarial, then a judge (`d1-*`, `d2-*`, `judge-d1.md`,
`judge-d2.md`).

- **Block cloud VMs from pushing to `main`?** (decision `fc5d34097c6e`) Recommend the guard alone,
  tightened: `scripts/ship-land.sh` refuses a real land when `CLAUDE_CODE_REMOTE` is true, local-folder
  remotes exempt, no committer-email test (it misses 48 of 341 cloud branches), and the tracked
  instructions say a cloud session never lands. 70%. The ruleset on `main` fell to 25%: the VM
  holds the operator's admin token and can edit a ruleset.
- **Claim the cloud credit?** Recommend claiming on one account first, then the rest if its
  usage-credits toggle still reads off. 68%.

**CORRECTED (2026-10-06):** the line below says claiming enables Usage Credit. The offer's own help
page (support.claude.com article 17152539) says the credit is claimed and used with usage credits
off and is drawn before plan quota; the legal terms only permit Anthropic to enable it. Deadline is
Oct 7 11:59 PM Pacific.

Side finding with a date: the post's cloud credit must be claimed by 2026-10-07 and its terms
enable Usage Credit, which `accounts.json` forbids (`a4-economics-and-live-state.md`).
