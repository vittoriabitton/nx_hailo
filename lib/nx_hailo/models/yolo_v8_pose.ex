defmodule NxHailo.Parsers.YoloV8Pose do
  @moduledoc """
  Parser for YOLOv8 pose estimation models with embedded NMS output.

  The Hailo NMS output for pose uses the same run-length encoding as the
  detection parser, but each detection carries 17 COCO keypoints in addition
  to the bounding box:

      [count, ymin, xmin, ymax, xmax, score,
       kp0_y, kp0_x, kp0_vis, ..., kp16_y, kp16_x, kp16_vis, ...]

  There is only one class (person), so the count prefix appears once.

  Keypoint indices follow the COCO convention:
  `nose, left_eye, right_eye, left_ear, right_ear,
   left_shoulder, right_shoulder, left_elbow, right_elbow,
   left_wrist, right_wrist, left_hip, right_hip,
   left_knee, right_knee, left_ankle, right_ankle`

  > **Note:** This parser is based on the expected Hailo NMS output format
  > for YOLOv8 pose models. Verify keypoint order against your specific HEF
  > if results look incorrect.
  """

  @behaviour NxHailo.Hailo.OutputParser

  @coco_keypoints [
    :nose,
    :left_eye,
    :right_eye,
    :left_ear,
    :right_ear,
    :left_shoulder,
    :right_shoulder,
    :left_elbow,
    :right_elbow,
    :left_wrist,
    :right_wrist,
    :left_hip,
    :right_hip,
    :left_knee,
    :right_knee,
    :left_ankle,
    :right_ankle
  ]

  @num_keypoints length(@coco_keypoints)
  # bbox (5) + (y, x, visibility) per keypoint
  @floats_per_detection 5 + @num_keypoints * 3

  defmodule Keypoint do
    @moduledoc "A single body keypoint with normalized coordinates and visibility score."
    defstruct [:name, :x, :y, :visibility]
  end

  defmodule RawDetectedPerson do
    @moduledoc """
    Detected person with normalized coordinates in padded image space.

    ((0, 0) is top-left, (1, 1) is bottom-right)
    """
    defstruct [:ymin, :ymax, :xmin, :xmax, :score, :keypoints]
  end

  defmodule DetectedPerson do
    @moduledoc """
    Detected person with coordinates mapped to the original image space.

    ((0, 0) is top-left, (height, width) is bottom-right)
    """
    defstruct [:ymin, :ymax, :xmin, :xmax, :score, :keypoints]
  end

  @impl NxHailo.Hailo.OutputParser
  def parse(output_map, opts) when is_list(opts) do
    opts = Keyword.validate!(opts, [:key])
    key = Keyword.fetch!(opts, :key)

    floats_list =
      for <<x::float-32-little <- Map.fetch!(output_map, key)>> do
        x
      end

    parse_list(floats_list, [])
  end

  @doc """
  Remaps coordinates from padded image space to the original image space.

  ## Parameters

  - `detected_persons`: List of `%RawDetectedPerson{}` structs.
  - `input_shape`: The original image shape as `{height, width}`.

  ## Returns

  A list of `%DetectedPerson{}` structs with pixel coordinates.
  """
  def postprocess(detected_persons, input_shape) do
    {input_height, input_width} = input_shape
    max_dim = max(input_height, input_width)
    padding_h = div(max_dim - input_height, 2)
    padding_w = div(max_dim - input_width, 2)

    Enum.map(detected_persons, fn %RawDetectedPerson{} = person ->
      %DetectedPerson{
        ymin: remap(person.ymin, max_dim, padding_h, input_height),
        ymax: remap(person.ymax, max_dim, padding_h, input_height),
        xmin: remap(person.xmin, max_dim, padding_w, input_width),
        xmax: remap(person.xmax, max_dim, padding_w, input_width),
        score: person.score,
        keypoints:
          Enum.map(person.keypoints, fn kp ->
            %Keypoint{
              name: kp.name,
              x: remap(kp.x, max_dim, padding_w, input_width),
              y: remap(kp.y, max_dim, padding_h, input_height),
              visibility: kp.visibility
            }
          end)
      }
    end)
  end

  defp remap(coordinate, scale, padding, max_size) do
    (coordinate * scale - padding)
    |> round()
    |> max(0)
    |> min(max_size)
  end

  defp parse_list([], acc), do: {:ok, acc}

  defp parse_list([count | rest], acc) when count == 0 do
    parse_list(rest, acc)
  end

  defp parse_list([count | rest], acc) do
    count = trunc(count)
    {detection_floats, remaining} = Enum.split(rest, count * @floats_per_detection)

    persons =
      detection_floats
      |> Enum.chunk_every(@floats_per_detection)
      |> Enum.map(&parse_detection/1)

    parse_list(remaining, persons ++ acc)
  end

  defp parse_detection([ymin, xmin, ymax, xmax, score | keypoint_floats]) do
    keypoints =
      keypoint_floats
      |> Enum.chunk_every(3)
      |> Enum.zip(@coco_keypoints)
      |> Enum.map(fn {[y, x, vis], name} ->
        %Keypoint{name: name, x: x, y: y, visibility: vis}
      end)

    %RawDetectedPerson{
      ymin: ymin,
      ymax: ymax,
      xmin: xmin,
      xmax: xmax,
      score: score,
      keypoints: keypoints
    }
  end
end
