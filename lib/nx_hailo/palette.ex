defmodule NxHailo.Palette do
  @moduledoc """
  A fixed colour per class id, for drawing detections.

  Every demo that renders boxes needs the same thing: a stable, reasonably
  distinct colour for each class. Ids beyond the palette, and any id with no
  colour of its own, come back red.

  OpenCV — and so Evision — orders channels blue, green, red, which is what
  `bgr/1` returns. `rgb/1` is the same colour the usual way round.
  """

  # A ~w sigil keeps this readable as a grid; mix format would otherwise put
  # each colour on a line of its own.
  @colors ~w(
    FF0000 00FF00 0000FF FFFF00 FF00FF 00FFFF
    800000 008000 000080 FF00FF 800080 008080
    C0C0C0 FFA500 A52A2A 8A2BE2 5F9EA0 7FFF00
    D2691E FF7F50 6495ED DC143C 00FFFF 00008B
    008B8B B8860B A9A9A9 006400 BDB76B 8B008B
    556B2F FF8C00 9932CC 8B0000 E9967A 8FBC8F
    483D8B 2F4F4F 00CED1 9400D3 FF1493 00BFFF
    696969 1E90FF B22222 FFFAF0 228B22 FF00FF
    DCDCDC F8F8FF FFD700 DAA520 808080 ADFF2F
    F0FFF0 FF69B4 CD5C5C 4B0082 FFFFF0 F0E68C
    E6E6FA FFF0F5 7CFC00 FFFACD ADD8E6 F08080
    E0FFFF FAFAD2 D3D3D3 90EE90 FFB6C1 FFA07A
    20B2AA 87CEFA 778899 B0C4DE FFFFE0 00FF7F
    4682B4 D2B48C 008080 D8BFD8 FF6347 40E0D0
    EE82EE F5DEB3 FFFFFF F5F5F5
  )
          |> Enum.with_index(fn hex, index ->
            <<red, green, blue>> = Base.decode16!(hex)
            {index, {red, green, blue}}
          end)
          |> Map.new()

  @fallback {255, 0, 0}

  @typedoc "A colour as three 0-255 channels."
  @type color :: {0..255, 0..255, 0..255}

  @doc """
  Returns the colour for `class_id` as `{red, green, blue}`.

  ## Examples

      iex> NxHailo.Palette.rgb(0)
      {255, 0, 0}

      iex> NxHailo.Palette.rgb(1_000)
      {255, 0, 0}

  """
  @spec rgb(non_neg_integer()) :: color()
  def rgb(class_id), do: Map.get(@colors, class_id, @fallback)

  @doc """
  Returns the colour for `class_id` as `{blue, green, red}`, the order OpenCV uses.

  ## Examples

      iex> NxHailo.Palette.bgr(1)
      {0, 255, 0}

  """
  @spec bgr(non_neg_integer()) :: color()
  def bgr(class_id) do
    {red, green, blue} = rgb(class_id)
    {blue, green, red}
  end

  @doc """
  Returns how many class ids have a colour of their own.
  """
  @spec size() :: pos_integer()
  def size, do: map_size(@colors)
end
