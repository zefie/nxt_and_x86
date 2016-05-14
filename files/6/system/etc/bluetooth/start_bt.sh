#!/bin/bash
#
# Shell script to install Bluetooth firmware and attach BT part of
# RTL8723BS

TTY="/dev/ttyS1"
/system/xbin/hciattach -n -s 115200 $TTY rtk_h5 > /hciattach.txt 2>&1 &
