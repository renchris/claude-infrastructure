---
name: csv-quote-escaping
description: CSV export breaks when a field contains a double quote
metadata:
  type: reference
---

A field containing a double quote must be escaped by doubling it; the exporter now uses the csv module instead of string joins.
