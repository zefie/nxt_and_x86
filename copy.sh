#!/bin/bash
if [ "$UID" -ne "0" ]; then
	echo "Please run as root."
	exit 1
fi

USBDISK=NXT_AND_X86
SIZE_M=1536
#BOOTARGS="reboot=acpi noefi"
#BOOTARGS="intel_idle.max_cstate=1 reboot=apci acpi_backlight=vendor noefi"
BOOTARGS="tsc=reliable force_tsc_stable=1 clocksource_failover=tsc reboot=apci acpi_backlight=vendor noefi"

if [ "$1" == "cm" ]; then
	ANDTYPE=CyanogenMod
	FLAVOR=android-x86-cm
	PRODUCT=android_x86
fi
if [ "$1" == "aosp" ]; then
	ANDTYPE=AOSP
	FLAVOR=android-x86
	PRODUCT=x86
fi

if [ -z "$FLAVOR" ]; then
        echo "  ERROR   Please choose a flavor (cm or aosp)"
	exit 1
fi


if [ "$2" == "prebuilt" ]; then
	if [ ! -z "$3" ] && [ "$3" != "squash" ] && [ "$3" != "list" ]; then
		FLAVOR=$3
		AND_BUILD=./prebuilt/$FLAVOR
	else
		if [ "$3" == "squash" ]; then
			echo "  ERROR   Prebuilt image folder cannot be named \"squash\" :)"
		elif [ "$3" == "list" ]; then
			echo "  INFO    Available images:"
			for f in $(find prebuilt/ -type d |sed 's#.*/##'); do
				echo "          $f"
			done
			exit 0;
		else
		        echo "  ERROR   Please choose a prebuilt image (subfolder)"
		fi
		exit 1;
	fi
else
	AND_BUILD=../$FLAVOR/out/target/product/$PRODUCT
fi

KDIR=../kernel_nextbook


USE_SQUASH=0
if [ "$2" == "squash" ] || [ "$3" == "squash" ] || [ "$4" == "squash" ]; then
        USE_SQUASH=1;
fi

MOUNTP=$HOME/zefie_processing
USBD=$(ls -l /dev/disk/by-label | grep $USBDISK | rev | cut -d'/' -f1 | rev) 
MOUNTD=$(cat /proc/mounts | grep /dev/$USBD | cut -d' ' -f2)
if [ -z "$MOUNTD" ] || [ -z "$USBD" ]; then
        echo "  ERROR   Cannot find $USBDISK"
	echo "          This is not a download-and-run script. It was designed to"
        echo "          make my life easier, and may need adjustment for usage"
        echo "          on other systems."
	exit 1;
fi

THISDIR=$(pwd)

trap ctrl_c INT

if [ ! -d "$MOUNTP" ]; then
        echo "  INFO    Creating $MOUNTP"
	mkdir $MOUNTP;
fi

function z_umount() {
        echo "  UMOUNT  $2"
	umount $1 2>/dev/null
	while [ "$(check_mounted $1)" -gt "0" ]; do
		echo "  WARN    Failed to unmount $2 .. retrying in 3 seconds"
		sleep 3
		umount $1
	done;
	echo "  SUCCESS Unmounted $2"
}

function detect_android_version() {
	# TODO: Make this better
	ZANDVERS=$(cat $MOUNTP/build.prop | grep ro.build.version.release | cut -d'=' -f2 | cut -d'.' -f1);
	re='^[0-9]+$'
	if ! [[ $ZANDVERS =~ $re ]] ; then
		# For some reason we didn't get a number.
		return 0;
	else
		return $ZANDVERS
	fi
}

function patch_grub() {
	if [ "$USE_SQUASH" -eq "1" ]; then
		if [ "$(grep system.img $MOUNTD/boot/grub/grub.cfg | wc -l)" -gt "0" ]; then
			sed -i 's|system.img|system.sfs|g' $MOUNTD/boot/grub/grub.cfg
		fi
	else
		if [ "$(grep system.sfs $MOUNTD/boot/grub/grub.cfg | wc -l)" -gt "0" ]; then
			sed -i 's|system.sfs|system.img|g' $MOUNTD/boot/grub/grub.cfg
		fi
	fi
	sed -i "s|#HW#|$1|g" $MOUNTD/boot/grub/grub.cfg
	sed -i "s|#BOOTARGS#|$BOOTARGS|g" $MOUNTD/boot/grub/grub.cfg
	sed -i "s|#TITLE#|$ANDTYPE $(date --date=\@${2} +%Y-%m-%d)|g" $MOUNTD/boot/grub/grub.cfg
}

function check_mounted() {
	if [ "$(df | grep $1 | wc -l)" -gt "0" ]; then
		echo 1;
	else
		echo 0;
	fi
}

