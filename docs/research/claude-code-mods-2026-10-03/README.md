# Claude Code mods and the 2.1.285–2.1.289 delta (2026-10-03)

Two multi-agent investigations, run from the 2.1.284 pin, into whether the fleet should build or
adopt a mod (the in-process TypeScript plugin API, CC ≥ 2.1.287) and what the 2.1.285–2.1.289
changelog means for the fleet.

| File | What it holds |
|---|---|
| `REPORT.md` | Mods verdict: build nothing now (85%). Seven candidates, each prototyped and attacked by a skeptic; all refuted. The one to revisit after a 2.1.289+ move is a prompt-delivery actuator (45%). |
| `REPORT-289.md` | 2.1.285–2.1.289 triage: upgrade to 2.1.289 through the gate, never to 2.1.285–2.1.287; "shared agents" is a misreading of a mods-API line; upgrade-gate additions. |
| `U-api.md` | The mods API as shipped, read from the 2.1.289 types and a scratch `plugin validate` / `plugin test` run. |
| `U-hooks.md` · `U-pain.md` · `U-eco.md` · `U-adopt.md` | Hook inventory, evidenced fleet pain, ecosystem two days after launch, adoption cost. |
| `proto/C1`–`proto/C7` | Prototype sources only (no generated types, debug logs or scratch config). |

Paths in the reports that start with `/tmp/mods-research/` were scratch and are gone; the reports,
the `U-*.md` files and the prototype sources were copied here, everything else was not kept.

Driven from this research: `008330afe` (the permission beacon no longer lets a failing sibling
tool clear a still-pending prompt). Version cautions for the next upgrade audit are indexed in
`skills/cc-upgrade/holds.md`.
