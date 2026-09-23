defmodule NxHailo.APITest do
  use ExUnit.Case, async: false

  import NxHailo.Fixtures

  alias NxHailo.API
  alias NxHailo.API.VDevice

  # The accelerator is shared VM-wide, so these cannot run alongside each other.
  setup do
    on_exit(&API.close_vdevice/0)
    API.close_vdevice()
  end

  describe "create_vdevice/1" do
    test "hands the open accelerator to a caller asking for the same options" do
      vdevice = open_vdevice(%{scheduling_algorithm: :round_robin})

      assert {:ok, ^vdevice} = API.create_vdevice(%{scheduling_algorithm: :round_robin})
    end

    test "refuses to open a second accelerator with different options" do
      open_vdevice(%{})

      assert {:error, message} = API.create_vdevice(%{scheduling_algorithm: :round_robin})
      assert message =~ "already open with %{}"
      assert message =~ "close_vdevice/0"
    end

    test "reports the options it was opened with" do
      open_vdevice(%{scheduling_algorithm: :none})

      assert {:error, message} = API.create_vdevice(%{scheduling_algorithm: :round_robin})
      assert message =~ "scheduling_algorithm: :none"
    end
  end

  describe "close_vdevice/0" do
    test "lets the next caller open the accelerator with different options" do
      open_vdevice(%{scheduling_algorithm: :none})
      assert {:error, _message} = API.create_vdevice(%{scheduling_algorithm: :round_robin})

      assert :ok = API.close_vdevice()
      # Nothing is cached now, so this call reaches the NIF, which is absent here.
      assert_raise UndefinedFunctionError, fn ->
        API.create_vdevice(%{scheduling_algorithm: :round_robin})
      end
    end

    test "is fine when nothing is open" do
      assert :ok = API.close_vdevice()
      assert :ok = API.close_vdevice()
    end
  end

  describe "infer/2" do
    test "rejects input naming the wrong vstream before reaching the device" do
      pipeline = pipeline([vstream_info(name: "in", frame_size: 4)])

      assert {:error, message} = API.infer(pipeline, %{"typo" => <<0, 0, 0, 0>>})
      assert message =~ ~s(missing input for ["in"])
    end
  end

  # There is no accelerator in the test environment, so stand in for the NIF by
  # seeding the cache create_vdevice/1 reads.
  defp open_vdevice(opts) do
    vdevice = %VDevice{ref: make_ref()}
    :persistent_term.put({API, :vdevice}, {opts, vdevice})
    vdevice
  end
end
