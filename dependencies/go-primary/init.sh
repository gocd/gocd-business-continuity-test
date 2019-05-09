#!/bin/bash

yum install -y which net-tools

echo "Setting up an empty Go config file, with site URLs set."
tee /godata/config/cruise-config.xml >/dev/null <<EOF
<?xml version="1.0" encoding="utf-8"?>
<cruise xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="cruise-config.xsd" schemaVersion="90">
  <server artifactsdir="artifacts" siteUrl="http://localhost:8153" secureSiteUrl="https://localhost:8154" agentAutoRegisterKey="123456789abcdef" commandRepositoryLocation="default" serverId="5841e844-cfef-4ac1-adcd-8550bb6e918b">
  <security>
      <authConfigs>
        <authConfig id="password_file" pluginId="cd.go.authentication.passwordfile">
          <property>
            <key>PasswordFilePath</key>
            <value>/godata/password.properties</value>
          </property>
        </authConfig>
      </authConfigs>
    </security>
   </server>
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

mv -f '/godata/business-continuity-token' '/godata/config/business-continuity-token'

touch /etc/rc.local

echo "Assigning this Go Server machine the virtual IP: 172.17.17.17"
java -Dinterface=eth0:0 -Dip=172.17.17.17 -Dnetmask=255.255.0.0 -jar /godata/addons/go-business-continuity-*.jar assign
RES=$?
if [ $RES -ne 0 ]; then
  echo "Failed to assign Virtual IP to primary server"
  exit -1
fi

chown -R 1000:1000 /godata/*

bash -x /docker-entrypoint.sh
