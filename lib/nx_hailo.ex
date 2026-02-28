defmodule NxHailo do
  @moduledoc """
  Top-level API for Hailo integration with Nx.

  Provides convenience functions for loading named models and class labels.
  See `NxHailo.Models` for the full catalog of supported models.

  ## Quick start

      # Load a model by name
      {:ok, model} = NxHailo.load_model(:yolov8m)

      # Load its class labels
      classes = NxHailo.load_classes(:yolov8m)

      # Prepare your input tensor, then infer
      {:ok, detections} = NxHailo.Hailo.infer(model, inputs, NxHailo.Parsers.YoloV8,
        key: output_key, classes: classes)
  """

  @doc """
  Loads a named model from its HEF file in `priv`.

  The model must have been downloaded at compile time. Add its atom to
  `@models_to_download` in `mix.exs` before running `mix compile`.

  ## Examples

      {:ok, model} = NxHailo.load_model(:yolov8m)
      {:ok, model} = NxHailo.load_model(:yolov8n)
      {:ok, model} = NxHailo.load_model(:yolov8m_pose)
  """
  def load_model(name) when is_atom(name) do
    NxHailo.Hailo.load(NxHailo.Models.hef_path(name))
  end

  @doc """
  Loads the class labels for a named model as a `%{index => name}` map.

  Returns `nil` for models without class labels (e.g. pose models).

  ## Examples

      classes = NxHailo.load_classes(:yolov8m)
      # %{0 => "person", 1 => "bicycle", ...}

      NxHailo.load_classes(:yolov8m_pose)
      # nil
  """
  def load_classes(name) when is_atom(name) do
    NxHailo.Models.load_classes(name)
  end
end
