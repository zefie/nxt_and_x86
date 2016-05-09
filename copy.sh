#!/bin/bash
if [ "$UID" -ne "0" ]; then
	echo "Please run as root."
	exit 1
fi

USBDISK=NXT_AND_X86
AND_BUILD=../android-x86/out/target/product/x86
KDIR=../kernel_nextbook
SIZE_M=1536


USE_SQUASH=0
if [ "$1" == "squash" ]; then
        USE_SQUASH=1;
fi

MOUNTP=$HOME/zefie_processing
MOUNTD=$(df /dev/$(ls -l  /dev/disk/by-label | grep $USBDISK | rev | cut -d'/' -f1 | rev) | rev | cut -d'%' -f1 | cut -d' ' -f1 | grep / | rev)

if [ "$MOUNTD" == "/dev/" ]; then
        echo "  ERROR   Cannot find $USBDISK"
	echo "This is not a download-and-run script. It was designed to"
        echo "make my life easier, and may need adjustment for usage"
        echo "on other systems."
	exit 1;
fi

THISDIR=$(pwd)

trap ctrl_c INT

if [ ! -d "$MOUNTP" ]; then
        echo "  INFO    Creating $MOUNTP"
	mkdir $MOUNTP;
fi

function clean_workdir() {
	echo "  CLEAN   workdir"
	rm -rf workdir
}

function clean_mountp() {
        if [ "$(ls -A $MOUNTP)" ]; then
                echo "  WARN    Not removing $MOUNTP ... Not empty"
        else
	        echo "  INFO    Removing $MOUNTP"
                rmdir $MOUNTP
        fi
}

function copy_files() {
	# This function copies files, sets their mode,
	# and chowns the file to root. When checking out
	# from git, permissions are preserved but ownership
	# is lost, thus we want to override the ownership

        ZPATH="files/$1/"
        OUTPATH="$2"

        for f in $(find $ZPATH); do
                ZOUT=$(echo "$f" | sed "s|$ZPATH||")
                if [ "$ZOUT" ]; then
                        ZOUT=$OUTPATH/$ZOUT
                        if [ -d "$f" ]; then
                                mkdir -p $ZOUT
                        else
                                PERM=$(stat -c "%a" $f)
                                cp $f $ZOUT
                                chmod $PERM $ZOUT
				chown root:root $ZOUT
                        fi
                fi
        done;
}


trap ctrl_c INT

function ctrl_c() {
	echo -ne '\r'
        echo "  WARN    CTRL-C Pressed... cancelling and unmounting"
        echo "  UMOUNT  $MOUNTD/system.img"
        umount $MOUNTP 2>/dev/null
	clean_mountp
	clean_workdir
        exit 130
}

if [ ! -f "$AND_BUILD/system.img" ]; then
	echo "  ERROR   Could not find system.img in Android build dir"
	clean_mountp
	exit 1;
fi

clean_workdir
mkdir workdir

echo "  COPY    system.img > workdir"
cp $AND_BUILD/system.img workdir/

CURSIZE=$(du -m workdir/system.img | cut -f1)
SIZEDIFF=$(expr $SIZE_M - $CURSIZE)
if [ "$SIZEDIFF" -gt "0" ]; then
	echo "  GROW    workdir/system.img by ${SIZEDIFF}M"
	dd if=/dev/zero bs=1M count=SIZEDIFF 2>/dev/null >> workdir/system.img
	fsck.ext4 -fp workdir/system.img 2>/dev/null > /dev/null
	resize2fs workdir/system.img 2>/dev/null > /dev/null
	fsck.ext4 -fp workdir/system.img 2>/dev/null > /dev/null
fi

echo "  MOUNT   workdir/system.img"
mount -o loop -t ext4 workdir/system.img $MOUNTP/

if [ "$(df -h | grep $MOUNTP | wc -l)" -ne "1" ]; then
	echo "  ERROR   Failed to mount system.img"
	clean_mountp
	clean_workdir
	exit 1;
fi

echo "  COPY    System files"
copy_files system $MOUNTP

if [ -f "$KDIR/arch/x86/boot/bzImage" ]; then
	cd $KDIR
	scripts/z_modinst.sh nomount
	cd $THISDIR
else
	echo "  ERROR   Kernel not compiled!"
	exit 1
fi

echo "  PATCH   build.prop"
echo 'hal.sensors.iio.accel.matrix=0,1,0,1,0,0,0,0,-1' >> $MOUNTP/build.prop

echo "  UMOUNT  workdir/system.img"
umount $MOUNTP/

if [ "$USE_SQUASH" -eq "1" ]; then
	if [ -f "$MOUNTD/system.img" ]; then
		echo "  REMOVE  $MOUNTD/system.img";
		rm $MOUNTD/system.img
	fi
	if [ "$(grep system.img $MOUNTD/boot/grub/grub.cfg | wc -l)" -gt "0" ]; then
		echo "  PATCH   $MOUNTD/boot/grub/grub.cfg"
		sed -i 's|system.img|system.sfs|g' $MOUNTD/boot/grub/grub.cfg
	fi
	echo "  SQUASH  workdir/system.img > workdir/system.sfs"
	cd workdir
	mksquashfs system.img system.sfs 2>&1 > /dev/null
	cd ..

	echo "  COPY    workdir/system.sfs > $MOUNTD/system.sfs"
	cp workdir/system.sfs $MOUNTD/system.sfs
else
	if [ -f "$MOUNTD/system.sfs" ]; then
		echo "  REMOVE  $MOUNTD/system.sfs";
		rm $MOUNTD/system.sfs
	fi
	if [ "$(grep system.sfs $MOUNTD/boot/grub/grub.cfg | wc -l)" -gt "0" ]; then
		echo "  PATCH   $MOUNTD/boot/grub/grub.cfg"
		sed -i 's|system.sfs|system.img|g' $MOUNTD/boot/grub/grub.cfg
	fi
	echo "  COPY    workdir/system.img > $MOUNTD/system.img"
	cp workdir/system.img $MOUNTD/system.img
fi

echo "  COPY    install.img > $MOUNTD/install.img"
cp "$AND_BUILD/install.img" "$MOUNTD/install.img"

echo "  COPY    initrd.img > $MOUNTD/initrd.img"
cp "$AND_BUILD/initrd.img" "$MOUNTD/initrd.img"

clean_workdir
mkdir workdir

echo "  COPY    ramdisk.img > workdir/initrd.img.gz"
cp "$AND_BUILD/ramdisk.img" "workdir/ramdisk.img.gz"

echo "  EXT     ramdisk > workdir"
cd workdir
gzip -dc ramdisk.img.gz | cpio -id 2>/dev/null > /dev/null
cd ..

echo "  COPY    ramdisk files"
copy_files root workdir

echo "  BUILD   ramdisk > $MOUNTD/ramdisk.img"
cd workdir
find . -name ramdisk.img.gz -prune -o -print | cpio --create --format='newc' 2>/dev/null | gzip -9c > $MOUNTD/ramdisk.img
cd ..

clean_workdir
clean_mountp
