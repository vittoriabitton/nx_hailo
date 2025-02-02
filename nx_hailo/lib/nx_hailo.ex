defmodule NxHailo do
  @moduledoc """
  Documentation for `NxHailo`.
  """

  alias Evision, as: CV

  @doc """
  Hello world.

  ## Examples

      iex> NxHailo.hello()
      :world

  """
  def hello do
    :world
  end

  def get_video_capture, do: CV.VideoCapture.videoCapture()

  def get_frame(capture) do
    mat = CV.VideoCapture.read(capture)

    CV.Mat.to_nx(mat)
    |> Nx.backend_transfer({EXLA.Backend, client: :host})
  end
end
