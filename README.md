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

- `libhailort` must be installed and discoverable on the build host (the NIF links against `-lhailort`)
- Elixir ~> 1.17 / compatible OTP

## Setup

```shell
mix deps.get
mix compile
```

By default, `mix compile` will download the YOLOv8m model and class labels into `priv/`. To skip this (e.g. in CI or when the models are already present):

```shell
NX_HAILO_DOWNLOAD_MODELS=false mix compile
```

## Usage

```elixir
# Load a model and run inference
{:ok, model} = NxHailo.load("priv/yolov8m.hef")
{:ok, results} = NxHailo.run(model, input_tensor)
```

See the `livebooks/` directory for runnable examples.
