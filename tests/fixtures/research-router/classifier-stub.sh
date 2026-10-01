#!/bin/bash
# A stand-in for the haiku classifier (router.py CC_RESEARCH_CLASSIFIER): reads the classifier input
# on stdin, takes the text after the PROMPT: line, and answers by keyword. Planted failure modes:
# STUB-SLEEP (outlives the timeout), STUB-ERROR (exit 3), STUB-MIXED (two labels), STUB-JUNK.
# Every call is appended to $STUB_LOG when set, so a test can prove the classifier was NOT called.
input="$(cat)"
p="${input#*PROMPT:}"
p="${p%LABEL:*}"
[ -n "${STUB_LOG:-}" ] && printf 'called\n' >> "$STUB_LOG"
case "$p" in
  *STUB-SLEEP*) sleep 5; echo completeness ;;
  *STUB-ERROR*) exit 3 ;;
  *STUB-MIXED*) echo "completeness work-order" ;;
  *STUB-JUNK*) echo "maybe" ;;
  *"are you sure"*|*"really?"*) echo pushback ;;
  *"line "[0-9]*) echo concern ;;
  *"what about"*|*competitor*) echo new-idea ;;
  *"research it"*|*"exhaustive research"*) echo research-order ;;
  *build*|*fix*) echo work-order ;;
  *"good to close"*|*"are we done"*|*"100.00"*) echo completeness ;;
  *) echo other ;;
esac
