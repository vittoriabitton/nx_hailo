defmodule NxHailo.Parsers.ImageNetClassifier do
  @moduledoc """
  Parser for image classification models with a softmax output over ImageNet classes.

  Expects a single output tensor of 1000 float32 scores (one per ImageNet class).
  Returns the top-k predictions sorted by score descending.

  ## Usage

      {:ok, model} = NxHailo.load_model(:resnet_v1_50)
      classes = NxHailo.load_classes(:resnet_v1_50)

      [output_info] = model.pipeline.output_vstream_infos
      {:ok, predictions} =
        NxHailo.Hailo.infer(model, inputs, NxHailo.Parsers.ImageNetClassifier,
          key: output_info.name, classes: classes)

      # predictions is a list of %Classification{} sorted by score descending
      top = hd(predictions)
      IO.puts(\"#{top.class_name}: #{Float.round(top.score * 100, 1)}%\")
  """

  @behaviour NxHailo.Hailo.OutputParser

  defmodule Classification do
    @moduledoc "A single classification result."
    defstruct [:class_id, :class_name, :score]
  end

  @impl NxHailo.Hailo.OutputParser
  def parse(output_map, opts) when is_list(opts) do
    opts = Keyword.validate!(opts, [:classes, :key, top_k: 5])
    key = Keyword.fetch!(opts, :key)
    classes = Keyword.fetch!(opts, :classes)
    top_k = Keyword.fetch!(opts, :top_k)

    scores =
      for <<x::float-32-little <- Map.fetch!(output_map, key)>> do
        x
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
