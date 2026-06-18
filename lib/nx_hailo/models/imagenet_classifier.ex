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

    # Hailo HEFs for classification typically bake softmax into the graph and
    # output quantized uint8 probabilities. Only apply softmax when reading raw
    # float32 logits (i.e. a model that does NOT include a softmax layer).
    scores =
      cond do
        match?(%{qp_zp: _, qp_scale: _}, quant_info) ->
          %{qp_zp: zp, qp_scale: scale} = quant_info
          for <<x::unsigned-8 <- raw>>, do: (x - zp) * scale

        true ->
          logits = for <<x::float-32-little <- raw>>, do: x
          softmax(logits)
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

  defp softmax(logits) do
    max_val = Enum.max(logits)
    exp_vals = Enum.map(logits, fn x -> :math.exp(x - max_val) end)
    sum = Enum.sum(exp_vals)
    Enum.map(exp_vals, fn e -> e / sum end)
  end
end