function patch_buildprop() {
	echo "  PATCH   build.prop"
	sed -i '/hal.sensors.iio.accel.matrix/d' $MOUNTP/build.prop
	sed -i '/ro.product.model/d' $MOUNTP/build.prop
	sed -i '/ro.product.brand/d' $MOUNTP/build.prop
	sed -i '/ro.product.board/d' $MOUNTP/build.prop
	sed -i '/ro.product.manufacturer/d' $MOUNTP/build.prop
	sed -i '/ro.product.platform/d' $MOUNTP/build.prop
	sed -i '/ro.sf.lcd_density/d' $MOUNTP/build.prop
	sed -i '/ro.radio.noril/d' $MOUNTP/build.prop
	echo 'ro.product.model=NXW101QC232' >> $MOUNTP/build.prop
	echo 'ro.product.brand=NextBook' >> $MOUNTP/build.prop
	echo 'ro.product.board=baytrail' >> $MOUNTP/build.prop
	echo 'ro.product.manufacturer=Yifang' >> $MOUNTP/build.prop
	echo 'ro.board.platform=baytrail' >> $MOUNTP/build.prop
	echo 'ro.radio.noril=yes' >> $MOUNTP/build.prop
	echo 'hal.sensors.iio.accel.matrix=0,1,0,1,0,0,0,0,-1' >> $MOUNTP/build.prop
	if [ "$1" == "aosp" ]; then
		echo 'ro.sf.lcd_density=160' >> $MOUNTP/build.prop
	fi
	if [ "$1" == "cm" ]; then
		echo 'ro.sf.lcd_density=180' >> $MOUNTP/build.prop
		echo 'persist.sys.lcd_density=180' >> $MOUNTP/build.prop
	fi
}

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

        ZPATH="files/$1/$2/"
        OUTPATH="$3"

        for f in $(find $ZPATH); do
                ZOUT=$(echo "$f" | sed "s|$ZPATH||")
                if [ "$ZOUT" ]; then
                        ZOUT=$OUTPATH/$ZOUT
                        if [ -d "$f" ]; then
                                mkdir -p $ZOUT
                        else
                                PERM=$(stat -Lc "%a" $f)
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
        z_umount $MOUNTP "workdir/system.img"
	clean_mountp
	clean_workdir
        exit 130
}

if [ ! -f "$AND_BUILD/system.img" ]; then
	echo "  ERROR   Could not find system.img in $FLAVOR build dir"
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
	dd if=/dev/zero bs=1M count=$SIZEDIFF 2>/dev/null >> workdir/system.img
	fsck.ext4 -fp workdir/system.img 2>/dev/null > /dev/null
	resize2fs workdir/system.img 2>/dev/null > /dev/null
	fsck.ext4 -fp workdir/system.img 2>/dev/null > /dev/null
fi

echo "  MOUNT   workdir/system.img"
mount -o loop -t ext4 workdir/system.img $MOUNTP/

detect_android_version
ANDVERS=$?

if [ "$ANDVERS" -gt "0" ]; then
	echo "  DETECT  Found Android v${ANDVERS}"
else
	echo "  ERROR   Could not detect Android version"
        z_umount $MOUNTP "workdir/system.img"
	clean_mountp
	clean_workdir
	exit 1;
fi


if [ "$(df -h | grep $MOUNTP | wc -l)" -ne "1" ]; then
	echo "  ERROR   Failed to mount system.img"
	clean_mountp
	clean_workdir
	exit 1;
fi

echo "  COPY    System files"
copy_files $ANDVERS system $MOUNTP

if [ -f "$KDIR/arch/x86/boot/bzImage" ]; then
	cd $KDIR
	scripts/z_modinst.sh nomount
	cd $THISDIR
else
	echo "  ERROR   Kernel not compiled!"
	exit 1
fi

patch_buildprop $1

z_umount $MOUNTP "workdir/system.img"

if [ "$USE_SQUASH" -eq "1" ]; then
	if [ -f "$MOUNTD/system.img" ]; then
		echo "  REMOVE  $MOUNTD/system.img";
		rm $MOUNTD/system.img
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
	echo "  COPY    workdir/system.img > $MOUNTD/system.img"
	cp workdir/system.img $MOUNTD/system.img
fi

echo "  COPY    install.img > $MOUNTD/install.img"
if [ -f "$AND_BUILD/install.img" ]; then
	cp "$AND_BUILD/install.img" "$MOUNTD/install.img"
else
	cp "files/generic/install.img" "$MOUNTD/install.img"
fi

echo "  COPY    initrd.img > $MOUNTD/initrd.img"
if [ -f "$AND_BUILD/initrd.img" ]; then
	cp "$AND_BUILD/initrd.img" "$MOUNTD/initrd.img"
else
	cp "files/generic/initrd.img" "$MOUNTD/initrd.img"
fi

echo "  COPY    boot files"
cp -r "files/generic/boot/boot" $MOUNTD
cp -r "files/generic/boot/efi" $MOUNTD

clean_workdir
mkdir workdir

echo "  COPY    ramdisk.img > workdir/ramdisk.img.gz"
cp "$AND_BUILD/ramdisk.img" "workdir/ramdisk.img.gz"

echo "  EXT     ramdisk > workdir"
cd workdir
gzip -dc ramdisk.img.gz | cpio -id 2>/dev/null > /dev/null
cd ..

PBMACH=$(find workdir |sed 's#.*/##' | grep fstab | cut -d'.' -f2-);
PBDATE=$(cat workdir/default.prop | grep ro.bootimage.build.date.utc | cut -d'=' -f2)
patch_grub $PBMACH $PBDATE

echo "  COPY    ramdisk files"
copy_files $ANDVERS root workdir

echo "  BUILD   ramdisk > $MOUNTD/ramdisk.img"
cd workdir
find . -name ramdisk.img.gz -prune -o -print | cpio --create --format='newc' 2>/dev/null | gzip -c > $MOUNTD/ramdisk.img
cd ..

clean_workdir
clean_mountp
