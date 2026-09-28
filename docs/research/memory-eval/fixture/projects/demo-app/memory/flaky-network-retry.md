---
name: flaky-network-retry
description: the upload client must retry transient HTTP failures with exponential backoff
metadata:
  type: feedback
---

The upload client gave up after a single 503. Retry transient failures up to five times with exponential backoff before surfacing an error.
