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

- `libhailort` version `4.22` must be installed and discoverable on the build host (the NIF links against `-lhailort`)
  - See the official website for downloads: <https://hailo.ai/developer-zone/software-downloads/>
  - For compiling on macOS, the suggested setup is to setup a Linux VM with Debian
  - To burn the firmware from the VM, first build it with the proper `mix firmware --output=<path>` call, copy it to the host OS and then use `fwup -a -i your_firmware.fw -t complete -d <device path>` with the correct firmware filename and device path.
- Elixir ~> 1.17 / compatible OTP

## Setup

```shell
mix deps.get
mix compile
```

## Getting Models

You need to obtain a compiled `.hef` file and place it in `priv/` before running inference.

Pre-compiled HEF files for supported Hailo devices can be found in the [Hailo Model Zoo](https://github.com/hailo-ai/hailo_model_zoo). Look under the `hailo_models/` directory or refer to the S3 URLs referenced in the model zoo configuration files.

For a runnable example that downloads the YOLOv8m model and generates the COCO class labels JSON, see [`livebooks/download_models.livemd`](livebooks/download_models.livemd).

## Usage

```elixir
# Load a model and run inference
{:ok, model} = NxHailo.load("priv/yolov8m.hef")
{:ok, results} = NxHailo.run(model, input_tensor)
```

See the `livebooks/` directory for runnable examples.
