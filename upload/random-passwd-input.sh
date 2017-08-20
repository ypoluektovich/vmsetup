#!/usr/bin/env sh
tehpass=$( cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 32 )
echo -e "${tehpass}\n${tehpass}"
