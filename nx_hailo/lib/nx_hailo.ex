defmodule NxHailo do
  @moduledoc """
  Top-level API for Hailo integration with Nx.
  Provides simple functions to load models and run inference.
  """

  alias NxHailo.API

  defmodule Model do
    @moduledoc """
    Represents a loaded Hailo model, ready for inference.
    This struct encapsulates the inference pipeline and associated metadata.
    """
    defstruct pipeline: nil, # Holds an %NxHailo.API.InferPipeline{}
              name: nil,     # e.g., HEF filename or a custom model name
              input_infos: [], # List of input vstream info maps (name, frame_size, etc.)
              output_infos: [] # List of output vstream info maps
  end

  @doc """
  Loads a Hailo model from a HEF file and prepares it for inference.

  This function handles VDevice creation, network configuration, and pipeline setup.

  Parameters:
    - `hef_path`: The path to the .hef model file.
    - `model_name` (optional): A name to associate with the loaded model.

  Returns `{:ok, %NxHailo.Model{}}` or `{:error, reason}`.
  """
  def load(hef_path, model_name \\ nil) when is_binary(hef_path) do
    with {:ok, vdevice} <- API.create_vdevice(),
         {:ok, ng} <- API.configure_network_group(vdevice, hef_path),
         {:ok, pipeline_struct} <- API.create_pipeline(ng) do
      model = %Model{
        pipeline: pipeline_struct,
        name: model_name || Path.basename(hef_path),
        input_infos: pipeline_struct.input_vstream_infos,
        output_infos: pipeline_struct.output_vstream_infos
      }
      {:ok, model}
    else
      # Consolidate error handling if needed, or pass through NIF/API errors
      {:error, reason} -> {:error, reason}
      error_tuple -> error_tuple # For other unexpected error formats
    end
  end

  @doc """
  Runs inference on a previously loaded Hailo model.

  Parameters:
    - `model`: The `%NxHailo.Model{}` struct obtained from `load/1`.
    - `inputs`: A map where keys are input vstream names (strings or atoms)
      and values are binaries containing the input data.
      Example: `%{ "input_layer_name" => <<...>> }` or `%{ input_layer_name: <<...>> }`

  Returns `{:ok, output_data_map}` or `{:error, reason}`.
  The `output_data_map` will have string keys for output vstream names.
  """
  def infer(%Model{pipeline: pipeline_struct} = _model, inputs) when is_map(inputs) do
    # The API.infer function expects string keys for input map.
    # We can be flexible and convert atom keys here if necessary,
    # or enforce string keys in the doc/spec for this top-level infer.
    # For now, assume API.infer's validation handles it or user provides string keys.
    API.infer(pipeline_struct, inputs)
  end
end
