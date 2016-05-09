#!/system/bin/sh
# Disable Internal Mic
alsa_amixer -c0 sset 'Stereo ADC MIXL ADC1' off
alsa_amixer -c0 sset 'Stereo ADC MIXR ADC1' off
alsa_amixer -c0 sset 'Internal Mic' off
