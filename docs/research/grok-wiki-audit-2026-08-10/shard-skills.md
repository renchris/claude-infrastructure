========== ANSWER ==========

I’ll map the three target directories first, then trace tests and supporting scripts around the risky paths so coverage claims are grounded rather than inferred.The target surface is mostly Markdown command/skill specs plus several shell activation scripts and one Python asset package under `skills/kpmg-deck`. I’m shifting from inventory to guard/gate/error-handler patterns, then I’ll verify any test-gap claims against the whole test tree.The broad search was too noisy, but it exposed useful context: deployment parity and activation-watch tests do cover parts of `commands/`, `skills/`, and `docs/activation`. I’m narrowing to executable/code-bearing files inside the audited directories and then checking those exact subjects against tests.There are two different kinds of risk here: runnable activation/skill code, and command Markdown that acts as operational code for agents. I’m treating command instructions as in-scope only where a specific line can drive a repeatable wrong action, and I’m checking whether a real script already supersedes or tests that path.One concrete pattern is emerging: several activation scripts validate a JSON transform but only print “FAILED” for a config dir and still finish with success. I’m checking whether tests already pin that partial-failure behavior before deciding how to classify it.The first coverage search hit a shell glob issue because this checkout has no `tests/*.test.sh` files matching zsh expansion. I’m rerunning with `rg` globs so the search itself is valid and citable.Another candidate is the consolidated activation bundle: it links many live commands but effect-checks only a small subset. I’m reading the existing wiring tests before treating that as a real gap.I’m now auditing the Python skill package, especially validators and error handlers. The goal is to avoid reporting a speculative presentation-quality issue unless the code path is plainly wrong under a specific deck/input state.The deck verifier has many intentional warning-only checks, so I’m separating design judgments from latent verifier bugs. I’m focusing on cases where an advertised “ERROR” check cannot run or can be bypassed by ordinary inputs.The command docs contain executable advice that can mutate git state. I’m reading the high-risk commit/ship/wrap surfaces and checking whole-repo tests for any suites that pin those instructions, not just the underlying scripts.I have enough candidates now. I’m doing one last pass for the exact “no covering test” searches I’ll cite, so the final answer doesn’t overstate coverage gaps.**(1) DESIGN FLAWS**

**Rank 2 — Recurrence: global scratch-patch isolation in command prose.**  
`/commit` and `/ship` both tell agents to protect unrelated work with `git diff > /tmp/stash.patch`, destructive checkout, then `git apply /tmp/stash.patch`. Sources: [commands/commit.md:17-20](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/commands/commit.md:17), [commands/commit.md:34-35](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/commands/commit.md:34), [commands/ship.md:19-20](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/commands/ship.md:19).

Concrete failure scenario: two local agents run `/commit` or `/ship` concurrently; agent A saves unrelated diffs to `/tmp/stash.patch`, agent B overwrites the same path, agent A checks out unrelated files and later applies B’s patch or fails to restore its own. Binary/untracked unrelated changes are also outside plain `git diff`.

Blast radius: user work loss or cross-session patch injection during the core commit/land path. Likelihood: medium-high in this repo because the workflow is explicitly multi-session/concurrent.

Coverage search that found no covering test:  
`rg -n --glob '*.bats' --glob '*.test.sh' "commands/commit\.md|git diff > /tmp/stash\.patch|/tmp/stash\.patch|git apply /tmp/stash\.patch" tests`  
No output.

**(2) LATENT BUGS**

**Rank 1 — C10 hook activators can report success after failing to wire a config.**  
The three activation scripts all print “FAILED (left intact)” when a `settings.json` transform fails, but they do not set a failure flag or exit non-zero; the script later prints `DONE`. Sources: [docs/activation/rm-safe-activate.sh:75-102](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/docs/activation/rm-safe-activate.sh:75), [docs/activation/ship-rail-push-activate.sh:77-104](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/docs/activation/ship-rail-push-activate.sh:77), [docs/activation/reset-hard-activate.sh:86-116](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/docs/activation/reset-hard-activate.sh:86).

Concrete failure scenario: one config dir has malformed `settings.json`, a bad temp path, or an unexpected shape that makes `jq` fail. The target hook is not registered there, but the operator sees `DONE` and may believe `rm` allowlisting, ship-rail push allow, or reset-hard shadow logging is active across all configs.

Blast radius: permission gates silently absent in one or more Claude config dirs. Likelihood: medium; config drift is common enough that this repo has settings-drift tooling.

Coverage search that found no covering test:  
`rg -n --glob '*.bats' --glob '*.test.sh' "reset-hard-activate|rm-safe-activate|ship-rail-push-activate|transform did not validate|FAILED \(left intact\)|docs/activation/(reset-hard|rm-safe|ship-rail-push)-activate" tests`  
No output.

