# iDAC

i(Pad)?OS Devices as a DAC.

## Setup with PulseAudio

with iDAC, you can use iOS device as PulseAudio DAC.

1. Install iproxy command (in Arch Linux, package name is `libusbmuxd`)
1. Launch iproxy by `iproxy 48000:48000`
    - If connected two or more devices to your computer, you may need to specify device UUID that running iDAC in iproxy options. please check iproxy help.
1. Create null sink that provide sounds to iDAC. (if you want to hear already exists output monitor device in iDAC, please skip this step)
    - `pactl load-module module-null-sink sink_name=iDAC_Output sink_properties=device.description=iDAC_Output format=float32le channels=2 rate=48000`
    - If successful, pactl shows number (that is module number, you can unload module with `pactl unload-module NUMBER`).
1. Create null sink that outputs microphone sounds from iDAC.
    - `pactl load-module module-null-sink sink_name=iDAC_Input sink_properties=device.description=iDAC_Input format=float32le channels=1 rate=48000`
    - If successful, pactl shows number (that is module number, you can unload module with `pactl unload-module NUMBER`).
1. Launch iDAC App
1. Run command
    - `parec --rate=48000 --format=float32le --channels=2 --device=iDAC_Output.monitor --latency-msec=1 | nc localhost 48000 | pacat --rate=48000 --format=float32le --channels=1 --latency-msec=10 --device=iDAC_Input`
1. Set output device to `iDAC_Output` and input device to `Monitor of iDAC_Input` or `iDAC_Input.monitor`.

### Know Issues with PulseAudio

- sometimes usbmuxd using 100% CPU
    - workaround: disconnect & connect USB cable, then `sudo killall usbmuxd`
- some Linux applications (e.g. Discord) cant show iDAC_Input device
    - workaround: Use PulseAudio's `module-remap-source`.
    - Run `pactl load-module module-remap-source master=iDAC_Input.monitor source_name="iDAC_Input_Remapped"` and use `Remapped of Monitor of iDAC_Input` as input device.
