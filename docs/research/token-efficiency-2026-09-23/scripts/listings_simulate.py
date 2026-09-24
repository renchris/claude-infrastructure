#!/usr/bin/env python3
"""Re-implementation of Claude Code 2.1.280's skill-listing budget (fn JBt) + the proposed
descriptions, and a before/after simulation.

Binary facts (claude.exe 2.1.280, byte-searched; see measure/listings.md §1):
  budget  = SLASH_COMMAND_TOOL_CHAR_BUDGET or floor(contextWindow * bytesPerToken * fraction)
            fraction = settings.skillListingBudgetFraction ?? 0.01; bytesPerToken = 3 for
            Opus 5.x / Fable (4 for the listed pre-5 models); window 1M -> 30,000 chars; 200k -> 6,000.
  entry   = "- <name>: <desc>" (desc = description [+ " - " + when_to_use], cut to
            skillListingMaxDescChars ?? 1536 with an ellipsis) or "- <name>" when name-only.
  if sum(entries)+newlines > budget: bundled prompt skills + name-only keep their entry; all others
  start as "- <name>", then, sorted by usage score desc (usageCount * max(0.5**(days/7), 0.1) from
  <configdir>/.claude.json skillUsage; stable), each gets its full text iff the increment still fits.

Inputs: measure/listings_raw/latest_listing_entries.json (per-entry rendered lengths of the most
recent real claude-infrastructure main listing), frontmatter.json, a .claude.json for the scores.
Outputs JSON with: validation (simulated vs actual described set), and after-proposal state.
Usage: python3 listings_simulate.py <raw_dir> <claude.json> <out.json>
"""

import json, sys, time, os

RAW, CJ, OUT = sys.argv[1:4]
BUDGET = 30000
MAXD = 1536

