#!/bin/bash

set -e

trap 'exit 1' INT TERM

echo "Starting replication ..."

PRIMARY="${PRIMARY_DB_HOST_OR_IP:-primarydb}"

count=0
while [ "$count" -lt "30" -a "$(nc -zv "${PRIMARY}" 5432 2>/dev/null; echo $?)" -ne "0" ]; do
  echo "Waiting for primary DB to be up."
  sleep 2
  count=$((count + 1))
done

PGPASSWORD=rep pg_basebackup -h "${PRIMARY}" -U rep -w -D "$PGDATA"
chmod -R 700 "$PGDATA"

cat >"${PGDATA}/recovery.conf" <<-EOF
standby_mode = 'on'
primary_conninfo = 'host=${PRIMARY} port=5432 user=rep password=rep'
restore_command = 'cp /share/master_wal/%f %p'
trigger_file = '/tmp/postgresql.trigger.5432'
EOF

bash -x /docker-entrypoint.sh postgres
