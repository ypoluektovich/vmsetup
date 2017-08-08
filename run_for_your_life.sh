#!/bin/bash

set -xe

./px_up.py gitbs utilities.sh
./px_up.py gitbs interfaces.txt
./px_up.py gitbs bs_sshd_config.txt
./px_up.py gitbs zero-to-ssh.sh
./px_run.py gitbs 'chmod +x zero-to-ssh.sh'
./px_run.py gitbs './zero-to-ssh.sh'

GITBSIP=$(virsh -c qemu:///system domifaddr gitbs | grep -Po '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')

exec_ssh() {
	local SSHCOMMAND=$1
	shift
	sshpass -p1 $SSHCOMMAND -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o CheckHostIP=no "$@"
}

exec_ssh scp upload/* root@$GITBSIP:.
exec_ssh ssh root@$GITBSIP 'chmod +x *.sh'

exec_ssh ssh root@$GITBSIP './vibaelia.sh'

exec_ssh ssh root@$GITBSIP 'poweroff'
