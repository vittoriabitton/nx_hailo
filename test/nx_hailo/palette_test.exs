defmodule NxHailo.PaletteTest do
  use ExUnit.Case, async: true

  alias NxHailo.Palette

  doctest Palette

  test "decodes hex into channels" do
    assert Palette.rgb(0) == {255, 0, 0}
    assert Palette.rgb(1) == {0, 255, 0}
    assert Palette.rgb(2) == {0, 0, 255}
  end

  test "bgr/1 swaps the outer channels" do
    for class_id <- [0, 1, 2, 13, Palette.size() - 1] do
      {red, green, blue} = Palette.rgb(class_id)
      assert Palette.bgr(class_id) == {blue, green, red}
    end
  end

  test "gives every id in the palette a colour" do
    colors = Enum.map(0..(Palette.size() - 1), &Palette.rgb/1)

    assert length(colors) == Palette.size()
    assert Enum.all?(colors, fn {r, g, b} -> Enum.all?([r, g, b], &(&1 in 0..255)) end)
  end

  test "falls back to red past the end of the palette" do
    assert Palette.rgb(Palette.size()) == {255, 0, 0}
    assert Palette.bgr(Palette.size()) == {0, 0, 255}
  end

  test "covers the 80 COCO classes" do
    assert Palette.size() >= 80
  end
end
