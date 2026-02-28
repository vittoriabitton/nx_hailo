defmodule NxHailo.Models do
  @moduledoc """
  Catalog of supported Hailo models with download URLs, parsers, and metadata.

  Each catalog entry has a `:chip` field indicating the target Hailo chip.
  Make sure the model's chip matches your hardware before downloading.

  ## Object Detection — hailo8l (COCO 80 classes)

  All YOLOv8 detection models share the same `NxHailo.Parsers.YoloV8` parser
  and COCO class labels. They differ only in size/speed/accuracy trade-offs:

  | Model      | Size   | Notes                         |
  |------------|--------|-------------------------------|
  | `:yolov8n` | nano   | Fastest, least accurate       |
  | `:yolov8s` | small  |                               |
  | `:yolov8m` | medium | Default — balanced            |
  | `:yolov8l` | large  |                               |
  | `:yolov8x` | xlarge | Slowest, most accurate        |

  ## Pose Estimation — hailo8l (COCO 17 keypoints)

  YOLOv8 pose models detect people and their body keypoints.

  | Model           | Notes                               |
  |-----------------|-------------------------------------|
  | `:yolov8s_pose` | Small — faster                      |
  | `:yolov8m_pose` | Medium — more accurate              |

  ## Image Classification — hailo8 (ImageNet 1000 classes)

  | Model           | Notes                               |
  |-----------------|-------------------------------------|
  | `:resnet_v1_50` | ResNet-50 v1 — ImageNet classifier  |

  ## Usage

      {:ok, model} = NxHailo.load_model(:yolov8m)
      classes = NxHailo.load_classes(:yolov8m)

  To download a model's HEF file, add its atom (or `{atom, url}` tuple for
  non-standard URLs) to `@models_to_download` in `mix.exs` before `mix compile`.
  """

  @zoo8l_base "https://hailo-model-zoo.s3.eu-west-2.amazonaws.com/ModelZoo/Compiled/v2.15.0/hailo8l"

  @catalog %{
    # --- YOLOv8 Object Detection (hailo8l) ---
    yolov8n: %{
      hef_url: "#{@zoo8l_base}/yolov8n.hef",
      parser: NxHailo.Parsers.YoloV8,
      classes_file: "coco_classes.json",
      chip: :hailo8l,
      description: "YOLOv8 Nano — fastest, least accurate"
    },
    yolov8s: %{
      hef_url: "#{@zoo8l_base}/yolov8s.hef",
      parser: NxHailo.Parsers.YoloV8,
      classes_file: "coco_classes.json",
      chip: :hailo8l,
      description: "YOLOv8 Small"
    },
    yolov8m: %{
      hef_url: "#{@zoo8l_base}/yolov8m.hef",
      parser: NxHailo.Parsers.YoloV8,
      classes_file: "coco_classes.json",
      chip: :hailo8l,
      description: "YOLOv8 Medium — balanced speed and accuracy"
    },
    yolov8l: %{
      hef_url: "#{@zoo8l_base}/yolov8l.hef",
      parser: NxHailo.Parsers.YoloV8,
      classes_file: "coco_classes.json",
      chip: :hailo8l,
      description: "YOLOv8 Large"
    },
    yolov8x: %{
      hef_url: "#{@zoo8l_base}/yolov8x.hef",
      parser: NxHailo.Parsers.YoloV8,
      classes_file: "coco_classes.json",
      chip: :hailo8l,
      description: "YOLOv8 XLarge — slowest, most accurate"
    },
    # --- YOLOv8 Pose Estimation (hailo8l) ---
    yolov8s_pose: %{
      hef_url: "#{@zoo8l_base}/yolov8s_pose.hef",
      parser: NxHailo.Parsers.YoloV8Pose,
      classes_file: nil,
      chip: :hailo8l,
      description: "YOLOv8 Small Pose — human keypoint detection"
    },
    yolov8m_pose: %{
      hef_url: "#{@zoo8l_base}/yolov8m_pose.hef",
      parser: NxHailo.Parsers.YoloV8Pose,
      classes_file: nil,
      chip: :hailo8l,
      description: "YOLOv8 Medium Pose — human keypoint detection"
    },
    # --- Image Classification (hailo8) ---
    resnet_v1_50: %{
      hef_url:
        "https://hailo-model-zoo.s3.eu-west-2.amazonaws.com/ModelZoo/Compiled/v2.17.0/hailo8/resnet_v1_50.hef",
      parser: NxHailo.Parsers.ImageNetClassifier,
      classes_file: "imagenet_classes.json",
      chip: :hailo8,
      description: "ResNet-50 v1 — ImageNet image classification (hailo8)"
    }
  }

  @doc "Returns the full model catalog."
  def catalog, do: @catalog

  @doc """
  Returns metadata for a named model.

  Returns `{:ok, metadata}` or `:error` if the model is not in the catalog.
  """
  def get(name) when is_atom(name), do: Map.fetch(@catalog, name)

  @doc "Returns the absolute path to the model's HEF file in `priv`."
  def hef_path(name) when is_atom(name) do
    Path.join(priv_dir(), "#{name}.hef")
  end

  @doc """
  Loads the class labels for a model as a `%{index => name}` map.

  Returns `nil` for models without a class file (e.g. pose models).
  """
  def load_classes(name) when is_atom(name) do
    case Map.fetch!(@catalog, name) do
      %{classes_file: nil} ->
        nil

      %{classes_file: file} ->
        Path.join(priv_dir(), file)
        |> File.read!()
        |> Jason.decode!()
        |> Enum.with_index()
        |> Map.new(fn {class_name, idx} -> {idx, class_name} end)
    end
  end

  defp priv_dir, do: :code.priv_dir(:nx_hailo) |> to_string()
end
