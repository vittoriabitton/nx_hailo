defmodule NxHailo.Tensor do
  @moduledoc """
  Integration with Nx for tensor operations on Hailo hardware.

  This module provides functions to run inference on Hailo hardware
  with Nx tensors as inputs and outputs.
  """

  alias NxHailo.Hailo

  @doc """
  Runs inference on Hailo hardware with Nx tensors.

  Takes Nx tensors as input and returns Nx tensors as output.

  ## Parameters

  - `pipeline` - Pipeline resource reference from `Hailo.create_pipeline/1`
  - `input_tensors` - Map of input vstream names to Nx tensors

  ## Examples

      {:ok, network_group} = NxHailo.Hailo.load_network("model.hef")
      {:ok, pipeline} = NxHailo.Hailo.create_pipeline(network_group)

      # Prepare input tensors
      input_tensors = %{"input_1" => Nx.tensor([[1, 2], [3, 4]])}

      # Run inference
      {:ok, result_tensors} = NxHailo.Tensor.infer(pipeline, input_tensors)
  """
  @spec infer(reference(), map()) :: {:ok, map()} | {:error, String.t()}
  def infer(pipeline, input_tensors) when is_map(input_tensors) do
    # Convert Nx tensors to binaries
    input_binaries =
      input_tensors
      |> Enum.map(fn {name, tensor} -> {name, tensor_to_binary(tensor)} end)
      |> Map.new()

    # Run inference
    with {:ok, output_binaries} <- Hailo.infer(pipeline, input_binaries),
         {:ok, output_info} <- Hailo.output_vstream_info(pipeline) do
      # Convert output binaries back to tensors
      output_tensors =
        output_info
        |> Enum.map(fn %{name: name, frame_size: size} ->
          binary = Map.get(output_binaries, name)
          {name, binary_to_tensor(binary, size)}
        end)
        |> Map.new()

      {:ok, output_tensors}
    end
  end

  @doc """
  Runs model inference directly from a HEF file with Nx tensors.

  ## Parameters

  - `hef_path` - Path to the HEF file
  - `input_tensors` - Map of input vstream names to Nx tensors

  ## Examples

      # Run inference with tensors
      {:ok, result_tensors} = NxHailo.Tensor.run_inference("model.hef", %{"input_1" => input_tensor})
  """
  @spec run_inference(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  def run_inference(hef_path, input_tensors) when is_binary(hef_path) and is_map(input_tensors) do
    with {:ok, network_group} <- Hailo.load_network(hef_path),
         {:ok, pipeline} <- Hailo.create_pipeline(network_group),
         {:ok, results} <- infer(pipeline, input_tensors) do
      {:ok, results}
    end
  end

  # Helper function to convert Nx tensor to binary
  defp tensor_to_binary(tensor) do
    tensor
    |> Nx.as_type({:u, 8})
    |> Nx.to_binary()
  end

  # Helper function to convert binary back to tensor
  # This is a simplified version; in a real implementation, you'd need to know
  # the expected shape and type of the output tensor
  defp binary_to_tensor(binary, _size) do
    # For now, just create a flat tensor of bytes
    # In a real implementation, you would reshape this based on the model's output shape
    Nx.from_binary(binary, {:u, 8})
  end
end
