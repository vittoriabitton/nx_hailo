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
  def load_network_group(_hef_path), do: :erlang.nif_error(:nif_not_loaded)
  def create_pipeline(_network_group), do: :erlang.nif_error(:nif_not_loaded)
  def get_output_vstream_info(_pipeline), do: :erlang.nif_error(:nif_not_loaded)
  def infer(_pipeline, _input_data), do: :erlang.nif_error(:nif_not_loaded)
end
