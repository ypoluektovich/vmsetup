#!/bin/bash

###### CONFIGURATION

if [[ "$#" -eq 0 ]]; then
	echo "specify RFYL profile directory as a parameter" >&2
	exit 1
fi

RFYL_PROFILE="$1"
shift
RFYL_PROFILE=$( realpath "$RFYL_PROFILE" )
echo "using profile $RFYL_PROFILE"

if [[ ! -d "$RFYL_PROFILE" ]]; then
	echo "specified profile does not exist or is not a directory"
	exit 1
fi

if [[ ! -f "$RFYL_PROFILE/config.sh" ]]; then
	echo "missing or bad config.sh in the profile"
	exit 1
fi


# set to any non-null value to enable debug mode
RFYL_DEBUG=
# name of the transient bootstrap VM
RFYL_BS_VM_NAME=
# integer value, in megabytes
RFYL_BS_VM_RAM=
# name of the virsh network for the bootstrap VM
RFYL_BS_NET=
# name of the production VM
RFYL_PR_VM_NAME=
# integer value, in megabytes
RFYL_PR_VM_RAM=
# name of the virsh network for the production VM
RFYL_PR_NET=
# connect order, pool, name, size, action on completion (keep/drop)
RFYL_STORAGE_TO_CREATE=""
# connect order, pool, name, "keep" or not for the production VM
RFYL_STORAGE_TO_CONNECT=""
# device, [mbr], space-separated sfdisk lines
RFYL_STORAGE_MKPART=""
# device, mount point
RFYL_STORAGE_MOUNT=""

source "$RFYL_PROFILE/config.sh"

# todo: validate config


###### UTILITIES

VIRSH="virsh -c qemu:///system"
#VIRSH="echo"
VIRTINSTALL="virt-install --connect qemu:///system"
#VIRTINSTALL="echo"

LINEFEED="
"

print_error() {
	local lastcode="$?"
	echo ""
	echo "/!\ there was an error ($lastcode); script will now abort"
	echo ""
}


###### SUBROUTINES

#### disk image manipulation

RFYL_STORAGE_CREATED=""
RFYL_STORAGE_TO_DROP=""
RFYL_STORAGE_ORDERED="$RFYL_STORAGE_TO_CONNECT"
RFYL_STORAGE_BS_ARGS=()
RFYL_STORAGE_PR_ARGS=()

storage_cleanup() {
	echo "cleanup: removing disk images"
	local img_pool="" img_name=""
	while read img_pool img_name; do
		$VIRSH vol-delete --pool "$img_pool" "$img_name"
	done
}

storage_cleanup_on_abort() {
	[[ -z "$RFYL_STORAGE_CREATED" ]] && return 0
	storage_cleanup <<< $(echo -e "$RFYL_STORAGE_CREATED")
}

storage_cleanup_on_complete() {
	[[ -z "$RFYL_STORAGE_TO_DROP" ]] && return 0
	storage_cleanup <<< $(echo -e "$RFYL_STORAGE_TO_DROP")
}

storage_create_all() {
	echo "creating disk images"
	[[ -z "$RFYL_STORAGE_TO_CREATE" ]] && echo "no disks to create" && return 0
	local img_order="" img_pool="" img_name="" img_size="" img_act="" img_rec_del="" img_rec=""
	while read img_order img_pool img_name img_size img_act; do
		$VIRSH vol-create-as "$img_pool" "$img_name" "$img_size" --format raw || return 1

		img_rec_del="$img_pool $img_name\n"
		RFYL_STORAGE_CREATED="${RFYL_STORAGE_CREATED}${img_rec_del}"
		case "$img_act" in
			"keep") ;;
			"drop") RFYL_STORAGE_TO_DROP="${RFYL_STORAGE_TO_DROP}${img_rec_del}" ;;
			*) echo "unrecognized on-completion act: $img_act"; return 1 ;;
		esac

		img_rec="${img_order} ${img_pool} ${img_name} ${img_act}"
		RFYL_STORAGE_ORDERED="${RFYL_STORAGE_ORDERED}${RFYL_STORAGE_ORDERED:+$LINEFEED}${img_rec}"
	done <<< "$RFYL_STORAGE_TO_CREATE"
}

