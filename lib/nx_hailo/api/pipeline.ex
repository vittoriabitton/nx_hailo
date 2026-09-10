defmodule NxHailo.API.Pipeline do
  @moduledoc """
  A configured network group that is ready to run frames.

  Carries the input and output vstreams, which say what shape and type each
  frame has to be and how the results come back.
  """

  defstruct ref: nil,
            network_group_ref: nil,
            input_vstream_infos: [],
            output_vstream_infos: []

  @type t :: %__MODULE__{
          ref: reference(),
          network_group_ref: reference(),
          input_vstream_infos: [NxHailo.API.VStreamInfo.t()],
          output_vstream_infos: [NxHailo.API.VStreamInfo.t()]
        }
end
