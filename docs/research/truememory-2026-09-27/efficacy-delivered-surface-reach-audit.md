# Efficacy lens: delivered-surface-reach-audit

Question: does TrueMemory have a mechanism that works for "what the model can actually reach"?

## MEASURED (read or ran)
- MCP instructions string: mcp_server.py:329-388. Measured length 4,865 chars (python slice between the triple quotes). Nothing in TM source measures or warns about host truncation. The 2,048-char delivered figure is a Claude Code host behaviour and is CLAIMED, not in TM code.
- Hook output shape: session_start.py:752 `output = {"additionalContext": context}` and user_prompt_submit.py:831 `print(json.dumps({"additionalContext": ...}))` emit a top-level key, not `hookSpecificOutput.additionalContext`. grep for hookSpecificOutput in truememory/ finds 0 hits. The shape is still wrong at HEAD.
- The test asserts the wrong shape: tests/ingest/test_onboarding.py:61 `assert "additionalContext" in data`. It checks the emitted string, not what the host delivers, so it passes on a payload the host drops.
- Degradation reporting: _build_health_payload at mcp_server.py:920-970 reports model_server, reranker, hyde_llm, vectors and encoding_gate. All of these are in-process subsystems. Nothing covers whether a hook fired, whether context was delivered, or how much instruction text survived.
- Issue #592 "surface silent degradation in truememory_status" is CLOSED (2026-06-10) and covers only those subsystems.
- Issue #722 is OPEN. Its SessionEnd hook never fired in Claude Desktop on Windows, so auto-extraction did nothing for 6+ days. The user found this through empty log directories, not through the health payload. So TM's degradation reporting failed on exactly the delivery-class failure this candidate targets.
- Issue #696 is CLOSED: clustering was silently dead because an hdbscan dependency was not declared. It was found by a human, not by a mechanism.
- Issue #578 capped the session-start payload with a budget. That shapes what TM sends; it does not verify what arrives.
- Benchmarks: benchmarks/{beam,locomo,longmemeval} contain no reference to mcp_server, session_start, additionalContext or _build_health (grep, 0 files). The mechanism does not bear on the benchmark numbers.
- History: shallow clone of 50 commits, boundary 1548ace, HEAD dated 2026-08-29. `git log -S _build_health_payload` finds 9f1b3fe (#676). The additionalContext line's origin is cut off by the shallow boundary. Nothing was reverted within the window.

## Our side (MEASURED)
- scripts/memory-fleet-sweep.sh:21-24,97 counts DARK tail-dropped entries only. It has no reach, orphan or closure metrics.
- bin/cc-memory-rotate:426,700,755 already counts dangling index lines (verdict tokens `dangling=`). That covers index-line to file only, not wikilinks between topics.
- hooks/lib/memory-index-measure.sh:142 has mim_effective_file.
- hooks/lib/rules-loaded.sh does NOT exist, so the candidate's target file is wrong. claudeMdExcludes awareness currently lives in comments or logic in hooks/memory-nudge.sh:535, bin/cc-memory-rotate:612 and scripts/rules-hook-budget-lint.sh:43.
- docs/plans/MEMORY_KNOWLEDGE_V2.md:249-252 (R5) says the alarm row belongs to row 10, which matches the candidate.
- I did not re-measure the study's figures (189 demoted hooks, 150/496 one hop, 192 unreachable, 11 orphans, 46 dangling wikilinks). They are carried over as the prior study's numbers.

## Verdict reasoning
TM has no effective version of this mechanism. The evidence is negative: TM shipped a wrong-shape payload, a test that asserts the source string, and a health payload blind to delivery, which let #722 go silent for days. That makes a strong case for the gap and no case for copying TM's approach. Copying #592-style subsystem health would not have caught any of the cited failures. Adapt: build it as our own delivered-side measurement, framed as a counter-example to TM rather than a port, with the target files corrected.
