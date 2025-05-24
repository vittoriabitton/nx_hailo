defmodule NxHailo.API do
  @moduledoc """
  Provides an Elixir API for interacting with Hailo devices.
  """

  alias NxHailo.NIF
  alias NxHailo.VStreamInfo

  defmodule VDevice do
    @moduledoc """
    Represents a Hailo Virtual Device.
    """
    defstruct ref: nil
  end

  defmodule ConfiguredNetworkGroup do
    @moduledoc """
    Represents a configured network group on a VDevice.
    """
    defstruct ref: nil,
              vdevice_ref: nil,
              name: nil, # Placeholder, might need to get from NIF if available
              input_vstream_infos: [],
              output_vstream_infos: []
  end

  defmodule InferPipeline do
    @moduledoc """
    Represents an inference pipeline.
    """
    defstruct ref: nil,
              network_group_ref: nil,
              input_vstream_infos: [],
              output_vstream_infos: []
  end

  @doc """
  Creates a new Hailo Virtual Device.

  Returns `{:ok, %VDevice{}}` or `{:error, reason}`.
  """
  def create_vdevice() do
    if dev = :persistent_term.get({__MODULE__, :vdevice}, nil) do
      {:ok, dev}
    else
      case NIF.create_vdevice() do
        {:ok, ref} ->
          dev = %VDevice{ref: ref}
          :persistent_term.put({__MODULE__, :vdevice}, dev)
          {:ok, dev}
        error -> error
      end
    end
  end

  @doc """
  Configures a network group on the given VDevice using a HEF file.

  Parameters:
    - `vdevice`: The `%VDevice{}` struct.
    - `hef_path`: The path to the HEF file (string).

  Returns `{:ok, %ConfiguredNetworkGroup{}}` or `{:error, reason}`.
  """
  def configure_network_group(%VDevice{ref: vdevice_ref} = _vdevice, hef_path)
      when is_binary(hef_path) do
    with {:ok, ng_ref} <- NIF.configure_network_group(vdevice_ref, hef_path),
         {:ok, raw_input_infos} <- NIF.get_input_vstream_infos_from_ng(ng_ref),
         {:ok, raw_output_infos} <- NIF.get_output_vstream_infos_from_ng(ng_ref) do

      input_infos = Enum.map(raw_input_infos, &VStreamInfo.from_map/1)
      output_infos = Enum.map(raw_output_infos, &VStreamInfo.from_map/1)

      {:ok,
       %ConfiguredNetworkGroup{
         ref: ng_ref,
         vdevice_ref: vdevice_ref,
         input_vstream_infos: input_infos,
         output_vstream_infos: output_infos
       }}
    else
      error -> error
    end
  end

  @doc """
  Creates an inference pipeline from a configured network group.

  Parameters:
    - `network_group`: The `%ConfiguredNetworkGroup{}` struct.

  Returns `{:ok, %InferPipeline{}}` or `{:error, reason}`.
  """
  def create_pipeline(%ConfiguredNetworkGroup{ref: ng_ref} = _network_group) do
    with {:ok, pipeline_ref} <- NIF.create_pipeline(ng_ref),
         {:ok, raw_input_infos} <- NIF.get_input_vstream_infos_from_pipeline(pipeline_ref),
         {:ok, raw_output_infos} <- NIF.get_output_vstream_infos_from_pipeline(pipeline_ref) do

      input_infos = Enum.map(raw_input_infos, &VStreamInfo.from_map/1)
      output_infos = Enum.map(raw_output_infos, &VStreamInfo.from_map/1)

      {:ok,
        %InferPipeline{
          ref: pipeline_ref,
          network_group_ref: ng_ref,
          input_vstream_infos: input_infos,
          output_vstream_infos: output_infos
        }}
    end
  end

  @doc """
  Runs inference on the given pipeline with the provided input data.

  Parameters:
    - `pipeline`: The `%InferPipeline{}` struct.
    - `input_data`: A map where keys are input vstream names (strings)
      and values are binaries containing the input data.
      Example: `%{ "input_layer1" => <<...>> }`

  Returns `{:ok, output_data_map}` or `{:error, reason}`.
  The `output_data_map` is a map of output vstream names (strings) to binaries.
  """
  def infer(%InferPipeline{ref: pipeline_ref, input_vstream_infos: expected_infos} = _pipeline, input_data)
      when is_map(input_data) do
    case validate_input_data(expected_infos, input_data) do
      :ok ->
        NIF.infer(pipeline_ref, input_data)
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Retrieves input vstream information for a configured resource.
  Accepts either a `%ConfiguredNetworkGroup{}` or an `%InferPipeline{}` struct.
  """
  def get_input_vstream_infos(%ConfiguredNetworkGroup{ref: ng_ref}) do
    case NIF.get_input_vstream_infos_from_ng(ng_ref) do
      {:ok, raw_infos} -> {:ok, Enum.map(raw_infos, &VStreamInfo.from_map/1)}
      error -> error
    end
  end
  def get_input_vstream_infos(%InferPipeline{ref: pipeline_ref}) do
    case NIF.get_input_vstream_infos_from_pipeline(pipeline_ref) do
      {:ok, raw_infos} -> {:ok, Enum.map(raw_infos, &VStreamInfo.from_map/1)}
      error -> error
    end
  end

  @doc """
  Retrieves output vstream information for a configured resource.
  Accepts either a `%ConfiguredNetworkGroup{}` or an `%InferPipeline{}` struct.
  """
  def get_output_vstream_infos(%ConfiguredNetworkGroup{ref: ng_ref}) do
    case NIF.get_output_vstream_infos_from_ng(ng_ref) do
      {:ok, raw_infos} -> {:ok, Enum.map(raw_infos, &VStreamInfo.from_map/1)}
      error -> error
    end
  end
  def get_output_vstream_infos(%InferPipeline{ref: pipeline_ref}) do
    case NIF.get_output_vstream_infos_from_pipeline(pipeline_ref) do
      {:ok, raw_infos} -> {:ok, Enum.map(raw_infos, &VStreamInfo.from_map/1)}
      error -> error
    end
  end

  defp validate_input_data(expected_infos, input_data) do
    expected_names = Enum.map(expected_infos, &(&1.name))
    provided_names = Map.keys(input_data)

    missing_streams = Enum.filter(expected_names, fn name -> not Enum.member?(provided_names, name) end)
    extra_streams = Enum.filter(provided_names, fn name -> not Enum.member?(expected_names, name) end)

    cond do
      length(missing_streams) > 0 ->
        {:error, "Missing input for vstreams: #{inspect(missing_streams)}"}
      length(extra_streams) > 0 ->
        {:error, "Extra input for vstreams: #{inspect(extra_streams)}"}
      true ->
        Enum.reduce_while(expected_infos, :ok, fn expected_info, _acc ->
          stream_name = expected_info.name
          expected_size = expected_info.frame_size
          actual_data = input_data[stream_name]

          unless is_binary(actual_data) do
            {:stop, {:error, "Input data for vstream '#{stream_name}' must be a binary."}}
          else
            if byte_size(actual_data) != expected_size do
              {:stop, {:error, "Invalid input data size for vstream '#{stream_name}'. Expected: #{expected_size}, Got: #{byte_size(actual_data)}"}}
            else
              {:cont, :ok}
            end
          end
        end)
    end
  end
end