# NxHailo

Elixir library for interfacing with the [Hailo AI accelerator](https://hailo.ai/) via a NIF backed by the HailoRT C++ SDK.

## Installation

Add `nx_hailo` to your dependencies:

```elixir
# from Hex (when published)
{:nx_hailo, "~> 0.1"}

# from GitHub
{:nx_hailo, github: "vittoriabitton/nx_hailo"}
```

## Requirements

- **HailoRT** must be installed on the build host (the NIF links against `-lhailort` and includes `hailo/hailort.hpp`):
  - **Hailo-10 / Hailo-15**: use HailoRT v5 (master branch) from the [hailort repo](https://github.com/hailo-ai/hailort).
  - **Hailo-8 / 8L / 8R**: use the `hailo8` branch of HailoRT.
  - See <https://hailo.ai/developer-zone/software-downloads/> for official packages.
- If the compiler cannot find the HailoRT headers, set the include (and optionally lib) path:
  - **Environment:** `export HAILORT_INCLUDE_DIR=/path/to/include` (directory that contains a `hailo/` subdir). Optionally `export HAILORT_LIB_DIR=/path/to/lib`.
  - **Config:** in `config/config.exs`, `config :nx_hailo, :hailort_include_dir, "/path/to/include"` and optionally `:hailort_lib_dir, "/path/to/lib"`.
- Build target is chosen by `config :nx_hailo, :target, :hailo10` (default) or `:hailo8`; the matching HailoRT branch must be installed.
- Elixir ~> 1.18 / compatible OTP

## Setup

```shell
mix deps.get
mix compile
```

## Getting Models

You need a compiled `.hef` file in `priv/` before running inference.

Pre-compiled HEF files for supported Hailo devices are available in the [Hailo Model Zoo](https://github.com/hailo-ai/hailo_model_zoo). The S3 URL pattern is:

```
https://hailo-model-zoo.s3.eu-west-2.amazonaws.com/ModelZoo/Compiled/<version>/<device>/<model>.hef
```

Use the model zoo version matching your HailoRT version (`hailortcli --version`). For Hailo-10H with HailoRT 5.x, use `version=v5.x.x` and `device=hailo10h`.

For a runnable example that downloads the YOLOv8m model and generates the COCO class labels JSON, see [`livebooks/download_models.livemd`](livebooks/download_models.livemd).

## Running Livebooks

The livebooks in `livebooks/` are designed to run against an Elixir node on the device with the Hailo hardware. Use Livebook's **Attached Node** runtime to connect your local Livebook instance to the device.

### 1. Start the node on the device

```shell
./scripts/start_node.sh
# or pass the device IP explicitly:
./scripts/start_node.sh 192.168.2.4
```

The script auto-detects the IP from `eth0` (assumes the device is connected via Ethernet). If using Wi-Fi or a different interface, pass the IP explicitly as an argument.

**Environment variables (optional overrides):**

| Variable | Default | Description |
|---|---|---|
| `NODE_NAME` | `<whoami>@<eth0-ip>` | Full Erlang node name |
| `COOKIE` | node base name (part before `@`) | Erlang cookie |
| `HAILO_TARGET` | `hailo10` | Target device: `hailo10`, `hailo8`, `hailo8l`, etc. |
| `DOWNLOAD_DIR` | `<project>/priv` | Where downloaded models are saved |

### 2. Connect Livebook

Open Livebook on your machine, then for the notebook go to **Runtime → Attached Node** and enter:

- **Node:** `user@<device-ip>` (printed by the script)
- **Cookie:** `cookie`

### 3. Run the livebooks

- [`livebooks/download_models.livemd`](livebooks/download_models.livemd) — downloads a `.hef` model and COCO class labels to `priv/`
- [`livebooks/remote_device_inference.livemd`](livebooks/remote_device_inference.livemd) — runs YOLOv8 inference using the camera

## Usage

```elixir
# Load a model and run inference
{:ok, model} = NxHailo.load("priv/yolov8m.hef")
{:ok, results} = NxHailo.run(model, input_tensor)
```
