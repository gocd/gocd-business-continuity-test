#!/bin/bash

echo "Setting up an empty Go config file, with site URLs set."
tee /godata/config/cruise-config.xml >/dev/null <<EOF
<?xml version="1.0" encoding="utf-8"?>
<cruise xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="cruise-config.xsd" schemaVersion="90">
  <server artifactsdir="artifacts" siteUrl="http://localhost:8153" secureSiteUrl="https://localhost:8154" agentAutoRegisterKey="123456789abcdef" commandRepositoryLocation="default" serverId="5841e844-cfef-4ac1-adcd-8550bb6e918b" />
</cruise>
EOF

# Wait for Postgres to be ready and serving.
DB="${DB_HOST_OR_IP:-db}"
count=0
while [ "$count" -lt "30" -a "$(nc -zv "${DB}" 5432 2>/dev/null; echo $?)" -ne "0" ]; do
  echo "Waiting for DB to be up."
  sleep 2
  count=$((count + 1))
done

touch /etc/rc.local

echo "Assigning this Go Server machine the virtual IP: 172.17.17.17"
java -Dinterface=eth0:0 -Dip=172.17.17.17 -Dnetmask=255.255.0.0 -jar /godata/addons/go-business-continuity-*.jar assign

bash -x /docker-entrypoint.sh
