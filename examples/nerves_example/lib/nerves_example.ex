defmodule NervesExample do
  @moduledoc """
  Helper functions for the NervesExample Hailo inference demo.
  """

  @doc """
  Loads the YOLOv8 model and class labels from nx_hailo's priv directory.

  Returns `{:ok, {hailo_model, classes, input_name, output_key}}`.
  """
  def load do
    priv = to_string(:code.priv_dir(:nx_hailo))
    {:ok, hailo_model} = NxHailo.load("#{priv}/yolov8m.hef")

    classes =
      "#{priv}/yolov8m_classes.json"
      |> File.read!()
      |> Jason.decode!()
      |> Enum.with_index()
      |> Map.new(fn {v, k} -> {k, v} end)

    [%{name: input_name}] = hailo_model.pipeline.input_vstream_infos
    [%{name: output_key}] = hailo_model.pipeline.output_vstream_infos

    {:ok, {hailo_model, classes, input_name, output_key}}
  end

  @doc """
  Finds the first working video capture device under /dev/video*.

  Returns `{capture, device_path}`, or `nil` if none found.
  """
  def find_capture do
    Path.wildcard("/dev/video*")
    |> Enum.find_value(fn device ->
      cap = Evision.VideoCapture.videoCapture(device)

      cond do
        not Evision.VideoCapture.isOpened(cap) ->
          Evision.VideoCapture.release(cap)
          false

        not Evision.VideoCapture.grab(cap) ->
          Evision.VideoCapture.release(cap)
          false

        true ->
          {cap, device}
      end
    end)
  end

  @doc """
  Resizes `image` to `target_shape` with letterbox padding (grey fill).

  `image_shape` is `{h, w}`, `target_shape` is `{target_h, target_w}`.
  """
  def resize_and_pad(image, {h, w}, {_target_h, _target_w} = target_shape) do
    size = max(h, w)
    pad_h = div(size - h, 2)
    pad_w = div(size - w, 2)
    pad_h_extra = rem(size - h, 2)
    pad_w_extra = rem(size - w, 2)

    padded =
      Evision.copyMakeBorder(
        image,
        pad_h,
        pad_h + pad_h_extra,
        pad_w,
        pad_w + pad_w_extra,
        Evision.Constant.cv_BORDER_CONSTANT(),
        value: {114, 114, 114}
      )

    Evision.resize(padded, target_shape)
  end
end
