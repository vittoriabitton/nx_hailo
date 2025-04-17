# NxHailo

## Building via Ubuntu on UTM (macOS)

- Install elixir and erlang
- Setup github SSH keys
- Clone this repository
- Set the environment variables:

```shell
export MIX_TARGET=hailo_rpi5
export XLA_TARGET_PLATFORM=aarch64-linux-gnu
export EXLA_FORCE_REBUILD=true
export EVISION_PREFER_PRECOMPILED=false
```

- If OpenCV fails, go into the Evision deps folder and edit the download scrips to have the --no-check-certificate option

- The SD card must either be:
  - read via an USB reader and mounted to UTM; OR
  - mounted via the SD card reader on the Macbook and then the device file pointer must be added to the shared directory for UTM

- `sudo chown $USER:disk <sd card device>` to remove the need for `sudo`
- `mix firmware`
- `mix burn`