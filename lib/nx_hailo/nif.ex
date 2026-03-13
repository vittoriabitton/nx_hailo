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

  # Load the NIF for the configured target: :hailo10 (v5/InferModel) or :hailo8 (v4/VDevice).
  # The Makefile builds the chosen lib and writes the target to priv/.hailo_target;
  # if that file is missing we use config :nx_hailo, :target (default :hailo10).
  def load_nif do
    target = read_target()
    nif_name = nif_name_for_target(target)
    path = :filename.join(:code.priv_dir(:nx_hailo), nif_name)
    :erlang.load_nif(path, 0)
  end

  defp read_target do
    priv = :code.priv_dir(:nx_hailo) |> to_string()
    built_target_file = Path.join(priv, ".hailo_target")

    case File.read(built_target_file) do
      {:ok, t} ->
        case String.trim(t) do
          "hailo8" -> :hailo8
          "hailo10" -> :hailo10
          _ -> Application.get_env(:nx_hailo, :target, :hailo10)
        end

      _ ->
        Application.get_env(:nx_hailo, :target, :hailo10)
    end
  end

  defp nif_name_for_target(:hailo10), do: ~c"libnx_hailo"
  defp nif_name_for_target(:hailo8), do: ~c"libnx_hailo_hailo8"
  defp nif_name_for_target(_), do: ~c"libnx_hailo"

  # NIF functions
  defnif create_vdevice()
  defnif configure_network_group(_vdevice_ref, _hef_path)
  defnif create_pipeline(_network_group_ref)
  defnif get_input_vstream_infos_from_ng(_network_group_ref)
  defnif get_output_vstream_infos_from_ng(_network_group_ref)
  defnif get_input_vstream_infos_from_pipeline(_pipeline_ref)
  defnif get_output_vstream_infos_from_pipeline(_pipeline_ref)
  defnif infer(_pipeline_ref, _input_data)
end
