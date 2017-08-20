#!/bin/false
# this is not a thing to be executed on its own

setup_interfaces() {
	local ROOT="$1" FILE="$2"
	cat "$FILE" > "${ROOT}etc/network/interfaces"
}


setup_tz() {
	local ROOT="$1"
	local ZROOT=/usr/share/zoneinfo

	mkdir -p "${ROOT}etc/zoneinfo"
	cp "$ZROOT/UTC" "${ROOT}etc/zoneinfo/"
	rm -f "${ROOT}etc/localtime"
	ln -s "$ZROOT/UTC" "${ROOT}etc/localtime"
}
