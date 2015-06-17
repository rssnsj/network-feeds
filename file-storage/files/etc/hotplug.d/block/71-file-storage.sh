#!/bin/sh
# Copyright (C) 2012-2013 hiwifi.com
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

trigger_reload()
{
	local call_script=/tmp/X-mount-exec
	local call_lock=/tmp/file-storage.lock

	/etc/init.d/file-storage enabled || return 0

	if mkdir $call_lock 2>/dev/null; then
		cat > $call_script <<EOF
#!/bin/sh
sleep 5
/etc/init.d/file-storage reload
rm -f $call_script
rmdir $call_lock
EOF
		chmod +x $call_script
		start-stop-daemon -S -b -x $call_script -- || {
			rm -f $call_script
			rmdir $call_lock
		}
	fi

	return 0
}

device=`basename $DEVPATH`

case "$device" in
	sd*|mmcblk*)
		case "$ACTION" in
			add) trigger_reload;;
			remove) trigger_reload;;
		esac
		;;
esac
