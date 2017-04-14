#!/bin/bash

# Make sure that the secondary Go Server waits till the primary Go Server is up, before coming up and putting itself in
# inactive mode.

PRIMARY_GO="${PRIMARY_GO_SERVER_HOST_OR_IP:-primarygo}"

count=0
while [ "$count" -lt "60" -a "$(nc -zv "${PRIMARY_GO}" 8153 2>/dev/null; echo $?)" -ne "0" ]; do
  [[ "$((count % 10))" = "0" ]] && echo "Waiting for primary Go Server to be up ..."
  sleep 2;
  count=$((count + 1))
done

bash -x /docker-entrypoint.sh
