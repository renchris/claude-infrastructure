#!/usr/bin/env bash
# sample.sh — append one meter reading (next4 = arm account, next = judge account) per call.
claude-accounts --fresh --json 2>/dev/null | jq -c --arg t "$(date -u +%FT%TZ)" \
  '[.rows[] | select(.acct=="next4" or .acct=="next") | {acct, session_pct, weekly_pct, fable_pct, session_reset_at}] | {t:$t, rows:.}'
