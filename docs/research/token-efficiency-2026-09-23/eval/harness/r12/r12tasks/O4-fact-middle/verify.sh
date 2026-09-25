#!/bin/bash
# verify.sh <answer-file> — PASS when the answer carries 42 (on-hand of SKU-7731).
grep -qw 42 "$1" && echo PASS || echo FAIL
