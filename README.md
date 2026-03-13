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
