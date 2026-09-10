defmodule NervesExample do
  @moduledoc """
  YOLOv8 object detection on a camera attached to the device.

  `livebooks/remote_device_inference.livemd` drives these functions from a
  Livebook attached to the running device.

  Both the model and its class labels have to be on the device before this will
  work — see `livebooks/download_models.livemd` in the `nx_hailo` repository.
  """

  @model "yolov8m"

  @doc """
  Loads the model and its class labels.

  Returns the model, a map of class id to class name, and the names of the
  input and output vstreams, which `NxHailo.infer/4` needs.
  """
  def load(model \\ @model) do
    priv = to_string(:code.priv_dir(:nx_hailo))

    with {:ok, hailo_model} <- NxHailo.load(Path.join(priv, "#{model}.hef")),
         {:ok, classes} <- load_classes(Path.join(priv, "#{model}_classes.json")) do
      [input] = hailo_model.pipeline.input_vstream_infos
      [output] = hailo_model.pipeline.output_vstream_infos

      {:ok, {hailo_model, classes, input.name, output.name}}
    end
  end

  @doc """
  Returns the first camera that opens and delivers a frame, as `{capture, device}`.
  """
  def find_capture do
    Enum.find_value(Path.wildcard("/dev/video*"), fn device ->
      capture = Evision.VideoCapture.videoCapture(device)

      if Evision.VideoCapture.isOpened(capture) and Evision.VideoCapture.grab(capture) do
        {capture, device}
      else
        Evision.VideoCapture.release(capture)
        false
      end
    end)
  end

  @doc """
  Grabs the newest frame from `capture`.

  Shrinking the buffer to one frame keeps the loop showing what the camera sees
  now rather than working through a backlog.
  """
  def frame(capture) do
    Evision.VideoCapture.set(capture, Evision.Constant.cv_CAP_PROP_BUFFERSIZE(), 1)
    true = Evision.VideoCapture.grab(capture)
    Evision.VideoCapture.read(capture)
  end

  @doc """
  Pads a frame out to a square, then resizes it to what the model takes.

  Padding first keeps the image from being stretched; the grey border is the
  usual YOLO letterbox fill. `NxHailo.Parsers.YoloV8.postprocess/2` undoes the
  padding on the way back out.
  """
  def resize_and_pad(image, {height, width}, {target_height, target_width}) do
    side = max(height, width)
    padding_h = div(side - height, 2)
    padding_w = div(side - width, 2)

    image
    |> Evision.copyMakeBorder(
      padding_h,
      padding_h + rem(side - height, 2),
      padding_w,
      padding_w + rem(side - width, 2),
      Evision.Constant.cv_BORDER_CONSTANT(),
      value: {114, 114, 114}
    )
    |> Evision.resize({target_width, target_height})
  end

  defp load_classes(path) do
    with {:ok, contents} <- File.read(path) do
      classes =
        contents
        |> JSON.decode!()
        |> Enum.with_index(fn name, index -> {index, name} end)
        |> Map.new()

      {:ok, classes}
    end
  end
end
