# NxHailo

## Installing in your project

If installing as a Git dependency, you should make sure that the `:sparse` option
is used:

```elixir
[
  {:nx_hailo, github: "vittoriabitton/nx_hailo", sparse: "nx_hailo"}
]
```

## Building (macOS via Ubuntu on UTM or Docker)

- Install elixir and erlang
- Setup github SSH keys
- Clone this repository
- Set the environment variables:

```shell
export MIX_TARGET=rpi5
export XLA_TARGET_PLATFORM=aarch64-linux-gnu
export EXLA_FORCE_REBUILD=false
export EVISION_PREFER_PRECOMPILED=true
```

- `mix deps.get`
- `mix firmware`
- If OpenCV fails, go into the Evision deps folder and edit the download scrips to have the --no-check-certificate option

- The SD card must either be:
  - read via an USB reader and mounted to UTM; OR
  - mounted via the SD card reader on the Macbook and then the device file pointer must be added to the shared directory for UTM

- `sudo chown $USER:disk <sd card device>` to remove the need for `sudo`
- `mix burn`

- For `mix upload`, use `mix upload <ip>`, because UTM lives in a different subnet and won't resolve `nerves.local`. Use `ping nerves.local` on the host OS to discover the IP address.

- To access the device from the host machine, copy over the SSH keys to the host and use `ssh -i <non .pub key path> nerves.local`

# Possible issues

- for some reason evision was seeing i686 target toolchain, so I had to manually link gcc/g++ to the proper aarch64 toolchain. This also included creating gcc-gcc and gcc-g++ links besides gcc and g++ inside the /artifacts/hailo_rpi5-portable-0.4.0/host/bin/
