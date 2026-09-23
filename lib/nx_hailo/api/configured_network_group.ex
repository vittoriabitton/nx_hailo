defmodule NxHailo.API.NetworkGroup do
  @moduledoc """
  A HEF loaded onto a `NxHailo.API.VDevice`.

  Build one with `NxHailo.API.configure_network_group/3`, then turn it into a
  runnable pipeline with `NxHailo.API.create_pipeline/1`.
  """

  defstruct ref: nil,
            vdevice_ref: nil,
            name: nil,
            input_vstream_infos: [],
            output_vstream_infos: []

  @type t :: %__MODULE__{
          ref: reference(),
          vdevice_ref: reference(),
          name: String.t() | nil,
          input_vstream_infos: [NxHailo.API.VStreamInfo.t()],
          output_vstream_infos: [NxHailo.API.VStreamInfo.t()]
        }
end
