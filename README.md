# NxHailo

Run neural networks on a [Hailo](https://hailo.ai/) AI accelerator from Elixir.

NxHailo is a NIF over the HailoRT C++ SDK. You hand it an `Nx` tensor, it runs a
model on the accelerator and hands the results back.

```elixir
{:ok, model} = NxHailo.load("priv/yolov8m.hef")

[input] = model.pipeline.input_vstream_infos
[output] = model.pipeline.output_vstream_infos

{:ok, detections} =
  NxHailo.infer(model, %{input.name => frame}, NxHailo.Parsers.YoloV8,
    classes: classes,
    key: output.name
  )
```

## What you need

**HailoRT, on the machine that builds the NIF.** Which version depends on the
accelerator, and the two are not interchangeable:

| Accelerator | HailoRT |
|---|---|
| Hailo-10, Hailo-15 | v5 (`master` branch of [hailort](https://github.com/hailo-ai/hailort)) |
| Hailo-8, 8L, 8R | the `hailo8` branch |

Official packages are at
<https://hailo.ai/developer-zone/software-downloads/>.

**Elixir 1.18 or later**, on a compatible OTP.

## Setup

Add the dependency:

```elixir
# from Hex (when published)
{:nx_hailo, "~> 0.1"}

# from GitHub
{:nx_hailo, github: "vittoriabitton/nx_hailo"}
```

Then say which accelerator you have. There is no default — the wrong backend
builds a NIF that loads and then fails at inference time, so the build stops
rather than guess:

```elixir
# config/config.exs
config :nx_hailo, :target, "hailo10"
```

Valid targets are `hailo8`, `hailo8l`, `hailo8r`, `hailo10`, `hailo10h`,
`hailo15`, `hailo15h` and `hailo15l`.

If HailoRT is not on the default search path, point the build at it, either
through the environment:

```shell
export HAILORT_INCLUDE_DIR=/path/to/include   # the directory containing hailo/
export HAILORT_LIB_DIR=/path/to/lib           # the directory containing libhailort.so
```

or through config:

```elixir
config :nx_hailo, :hailort_include_dir, "/path/to/include"
config :nx_hailo, :hailort_lib_dir, "/path/to/lib"
```

Then build:

```shell
mix deps.get
mix compile
```

## Getting models

Models are compiled ahead of time into `.hef` files. Pre-compiled ones for every
supported accelerator are in the
[Hailo Model Zoo](https://github.com/hailo-ai/hailo_model_zoo), served from S3:

```
https://hailo-model-zoo.s3.eu-west-2.amazonaws.com/ModelZoo/Compiled/<version>/<device>/<model>.hef
```

Use the model zoo version matching your HailoRT (`hailortcli --version`). For a
Hailo-10H on HailoRT 5.x that means `version=v5.1.0` and `device=hailo10h`.

[`livebooks/download_models.livemd`](livebooks/download_models.livemd) downloads
a model and writes the matching COCO class labels next to it.

## Running on a device

The accelerator lives on the device — a Raspberry Pi, say — so the code has to
run there too. The notebooks in `livebooks/` are written for Livebook's
**Attached Node** runtime: Livebook stays on your machine, the code runs on the
device.

Start a node there:

```shell
./scripts/start_node.exs
```

It picks up the device's `eth0` address and prints the node name and a freshly
generated cookie. Pass `--node-ip` if the device is on Wi-Fi or another
interface, and `--short-names` if you are attaching from the Livebook desktop
app.

| Option | Default | What it does |
|---|---|---|
| `--node-ip` | the `eth0` address | Address to reach the node on |
| `--node-name` | `<whoami>@<node-ip>` | Full node name |
| `--cookie` | randomly generated | Erlang cookie |
| `--hailo-target` | `hailo10` | Which accelerator to build for |
| `--download-dir` | `<project>/priv` | Where notebooks save models |
| `--short-names` | off | Use short names instead of long ones |

Anyone who can reach the node and knows its cookie can run code on the device,
so treat the cookie as a password and keep the device off untrusted networks.

Then open a notebook, choose **Runtime → Attached Node**, and give it the node
name and cookie the script printed:

- [`download_models.livemd`](livebooks/download_models.livemd) — fetch a model
  and its class labels
- [`remote_device_inference.livemd`](livebooks/remote_device_inference.livemd) —
  YOLOv8 on a camera feed
- [`concurrent_inference.livemd`](livebooks/concurrent_inference.livemd) — two
  models sharing the accelerator

[`examples/nerves_example`](examples/nerves_example) is the same idea as a
Nerves firmware.

## Several models at once

One accelerator can hold more than one model. Create the VDevice yourself with
the round-robin scheduler, configure each model on it, and give each its own
pipeline:

```elixir
{:ok, vdevice} = NxHailo.API.create_vdevice(%{scheduling_algorithm: :round_robin})

{:ok, ng} = NxHailo.API.configure_network_group(vdevice, "priv/yolov8m.hef")
{:ok, pipeline} = NxHailo.API.create_pipeline(ng)
```

Calls on separate pipelines overlap, and HailoRT decides how the accelerator is
split between them. Calls on a single pipeline queue up. `NxHailo.API` has the
details, including the scheduler knobs that trade latency for throughput.

## Development

The test suite covers the Elixir side — encoding, validation, output parsing —
so it needs neither HailoRT nor an accelerator, and `mix test` runs anywhere:

```shell
mix test
```

To compile without building the NIF outside the test environment, for instance
to read the docs on a laptop:

```shell
NX_HAILO_SKIP_NIF=1 mix compile
```

## License

MIT. See [LICENSE](LICENSE).