# ---- proposed descriptions (<= 250 chars each): behaviour + the trigger actually used (the name)
PROPOSED = {
    "cafe-wifi-optimization": "Client-side ladder for slow GUEST Wi-Fi you cannot administer (cafe, hotel, airport): route, SNR, capacity, bufferbloat direction, and the Wi-Fi vs iPhone-tether call. Not for any network whose router you can log into.",
    "limit-recover": "Recover delegated work after any interruption (usage or weekly limit, login cliff, network drop, stalled agent or workflow, crash or resume): audit every slot, subagent and teammate from disk, re-run what is incomplete, or move to another account.",
    "frontier-routing": "Policy for when to use the frontier model (Fable) instead of the default tier: only for unknown-unknowns after research stalls, inside the hook-enforced spawn cap. Points to /frontier-hole, /frontier-run and /frontier-campaign.",
    "permission-harvest": "Weekly review of manual permission prompts: runs cc-permission-harvest read-only, buckets the prompts, proposes composable prefix allow rules and hands the operator one cc-do apply step. Never writes settings files.",
    "dia-agent": "Drive the operator's real logged-in Dia browser without consent prompts: AppleScript for tabs, windows and JS; CDP via dia://inspect for trusted input, screenshots, network and cookies; a clean-profile launcher as fallback.",
    "manual-command-delivery": "Load before asking the user to do anything (login, sudo, a blocked or destructive step): write one re-runnable /tmp script that drives every drivable step, gates irreversible ones behind a typed yes, and hand over one command.",
    "plan-conventions": "Rules for writing and updating plan or design docs: integrate, never overwrite; compact completed sections; expand upcoming ones with file:line detail; mandatory Phase 0 with a per-wave execution locus. Load when editing a *plan*.md.",
    "demo-recording": "Record a live screen, terminal or agent demo and embed it in a README as animated WebP (GitHub strips <video>): capture, iTerm2 sizing, near-lossless encode recipe, contact-sheet review. Not for understanding an existing video.",
    "research-subagents": "Discipline for read-only research fan-out: decomposition artifact, default N=10, a 7-field brief with a file delivery path, adversarial sampling, stop and synthesis rules. Load before spawning research subagents; not for code-writing teammates.",
    "browsermcp": 'History of the retired BrowserMCP server plus the browser-automation decision tree; the agent-browser CLI is the live path. Load when browser tools report "No such tool available".',
    "agent-teams": "Orchestrating code-writing teammates (Agent with name:): runtime detection, 150-line brief rules, pre-spawn checklist, model and effort pinning, lifecycle, shutdown and crash recovery. Load before spawning teammates or planning 2+ code tasks.",
    "recover": "Front door for recovering delegated work after any interruption (network drop, stalled agent, killed task, crash or resume, quota, login cliff), or for moving a healthy session to another account. Modes: limit, resume-in-place, stall, switch.",
    "codex-security": "Run OpenAI's Codex Security methodology natively (vendored plugin; no Codex or OpenAI account): repo and diff security scans, threat models, finding validation and triage, fixes, write-ups and SARIF output.",
    "coding-standards": "House style for TypeScript, React/Next.js and Python (FastAPI, Pydantic v2, mypy strict, ruff): strictness, exports, Server Components, naming. Load when writing a new component, module or endpoint, or for a style review.",
    "self-explaining-artifact": "Build a self-contained animated HTML explainer of an article, dataset or mechanism, and verify it with measured gates (word count, AA contrast, frame budget). Use when an explainer was rejected as walls of text or hard to follow.",
    "repo-wiki": "Generate a source-grounded README or multi-page wiki for a repository in two passes (a structure plan, then pages), with citation and diagram rules and 15 named styles. Use to write a README or document a codebase.",
    "autonomous-authenticated-web-access": "Choose and run read-only access to a logged-in web app: API token, then clean-profile CDP, then warm Dia CDP; plus trusted-input, shadow-DOM and consent-modal techniques for hardened SPAs. Pairs with dia-agent and agent-browser.",
    "resume-sessions": "Resume every Claude Code session across the 4 accounts after a crash or reboot: find open sessions, recreate worktrees, take the full session rather than the summary, clear terminal gibberish, re-engage them and keep them alive.",
    "grok-wiki-audit": "Our recipe for a multi-shard defect sweep of a repo with grok-wiki ask: preflight checks (a broken claude stub, the codex config override), shard design, and verifying each finding against the pre-fix artifact before fixing it.",
    "model-upgrade": "Runbook for moving to a new Claude model or off one: the binary gate first (does the pinned Claude Code register the id?), the model-id census, config and doc sweeps, the model ladder. Use when a model ships or frontier access changes.",
}
PROPOSED_AGENTS = {
    "deep-research": 'Deep research subagent (Opus tier; the lead may pass model "fable" per model-config.yaml). Default for research fan-out slots and for adversarial or multi-hop briefs. Returns signal-dense findings.',
    "deep-research-sonnet": "Sonnet-tier research worker, benched: use only in a probe-certified low- or medium-effort Workflow (~/.claude/model-routing-freewin-probe.md). Otherwise use deep-research.",
    "frontier-derivation": 'Read-only, baseline-blind panelist for /frontier-run: derives failure modes from the system model first, then reads code to confirm or refute them. One per hole; the lead passes model "fable".',
}


def score_map(path):
    su = json.load(open(path)).get("skillUsage") or {}
    now = time.time() * 1000
    return {
        k: v["usageCount"] * max(0.5 ** (((now - v["lastUsedAt"]) / 86400000) / 7), 0.1)
        for k, v in su.items()
    }


def simulate(entries, full_len, bundled, fixed_nameonly, score):
    """entries: ordered names; full_len[name]: full entry length; returns (described set, total)."""
    n = len(entries)
    nameonly_len = {e: len(e) + 2 for e in entries}
    total_full = sum(full_len[e] for e in entries) + n - 1
    if total_full <= BUDGET:
        return set(e for e in entries if e not in fixed_nameonly), total_full, "fits"
    keep = [e for e in entries if e in bundled or e in fixed_nameonly]
    rest = [e for e in entries if e not in keep]
    fixed = (
        sum(full_len[e] if e in bundled else nameonly_len[e] for e in entries) + n - 1
    )
    room = BUDGET - fixed
    got = set(e for e in entries if e in bundled)
    for e in sorted(
        rest, key=lambda x: -score.get(x, 0)
    ):  # Python sort is stable, like JS
        inc = full_len[e] - nameonly_len[e]
        if inc <= room:
            got.add(e)
            room -= inc
    total = sum(full_len[e] if e in got else nameonly_len[e] for e in entries) + n - 1
    return got, total, "priority"


