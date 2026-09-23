defmodule NxHailo.NIF.Macro do
  @moduledoc false

  defmacro defnif(call) do
    {name, _meta, args} = call

    quote do
      def unquote(name)(unquote_splicing(args)) do
        :erlang.nif_error(:nif_not_loaded)
      end
    end
  end
end

defmodule NxHailo.NIF do
  @moduledoc false
  # Direct bindings to the C++ backend. Which backend is behind them is decided
  # at build time by the :target configuration — see the Makefile. Go through
  # NxHailo or NxHailo.API rather than calling these.

  @on_load :load_nif

  import NxHailo.NIF.Macro

  def load_nif do
    path = :filename.join(:code.priv_dir(:nx_hailo), ~c"libnx_hailo")

    case :erlang.load_nif(path, 0) do
      :ok ->
        :ok

      {:error, {reason, _details}} ->
        {:error,
         {reason,
          ~c"could not load the NxHailo NIF. Run `mix compile` on a machine with HailoRT " ++
            ~c"installed, or set NX_HAILO_SKIP_NIF=1 to work without the accelerator."}}
    end
  end

  defnif hailo_version()
  defnif create_vdevice(_opts)
  defnif configure_network_group(_vdevice_ref, _hef_path, _opts)
  defnif create_pipeline(_network_group_ref)
  defnif get_input_vstream_infos_from_ng(_network_group_ref)
  defnif get_output_vstream_infos_from_ng(_network_group_ref)
  defnif get_input_vstream_infos_from_pipeline(_pipeline_ref)
  defnif get_output_vstream_infos_from_pipeline(_pipeline_ref)
  defnif infer(_pipeline_ref, _input_data)
  # hailo8 only. On hailo10 these return an error telling you to pass
  # :scheduler_timeout_ms / :scheduler_threshold to configure_network_group/3.
  defnif set_scheduler_timeout(_network_group_ref, _timeout_ms)
  defnif set_scheduler_threshold(_network_group_ref, _threshold)
end
