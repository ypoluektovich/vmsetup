#!/usr/bin/env sh

set -xe

source utilities.sh

echo -e "1\n1" | passwd

# set up interfaces for the bootstrap system
setup_interfaces "/" "interfaces.txt"

# start the networking
/etc/init.d/networking --quiet start >/dev/null

# set up timezone in the bootstrap system
apk add --quiet tzdata
setup_tz "/"

# set up ssh in the bootstrap system
apk add --quiet openssh >/dev/null
cp bs_sshd_config.txt /etc/ssh/sshd_config
rc-update add sshd default
rc-service sshd start
