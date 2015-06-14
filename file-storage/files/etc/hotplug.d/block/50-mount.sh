#!/bin/sh

call_mount()
{
	local name=`basename $DEVPATH`
	local mount_dir=/tmp/storage/$name

	# Ignore major disk if it has partitions
	case "$name" in
		[sh]d[a-z]*|mmcblk*)
			if ls /dev/$name?* >/dev/null 2>&1; then
				echo "WARNING: Device '/dev/$name' has partitions, ignored."
				return 0
			fi
			;;
		*)
			return 0
			;;
	esac

	device=/dev/$name
	local mount_opts=""
	local blk_info=`blkid "$device"`
	local fs_type=`expr "$blk_info" : '.*TYPE="\([^"]*\)'`

	case "$fs_type" in
		ntfs*)
			mount_opts="$mount_opts -t ntfs-3g -o dmask=0000,fmask=0000"
			;;
		vfat)
			mount_opts="$mount_opts -t vfat -o dmask=0000,fmask=0000"
			;;
		"")
			mount_opts="$mount_opts -o dmask=0000,fmask=0000"
			;;
		*)
			mount_opts="$mount_opts -t $fs_type"
			;;
	esac

	mkdir -p $mount_dir

	if mount $device $mount_dir $mount_opts; then
		chmod 777 $mount_dir
		if [ ! -L /tmp/data ]; then
			rm -rf /tmp/data
			ln -s $mount_dir /tmp/data
		fi
	else
		# Delay to mount by 'file-storage' if it fails due to kmod not ready
		case "$fs_type" in
			ext?|vfat|ntfs*)
				local __enabled_fs=`awk -vf=$fs_type '$NF==f{print $NF}' /proc/filesystems`
				if [ -z "$__enabled_fs" ]; then
					echo "$DEVPATH" >> /tmp/delayed_mounts
				fi
				;;
		esac

		rmdir $mount_dir
	fi
}

[ "$ACTION" = "add" ] && call_mount || :

