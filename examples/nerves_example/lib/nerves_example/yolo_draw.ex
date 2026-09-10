defmodule NervesExample.YOLODraw do
  @moduledoc """
  Draws detections onto an Evision `Mat`.

  Coordinates have to be in pixels, so run detections through
  `NxHailo.Parsers.YoloV8.postprocess/2` first.
  """

  alias NxHailo.Palette

  @font Evision.Constant.cv_FONT_HERSHEY_SIMPLEX()
  @line_type Evision.Constant.cv_LINE_AA()
  @filled -1

  @label_scale 0.5
  @caption_scale 0.7
  @stroke_width 2
  @padding 5

  @white {255, 255, 255}
  @black {0, 0, 0}
  @blue {255, 0, 0}

  @doc """
  Draws each detection as a box in its class colour, labelled with the score.

  `caption` goes in the bottom-right corner — a frame rate, say, or a model name.
  """
  def draw_detected_objects(mat, detections, caption) do
    # Boxes first, then labels, so a label is never covered by the box of a
    # detection drawn after it.
    mat = Enum.reduce(detections, mat, &draw_box(&2, &1))
    mat = Enum.reduce(detections, mat, &draw_label(&2, &1))

    draw_caption(mat, caption)
  end

  defp draw_box(mat, detection) do
    Evision.rectangle(
      mat,
      {detection.xmin, detection.ymin},
      {detection.xmax, detection.ymax},
      Palette.bgr(detection.class_id),
      thickness: @stroke_width
    )
  end

  defp draw_label(mat, detection) do
    text = "#{detection.class_name} #{round(detection.score * 100)}%"
    {{width, height}, baseline} = Evision.getTextSize(text, @font, @label_scale, 1)

    top_left = {detection.xmin, max(detection.ymin - height - 2 * @padding - baseline, 0)}
    bottom_right = {detection.xmin + width + 2 * @padding, max(detection.ymin - baseline, 0)}
    baseline_at = max(detection.ymin - @padding - baseline, height + @padding)

    mat
    |> Evision.rectangle(top_left, bottom_right, @black, thickness: @filled)
    |> put_text(text, {detection.xmin + @padding, baseline_at}, @label_scale)
  end

  defp draw_caption(mat, caption) do
    # Evision reports shape as {height, width, channels}.
    {frame_height, frame_width, _channels} = Evision.Mat.shape(mat)
    {{width, height}, _baseline} = Evision.getTextSize(caption, @font, @caption_scale, 1)

    box_width = width + 2 * @padding
    box_height = height + 2 * @padding

    mat
    |> Evision.rectangle(
      {frame_width - box_width, frame_height - box_height},
      {frame_width, frame_height},
      @blue,
      thickness: @filled
    )
    |> put_text(
      caption,
      {frame_width - box_width + @padding, frame_height - @padding},
      @caption_scale
    )
  end

  defp put_text(mat, text, origin, scale) do
    Evision.putText(mat, text, origin, @font, scale, @white, thickness: 1, lineType: @line_type)
  end
end