storage_check_and_assemble_args() {
	RFYL_STORAGE_ORDERED=$( sort -n -k 1 <<< "$RFYL_STORAGE_ORDERED" )

	echo "checking disk connection config correctness"
	( cut -d" " -f1 <<< "$RFYL_STORAGE_ORDERED" | sort -nCu )

	RFYL_STORAGE_ORDERED=$( cut -d" " -f2- <<< "$RFYL_STORAGE_ORDERED" )

	local img_vol="" img_name="" img_act=""
	while read img_vol img_name img_act; do
		RFYL_STORAGE_BS_ARGS=( "${RFYL_STORAGE_BS_ARGS[@]}" "--disk" "vol=${img_vol}/${img_name}" )
		if [[ "$img_act" == "keep" ]]; then
			RFYL_STORAGE_PR_ARGS=( "${RFYL_STORAGE_PR_ARGS[@]}" "--disk" "vol=${img_vol}/${img_name}" )
		fi
	done <<< "$RFYL_STORAGE_ORDERED"
}

#### domain cleanup

destroy_domain() {
	echo "cleanup: destroying the bootstrap VM"
	$VIRSH destroy ${RFYL_BS_VM_NAME}
}


###### HASSHIN!


${RFYL_DEBUG:+ set -x}


trap 'print_error; storage_cleanup_on_abort; exit 1' ERR

storage_create_all

storage_check_and_assemble_args


echo "creating the bootstrap VM"

$VIRTINSTALL \
    ${RFYL_DEBUG:+ --debug} \
    --name=${RFYL_BS_VM_NAME} \
    --vcpus=1 --cpu host \
    --ram=${RFYL_BS_VM_RAM} \
    --os-type=linux --os-variant=generic \
    --cdrom /var/lib/libvirt/images/alpine-virt-3.6.2-x86_64.iso \
    "${RFYL_STORAGE_BS_ARGS[@]}" \
    --network=network="$RFYL_BS_NET",model=virtio \
    --graphics none \
    --livecd --noautoconsole --transient

trap 'print_error; destroy_domain; storage_cleanup_on_abort; exit 1' ERR


./px_run.py $RFYL_BS_VM_NAME "mount -o remount,size=1M /dev/shm; mount -o remount,size=$((RFYL_BS_VM_RAM - 5))M /"

./px_up.py $RFYL_BS_VM_NAME early_utils.sh
./px_up.py $RFYL_BS_VM_NAME interfaces.txt
./px_up.py $RFYL_BS_VM_NAME bs_sshd_config.txt
./px_up.py $RFYL_BS_VM_NAME zero-to-ssh.sh
./px_run.py $RFYL_BS_VM_NAME 'chmod +x zero-to-ssh.sh'
./px_run.py $RFYL_BS_VM_NAME './zero-to-ssh.sh'

RFYL_BS_VM_IP=$($VIRSH domifaddr $RFYL_BS_VM_NAME | grep -Po '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')

exec_ssh() {
	local SSHCOMMAND=$1
	shift
	sshpass -p1 $SSHCOMMAND -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o CheckHostIP=no "$@"
}

exec_ssh scp upload/* root@$RFYL_BS_VM_IP:.
exec_ssh ssh root@$RFYL_BS_VM_IP 'chmod +x *.sh'

exec_ssh scp -r "${RFYL_PROFILE}/upload" root@$RFYL_BS_VM_IP:profile

exec_ssh ssh root@$RFYL_BS_VM_IP 'cat >mkpart.txt' <<<"$RFYL_STORAGE_MKPART"
exec_ssh ssh root@$RFYL_BS_VM_IP 'cat >mount.txt' <<<"$RFYL_STORAGE_MOUNT"

exec_ssh ssh root@$RFYL_BS_VM_IP './vibaelia.sh'

exec_ssh ssh root@$RFYL_BS_VM_IP 'poweroff'

while $VIRSH domid $RFYL_BS_VM_NAME >/dev/null 2>&1; do sleep 1; done

trap 'print_error; storage_cleanup_on_abort; exit 1' ERR

$VIRTINSTALL \
    ${RFYL_DEBUG:+ --debug} \
    --name=${RFYL_PR_VM_NAME} \
    --vcpus=1 --cpu host \
    --ram=${RFYL_PR_VM_RAM} \
    --os-type=linux --os-variant=generic \
    --import \
    "${RFYL_STORAGE_PR_ARGS[@]}" \
    --network=network="$RFYL_PR_NET",model=virtio \
    --graphics none \
    --noautoconsole --noreboot

storage_cleanup_on_complete
