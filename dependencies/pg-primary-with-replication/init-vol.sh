#!/bin/bash

set -x

mkdir -p /share && chown postgres:postgres /share

bash -x /docker-entrypoint.sh postgres
