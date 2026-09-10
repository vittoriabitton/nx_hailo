defmodule NxHailo.API.VStreamInfoTest do
  use ExUnit.Case, async: true

  alias NxHailo.API.VStreamInfo

  describe "from_map/1" do
    test "builds a struct from the map the NIF returns" do
      info =
        VStreamInfo.from_map(%{
          name: "yolov8m/input_layer1",
          network_name: "yolov8m",
          direction: :h2d,
          frame_size: 1_228_800,
          format: %{type: :uint8, order: :nhwc, flags: :none},
          shape: %{height: 640, width: 640, features: 3},
          nms_shape: nil,
          quant_info: %{qp_zp: 0.0, qp_scale: 1.0}
        })

      assert info.name == "yolov8m/input_layer1"
      assert info.direction == :h2d
      assert info.frame_size == 1_228_800
      assert info.shape == %{height: 640, width: 640, features: 3}
      assert info.quant_info == %{qp_zp: 0.0, qp_scale: 1.0}
    end

    test "accepts string keys" do
      info = VStreamInfo.from_map(%{"name" => "out", "direction" => "d2h"})

      assert info.name == "out"
      assert info.direction == "d2h"
    end

    test "leaves keys the map does not carry as nil" do
      info = VStreamInfo.from_map(%{name: "out"})

      assert info.shape == nil
      assert info.nms_shape == nil
      assert info.format == nil
    end

    test "keeps the nms_shape of a detection output" do
      info =
        VStreamInfo.from_map(%{
          name: "yolov8m/yolov8_nms_postprocess",
          direction: :d2h,
          shape: nil,
          nms_shape: %{
            number_of_classes: 80,
            max_bboxes_per_class: 100,
            max_bboxes_total: 100
          }
        })

      assert info.shape == nil
      assert info.nms_shape.number_of_classes == 80
    end
  end
end
