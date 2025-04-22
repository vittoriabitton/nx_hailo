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
  @moduledoc """
  Native Implemented Functions (NIFs) for NxHailo.
  This module contains the low-level NIF bindings.
  """

  @on_load :load_nif

  import NxHailo.NIF.Macro

  def load_nif do
    nif_file = ~c"#{:code.priv_dir(:nx_hailo)}/libnx_hailo"

    case :erlang.load_nif(nif_file, 0) do
      :ok -> :ok
      {:error, {:load_failed, error}} -> IO.puts("Failed to load NIF: #{error}")
      {:error, error} -> IO.puts("Failed to load NIF: #{error}")
    end
  end

  defnif identity(_term)
end
