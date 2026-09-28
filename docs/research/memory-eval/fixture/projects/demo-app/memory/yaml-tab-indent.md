---
name: yaml-tab-indent
description: a YAML config with tab indentation fails to parse
metadata:
  type: project
---

The settings loader rejects a YAML file indented with tab characters. Indent with spaces; the editor config now enforces it.
