defmodule NxHailo.Parsers.YoloV8Test do
  use ExUnit.Case, async: true

  import NxHailo.Fixtures

  alias NxHailo.Parsers.YoloV8
  alias NxHailo.Parsers.YoloV8.DetectedObject
  alias NxHailo.Parsers.YoloV8.RawDetectedObject

  doctest YoloV8

  @classes %{0 => "person", 1 => "bicycle", 2 => "car"}

  defp parse(detections_by_class, opts \\ []) do
    output = %{"yolov8m/nms" => nms_output(detections_by_class)}
    opts = Keyword.merge([classes: @classes, key: "yolov8m/nms"], opts)

    YoloV8.parse(output, opts)
  end

  describe "parse/2" do
    test "reads one detection" do
      assert {:ok, [detection]} = parse([[{0.25, 0.5, 0.75, 1.0, 0.5}]])

      assert %RawDetectedObject{
               ymin: 0.25,
               xmin: 0.5,
               ymax: 0.75,
               xmax: 1.0,
               score: 0.5,
               class_id: 0,
               class_name: "person"
             } = detection
    end

    test "returns detections in class order" do
      detections =
        parse([
          [{0.0, 0.0, 0.5, 0.5, 0.5}],
          [],
          [{0.5, 0.5, 1.0, 1.0, 0.25}, {0.25, 0.25, 0.75, 0.75, 0.75}]
        ])

      assert {:ok, [first, second, third]} = detections
      assert [first.class_id, second.class_id, third.class_id] == [0, 2, 2]
      assert [first.class_name, second.class_name, third.class_name] == ~w(person car car)
      assert second.score == 0.25
      assert third.score == 0.75
    end

    test "skips classes with nothing detected" do
      assert {:ok, []} = parse([[], [], []])
    end

    test "handles an empty output" do
      assert {:ok, []} = parse([])
    end

    test "leaves class_name nil for a class the caller did not name" do
      assert {:ok, [detection]} = parse([[], [], [], [{0.0, 0.0, 1.0, 1.0, 0.5}]])
      assert detection.class_id == 3
      assert detection.class_name == nil
    end

    test "reads from the requested output vstream" do
      output = %{
        "other" => nms_output([[{0.0, 0.0, 1.0, 1.0, 0.5}]]),
        "wanted" => nms_output([[], [{0.25, 0.25, 0.5, 0.5, 0.25}]])
      }

      assert {:ok, [detection]} = YoloV8.parse(output, classes: @classes, key: "wanted")
      assert detection.class_id == 1
    end

    test "rejects unknown options" do
      assert_raise ArgumentError, fn -> parse([[]], nope: true) end
    end
  end

  describe "postprocess/2" do
    test "removes the padding added to a landscape frame" do
      # A 640x480 frame is padded to 640x640, so 80px of padding sits above and
      # below the image. Half way down the padded square is half way down the
      # frame; the very top of the padded square is above it, and clamps to 0.
      [middle, top] =
        YoloV8.postprocess(
          [
            raw_detection(ymin: 0.5, ymax: 0.5, xmin: 0.5, xmax: 0.5),
            raw_detection(ymin: 0.0, ymax: 0.0, xmin: 0.0, xmax: 0.0)
          ],
          {480, 640}
        )

      assert %DetectedObject{ymin: 240, ymax: 240, xmin: 320, xmax: 320} = middle
      assert %DetectedObject{ymin: 0, ymax: 0, xmin: 0, xmax: 0} = top
    end

    test "removes the padding added to a portrait frame" do
      [detection] =
        YoloV8.postprocess(
          [raw_detection(ymin: 0.5, ymax: 0.5, xmin: 0.5, xmax: 0.5)],
          {640, 480}
        )

      assert %DetectedObject{ymin: 320, ymax: 320, xmin: 240, xmax: 240} = detection
    end

    test "leaves a square frame untouched" do
      [detection] =
        YoloV8.postprocess(
          [raw_detection(ymin: 0.25, ymax: 0.75, xmin: 0.0, xmax: 1.0)],
          {640, 640}
        )

      assert %DetectedObject{ymin: 160, ymax: 480, xmin: 0, xmax: 640} = detection
    end

    test "clamps coordinates to the frame" do
      [detection] =
        YoloV8.postprocess(
          [raw_detection(ymin: -0.5, ymax: 2.0, xmin: -1.0, xmax: 3.0)],
          {480, 640}
        )

      assert %DetectedObject{ymin: 0, ymax: 480, xmin: 0, xmax: 640} = detection
    end

    test "carries the score and class through untouched" do
      [detection] =
        YoloV8.postprocess(
          [raw_detection(score: 0.875, class_id: 7, class_name: "cat")],
          {480, 640}
        )

      assert %DetectedObject{score: 0.875, class_id: 7, class_name: "cat"} = detection
    end
  end

  defp raw_detection(attrs) do
    struct!(
      RawDetectedObject,
      Keyword.merge(
        [
          ymin: 0.0,
          xmin: 0.0,
          ymax: 1.0,
          xmax: 1.0,
          score: 0.5,
          class_id: 0,
          class_name: "person"
        ],
        attrs
      )
    )
  end
end
