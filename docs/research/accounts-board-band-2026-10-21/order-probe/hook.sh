#!/bin/bash
in="$(cat)"; sid="$(printf '%s' "$in" | jq -r .session_id)"; src="$(printf '%s' "$in" | jq -r .source)"
st=absent; [ -e "/tmp/abb-order/out/$sid.stamp" ] && st=present
printf '%s hook source=%s sid=%s stamp=%s\n' "$(python3 -c 'import time;print(int(time.time()*1000))')" "$src" "$sid" "$st" >> /tmp/abb-order/out/hooklog.txt
jq -nc --arg m "ORDER-PROBE stamp=$st" '{systemMessage:$m}'
