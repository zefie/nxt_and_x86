#!/system/bin/sh
# Enable Internal Mic
alsa_amixer -c0 sset 'Internal Mic' on
alsa_amixer -c0 sset 'IN1 Boost' 3
alsa_amixer -c0 sset 'RECMIXL BST1' on
alsa_amixer -c0 sset 'RECMIXR BST1' on

alsa_amixer -c0 sset 'Stereo ADC1 Mux' ADC
alsa_amixer -c0 sset 'Stereo ADC MIXL ADC1' on
alsa_amixer -c0 sset 'Stereo ADC MIXR ADC1' on
