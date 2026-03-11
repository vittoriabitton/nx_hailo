defmodule NxHailo.Parsers.ImageNetClassifier do
  @moduledoc """
  Parser for image classification models with a softmax output over ImageNet classes.

  Expects a single output tensor of 1000 float32 scores (one per ImageNet class).
  Returns the top-k predictions sorted by score descending.

  ## Usage
  """

  @behaviour NxHailo.Hailo.OutputParser

  defmodule Classification do
    @moduledoc "A single classification result."
    defstruct [:class_id, :class_name, :score]
  end

  @impl NxHailo.Hailo.OutputParser
  def parse(output_map, opts) when is_list(opts) do
	opts = Keyword.validate!(opts, [:classes, :key, :quant_info, top_k: 5])
    key = Keyword.fetch!(opts, :key)
    classes = Keyword.fetch!(opts, :classes)
    top_k = Keyword.fetch!(opts, :top_k)
    quant_info = Keyword.get(opts, :quant_info)

    raw = Map.fetch!(output_map, key)

    scores = case quant_info do
        %{qp_zp: zp, qp_scale: scale} ->
          for <<x::unsigned-8 <- raw>>, do: (x - zp) * scale

        _ ->
          for <<x::float-32-little <- raw>>, do: x
      end


    results =
      scores
      |> Enum.with_index()
      |> Enum.sort_by(fn {score, _idx} -> score end, :desc)
      |> Enum.take(top_k)
      |> Enum.map(fn {score, idx} ->
        %Classification{
          class_id: idx,
          class_name: classes[idx],
          score: score
        }
      end)

    {:ok, results}
  end
end
