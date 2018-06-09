#!/bin/bash

# Make sure that the secondary Go Server waits till the primary Go Server is up, before coming up and putting itself in
# inactive mode.
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

PRIMARY_GO="${PRIMARY_GO_SERVER_HOST_OR_IP:-primarygo}"

count=0
while [ "$count" -lt "60" -a "$(nc -zv "${PRIMARY_GO}" 8153 2>/dev/null; echo $?)" -ne "0" ]; do
  [[ "$((count % 10))" = "0" ]] && echo "Waiting for primary Go Server to be up ..."
  sleep 2;
  count=$((count + 1))
done

chown -R 1000:1000 /godata/*

bash -x /docker-entrypoint.sh
