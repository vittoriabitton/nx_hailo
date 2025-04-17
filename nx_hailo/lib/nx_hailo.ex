defmodule NxHailo do
  @moduledoc """
  Documentation for `NxHailo`.
  """

  alias Evision, as: CV

  ip = "192.168.68.105"
  port = "554"
  user = "admin"
  pass = "adminadmin5"
  @url "rtsp://#{user}:#{pass}@#{ip}:#{port}/mode=real&idc=1&ids=1"

  # Evision.imwrite("/tmp/frame.png", mat)
  # no host
  # scp nerves.local:/tmp/frame.png /tmp/frame.png

  # open /tmp/frame.png

  def get_video_capture(url \\ @url) do
    cap = CV.VideoCapture.videoCapture(url)
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
end