def main():
    lat = json.load(open(os.path.join(RAW, "latest_listing_entries.json")))
    fm = {
        x["name"]: x
        for x in sorted(json.load(open(os.path.join(RAW, "frontmatter.json"))), key=lambda x: x["kind"] == "skill")  # skill beats same-named command
        if x["kind"] != "agent"
    }
    score = score_map(CJ)
    ents = [e["name"] for e in lat["entries"]]
    actual = {e["name"] for e in lat["entries"] if e["described"]}
    BUILTIN_ALWAYS = {
        "dataviz",
        "update-config",
        "keybindings-help",
        "code-review",
        "simplify",
        "fewer-permission-prompts",
        "loop",
        "schedule",
        "claude-api",
        "workflow-authoring",
        "claude-in-chrome",
        "run",
    }
    fixed_nameonly = {
        e
        for e in ents
        if e.startswith("anthropic-skills:") or e in ("init", "security-review")
    }

    def full_of(name, desc_override=None):
        if name in fm:
            x = fm[name]
            d = (
                desc_override
                if desc_override is not None
                else (
                    x["description"]
                    + (" - " + x["when_to_use"] if x["when_to_use"] else "")
                )
            )
            if (
                not d
            ):  # no frontmatter description: Claude Code derives one from the body
                d = x["first_heading"][:100]
            return len(name) + 4 + min(len(d), MAXD)
        return next(e["chars"] for e in lat["entries"] if e["name"] == name)

    cur = {e: full_of(e) for e in ents}
    for e in BUILTIN_ALWAYS:
        cur[e] = next(x["chars"] for x in lat["entries"] if x["name"] == e)
    got, total, mode = simulate(ents, cur, BUILTIN_ALWAYS, fixed_nameonly, score)
    val = dict(
        mode=mode,
        simulated_total=total,
        actual_total_with_header=lat["total_chars"],
        described_actual=len(actual),
        described_sim=len(got),
        agree=len(actual & got),
        only_actual=sorted(actual - got),
        only_sim=sorted(got - actual),
        full_total_if_all_described=sum(cur.values()) + len(ents) - 1,
    )
    new = dict(cur)
    for k, v in PROPOSED.items():
        if k in new:
            new[k] = full_of(k, v)
    got2, total2, mode2 = simulate(ents, new, BUILTIN_ALWAYS, fixed_nameonly, score)
    after = dict(
        mode=mode2,
        total=total2,
        described=len(got2),
        newly_described=sorted(got2 - got),
        lost_description=sorted(got - got2),
        full_total_if_all_described=sum(new.values()) + len(ents) - 1,
        still_nameonly=sorted(
            e for e in ents if e not in got2 and e not in fixed_nameonly
        ),
    )
    per = []
    for k, v in PROPOSED.items():
        x = fm.get(k)
        old = x["description"] + (" - " + x["when_to_use"] if x["when_to_use"] else "")
        per.append(
            dict(
                name=k,
                kind=x["kind"],
                old_chars=len(old),
                old_listed_chars=min(len(old), MAXD),
                new_chars=len(v),
                saved_chars=min(len(old), MAXD) - len(v),
                proposed=v,
            )
        )
    agents = []
    fma = {
        x["name"]: x
        for x in json.load(open(os.path.join(RAW, "frontmatter.json")))
        if x["kind"] == "agent"
    }
    for k, v in PROPOSED_AGENTS.items():
        agents.append(
            dict(
                name=k,
                old_chars=fma[k]["desc_chars"],
                new_chars=len(v),
                saved_chars=fma[k]["desc_chars"] - len(v),
                proposed=v,
            )
        )
    assert all(
        len(v) <= 250 for v in list(PROPOSED.values()) + list(PROPOSED_AGENTS.values())
    ), "over 250"
    out = dict(
        budget=BUDGET,
        score_source=CJ,
        validation=val,
        after=after,
        proposals=per,
        agent_proposals=agents,
    )
    json.dump(out, open(OUT, "w"), indent=1)
    print(
        json.dumps(
            dict(validation=val, after={k: v for k, v in after.items()}), indent=1
        )
    )
    print(
        "skill chars saved",
        sum(p["saved_chars"] for p in per),
        "agent chars saved",
        sum(a["saved_chars"] for a in agents),
    )


if __name__ == "__main__":
    main()
