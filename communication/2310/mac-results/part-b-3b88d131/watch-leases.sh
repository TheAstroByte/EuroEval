#!/bin/bash
# Poll the redacted probe every 5s for up to 75 min; log distinct lease/model events.
RUN=/tmp/ee-2310-partB-3b88d131 S=/Users/daniel/.euroeval-worker-2310 END=$(date -d '+75 minutes' +%s 2>/dev/null || echo $(( $(date +%s) + 4500 )))
last=""
while [ $(date +%s) -lt $END ]; do
  out=$(python3 $RUN/probe.py $S 2>/dev/null)
  echo "{\"t\": $(date +%s), \"probe\": $out}" >> $RUN/b2-lease-watch.jsonl
  lid=$(echo "$out" | python3 -c "import json,sys; print(json.load(sys.stdin).get('lease_id',''))" 2>/dev/null)
  if [ -n "$lid" ] && [ "$lid" != "$last" ]; then
    echo "{\"t\": $(date +%s), \"event\": \"new_lease\", \"probe\": $out}" >> $RUN/b2-lease-events.jsonl
    last="$lid"
  fi
  sleep 5
done
echo "watcher done at $(date +%s)" >> $RUN/b2-lease-events.jsonl