**Rank 3 — KPMG deck render-dependent gates fail open from the common/advertised path.**  
The skill advertises mechanical verification, then says passing a render directory runs the density gate; `verify()` only runs rhythm/monotony when `render_dir` is truthy, and the CLI exits `0` if there are no structural errors even when no render directory exists. The course example verifies first, then renders, but does not re-run verification with the render. Sources: [skills/kpmg-deck/SKILL.md:276-292](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/skills/kpmg-deck/SKILL.md:276), [skills/kpmg-deck/assets/kpmg_deck/verify.py:1519-1548](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/skills/kpmg-deck/assets/kpmg_deck/verify.py:1519), [skills/kpmg-deck/assets/kpmg_deck/verify.py:1572-1581](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/skills/kpmg-deck/assets/kpmg_deck/verify.py:1572), [skills/kpmg-deck/examples/course.py:29-31](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/skills/kpmg-deck/examples/course.py:29).

Concrete failure scenario: `deck.pptx` has many near-empty or duplicate rendered slides, but no `render/` dir exists, or the user follows the course example. `python -m kpmg_deck.verify deck.pptx kpmg` exits `0`; the density and monotony gates never fire.

Blast radius: broken client decks can pass the “mechanical” gate. Likelihood: high for first-run decks because render output is optional by CLI state and absent until produced.

Coverage search that found no covering test:  
`rg -n --glob '*.bats' --glob '*.test.sh' "kpmg_deck\.verify|skills/kpmg-deck|kpmg-deck|render\.sh|examples/(proof|course|showcase)\.py|kpmg_deck" tests`  
No output.

**(3) VERIFICATION GAPS**

**Rank 4 — `wiring-all.sh` install coverage is token-presence, not effect coverage.**  
`wiring-all.sh` links many commands, but only effect-checks five of them; failures for entries like `desk-assert`, `cc-wave-plan`, `cc-dispatch`, and `cc-discover` can be missed. Sources: [docs/activation/wiring-all.sh:79-84](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/docs/activation/wiring-all.sh:79), [docs/activation/wiring-all.sh:109-134](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/docs/activation/wiring-all.sh:109), [docs/activation/wiring-all.sh:263-264](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/docs/activation/wiring-all.sh:263).

The covering test for `desk-assert` claims “resolves on PATH in prod” but only greps that the token appears in the install loop. It would still pass if `ln -sf` failed at runtime, if `$BIN` were unwritable, or if the effect-check omitted `desk-assert`. Source: [tests/desk-assert-wiring.bats:30-32](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/tests/desk-assert-wiring.bats:30).

Concrete failure scenario: fresh machine or partial install where `~/.claude/bin` is unwritable, or a listed binary is missing/dangling. `wiring-all.sh` can still reach the final “done” line; the test remains green because it never runs the script in a temp HOME and asserts the symlink target/executability for every listed tool.

Blast radius: live activation can be partially inert while tests assert wiring exists. Likelihood: medium; activation scripts are explicitly run on machines/config dirs with drift.

Coverage search:  
`rg -n --glob '*.bats' --glob '*.test.sh' "wiring-all\.sh|docs/activation/wiring-all\.sh|linked cc-dispatch|linked cc-discover|linked desk-assert|effect-check|symlink broken/foreign|cc-wave-plan cc-dispatch cc-discover" tests`  
It found only the `desk-assert` membership grep and comments, not an execution/effect test.

========== SOURCES ==========
  - commands/commit.md:17-20
  - commands/commit.md:34-35
  - commands/ship.md:19-20
  - docs/activation/reset-hard-activate.sh:86-116
  - docs/activation/rm-safe-activate.sh:75-102
  - docs/activation/ship-rail-push-activate.sh:77-104
  - docs/activation/wiring-all.sh:109-134
  - docs/activation/wiring-all.sh:263-264
  - docs/activation/wiring-all.sh:79-84
  - private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/commands/commit.md:17
  - private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/commands/commit.md:34
  - private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/commands/ship.md:19
  - private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/docs/activation/reset-hard-activate.sh:86
  - private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/docs/activation/rm-safe-activate.sh:75
  - private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/docs/activation/ship-rail-push-activate.sh:77
  - private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/docs/activation/wiring-all.sh:109
  - private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/docs/activation/wiring-all.sh:263
  - private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/docs/activation/wiring-all.sh:79
  - private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/skills/kpmg-deck/SKILL.md:276
  - private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/skills/kpmg-deck/assets/kpmg_deck/verify.py:1519
  - private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/skills/kpmg-deck/assets/kpmg_deck/verify.py:1572
  - private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-AC8eIW/repo/skills/kpmg-deck/examples/course.py:29
  - skills/kpmg-deck/SKILL.md:276-292
  - skills/kpmg-deck/assets/kpmg_deck/verify.py:1519-1548
  - skills/kpmg-deck/assets/kpmg_deck/verify.py:1572-1581
  - skills/kpmg-deck/examples/course.py:29-31
