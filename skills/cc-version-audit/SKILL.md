---
name: cc-version-audit
description: "Renamed: now /cc-upgrade (harness lane, audit phase). Stub kept one upgrade cycle for typed habit."
disable-model-invocation: true
allowed-tools: Skill
---

# cc-version-audit → cc-upgrade

Renamed. Invoke the Skill tool with `cc-upgrade` and arguments `harness $ARGUMENTS`; lane hint: harness lane, audit phase (audit.md).

This alias exists for one upgrade cycle so a typed `/cc-version-audit` keeps working. It is not in the
model's skill listing (`disable-model-invocation`), so it costs no context.
