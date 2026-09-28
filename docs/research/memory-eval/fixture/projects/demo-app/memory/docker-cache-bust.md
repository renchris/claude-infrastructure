---
name: docker-cache-bust
description: docker build reused a stale cached layer because COPY came before the dependency install
metadata:
  type: reference
---

Order the Dockerfile so dependency install precedes COPY of the source tree; otherwise a source change reuses a stale cached layer.
