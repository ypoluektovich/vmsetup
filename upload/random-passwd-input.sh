#!/usr/bin/env sh
if [[ -n "$1" ]]; then
	tehpass="$1"
else
	tehpass=$( cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 32 )
fi
echo -e "${tehpass}\n${tehpass}"
