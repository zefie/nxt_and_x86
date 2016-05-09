#!/system/bin/sh

checkbit(){
	[ $(( $1 & $(( 1 << $2 )) )) != 0 ]
}

setparm(){
	# only set param if it changed, hopefully to lower healthd dmesg spam
	if [ "$(cat $2)" != "$1" ]; then echo $1 > $2; fi
}

rmmod -f battery > /dev/null 2>&1
modprobe i2c-dev
modprobe test_power
export ADDR=4

setparm off /sys/module/test_power/parameters/usb_online
setparm LION /sys/module/test_power/parameters/battery_technology

while true
do
	rmmod battery 2>/dev/null # in case it reloaded
	source_status_reg=$(i2cget -f -y $ADDR 0x34 0x00)
	charger_status_reg=$(i2cget -f -y $ADDR 0x34 0x01)

	if checkbit $source_status_reg 4
	then
		setparm on /sys/module/test_power/parameters/ac_online
		if checkbit $charger_status_reg 6
		then
			setparm charging /sys/module/test_power/parameters/battery_status
		else
			setparm not-charging /sys/module/test_power/parameters/battery_status
		fi
	else
		setparm off /sys/module/test_power/parameters/ac_online
		setparm discharging /sys/module/test_power/parameters/battery_status
	fi
	hex=$(i2cget -f -y $ADDR 0x34 0xb9 | cut -c 3- | tr a-z A-Z)
	capacity=$(expr $(hex2dec $hex | cut -d' ' -f2) - 128)
	if [ $capacity -ge 0 ]
	then
		setparm $capacity /sys/module/test_power/parameters/battery_capacity
	fi
	sleep 10
done
