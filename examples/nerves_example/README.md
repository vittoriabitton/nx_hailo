# NervesExample

YOLOv8 object detection on a Raspberry Pi 5 with a Hailo AI HAT, built with
[Nerves](https://nerves-project.org/).

The firmware carries `nx_hailo` and the handful of functions the demo needs —
loading the model, opening the camera, preparing frames, drawing boxes. A
Livebook attached to the running device drives them; see
[`livebooks/remote_device_inference.livemd`](livebooks/remote_device_inference.livemd).

## What you need

- A Raspberry Pi 5 with a Hailo-8 accelerator (`config/config.exs` sets
  `config :nx_hailo, :target, "hailo8"` — change it if yours differs)
- A camera the Pi exposes at `/dev/video*`
- An SSH public key in `~/.ssh`, which the build uses to authorize firmware
  updates and the IEx prompt

## Build and burn

```shell
export MIX_TARGET=rpi5
mix deps.get
mix firmware
mix burn
```

Later updates can go over the network instead of the SD card:

```shell
mix upload nerves.local
```

## Run the demo

Put a compiled model and its class labels in `priv/` on the device — the
`download_models` notebook in the `nx_hailo` repository does both — then follow
the setup steps in
[`livebooks/remote_device_inference.livemd`](livebooks/remote_device_inference.livemd).

## Learn more

- Nerves docs: https://hexdocs.pm/nerves/getting-started.html
- Supported targets: https://hexdocs.pm/nerves/supported-targets.html
- Elixir Slack `#nerves`: https://elixir-slack.community/
