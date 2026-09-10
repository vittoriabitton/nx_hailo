defmodule NxHailo.Parsers.YoloV8 do
  @moduledoc """
  Parses the output of a YOLOv8 model compiled with NMS on the accelerator.

  The model returns one run-length encoded block per class: a count, followed by
  that many `ymin, xmin, ymax, xmax, score` tuples. A class with nothing detected
  contributes just a zero.

  Coordinates come back normalized against the *padded* square image the model
  was fed. `postprocess/2` maps them onto the original frame.
  """

  @behaviour NxHailo.OutputParser

  defmodule RawDetectedObject do
    @moduledoc """
    A detection in padded image space, with coordinates from 0.0 to 1.0.

    `{0.0, 0.0}` is the top-left corner and `{1.0, 1.0}` the bottom-right.
    """

    defstruct [:ymin, :ymax, :xmin, :xmax, :score, :class_name, :class_id]

    @type t :: %__MODULE__{
            ymin: float(),
            ymax: float(),
            xmin: float(),
            xmax: float(),
            score: float(),
            class_name: String.t() | nil,
            class_id: non_neg_integer()
          }
  end

  defmodule DetectedObject do
    @moduledoc """
    A detection in the original frame, with coordinates in pixels.

    `{0, 0}` is the top-left corner and `{height, width}` the bottom-right.
    """

    defstruct [:ymin, :ymax, :xmin, :xmax, :score, :class_name, :class_id]

    @type t :: %__MODULE__{
            ymin: non_neg_integer(),
            ymax: non_neg_integer(),
            xmin: non_neg_integer(),
            xmax: non_neg_integer(),
            score: float(),
            class_name: String.t() | nil,
            class_id: non_neg_integer()
          }
  end

  @doc """
  Parses one output vstream into detections, ordered by class.

  ## Options

    * `:key` - the output vstream name to read from `output_map`
    * `:classes` - a map of class id to class name, used to fill in
      `:class_name`. Ids with no entry come back as `nil`.

  """
  @impl NxHailo.OutputParser
  @spec parse(%{optional(String.t()) => binary()}, keyword()) :: {:ok, [RawDetectedObject.t()]}
  def parse(output_map, opts) when is_list(opts) do
    opts = Keyword.validate!(opts, [:classes, :key])
    key = Keyword.fetch!(opts, :key)
    classes = Keyword.fetch!(opts, :classes)

    scores = for <<value::float-32-little <- Map.fetch!(output_map, key)>>, do: value

    {:ok, parse_classes(scores, 0, classes, [])}
  end

  @doc """
  Maps detections from padded image space onto the original frame.

  Preprocessing pads a frame out to a square before handing it to the model, so
  the coordinates that come back are offset by however much padding was added.
  Pass the shape of the frame *before* padding, as `{height, width}`.
  """
  @spec postprocess([RawDetectedObject.t()], {pos_integer(), pos_integer()}) :: [
          DetectedObject.t()
        ]
  def postprocess(detected_objects, {height, width} = _input_shape) do
    # Preprocessing centres the frame in a square, so half the difference is
    # added to each side.
    side = max(height, width)
    padding_h = div(side - height, 2)
    padding_w = div(side - width, 2)

    Enum.map(detected_objects, fn %RawDetectedObject{} = object ->
      %DetectedObject{
        ymin: to_pixels(object.ymin, side, padding_h, height),
        ymax: to_pixels(object.ymax, side, padding_h, height),
        xmin: to_pixels(object.xmin, side, padding_w, width),
        xmax: to_pixels(object.xmax, side, padding_w, width),
        score: object.score,
        class_name: object.class_name,
        class_id: object.class_id
      }
    end)
  end

  defp to_pixels(coordinate, side, padding, limit) do
    (coordinate * side - padding)
    |> round()
    |> max(0)
    |> min(limit)
  end

  defp parse_classes([], _class_id, _classes, acc), do: Enum.reverse(acc)

  defp parse_classes([count | values], class_id, classes, acc) do
    {detections, rest} = Enum.split(values, trunc(count) * 5)

    acc =
      detections
      |> Enum.chunk_every(5)
      |> Enum.reduce(acc, fn [ymin, xmin, ymax, xmax, score], acc ->
        [
          %RawDetectedObject{
            ymin: ymin,
            xmin: xmin,
            ymax: ymax,
            xmax: xmax,
            score: score,
            class_id: class_id,
            class_name: classes[class_id]
          }
          | acc
        ]
      end)

    parse_classes(rest, class_id + 1, classes, acc)
  end
end
