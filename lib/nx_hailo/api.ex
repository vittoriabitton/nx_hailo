defmodule NxHailo.API do
  @moduledoc """
  Lower-level access to HailoRT, for setups `NxHailo.load/2` cannot express.

  `NxHailo.load/2` covers the common case of one model on the device. Reach for
  this module when you need several models sharing one accelerator, since that
  means creating the VDevice yourself and configuring each network group on it:

      {:ok, vdevice} = NxHailo.API.create_vdevice(%{scheduling_algorithm: :round_robin})

      {:ok, ng} = NxHailo.API.configure_network_group(vdevice, "priv/yolov8m.hef")
      {:ok, pipeline} = NxHailo.API.create_pipeline(ng)

  A VDevice stands for the physical accelerator, and HailoRT only lets one exist
  per VM, so `create_vdevice/1` opens it once and hands the same one to every
  later caller. See that function for what happens when a second caller asks for
  different options.
  """

  alias NxHailo.API.NetworkGroup
  alias NxHailo.API.Pipeline
  alias NxHailo.API.VDevice
  alias NxHailo.API.VStreamInfo
  alias NxHailo.Input
  alias NxHailo.NIF

  @vdevice_key {__MODULE__, :vdevice}

  @typedoc """
  Options for `create_vdevice/1`.

    * `:scheduling_algorithm` - `:round_robin` lets HailoRT interleave requests
      from every network group configured on this VDevice, which is what makes
      concurrent models possible. `:none` runs them in submission order.
  """
  @type vdevice_opts :: %{optional(:scheduling_algorithm) => :round_robin | :none}

  @typedoc """
  Options for `configure_network_group/3`.

    * `:scheduler_timeout_ms` - dispatch to the accelerator after this many
      milliseconds even if `:scheduler_threshold` frames have not queued up yet
    * `:scheduler_threshold` - how many frames to queue before dispatching

  Both only matter when the VDevice was created with `:round_robin`; they are
  the knobs that trade latency for throughput between competing models.
  """
  @type network_group_opts :: %{
          optional(:scheduler_timeout_ms) => non_neg_integer(),
          optional(:scheduler_threshold) => non_neg_integer()
        }

  @doc """
  Opens the accelerator, or returns the one already open.

  The first call decides the options for the lifetime of the VM. A later call
  asking for different ones returns an error rather than opening a second
  VDevice, which HailoRT would refuse anyway. Call `close_vdevice/0` first if
  you really do need to reopen it with different options.
  """
  @spec create_vdevice(vdevice_opts()) :: {:ok, VDevice.t()} | {:error, String.t()}
  def create_vdevice(opts \\ %{}) when is_map(opts) do
    case :persistent_term.get(@vdevice_key, nil) do
      nil -> open_vdevice(opts)
      cached -> reuse_vdevice(cached, opts)
    end
  end

  # Two processes racing to open the device would each get one, so take a lock
  # and look again inside it.
  defp open_vdevice(opts) do
    :global.trans({@vdevice_key, self()}, fn ->
      case :persistent_term.get(@vdevice_key, nil) do
        nil ->
          with {:ok, ref} <- NIF.create_vdevice(opts) do
            vdevice = %VDevice{ref: ref}
            :persistent_term.put(@vdevice_key, {opts, vdevice})
            {:ok, vdevice}
          end

        cached ->
          reuse_vdevice(cached, opts)
      end
    end)
  end

  defp reuse_vdevice({opts, vdevice}, opts), do: {:ok, vdevice}

  defp reuse_vdevice({open_opts, _vdevice}, opts) do
    {:error,
     "the accelerator is already open with #{inspect(open_opts)}, so it cannot also be " <>
       "opened with #{inspect(opts)}. Call NxHailo.API.close_vdevice/0 first, or pass the " <>
       "options on whichever call runs first"}
  end

  @doc """
  Forgets the open VDevice so the next `create_vdevice/1` opens a fresh one.

  The accelerator itself is released once the last model configured on it is
  garbage collected, so anything still holding a `NxHailo.Model` keeps working.
  """
  @spec close_vdevice() :: :ok
  def close_vdevice do
    :persistent_term.erase(@vdevice_key)
    :ok
  end

  @doc """
  Loads a HEF onto `vdevice` and returns the network group it defines.
  """
  @spec configure_network_group(VDevice.t(), Path.t(), network_group_opts()) ::
          {:ok, NetworkGroup.t()} | {:error, String.t()}
  def configure_network_group(%VDevice{ref: vdevice_ref}, hef_path, opts \\ %{})
      when is_binary(hef_path) and is_map(opts) do
    with {:ok, ng_ref} <- NIF.configure_network_group(vdevice_ref, hef_path, opts),
         {:ok, inputs} <- vstream_infos(&NIF.get_input_vstream_infos_from_ng/1, ng_ref),
         {:ok, outputs} <- vstream_infos(&NIF.get_output_vstream_infos_from_ng/1, ng_ref) do
      {:ok,
       %NetworkGroup{
         ref: ng_ref,
         vdevice_ref: vdevice_ref,
         input_vstream_infos: inputs,
         output_vstream_infos: outputs
       }}
    end
  end

  @doc """
  Builds the inference pipeline that `infer/2` runs frames through.
  """
  @spec create_pipeline(NetworkGroup.t()) :: {:ok, Pipeline.t()} | {:error, String.t()}
  def create_pipeline(%NetworkGroup{ref: ng_ref}) do
    with {:ok, pipeline_ref} <- NIF.create_pipeline(ng_ref),
         {:ok, inputs} <-
           vstream_infos(&NIF.get_input_vstream_infos_from_pipeline/1, pipeline_ref),
         {:ok, outputs} <-
           vstream_infos(&NIF.get_output_vstream_infos_from_pipeline/1, pipeline_ref) do
      {:ok,
       %Pipeline{
         ref: pipeline_ref,
         network_group_ref: ng_ref,
         input_vstream_infos: inputs,
         output_vstream_infos: outputs
       }}
    end
  end

  @doc """
  Runs one frame through `pipeline`.

  `input_data` maps input vstream names to raw binaries — `NxHailo.infer/4` is
  the version that takes tensors. Returns a map of output vstream names to raw
  binaries, which a `NxHailo.OutputParser` turns into something meaningful.

  Calls on one pipeline are serialized; calls on separate pipelines sharing a
  round-robin VDevice run concurrently.
  """
  @spec infer(Pipeline.t(), %{optional(String.t()) => binary()}) ::
          {:ok, %{optional(String.t()) => binary()}} | {:error, String.t()}
  def infer(%Pipeline{ref: pipeline_ref, input_vstream_infos: infos}, input_data)
      when is_map(input_data) do
    # The NIF checks the size of every binary it is handed, so this only has to
    # catch a caller naming the wrong vstream.
    with :ok <- Input.validate_names(infos, input_data) do
      NIF.infer(pipeline_ref, input_data)
    end
  end

  @doc """
  Returns the input vstreams of a network group or pipeline.
  """
  @spec get_input_vstream_infos(NetworkGroup.t() | Pipeline.t()) ::
          {:ok, [VStreamInfo.t()]} | {:error, String.t()}
  def get_input_vstream_infos(%NetworkGroup{ref: ref}),
    do: vstream_infos(&NIF.get_input_vstream_infos_from_ng/1, ref)

  def get_input_vstream_infos(%Pipeline{ref: ref}),
    do: vstream_infos(&NIF.get_input_vstream_infos_from_pipeline/1, ref)

  @doc """
  Returns the output vstreams of a network group or pipeline.
  """
  @spec get_output_vstream_infos(NetworkGroup.t() | Pipeline.t()) ::
          {:ok, [VStreamInfo.t()]} | {:error, String.t()}
  def get_output_vstream_infos(%NetworkGroup{ref: ref}),
    do: vstream_infos(&NIF.get_output_vstream_infos_from_ng/1, ref)

  def get_output_vstream_infos(%Pipeline{ref: ref}),
    do: vstream_infos(&NIF.get_output_vstream_infos_from_pipeline/1, ref)

  @doc """
  Sets the scheduler timeout on an already configured network group.

  Only the hailo8 backend supports this; on hailo10 the timeout has to be set
  while the model is configured, so pass `:scheduler_timeout_ms` to
  `configure_network_group/3` instead. That option works on both backends and is
  the one to reach for.
  """
  @spec set_scheduler_timeout(NetworkGroup.t(), non_neg_integer()) :: :ok | {:error, String.t()}
  def set_scheduler_timeout(%NetworkGroup{ref: ng_ref}, timeout_ms)
      when is_integer(timeout_ms) and timeout_ms >= 0 do
    NIF.set_scheduler_timeout(ng_ref, timeout_ms)
  end

  @doc """
  Sets the scheduler frame threshold on an already configured network group.

  Carries the same hailo8-only caveat as `set_scheduler_timeout/2`; prefer
  `:scheduler_threshold` in `configure_network_group/3`.
  """
  @spec set_scheduler_threshold(NetworkGroup.t(), non_neg_integer()) :: :ok | {:error, String.t()}
  def set_scheduler_threshold(%NetworkGroup{ref: ng_ref}, threshold)
      when is_integer(threshold) and threshold >= 0 do
    NIF.set_scheduler_threshold(ng_ref, threshold)
  end

  defp vstream_infos(nif_fun, ref) do
    with {:ok, raw_infos} <- nif_fun.(ref) do
      {:ok, Enum.map(raw_infos, &VStreamInfo.from_map/1)}
    end
  end
end
