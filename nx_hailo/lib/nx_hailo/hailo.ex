defmodule NxHailo.Hailo do
  @moduledoc """
  Interface for interacting with Hailo accelerators.

  This module provides high-level functions for loading models and running inference
  using Hailo AI accelerators through HailoRT.
  NOTE: This module provides a more direct NIF interaction layer.
  For a more user-friendly, higher-level API, see the main `NxHailo` module.
  """

  alias NxHailo.NIF
  # We refer to the main NxHailo module for the new top-level API if needed.
  # alias NxHailo # This line is only needed if calling functions from the main NxHailo module.

  @doc """
  Loads a network from a Hailo Executable Format (HEF) file.

  Returns a network group resource reference that can be used to create inference pipelines.
  This is a lower-level function directly interacting with NIFs.

  ## Parameters

  - `hef_path` - Path to the HEF file

  ## Examples

      {:ok, network_group} = NxHailo.Hailo.load_network("model.hef")
  """
  @spec load_network(String.t()) :: {:ok, reference()} | {:error, String.t()}
  def load_network(hef_path) when is_binary(hef_path) do
    case NIF.load_network_group(hef_path) do
      {:error, reason} -> {:error, reason}
      network_group -> {:ok, network_group}
    end
  end

  @doc """
  Creates an inference pipeline from a network group.
  This is a lower-level function directly interacting with NIFs.

  ## Parameters

  - `network_group` - Network group resource reference from `load_network/1`

  ## Examples

      {:ok, network_group} = NxHailo.Hailo.load_network("model.hef")
      {:ok, pipeline} = NxHailo.Hailo.create_pipeline(network_group)
  """
  @spec create_pipeline(reference()) :: {:ok, reference()} | {:error, String.t()}
  def create_pipeline(network_group) do
    case NIF.create_pipeline(network_group) do
      {:error, reason} -> {:error, reason}
      pipeline -> {:ok, pipeline}
    end
  end

  @doc """
  Returns information about the output vstreams of an inference pipeline.
  This is a lower-level function directly interacting with NIFs.

  ## Parameters

  - `pipeline` - Pipeline resource reference from `create_pipeline/1`

  ## Examples

      {:ok, network_group} = NxHailo.Hailo.load_network("model.hef")
      {:ok, pipeline} = NxHailo.Hailo.create_pipeline(network_group)
      {:ok, output_info} = NxHailo.Hailo.output_vstream_info(pipeline)
  """
  @spec output_vstream_info(reference()) :: {:ok, list(map())} | {:error, String.t()}
  def output_vstream_info(pipeline) do
    case NIF.get_output_vstream_infos_from_pipeline(pipeline) do
      {:error, reason} -> {:error, reason}
      info -> {:ok, info}
    end
  end

  @doc """
  Runs inference using the provided pipeline and input data.
  This is a lower-level function directly interacting with NIFs.

  ## Parameters

  - `pipeline` - Pipeline resource reference from `create_pipeline/1`
  - `input_data` - Map of input vstream names to binary data

  ## Examples

      {:ok, network_group} = NxHailo.Hailo.load_network("model.hef")
      {:ok, pipeline} = NxHailo.Hailo.create_pipeline(network_group)

      # Prepare input data
      input_data = %{"input_1" => <<...>>}

      # Run inference
      {:ok, results} = NxHailo.Hailo.infer(pipeline, input_data)
  """
  @spec infer(reference(), map()) :: {:ok, map()} | {:error, String.t()}
  def infer(pipeline, input_data) when is_map(input_data) do
    case NIF.infer(pipeline, input_data) do
      {:error, reason} -> {:error, reason}
      results -> {:ok, results}
    end
  end

  @doc """
  Convenience function to load a network, create a pipeline, and run inference in one call.
  This function now uses the top-level `NxHailo.load/1` and `NxHailo.infer/2` API.

  ## Parameters

  - `hef_path` - Path to the HEF file
  - `input_data` - Map of input vstream names to binary data

  ## Examples

      # Run inference directly
      {:ok, results} = NxHailo.Hailo.run_inference("model.hef", %{"input_1" => <<...>>})
  """
  @spec run_inference(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  def run_inference(hef_path, input_data) when is_binary(hef_path) and is_map(input_data) do
    # Ensure the main NxHailo module is aliased if not already globally available
    # or use fully qualified NxHailo.load and NxHailo.infer if prefered.
    # Assuming Elixir's default module resolution or a project-wide alias for NxHailo.
    with {:ok, model} <- NxHailo.load(hef_path),
         {:ok, results} <- NxHailo.infer(model, input_data) do
      {:ok, results}
    else
      # Propagate errors from load or infer
      {:error, _reason} = error -> error
      # Handle any other unexpected non-error tuple from with (should not happen with ok/error tuples)
      other_error -> {:error, "Unexpected error in run_inference: #{inspect(other_error)}"}
    end
  end
end
