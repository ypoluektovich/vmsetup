# wrapper to only show given device
_blkid() {
	blkid | grep "^$1:"
}

# if given device have an UUID display it, otherwise return the device
uuid_or_device() {
	local i=
	for i in $(_blkid "$1"); do
		case "$i" in
			UUID=*) eval $i;;
		esac
	done
	if [ -n "$UUID" ]; then
		echo "UUID=$UUID"
	else
		echo "$1"
	fi
}
