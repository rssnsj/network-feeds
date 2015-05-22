#!/bin/sh

call_unmount()
{
	local name=`basename $DEVPATH`
	local mount_dir=/tmp/storage/$name

	# Ignore major disk if it has partitions
	case "$name" in
		[sh]d[a-z]*|mmcblk*)
			ls /dev/$name?* >/dev/null 2>&1 && return 0 || :
			;;
		*)
			return 0
			;;
	esac

	umount $mount_dir
	while umount $mount_dir 2>/dev/null; do :; done
	rmdir $mount_dir
	[ -d /tmp/data ] || rm -f /tmp/data
}

[ "$ACTION" = "remove" ] && call_unmount || :

