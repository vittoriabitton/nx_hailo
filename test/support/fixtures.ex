defmodule NxHailo.Fixtures do
  @moduledoc false
  # Builds the metadata and binaries the NIF would normally produce, so the
  # Elixir side can be tested on a machine with no accelerator attached.

  alias NxHailo.API.Pipeline
  alias NxHailo.API.VStreamInfo

  @doc """
  A `VStreamInfo` for a 640x640 RGB input, overridable per field.
  """
  def vstream_info(attrs \\ []) do
    struct!(
      VStreamInfo,
      Keyword.merge(
        [
          name: "yolov8m/input_layer1",
          network_name: "yolov8m",
          direction: :h2d,
          frame_size: 640 * 640 * 3,
          format: %{type: :uint8, order: :nhwc, flags: :none},
          shape: %{height: 640, width: 640, features: 3},
          nms_shape: nil,
          quant_info: nil
        ],
        attrs
      )
    )
  end

  @doc """
  A `Pipeline` carrying `inputs`. Its refs are nil, so it cannot reach the NIF.
  """
  def pipeline(inputs, outputs \\ []) do
    %Pipeline{input_vstream_infos: inputs, output_vstream_infos: outputs}
  end

  @doc """
  Encodes detections the way a YOLOv8 network with on-chip NMS does.

  Takes one list of `{ymin, xmin, ymax, xmax, score}` tuples per class, in class
  order, and emits each class as a count followed by its detections.
  """
  def nms_output(detections_by_class) do
    for detections <- detections_by_class, into: <<>> do
      values = Enum.flat_map(detections, &Tuple.to_list/1)

      for value <- [length(detections) | values], into: <<>>, do: <<value::float-32-little>>
    end
  end
end
