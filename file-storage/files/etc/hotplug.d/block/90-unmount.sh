#!/bin/sh

call_unmount()
{
	local device=`basename $DEVPATH`
	local mount_dir=/tmp/storage/$device

	# Ignore major disk if it has partitions
	case "$device" in
		[sh]d[a-z])
			ls /dev/$device?* >/dev/null 2>&1 && return 0 || :
			;;
	esac

	umount $mount_dir
	rmdir $mount_dir
	[ -d /tmp/data ] || rm -f /tmp/data
}

[ "$ACTION" = "remove" ] && call_unmount || :

