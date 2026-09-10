defmodule NxHailo do
  @moduledoc """
  Run neural networks on a [Hailo](https://hailo.ai/) accelerator from Elixir.

  Load a compiled model, hand it a tensor, get detections back:

      {:ok, model} = NxHailo.load("priv/yolov8m.hef")

      [input] = model.pipeline.input_vstream_infos
      [output] = model.pipeline.output_vstream_infos

      {:ok, detections} =
        NxHailo.infer(model, %{input.name => frame}, NxHailo.Parsers.YoloV8,
          classes: classes,
          key: output.name
        )

  Models are compiled ahead of time into `.hef` files — see the README for where
  to get them. A model holds onto the accelerator until it is garbage collected,
  so keep it around for as long as you are running frames through it.

  For several models sharing one accelerator, see `NxHailo.API`.
  """

  alias NxHailo.API
  alias NxHailo.Input
  alias NxHailo.Model

  @load_opts [:name, :scheduling_algorithm, :scheduler_timeout_ms, :scheduler_threshold]

  @doc """
  Loads a compiled model from a `.hef` file.

  Opens the accelerator if it is not open already, loads the network, and builds
  the pipeline to run frames through.

  ## Options

    * `:name` - what to call the model. Defaults to the file name.
    * `:scheduling_algorithm` - `:round_robin` or `:none`. Belongs to the
      accelerator rather than this model, so it only takes effect on the call
      that opens it. See `NxHailo.API.create_vdevice/1`.
    * `:scheduler_timeout_ms` - dispatch after this many milliseconds even if
      fewer than `:scheduler_threshold` frames have queued up.
    * `:scheduler_threshold` - how many frames to queue before dispatching.

  The scheduler options only do anything when several models share a
  round-robin accelerator.
  """
  @spec load(Path.t(), keyword()) :: {:ok, Model.t()} | {:error, String.t()}
  def load(hef_path, opts \\ []) when is_binary(hef_path) and is_list(opts) do
    opts = Keyword.validate!(opts, @load_opts)
    {name, opts} = Keyword.pop(opts, :name, Path.basename(hef_path))
    {vdevice_opts, network_group_opts} = Keyword.split(opts, [:scheduling_algorithm])

    with {:ok, vdevice} <- API.create_vdevice(Map.new(vdevice_opts)),
         {:ok, network_group} <-
           API.configure_network_group(vdevice, hef_path, Map.new(network_group_opts)),
         {:ok, pipeline} <- API.create_pipeline(network_group) do
      {:ok, %Model{pipeline: pipeline, name: name}}
    end
  end

  @doc """
  Runs one frame through `model` and parses the result.

  `inputs` maps input vstream names to tensors, one per input vstream. Each
  tensor has to carry the type and byte size that vstream was configured for —
  read them off `model.pipeline.input_vstream_infos`.

  `output_parser` is a module implementing `NxHailo.OutputParser`; the raw
  output of a Hailo model is model-specific, so it needs one that matches.
  `output_parser_opts` is passed straight through to it.

  Calls on one model are serialized. To run models side by side, give each its
  own pipeline on a round-robin accelerator — see `NxHailo.API`.
  """
  @spec infer(Model.t(), %{optional(String.t()) => Nx.Tensor.t()}, module(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def infer(%Model{pipeline: pipeline}, inputs, output_parser, output_parser_opts \\ [])
      when is_map(inputs) and is_atom(output_parser) do
    with {:ok, encoded} <- Input.encode(pipeline.input_vstream_infos, inputs),
         {:ok, outputs} <- API.infer(pipeline, encoded) do
      output_parser.parse(outputs, output_parser_opts)
    end
  end
end
