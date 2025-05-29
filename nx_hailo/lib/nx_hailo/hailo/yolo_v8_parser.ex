# Parse the complete NMS structure
defmodule NxHailo.Hailo.YoloV8Parser do
  def parse_nms_output(binary_data, num_classes) do
    parse_classes(binary_data, 0, 0, num_classes, [])
  end

  defp parse_classes(binary_data, offset, class_id, num_classes, acc)
       when class_id < num_classes do
    if offset * 4 >= byte_size(binary_data) do
      # Reached end of data
      Enum.reverse(acc)
    else
      # Read count for this class
      <<_::binary-size(offset * 4), count_bytes::binary-size(4), _::binary>> = binary_data
      <<count::float-32-little>> = count_bytes

      # Convert to integer (should be exact)
      detection_count = round(count)

      # Calculate total floats for this class
      class_floats = 1 + detection_count * 5

      # Extract detections if any
      detections =
        if detection_count > 0 do
          detection_start = (offset + 1) * 4
          detection_bytes = detection_count * 5 * 4

          <<_::binary-size(detection_start), det_data::binary-size(detection_bytes), _::binary>> =
            binary_data

          # Parse detections as groups of 5 floats
          for i <- 0..(detection_count - 1) do
            det_offset = i * 5 * 4

            <<_::binary-size(det_offset), y_min::float-32-little, x_min::float-32-little,
              y_max::float-32-little, x_max::float-32-little, score::float-32-little,
              _::binary>> = det_data

            %{
              bbox: [x_min, y_min, x_max, y_max],
              score: score,
              class_id: class_id
            }
          end
        else
          []
        end

      acc =
        if detections == [] do
          acc
        else
          class_info = %{
            class_id: class_id,
            count: detection_count,
            detections: detections
          }

          [class_info | acc]
        end

      # Move to next class
      parse_classes(binary_data, offset + class_floats, class_id + 1, num_classes, acc)
    end
  end

  defp parse_classes(_binary_data, _offset, _class_id, _num_classes, acc) do
    Enum.reverse(acc)
  end
end
