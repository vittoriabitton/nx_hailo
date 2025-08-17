defmodule NxHailo.Video do
  @moduledoc """
  Video capture utilities using Evision.
  """

  # @doc """
  # Finds the first working camera device by trying each /dev/video* device.
  # Returns the device path if found, nil otherwise.
  # """
  # def find_working_camera do
  #   # Get list of video devices
  #   case System.cmd("sh", ["-c", "ls /dev/video*"]) do
  #     {devices, 0} ->
  #       devices
  #       |> String.split("\n")
  #       |> Enum.find(fn device ->
  #         cap = Evision.VideoCapture.videoCapture(device)

  #         case Evision.VideoCapture.isOpened(cap) do
  #           true ->
  #             # Try to grab a frame to verify it's a working camera
  #             case Evision.VideoCapture.grab(cap) do
  #               true ->
  #                 Evision.VideoCapture.release(cap)
  #                 true

  #               false ->
  #                 Evision.VideoCapture.release(cap)
  #                 false
  #             end

  #           false ->
  #             false
  #         end
  #       end)

  #     _ ->
  #       nil
  #   end
  # end

  # @doc """
  # Gets a video capture object for the given device.
  # """
  # @spec get_video_capture(String.t()) :: Evision.VideoCapture.t()
  # def get_video_capture(device), do: Evision.VideoCapture.videoCapture(device)

  # @doc """
  # Gets a realtime frame from the given video capture object.
  # """
  # @spec get_realtime_frame(Evision.VideoCapture.t()) :: Evision.Mat.t() | nil
  # def get_realtime_frame(capture) do
  #   # Force the buffer size to 1 so that we can easily get
  #   # the frame that the camera currently is seeing.
  #   Evision.VideoCapture.set(capture, Evision.Constant.cv_CAP_PROP_BUFFERSIZE(), 1)

  #   # grab/1 will consume the frame without all of the decoding overhead.
  #   # retrieve/1 could decode said frame, but seeing that we want to
  #   # just drop this one, we can then read the next one (which is
  #   # effectively the same as grab+retrieve).
  #   case Evision.VideoCapture.grab(capture) do
  #     true ->
  #       %Evision.Mat{} = mat = Evision.VideoCapture.read(capture)
  #       mat

  #     false ->
  #       nil
  #   end
  # end
end
