#!/bin/bash

count=0
while [ "$count" -lt "60" -a "$(nc -zv primarygo 8153 2>/dev/null; echo $?)" -ne "0" ]; do
  [[ "$((count % 10))" = "0" ]] && echo "Waiting for primary Go Server to be up ..."
  sleep 2;
  count=$((count + 1))
done

bash -x /docker-entrypoint.sh
