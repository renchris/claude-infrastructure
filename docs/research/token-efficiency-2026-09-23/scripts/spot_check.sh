#!/bin/bash
# Hand spot-check: recount a transcript file with jq (an independent parser) and print it beside
# extract.sqlite's figures for the same file. Usage: spot_check.sh <file> [<file> ...]
DB="$(cd "$(dirname "$0")/.." && pwd)/data/extract.sqlite"
for f in "$@"; do
  echo "== $f"
  # jq: per message.id keep the LAST record's usage (final) and FIRST record's output
  jq -s -r '
    [ .[] | select(.type=="assistant" and (.message.usage|type)=="object" and (.timestamp >= "2026-09-09")) ] as $a
    | ($a | group_by(.message.id)) as $g
    | "jq:     resp=\($g|length) records=\($a|length) input=\([$g[]|last.message.usage.input_tokens]|add) cc=\([$g[]|last.message.usage.cache_creation_input_tokens]|add) cr=\([$g[]|last.message.usage.cache_read_input_tokens]|add) out_final=\([$g[]|map(.message.usage.output_tokens)|max]|add) out_first=\([$g[]|first.message.usage.output_tokens]|add)"' "$f"
  sqlite3 "$DB" "select 'sqlite: resp='||n_resp||' records='||n_records_naive||' input='||input_tokens||' cc='||cc_total||' cr='||cache_read||' out_final='||output_tokens||' out_first='||output_first from ctx where file='$f';"
  jq -s -r '
    ([ .[] | select(.type=="user" and (.message.content|type)=="array") | .message.content[] | select(.type=="tool_result") ] | length) as $tr
    | ([ .[] | select(.type=="user" and (.message.content|type)=="array") | .message.content[] | select(.type=="tool_result" and .is_error==true) ] | length) as $te
    | ([ .[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") ] | length) as $tu
    | ([ .[] | select(.type=="attachment") ] | length) as $at
    | ([ .[] | select(.type=="attachment" and (.rendered|type)=="array" and (.rendered|length)>0) | .rendered[].content | length ] | add // 0) as $atc
    | ([ .[] | select(.type=="user" and (.message.content|type)=="array") | .message.content[] | select(.type=="tool_result") | (if (.content|type)=="string" then (.content|length) else ([.content[]? | select(.type=="text") | .text | length] | add // 0) end) ] | add // 0) as $trc
    | "jq:     tool_result=\($tr) errors=\($te) tool_use=\($tu) attachments=\($at) attach_rendered_chars=\($atc) tool_result_chars=\($trc)"' "$f"
  sqlite3 "$DB" "select 'sqlite: tool_result='||sum(kind='tool_result')||' errors='||sum(is_error)||' tool_use='||sum(kind='tool_use_input')||' attachments='||sum(kind='attachment')||' attach_rendered_chars='||sum(case when kind='attachment' then chars else 0 end)||' tool_result_chars='||sum(case when kind='tool_result' then chars else 0 end) from item where file='$f';"
done
