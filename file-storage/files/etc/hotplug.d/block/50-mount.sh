#!/bin/sh

call_mount()
{
	local device=`basename $DEVPATH`
	local mount_dir=/tmp/storage/$device

	# Ignore major disk if it has partitions
	case "$device" in
		[sh]d[a-z])
			ls /dev/$device?* >/dev/null 2>&1 && return 0 || :
			;;
	esac

	mkdir -p $mount_dir
	if mount /dev/$device $mount_dir -t ext3 || mount /dev/$device $mount_dir -o dmask=0000,fmask=0000; then
		chmod 777 $mount_dir
		if [ ! -L /tmp/data ]; then
			rm -rf /tmp/data
			ln -s $mount_dir /tmp/data
		fi
	else
		rmdir $mount_dir
	fi
}

[ "$ACTION" = "add" ] && call_mount || :

