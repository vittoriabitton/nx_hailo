defmodule NxHailo.API.VDevice do
  @moduledoc """
  A handle on the Hailo accelerator.

  HailoRT allows one per VM; `NxHailo.API.create_vdevice/1` owns it.
  """

  defstruct ref: nil

  @type t :: %__MODULE__{ref: reference()}
end
