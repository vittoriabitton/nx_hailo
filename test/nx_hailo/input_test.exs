defmodule NxHailo.InputTest do
  use ExUnit.Case, async: true

  import NxHailo.Fixtures

  alias NxHailo.Input

  @input vstream_info(name: "in", frame_size: 12, shape: %{height: 2, width: 2, features: 3})

  defp frame(type \\ :u8), do: Nx.broadcast(Nx.tensor(1, type: type), {2, 2, 3})

  describe "encode/2" do
    test "encodes a tensor into the binary the vstream takes" do
      assert {:ok, %{"in" => binary}} = Input.encode([@input], %{"in" => frame()})
      assert byte_size(binary) == 12
    end

    test "encodes every input" do
      other =
        vstream_info(name: "other", frame_size: 4, shape: %{height: 1, width: 1, features: 4})

      inputs = %{"in" => frame(), "other" => Nx.broadcast(Nx.tensor(0, type: :u8), {4})}

      assert {:ok, encoded} = Input.encode([@input, other], inputs)
      assert Map.keys(encoded) |> Enum.sort() == ["in", "other"]
    end

    test "rejects a tensor of the wrong type" do
      assert {:error, message} = Input.encode([@input], %{"in" => frame(:f32)})
      assert message =~ ~s(input "in" has type {:f, 32})
      assert message =~ "the vstream takes {:u, 8}"
    end

    test "rejects a tensor of the wrong size" do
      too_small = Nx.broadcast(Nx.tensor(1, type: :u8), {2, 2})

      assert {:error, message} = Input.encode([@input], %{"in" => too_small})
      assert message =~ "has 4 bytes"
      assert message =~ "the vstream takes 12"
    end

    test "accepts any type when the vstream leaves it to HailoRT" do
      auto = vstream_info(name: "in", frame_size: 48, format: %{type: :auto, order: :nhwc})

      assert {:ok, _encoded} = Input.encode([auto], %{"in" => frame(:f32)})
    end

    test "reports the first problem when several inputs are wrong" do
      other = vstream_info(name: "other", frame_size: 4)

      inputs = %{"in" => frame(:f32), "other" => frame(:f32)}

      assert {:error, message} = Input.encode([@input, other], inputs)
      assert message =~ ~s(input "in")
    end
  end

  describe "validate_names/2" do
    test "accepts exactly the expected vstreams" do
      assert :ok = Input.validate_names([@input], %{"in" => <<>>})
    end

    test "reports a missing input" do
      other = vstream_info(name: "other")

      assert {:error, message} = Input.validate_names([@input, other], %{"in" => <<>>})
      assert message =~ ~s(missing input for ["other"])
      assert message =~ ~s(expected ["in", "other"])
    end

    test "reports an input naming no vstream" do
      assert {:error, message} = Input.validate_names([@input], %{"in" => <<>>, "typo" => <<>>})
      assert message =~ ~s(no vstream named ["typo"])
    end

    test "reports a missing input before an unexpected one" do
      assert {:error, message} = Input.validate_names([@input], %{"typo" => <<>>})
      assert message =~ "missing input"
    end
  end
end
