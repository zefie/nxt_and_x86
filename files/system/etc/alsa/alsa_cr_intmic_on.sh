#!/system/bin/sh

# Enable Internal Mic
alsa_amixer -c0 sset 'IN3 Boost' 3
alsa_amixer -c0 sset 'RECMIXL BST3' on
alsa_amixer -c0 sset 'RECMIXR BST3' on
alsa_amixer -c0 sset 'Stereo ADC1 Mux' ADC
alsa_amixer -c0 sset 'Stereo ADC MIXL ADC1' on
alsa_amixer -c0 sset 'Stereo ADC MIXR ADC1' on
alsa_amixer -c0 sset 'ADC' 50%
alsa_amixer -c0 sset 'ADC Boost Gain' 1
alsa_amixer -c0 sset 'Internal Mic' on
