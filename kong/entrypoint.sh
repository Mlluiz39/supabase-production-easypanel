#!/bin/sh
cp /etc/kong/kong.template.yml /etc/kong/kong.yml
sed -i "s|__ANON_KEY__|${ANON_KEY}|g" /etc/kong/kong.yml
sed -i "s|__SERVICE_ROLE_KEY__|${SERVICE_ROLE_KEY}|g" /etc/kong/kong.yml
/docker-entrypoint.sh kong start
