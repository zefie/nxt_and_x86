#
# Copyright (C) 2013 The Android-x86 Open Source Project
#
# License: GNU Public License v2 or later
#

function init_misc()
{
	# a hack for USB modem
	lsusb | grep 1a8d:1000 && eject

	# in case no cpu governor driver autoloads
	[ -d /sys/devices/system/cpu/cpu0/cpufreq ] || modprobe acpi-cpufreq
	modprobe ak8975
}

function init_hal_audio() {
{
       case "$PRODUCT" in
                VirtualBox*|Bochs*)
                        [ -d /proc/asound/card0 ] || modprobe snd-sb16 isapnp=0 irq=5
                        ;;
                NXW101QC232)
                        modprobe snd-intel-sst-acpi
                        source /system/etc/alsa/alsa_cr.sh
                        source /system/etc/alsa/alsa_cr_spk.sh
                        source /system/etc/alsa/alsa_cr_intmic_on.sh
                        ;;
                *)
                        ;;
        esac
}

function init_hal_bluetooth()
{
	for r in /sys/class/rfkill/*; do
		type=$(cat $r/type)
		[ "$type" = "wlan" -o "$type" = "bluetooth" ] && echo 1 > $r/state
	done

	# these modules are incompatible with bluedroid
	rmmod ath3k
	rmmod btusb
	rmmod bluetooth
	set_property ro.rfkilldisabled 1

        case "$PRODUCT" in
                NXW101QC232)
                        source /etc/bluetooth/start_bt.sh
                        ;;
        esac

}

function init_hal_bluetooth()
{
	for r in /sys/class/rfkill/*; do
		type=$(cat $r/type)
		[ "$type" = "wlan" -o "$type" = "bluetooth" ] && echo 1 > $r/state
	done
	modprobe ak8975
	modprobe hci-uart
	BTUART_PORT=/dev/ttyS1
	brcm_patchram_plus -d --no2bytes --enable_hci --patchram /system/lib/firmware/brcm/bcm43241b4.hcd $BTUART_PORT
	set_property hal.bluetooth.uart $BTUART_PORT
	chown bluetooth.bluetooth $BTUART_PORT
	log -t hciconfig -p i "`hciconfig`"
}

function init_hal_camera()
{
	[ -c /dev/video0 ] || modprobe vivi
}

function init_hal_gps()
{
	# TODO
	return
}


function init_hal_hwcomposer()
{
	# TODO
	return
}

function init_hal_lights()
{
	chown 1000.1000 /sys/class/backlight/*/brightness
}

function init_hal_power()
{
	for p in /sys/class/rtc/*; do
		echo disabled > $p/device/power/wakeup
	done

	# TODO
	case "$PRODUCT" in
		*)
			;;
	esac
}

function init_cpu_governor()
{
	governor=$(getprop cpu.governor)

	[ $governor ] && {
		for cpu in $(ls -d /sys/devices/system/cpu/cpu?); do
			echo $governor > $cpu/cpufreq/scaling_governor || return 1
		done
	}
}

function do_init()
{
	busybox chown -R 1000.1000 /sys/bus/iio/devices/iio:device*/
	init_misc
	init_hal_audio
	init_hal_bluetooth
	init_hal_camera
	#init_hal_gps
	#init_hal_hwcomposer
	init_hal_lights
	init_hal_power
	post_init
}

function do_netconsole()
{
	modprobe netconsole netconsole="@/,@$(getprop dhcp.eth0.gateway)/"
}

function do_bootcomplete()
{
	init_cpu_governor

	[ -z "$(getprop persist.sys.root_access)" ] && setprop persist.sys.root_access 3

	# FIXME: autosleep works better on i965?
	[ "$(getprop debug.mesa.driver)" = "i965" ] && setprop debug.autosleep 1

	lsmod | grep -e brcmfmac && setprop wlan.no-unload-driver 1

#	for bt in $(lsusb -v | awk ' /Class:.E0/ { print $9 } '); do
#		chown 1002.1002 $bt && chmod 660 $bt
#	done

#	[ -d /proc/asound/card0 ] || modprobe snd-dummy
	for c in $(grep '\[.*\]' /proc/asound/cards | awk '{print $1}'); do
		f=/system/etc/alsa/$(cat /proc/asound/card$c/id).state
		if [ -e $f ]; then
			alsa_ctl -f $f restore $c
		else
			alsa_ctl init $c
			alsa_amixer -c $c set Master on
			alsa_amixer -c $c set Master 100%
			alsa_amixer -c $c set Headphone on
			alsa_amixer -c $c set Headphone 100%
			alsa_amixer -c $c set Speaker 80%
			alsa_amixer -c $c set Capture 100%
			alsa_amixer -c $c set Capture cap
			alsa_amixer -c $c set PCM 100 unmute
			alsa_amixer -c $c set 'Mic Boost' 3
			alsa_amixer -c $c set 'Internal Mic Boost' 3
		fi
	done
}

PATH=/system/bin:/system/xbin

DMIPATH=/sys/class/dmi/id
BOARD=$(cat $DMIPATH/board_name)
PRODUCT=$(cat $DMIPATH/product_name)

# import cmdline variables
for c in `cat /proc/cmdline`; do
	case $c in
		androidboot.hardware=*)
			;;
		*=*)
			eval $c
			;;
	esac
done

[ -n "$DEBUG" ] && set -x || exec &> /dev/null

case "$1" in
	netconsole)
		do_netconsole
		;;
	bootcomplete)
		do_bootcomplete
		;;
	init|"")
		do_init
		;;
esac

return 0
