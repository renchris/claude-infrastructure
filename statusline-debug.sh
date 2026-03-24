#!/bin/bash
INPUT=$(cat)

echo "=== RAW JSON ===" >&2
echo "$INPUT" | jq '.' >&2

echo "" >&2
echo "=== context_window fields ===" >&2
echo "$INPUT" | jq '.context_window' >&2

echo "" >&2
echo "=== Extracted values ===" >&2
echo "total_input_tokens: $(echo "$INPUT" | jq -r '.context_window.total_input_tokens // "MISSING"')" >&2
echo "total_output_tokens: $(echo "$INPUT" | jq -r '.context_window.total_output_tokens // "MISSING"')" >&2
echo "remaining_percentage: $(echo "$INPUT" | jq -r '.context_window.remaining_percentage // "MISSING"')" >&2

# Still output something for the statusline
echo "DEBUG MODE"
