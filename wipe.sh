#!/bin/bash
if [ "$UID" -ne "0" ]; then
	echo "Please run as root."
	exit 1
fi

USBDISK=NXT_AND_X86

USBD=$(ls -l /dev/disk/by-label | grep $USBDISK | rev | cut -d'/' -f1 | rev) 
MOUNTD=$(cat /proc/mounts | grep /dev/$USBD | cut -d' ' -f2)
if [ -z "$MOUNTD" ] || [ -z "$USBD" ]; then
        echo "  ERROR   Cannot find $USBDISK"
        echo "          This is not a download-and-run script. It was designed to"
        echo "          make my life easier, and may need adjustment for usage"
        echo "          on other systems."
        exit 1;
fi

if [ ! -f "$MOUNTD/data.img" ]; then
	echo "  CREATE  $MOUNTD/data.img"
	dd if=/dev/zero of=$MOUNTD/data.img bs=1M count=4095
fi
echo "  MKFS    $MOUNTD/data.img"
mkfs.ext4 -L data -m 0 $MOUNTD/data.img
