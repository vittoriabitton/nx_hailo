defmodule NxHailo.Model do
  @moduledoc """
  A model loaded onto the accelerator and ready to run frames.

  Built by `NxHailo.load/2`. Holds the accelerator resources for as long as it
  is reachable, and releases them when it is garbage collected.
  """

  defstruct pipeline: nil, name: nil

  @type t :: %__MODULE__{
          pipeline: NxHailo.API.Pipeline.t(),
          name: String.t()
        }
end
