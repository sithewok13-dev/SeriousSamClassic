#!/bin/bash
# ci_run.sh <title> <command...>
# Runs a CI step and, if it fails, republishes the interesting part of its
# output as a GitHub annotation (readable through the checks API, which is
# handy when the full log can't be downloaded).
title="$1"; shift
log=$(mktemp)
"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then
  {
    grep -nE "error|Error|ERROR|undefined|fatal|FAILED|not found|No such" "$log" | grep -v "Werror\|-Wno-error\|warning:" | head -40
    echo "----- undefined symbols -----"
    grep -A 40 "Undefined symbols" "$log" | grep -E '^ *"|referenced from' | grep '"' | sort -u | head -60
    echo "----- last lines -----"
    tail -40 "$log"
  } | cut -c1-400 > "$log.sum"
  msg=$(sed -e 's/%/%25/g' -e 's/\r//g' "$log.sum" | awk '{printf "%s%%0A", $0}')
  echo "::error title=${title}::${msg}"
fi
exit "$status"
