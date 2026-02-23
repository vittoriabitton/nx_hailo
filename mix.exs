defmodule NxHailo.MixProject do
  use Mix.Project

  @app :nx_hailo
  @version "0.1.0"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      compilers: [:download_models, :elixir_make] ++ Mix.compilers(),
      make_env: fn ->
        %{
          "MIX_BUILD_EMBEDDED" => "#{Mix.Project.config()[:build_embedded]}",
          "FINE_INCLUDE_DIR" => Fine.include_dir()
        }
      end
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nx, "~> 0.6"},
      {:elixir_make, "~> 0.6", runtime: false},
      {:fine, "~> 0.1.0", runtime: false},
      {:req, "~> 0.5.10", runtime: false, optional: true},
      {:yaml_elixir, "~> 2.10"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get"],
      "compile.download_models": [&download_yolov8_model/1]
    ]
  end

  defp download_yolov8_model(_args) do
    if System.get_env("NX_HAILO_DOWNLOAD_MODELS", "true") in ["1", "true", "yes"] do
      {:ok, _} = Application.ensure_all_started([:req])

      dataset_yml =
        "https://raw.githubusercontent.com/ultralytics/ultralytics/refs/heads/main/ultralytics/cfg/datasets/coco.yaml"

      model_hef_url =
        "https://hailo-model-zoo.s3.eu-west-2.amazonaws.com/ModelZoo/Compiled/v2.15.0/hailo8l/yolov8m.hef"

      priv = Path.join(__DIR__, "priv")

      File.mkdir_p!(priv)

      download_dataset_to_json_file(dataset_yml, Path.join(priv, "yolov8m_classes.json"))
      download_model(model_hef_url, Path.join(priv, "yolov8m.hef"))
    end
  end

  defp download_dataset_to_json_file(url, filename) do
    if File.exists?(filename) do
      :ok
    else
      %{body: yaml_contents} = Req.get!(url)

      contents =
        yaml_contents
        |> YamlElixir.read_from_string!()
        |> Map.get("names")
        |> Enum.sort_by(fn {index, _name} -> index end)
        |> Enum.map(fn {_index, name} -> name end)
        |> Jason.encode!()

      File.write!(filename, contents)
    end
  end

  defp download_model(url, filename) do
    marker_filename = filename <> ".marker"

    if File.exists?(marker_filename) do
      IO.puts("Model already exists: #{filename}. Skipping download.")
      :ok
    else
      IO.puts("Model does not exist: #{filename}. Downloading...")
      %{headers: headers, body: response_body} = Req.get!(url)

      if "application/zip" in headers["content-type"] do
        for {output_filename, contents} <- response_body do
          File.write!(Path.join(Path.dirname(filename), to_string(output_filename)), contents)
        end
      else
        File.write!(filename, response_body)
      end

      File.write!(marker_filename, "")
    end
  end
end
