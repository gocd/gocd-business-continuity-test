#!/bin/bash

set -x

psql --username postgres <<-EOF
CREATE USER rep REPLICATION LOGIN CONNECTION LIMIT 1 ENCRYPTED PASSWORD 'rep';
EOF

cat >>"${PGDATA}/pg_hba.conf" <<-EOF
host  replication  rep  0.0.0.0/0  md5
EOF

cat >>"${PGDATA}/postgresql.conf" <<-EOF
archive_mode = on
archive_command = 'test ! -f /share/master_wal/%f && (mkdir -p /share/master_wal || true) && cp %p /share/master_wal/%f && chmod 644 /share/master_wal/%f'
archive_timeout = 60
max_wal_senders = 1
hot_standby = on
wal_level = hot_standby
wal_keep_segments = 30
EOF

mkdir -p /share && chown postgres:postgres /share
