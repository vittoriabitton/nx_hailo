defmodule NxHailo.API do
  @moduledoc false
  # Internal API for interacting with Hailo devices.

  alias NxHailo.NIF
  alias NxHailo.API.VDevice
  alias NxHailo.API.NetworkGroup
  alias NxHailo.API.Pipeline
  alias NxHailo.API.VStreamInfo

  @doc """
  Creates a new Hailo Virtual Device.

  Returns `{:ok, %VDevice{}}` or `{:error, reason}`.
  """
  def create_vdevice(), do: create_vdevice(%{})

  @doc """
  Creates a new Hailo Virtual Device with scheduling configuration.

  Options (hailo8 only — ignored on hailo10 where scheduling is per-model):
    - `:scheduling_algorithm` — `:round_robin` (default) or `:none`

  Returns `{:ok, %VDevice{}}` or `{:error, reason}`.
  """
  def create_vdevice(opts) when is_map(opts) do
    cached = :persistent_term.get({__MODULE__, :vdevice}, nil)

    # Only use the cached vdevice if no options were given; a caller providing
    # opts (e.g. scheduling_algorithm) wants a vdevice configured accordingly.
    if cached && opts == %{} do
      {:ok, cached}
    else
      case NIF.create_vdevice(opts) do
        {:ok, ref} ->
          dev = %VDevice{ref: ref}
          # Only cache the default (no-opts) vdevice; opts-specific vdevices
          # are caller-managed to avoid hiding scheduling config mismatches.
          if opts == %{}, do: :persistent_term.put({__MODULE__, :vdevice}, dev)
          {:ok, dev}

        error ->
          error
      end
    end
  end

  @doc """
  Configures a network group on the given VDevice using a HEF file.

  Parameters:
    - `vdevice`: The `%VDevice{}` struct.
    - `hef_path`: The path to the HEF file (string).

  Returns `{:ok, %NetworkGroup{}}` or `{:error, reason}`.
  """
  def configure_network_group(%VDevice{} = vdevice, hef_path) when is_binary(hef_path),
    do: configure_network_group(vdevice, hef_path, %{})

  @doc """
  Configures a network group on the given VDevice using a HEF file, with scheduling options.

  Parameters:
    - `vdevice`: The `%VDevice{}` struct.
    - `hef_path`: The path to the HEF file (string).
    - `opts`: A map of scheduling options.

  hailo10 options (applied before `configure()` — cannot be changed after):
    - `:scheduler_algorithm` — `:round_robin` or `:none`
    - `:scheduler_timeout_ms` — integer milliseconds
    - `:scheduler_threshold` — integer frame count
    - `:queue_size` — integer, number of concurrent inference slots (default 1)

  hailo8 options (applied post-configure; scheduling algorithm is set at
  `create_vdevice/1` time):
    - `:scheduler_timeout_ms` — integer milliseconds
    - `:scheduler_threshold` — integer frame count

  Returns `{:ok, %NetworkGroup{}}` or `{:error, reason}`.
  """
  def configure_network_group(%VDevice{ref: vdevice_ref} = _vdevice, hef_path, opts)
      when is_binary(hef_path) and is_map(opts) do
    with {:ok, ng_ref} <- NIF.configure_network_group(vdevice_ref, hef_path, opts),
         {:ok, raw_input_infos} <- NIF.get_input_vstream_infos_from_ng(ng_ref),
         {:ok, raw_output_infos} <- NIF.get_output_vstream_infos_from_ng(ng_ref) do
      input_infos = Enum.map(raw_input_infos, &VStreamInfo.from_map/1)
      output_infos = Enum.map(raw_output_infos, &VStreamInfo.from_map/1)

      {:ok,
       %NetworkGroup{
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
    - `network_group`: The `%NetworkGroup{}` struct.

  Returns `{:ok, %Pipeline{}}` or `{:error, reason}`.
  """
  def create_pipeline(%NetworkGroup{ref: ng_ref} = _network_group) do
    with {:ok, pipeline_ref} <- NIF.create_pipeline(ng_ref),
         {:ok, raw_input_infos} <- NIF.get_input_vstream_infos_from_pipeline(pipeline_ref),
         {:ok, raw_output_infos} <- NIF.get_output_vstream_infos_from_pipeline(pipeline_ref) do
      input_infos = Enum.map(raw_input_infos, &VStreamInfo.from_map/1)
      output_infos = Enum.map(raw_output_infos, &VStreamInfo.from_map/1)

      {:ok,
       %Pipeline{
         ref: pipeline_ref,
         network_group_ref: ng_ref,
         input_vstream_infos: input_infos,
         output_vstream_infos: output_infos
       }}
    end
  end

  @doc """
  Sets the scheduler timeout on a configured network group (hailo8 only).

  The scheduler dispatches inference to hardware after `timeout_ms` milliseconds
  even if the frame threshold has not been reached.

  On hailo10, returns `{:error, reason}` — pass `:scheduler_timeout_ms` in
  `configure_network_group/3` opts instead.

  Returns `:ok` or `{:error, reason}`.
  """
  def set_scheduler_timeout(%NetworkGroup{ref: ng_ref}, timeout_ms)
      when is_integer(timeout_ms) and timeout_ms >= 0 do
    NIF.set_scheduler_timeout(ng_ref, timeout_ms)
  end

  @doc """
  Sets the scheduler frame threshold on a configured network group (hailo8 only).

  The scheduler dispatches inference to hardware once `threshold` frames have
  been queued.

  On hailo10, returns `{:error, reason}` — pass `:scheduler_threshold` in
  `configure_network_group/3` opts instead.

  Returns `:ok` or `{:error, reason}`.
  """
  def set_scheduler_threshold(%NetworkGroup{ref: ng_ref}, threshold)
      when is_integer(threshold) and threshold >= 0 do
    NIF.set_scheduler_threshold(ng_ref, threshold)
  end

  @doc """
  Runs inference on the given pipeline with the provided input data.

  Parameters:
    - `pipeline`: The `%Pipeline{}` struct.
    - `input_data`: A map where keys are input vstream names (strings)
      and values are binaries containing the input data.
      Example: `%{ "input_layer1" => <<...>> }`

  Returns `{:ok, output_data_map}` or `{:error, reason}`.
  The `output_data_map` is a map of output vstream names (strings) to binaries.
  """
  def infer(
        %Pipeline{ref: pipeline_ref, input_vstream_infos: expected_infos} = _pipeline,
        input_data
      )
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
  Accepts either a `%NetworkGroup{}` or an `%Pipeline{}` struct.
  """
  def get_input_vstream_infos(%NetworkGroup{ref: ng_ref}) do
    case NIF.get_input_vstream_infos_from_ng(ng_ref) do
      {:ok, raw_infos} -> {:ok, Enum.map(raw_infos, &VStreamInfo.from_map/1)}
      error -> error
    end
  end

  def get_input_vstream_infos(%Pipeline{ref: pipeline_ref}) do
    case NIF.get_input_vstream_infos_from_pipeline(pipeline_ref) do
      {:ok, raw_infos} -> {:ok, Enum.map(raw_infos, &VStreamInfo.from_map/1)}
      error -> error
    end
  end

  @doc """
  Retrieves output vstream information for a configured resource.
  Accepts either a `%NetworkGroup{}` or an `%Pipeline{}` struct.
  """
  def get_output_vstream_infos(%NetworkGroup{ref: ng_ref}) do
    case NIF.get_output_vstream_infos_from_ng(ng_ref) do
      {:ok, raw_infos} -> {:ok, Enum.map(raw_infos, &VStreamInfo.from_map/1)}
      error -> error
    end
  end

  def get_output_vstream_infos(%Pipeline{ref: pipeline_ref}) do
    case NIF.get_output_vstream_infos_from_pipeline(pipeline_ref) do
      {:ok, raw_infos} -> {:ok, Enum.map(raw_infos, &VStreamInfo.from_map/1)}
      error -> error
    end
  end

  defp validate_input_data(expected_infos, input_data) do
    expected_names = Enum.map(expected_infos, & &1.name)
    provided_names = Map.keys(input_data)

    missing_streams =
      Enum.filter(expected_names, fn name -> not Enum.member?(provided_names, name) end)

    extra_streams =
      Enum.filter(provided_names, fn name -> not Enum.member?(expected_names, name) end)

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
            {:halt, {:error, "Input data for vstream '#{stream_name}' must be a binary."}}
          else
            if byte_size(actual_data) != expected_size do
              {:halt,
               {:error,
                "Invalid input data size for vstream '#{stream_name}'. Expected: #{expected_size}, Got: #{byte_size(actual_data)}"}}
            else
              {:cont, :ok}
            end
          end
        end)
    end
  end
end
