# A top-level `effortLevel` does not reach a newly released model — pin it per model, or pass `--effort`

**2026-09-28** (Sonnet 5.5 adoption; evidence `docs/research/sonnet55-utilization-2026-09-28/notes/probe-effort-binding.md`).

Every account's `settings.json` carried `"effortLevel": "high"`, and the fleet believed that made "high" the
default everywhere. It did not. Read straight from API request bodies through a logging reverse proxy on
`ANTHROPIC_BASE_URL` (positive control: `--effort low` sent low, `--effort xhigh` sent xhigh), a launch of
`claude-opus-5-5` or `claude-sonnet-5-5` with **no `--effort`** sent `output_config.effort: "medium"` on both
2.1.280 and 2.1.284, with the setting present and with user settings dropped alike. `claude-opus-5` in the same
runs sent `high`.

The mechanism, from the binary: a top-level user `effortLevel` is stored as a LEGACY value and applied only to a
hard-coded list of older model ids. A model released after that list was written falls through to its catalog
`default_effort` (medium for both 5.5 models). What does bind per model is `modelSettings.<model>.effortLevel` —
the shape an interactive `/effort` writes — and, above everything, an explicit `--effort` flag,
`CLAUDE_CODE_EFFORT_LEVEL`, an agent definition's `effort:` (via `subagent_type`, NOT via `--agent`), or a Workflow
`agent({effort})`.

Why it stayed invisible: the interactive launcher always passes `--effort high`, so every lead looked right. Only
headless paths that called the binary without the flag (scorers, recoveries, probes) ran a rung low, and nothing
surfaces the effort a request carried — `/tasks` stopped showing it in 2.1.283.

**Rule.** A settings-level effort default is a claim about the models that existed when the setting was written.
On every model release, (1) pass `--effort` explicitly on every launch path that matters, (2) pin the new id
under `modelSettings` (migration `0044-effort-modelsettings-55.sh` is the pattern), and (3) verify from the
request body, never from the setting or from what the TUI shows.
