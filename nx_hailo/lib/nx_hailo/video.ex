defmodule NxHailo.Video do
  @moduledoc """
  Video capture utilities using Evision.
  """
  alias Evision, as: CV
  require Logger

  # Evision.imwrite("/tmp/frame.png", mat)
  # no host
  # scp nerves.local:/tmp/frame.png /tmp/frame.png

  # open /tmp/frame.png

  @doc """
  Finds the first working camera device by trying each /dev/video* device.
  Returns the device path if found, nil otherwise.
  """
  def find_working_camera do
    # Get list of video devices
    case System.cmd("ls", ["/dev/video*"]) do
      {devices, 0} ->
        devices
        |> String.split("\n")
        |> Enum.find(fn device ->
          cap = CV.VideoCapture.videoCapture(device)

          case CV.VideoCapture.isOpened(cap) do
            true ->
              CV.VideoCapture.release(cap)
              true

            false ->
              false
          end
        end)

      _ ->
        nil
    end
  end

  def get_video_capture(device \\ find_working_camera()) do
    cap = CV.VideoCapture.videoCapture(device)
    # Force the buffer size to 1 so that we can easily get
    # the frame that the camera currently is seeing.
    CV.VideoCapture.set(cap, CV.Constant.cv_CAP_PROP_BUFFERSIZE(), 1)

    cap
  end

  @spec get_realtime_frame(CV.VideoCapture.t()) :: CV.Mat.t()
  def get_realtime_frame(capture) do
    # This assumes that the buffer size is 1
    # so we grab the frame in the queue, which is outdated,
    # and then read the new frame, which is "around now".

    # grab/1 will consume the frame without all of the decoding overhead.
    # retrieve/1 could decode said frame, but seeing that we want to
    # just drop this one, we can then read the next one (which is
    # effectively the same as grab+retrieve).
    true = CV.VideoCapture.grab(capture)

    %CV.Mat{} = mat = CV.VideoCapture.read(capture)

    # TO DO: We might want to convert this to a tensor directly,
    # but given that we don't have any actual operation using this function,
    # returning the mat is more flexible.
    mat
  end

  @doc """
  Starts a local video stream that saves frames to a temporary file.
  The frames can be viewed by running `open /tmp/frame.png` in another terminal.
  """
  def start_local_stream do
    # Get the video capture
    cap = get_video_capture()

    # Start streaming in a separate process
    spawn(fn -> stream_frames(cap) end)

    Logger.info("Local video stream started. Run 'open /tmp/frame.png' to view frames.")
  end

  defp stream_frames(cap) do
    frame = get_realtime_frame(cap)

    CV.imwrite("/tmp/frame.png", frame)

    stream_frames(cap)
  end
end
