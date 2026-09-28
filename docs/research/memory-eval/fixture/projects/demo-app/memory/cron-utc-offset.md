---
name: cron-utc-offset
description: the nightly cron runs an hour late after daylight saving because it is scheduled in local time
metadata:
  type: project
---

The nightly report job ran one hour late after the clocks changed. Schedule it in UTC, not local time.
