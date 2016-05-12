#!/bin/bash
if [ "$UID" -ne "0" ]; then
	echo "Please run as root."
	exit 1
fi

USBDISK=NXT_AND_X86

MOUNTP=$HOME/zefie_processing
MOUNTD=$(df /dev/$(ls -l  /dev/disk/by-label | grep $USBDISK | rev | cut -d'/' -f1 | rev) | rev | cut -d'%' -f1 | cut -d' ' -f1 | grep / | rev)

if [ "$MOUNTD" == "/dev/" ]; then
        echo "  ERROR   Cannot find $USBDISK"
	echo "This is not a download-and-run script. It was designed to"
        echo "make my life easier, and may need adjustment for usage"
        echo "on other systems."
	exit 1;
fi

echo "  MKFS    $MOUNTD/data.img"
mkfs.ext4 -L data -m 0 $MOUNTD/data.img 4G
