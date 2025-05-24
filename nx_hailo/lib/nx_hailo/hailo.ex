defmodule NxHailo.Hailo do
  @moduledoc """
  Interface for interacting with Hailo accelerators.

  This module provides high-level functions for loading models and running inference
  using Hailo AI accelerators through HailoRT.
  """

  alias NxHailo.NIF

  @doc """
  Loads a network from a Hailo Executable Format (HEF) file.

  Returns a network group resource reference that can be used to create inference pipelines.

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

  The pipeline is optimized for inference and handles the data flow between
  host and device.

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

  This information includes the name and frame size of each output vstream.

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

  The input data should be a map where keys are input vstream names and values are binaries
  containing the raw input data. The function returns a map with output vstream names
  as keys and binaries of output data as values.

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

  ## Parameters

  - `hef_path` - Path to the HEF file
  - `input_data` - Map of input vstream names to binary data

  ## Examples

      # Run inference directly
      {:ok, results} = NxHailo.Hailo.run_inference("model.hef", %{"input_1" => <<...>>})
  """
  @spec run_inference(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  def run_inference(hef_path, input_data) when is_binary(hef_path) and is_map(input_data) do
    with {:ok, network_group} <- load_network(hef_path),
         {:ok, pipeline} <- create_pipeline(network_group),
         {:ok, results} <- infer(pipeline, input_data) do
      {:ok, results}
    end
  end
end
