---
name: cc-upgrade-gate
description: "Renamed: now /cc-upgrade (gate phase). Stub kept one upgrade cycle for typed habit."
disable-model-invocation: true
allowed-tools: Skill
---

# cc-upgrade-gate → cc-upgrade

Renamed. Invoke the Skill tool with `cc-upgrade` and arguments `$ARGUMENTS`; lane hint: gate phase (gate.md).

This alias exists for one upgrade cycle so a typed `/cc-upgrade-gate` keeps working. It is not in the
model's skill listing (`disable-model-invocation`), so it costs no context.
