defmodule NervesExample.YOLODraw do
  @moduledoc """
  Draws YOLO detection boxes and labels onto an Evision Mat.
  """

  @font_size 0.5
  @stroke_width 2
  @font_face Evision.Constant.cv_FONT_HERSHEY_SIMPLEX()
  @text_padding 5

  @class_colors [
    "#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF", "#00FFFF",
    "#800000", "#008000", "#000080", "#FF00FF", "#800080", "#008080",
    "#C0C0C0", "#FFA500", "#A52A2A", "#8A2BE2", "#5F9EA0", "#7FFF00",
    "#D2691E", "#FF7F50", "#6495ED", "#DC143C", "#00FFFF", "#00008B",
    "#008B8B", "#B8860B", "#A9A9A9", "#006400", "#BDB76B", "#8B008B",
    "#556B2F", "#FF8C00", "#9932CC", "#8B0000", "#E9967A", "#8FBC8F",
    "#483D8B", "#2F4F4F", "#00CED1", "#9400D3", "#FF1493", "#00BFFF",
    "#696969", "#1E90FF", "#B22222", "#FFFAF0", "#228B22", "#FF00FF",
    "#DCDCDC", "#F8F8FF", "#FFD700", "#DAA520", "#808080", "#ADFF2F",
    "#F0FFF0", "#FF69B4", "#CD5C5C", "#4B0082", "#FFFFF0", "#F0E68C",
    "#E6E6FA", "#FFF0F5", "#7CFC00", "#FFFACD", "#ADD8E6", "#F08080",
    "#E0FFFF", "#FAFAD2", "#D3D3D3", "#90EE90", "#FFB6C1", "#FFA07A",
    "#20B2AA", "#87CEFA", "#778899", "#B0C4DE", "#FFFFE0", "#00FF7F",
    "#4682B4", "#D2B48C", "#008080", "#D8BFD8", "#FF6347", "#40E0D0",
    "#EE82EE", "#F5DEB3", "#FFFFFF", "#F5F5F5"
  ]
  |> Enum.with_index()
  |> Map.new(fn {hex, i} ->
    <<r::8, g::8, b::8>> =
      hex
      |> String.replace_prefix("#", "")
      |> Base.decode16!(case: :upper)

    # OpenCV uses BGR
    {i, {b, g, r}}
  end)

  def draw_detected_objects(mat, detected_objects, fps_label) do
    # Note: Evision shape is {h, w, c}
    {full_height, full_width, _channels} = Evision.Mat.shape(mat)

    # FPS label background (blue, bottom-right corner)
    fps_text_color = {255, 255, 255}
    fps_bg_color = {255, 0, 0}

    {{fps_text_width, fps_text_height}, _baseline} =
      Evision.getTextSize(fps_label, @font_face, 0.7, 1)

    fps_bg_width = fps_text_width + 2 * @text_padding
    fps_bg_height = fps_text_height + 2 * @text_padding
    fps_bg_tl = {full_width - fps_bg_width, full_height - fps_bg_height}
    fps_bg_br = {full_width, full_height}

    mat = Evision.rectangle(mat, fps_bg_tl, fps_bg_br, fps_bg_color, thickness: -1)

    fps_text_org = {full_width - fps_bg_width + @text_padding, full_height - @text_padding}

    mat =
      Evision.putText(mat, fps_label, fps_text_org, @font_face, 0.7, fps_text_color,
        thickness: 1,
        lineType: Evision.Constant.cv_LINE_AA()
      )

    # Bounding boxes
    mat =
      Enum.reduce(
        detected_objects,
        mat,
        fn %NxHailo.Parsers.YoloV8.DetectedObject{} = obj, acc ->
          pt1 = {obj.xmin, obj.ymin}
          pt2 = {obj.xmax, obj.ymax}
          Evision.rectangle(acc, pt1, pt2, class_color(obj.class_id), thickness: @stroke_width)
        end
      )

    # Labels
    Enum.reduce(detected_objects, mat, fn %NxHailo.Parsers.YoloV8.DetectedObject{} = obj, acc ->
      prob = round(obj.score * 100)
      label = "#{obj.class_name} #{prob}%"

      text_color = {255, 255, 255}
      text_bg_color = {0, 0, 0}

      {{text_w, text_h}, baseline} = Evision.getTextSize(label, @font_face, @font_size, 1)

      text_bg_tl = {obj.xmin, max(obj.ymin - text_h - 2 * @text_padding - baseline, 0)}
      text_bg_br = {obj.xmin + text_w + 2 * @text_padding, max(obj.ymin - baseline, 0)}

      acc
      |> Evision.rectangle(text_bg_tl, text_bg_br, text_bg_color, thickness: -1)
      |> Evision.putText(
        label,
        {obj.xmin + @text_padding, max(obj.ymin - @text_padding - baseline, text_h + @text_padding)},
        @font_face,
        @font_size,
        text_color,
        thickness: 1,
        lineType: Evision.Constant.cv_LINE_AA()
      )
    end)
  end

  def class_color(class_idx), do: Map.get(@class_colors, class_idx, {255, 0, 0})
end
