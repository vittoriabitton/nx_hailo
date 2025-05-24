defmodule NxHailo.VStreamInfo do
  @moduledoc """
  Represents detailed information for a single Hailo VStream.
  """
  defstruct name: nil,
            network_name: nil,
            # :h2d or :d2h
            direction: nil,
            frame_size: 0,
            # %{type: atom(), order: atom(), flags: atom()}
            format: %{},
            # %{height: integer(), width: integer(), features: integer()} or nil
            shape: nil,
            # %{number_of_classes: integer(), max_bboxes_per_class_or_total: integer()} or nil
            nms_shape: nil,
            # %{qp_zp: float(), qp_scale: float()} or nil
            quant_info: nil

  @type t :: %__MODULE__{
          name: String.t() | nil,
          network_name: String.t() | nil,
          direction: :h2d | :d2h | nil,
          frame_size: non_neg_integer(),
          format: map(),
          shape: map() | nil,
          nms_shape: map() | nil,
          quant_info: map() | nil
        }

  def from_map(map) when is_map(map) do
    %NxHailo.VStreamInfo{
      name: Map.get(map, "name") || Map.get(map, :name),
      network_name: Map.get(map, "network_name") || Map.get(map, :network_name),
      direction: Map.get(map, "direction") || Map.get(map, :direction),
      frame_size: Map.get(map, "frame_size") || Map.get(map, :frame_size),
      format: Map.get(map, "format") || Map.get(map, :format),
      shape: Map.get(map, "shape") || Map.get(map, :shape),
      nms_shape: Map.get(map, "nms_shape") || Map.get(map, :nms_shape),
      quant_info: Map.get(map, "quant_info") || Map.get(map, :quant_info)
    }
  end
end
