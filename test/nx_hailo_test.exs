defmodule NxHailoTest do
  use ExUnit.Case, async: true

  import NxHailo.Fixtures

  alias NxHailo.Model

  doctest NxHailo

  defmodule PassthroughParser do
    @moduledoc false
    @behaviour NxHailo.OutputParser

    @impl true
    def parse(outputs, opts), do: {:ok, {outputs, opts}}
  end

  describe "load/2" do
    test "rejects an unknown option" do
      assert_raise ArgumentError, ~r/:nope/, fn ->
        NxHailo.load("yolov8m.hef", nope: true)
      end
    end

    test "accepts the documented options" do
      # There is no accelerator here, so this gets as far as the NIF and no
      # further — which is enough to show the options were understood.
      assert_raise UndefinedFunctionError, fn ->
        NxHailo.load("yolov8m.hef",
          name: "yolo",
          scheduling_algorithm: :round_robin,
          scheduler_timeout_ms: 100,
          scheduler_threshold: 2
        )
      end
    end
  end

  describe "infer/4" do
    setup do
      input = vstream_info(name: "in", frame_size: 12, shape: %{height: 2, width: 2, features: 3})

      %{model: %Model{pipeline: pipeline([input]), name: "test"}}
    end

    test "rejects a tensor of the wrong type before reaching the device", %{model: model} do
      inputs = %{"in" => Nx.broadcast(Nx.tensor(1.0, type: :f32), {2, 2, 3})}

      assert {:error, message} = NxHailo.infer(model, inputs, PassthroughParser)
      assert message =~ "the vstream takes {:u, 8}"
    end

    test "rejects a tensor of the wrong size before reaching the device", %{model: model} do
      inputs = %{"in" => Nx.broadcast(Nx.tensor(1, type: :u8), {2, 2})}

      assert {:error, message} = NxHailo.infer(model, inputs, PassthroughParser)
      assert message =~ "the vstream takes 12"
    end

    test "rejects input naming the wrong vstream", %{model: model} do
      inputs = %{"typo" => Nx.broadcast(Nx.tensor(1, type: :u8), {2, 2, 3})}

      assert {:error, message} = NxHailo.infer(model, inputs, PassthroughParser)
      assert message =~ ~s(missing input for ["in"])
    end
  end
end
