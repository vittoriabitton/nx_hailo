defmodule NxHailo.Input do
  @moduledoc false
  # Turns a map of `Nx.Tensor`s into the binaries the NIF expects.
  #
  # Every check here exists so a mistake surfaces as a sentence naming the
  # vstream, rather than as a HailoRT status code from deep inside the NIF.

  alias NxHailo.API.VStreamInfo

  @nx_types %{uint8: {:u, 8}, uint16: {:u, 16}, float32: {:f, 32}}

  @doc """
  Encodes `inputs` into `%{vstream_name => binary}`.

  Fails unless the input map has exactly one tensor per vstream, each with the
  type and byte size that vstream was configured for.
  """
  @spec encode([VStreamInfo.t()], %{optional(String.t()) => Nx.Tensor.t()}) ::
          {:ok, %{optional(String.t()) => binary()}} | {:error, String.t()}
  def encode(vstream_infos, inputs) when is_list(vstream_infos) and is_map(inputs) do
    with :ok <- validate_names(vstream_infos, inputs) do
      Enum.reduce_while(vstream_infos, {:ok, %{}}, fn info, {:ok, encoded} ->
        case encode_one(info, Map.fetch!(inputs, info.name)) do
          {:ok, binary} -> {:cont, {:ok, Map.put(encoded, info.name, binary)}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  @doc """
  Checks that `inputs` holds exactly the vstreams in `vstream_infos`.
  """
  @spec validate_names([VStreamInfo.t()], map()) :: :ok | {:error, String.t()}
  def validate_names(vstream_infos, inputs) do
    expected = MapSet.new(vstream_infos, & &1.name)
    given = MapSet.new(Map.keys(inputs))

    missing = expected |> MapSet.difference(given) |> Enum.sort()
    unexpected = given |> MapSet.difference(expected) |> Enum.sort()

    cond do
      missing != [] ->
        {:error, "missing input for #{inspect(missing)}, #{expected_names(expected)}"}

      unexpected != [] ->
        {:error, "no vstream named #{inspect(unexpected)}, #{expected_names(expected)}"}

      true ->
        :ok
    end
  end

  defp expected_names(expected), do: "expected #{inspect(Enum.sort(expected))}"

  defp encode_one(%VStreamInfo{} = info, tensor) do
    with :ok <- validate_type(info, tensor) do
      binary = Nx.to_binary(tensor)

      if byte_size(binary) == info.frame_size do
        {:ok, binary}
      else
        {:error,
         "input #{inspect(info.name)} has #{byte_size(binary)} bytes, but the vstream takes " <>
           "#{info.frame_size} (shape #{inspect(info.shape)}, type #{inspect(info.format[:type])})"}
      end
    end
  end

  defp validate_type(%VStreamInfo{} = info, tensor) do
    # :auto means HailoRT picks the type, so there is nothing to check against.
    case Map.get(@nx_types, info.format[:type]) do
      nil ->
        :ok

      expected ->
        case Nx.type(tensor) do
          ^expected ->
            :ok

          actual ->
            {:error,
             "input #{inspect(info.name)} has type #{inspect(actual)}, " <>
               "but the vstream takes #{inspect(expected)}"}
        end
    end
  end
end
