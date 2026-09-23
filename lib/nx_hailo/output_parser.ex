defmodule NxHailo.OutputParser do
  @moduledoc """
  Turns the raw output of a model into something meaningful.

  A Hailo model hands back one binary per output vstream, laid out however that
  particular network was compiled, so each model needs a parser that knows its
  layout. `NxHailo.Parsers.YoloV8` is the one shipped here — see it for what an
  implementation looks like.
  """

  @doc """
  Parses `outputs`, a map of output vstream name to raw binary.

  `opts` comes straight from `NxHailo.infer/4` and is whatever the parser needs
  — which vstream to read, class names to attach, and so on.
  """
  @callback parse(outputs :: %{optional(String.t()) => binary()}, opts :: keyword()) ::
              {:ok, term()} | {:error, term()}
end
