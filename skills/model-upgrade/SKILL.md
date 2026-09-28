---
name: model-upgrade
description: "Renamed: now /cc-upgrade (model lane). Stub kept one upgrade cycle for typed habit."
disable-model-invocation: true
allowed-tools: Skill
---

# model-upgrade → cc-upgrade

Renamed. Invoke the Skill tool with `cc-upgrade` and arguments `model $ARGUMENTS`; lane hint: model lane (model.md).

This alias exists for one upgrade cycle so a typed `/model-upgrade` keeps working. It is not in the
model's skill listing (`disable-model-invocation`), so it costs no context.
