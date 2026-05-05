defmodule NxHailo.NIF.Macro do
  defmacro defnif(call) do
    {name, _, args} = call

    quote do
      def unquote(name)(unquote_splicing(args)) do
        :erlang.nif_error(:nif_not_loaded)
      end
    end
  end
end

defmodule NxHailo.NIF do
  @moduledoc false

  @on_load :load_nif

  import NxHailo.NIF.Macro

  def load_nif do
    path = :filename.join(:code.priv_dir(:nx_hailo), ~c"libnx_hailo")
    :erlang.load_nif(path, 0)
  end

  # NIF functions
  defnif hailo_version()
  defnif create_vdevice(_opts)
  defnif configure_network_group(_vdevice_ref, _hef_path, _opts)
  defnif create_pipeline(_network_group_ref)
  defnif get_input_vstream_infos_from_ng(_network_group_ref)
  defnif get_output_vstream_infos_from_ng(_network_group_ref)
  defnif get_input_vstream_infos_from_pipeline(_pipeline_ref)
  defnif get_output_vstream_infos_from_pipeline(_pipeline_ref)
  defnif infer(_pipeline_ref, _input_data)
  # hailo8: sets scheduler timeout on a configured network group (post-configure)
  # hailo10: returns {:error, reason} — use configure_network_group/3 opts instead
  defnif set_scheduler_timeout(_network_group_ref, _timeout_ms)
  # hailo8: sets scheduler frame threshold on a configured network group (post-configure)
  # hailo10: returns {:error, reason} — use configure_network_group/3 opts instead
  defnif set_scheduler_threshold(_network_group_ref, _threshold)
end
