# NxHailo

## Building via Ubuntu on UTM (macOS)

- Install elixir and erlang
- Setup github SSH keys
- Clone this repository
- Set the environment variables:

```shell
export MIX_TARGET=hailo_rpi5
export XLA_TARGET_PLATFORM=aarch64-linux-gnu
export EXLA_FORCE_REBUILD=false
export EVISION_PREFER_PRECOMPILED=false
```

- If OpenCV fails, go into the Evision deps folder and edit the download scrips to have the --no-check-certificate option

- To ensure hailort is included, run `mix nerves.system.shell`. This will build the firmware and then give you a command to go into the build directory. From there:
  - `make hailort`
  - `make defconfig`
  - `make all`

- The SD card must either be:
  - read via an USB reader and mounted to UTM; OR
  - mounted via the SD card reader on the Macbook and then the device file pointer must be added to the shared directory for UTM

- `sudo chown $USER:disk <sd card device>` to remove the need for `sudo`
- `mix firmware`
- `mix burn`

- For `mix upload`, use `mix upload <ip>`, because UTM lives in a different subnet and won't resolve `nerves.local`. Use `ping nerves.local` on the host OS to discover the IP address.

- To access the device from the host machine, copy over the SSH keys to the host and use `ssh -i <non .pub key path> nerves.local`

# Possible issues

- for some reason evision was seeing i686 target toolchain, so I had to manually link gcc/g++ to the proper aarch64 toolchain. This also included creating gcc-gcc and gcc-g++ links besides gcc and g++ inside the /artifacts/hailo_rpi5-portable-0.4.0/host/bin/
