defmodule NxHailo.MixProject do
  use Mix.Project

  @app :nx_hailo
  @version "0.1.0"
  @all_targets [
    :rpi5,
    :hailo_rpi5
  ]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.17",
      archives: [nerves_bootstrap: "~> 1.13.1"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: [{@app, release()}],
      preferred_cli_target: [run: :host, test: :host],
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_env: fn ->
        %{
          "MIX_BUILD_EMBEDDED" => "#{Mix.Project.config()[:build_embedded]}",
          "FINE_INCLUDE_DIR" => Fine.include_dir(),
          "HAILO_INCLUDE_DIR" =>
            Path.join([__DIR__, "deps/hailort_include/hailort/libhailort/include"]) |> dbg()
        }
      end
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {NxHailo.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Dependencies for all targets
      {:nerves, "~> 1.10", runtime: false},
      {:shoehorn, "~> 0.9.1"},
      {:ring_logger, "~> 0.11.0"},
      {:toolshed, "~> 0.4.0"},

      # Allow Nerves.Runtime on host to support development, testing and CI.
      # See config/host.exs for usage.
      {:nerves_runtime, "~> 0.13.0"},

      # Dependencies for all targets except :host
      {:nerves_pack, "~> 0.7.1", targets: @all_targets},

      # Dependencies for specific targets
      # NOTE: It's generally low risk and recommended to follow minor version
      # bumps to Nerves systems. Since these include Linux kernel and Erlang
      # version updates, please review their release notes in case
      # changes to your application are needed.
      {:nerves_system_rpi5, "~> 0.2", runtime: false, targets: :rpi5},
      {:hailo_rpi5,
       path: "../hailo_rpi5", runtime: false, targets: :hailo_rpi5, nerves: [compile: true]},
      {:evision, "~> 0.2"},
      {:exla, "~> 0.9.0"},
      {:phoenix, "~> 1.7.20"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0.0"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.5"},
      {:nx, "~> 0.6"},
      {:elixir_make, "~> 0.6", runtime: false},
      {:fine, "~> 0.1.0", runtime: false},
      {
        :hailort_include,
        ">= 0.0.0",
        github: "cocoa-xu/hailort",
        ref: "v4.20.0-build-nerves",
        app: false,
        compile: false,
        sparse: "hailort/libhailort/include"
      },
      {:req, "~> 0.4.0"},
      {:yaml_elixir, "~> 2.10"}
    ]
  end

  def release do
    [
      overwrite: true,
      # Erlang distribution is not started automatically.
      # See https://hexdocs.pm/nerves_pack/readme.html#erlang-distribution
      cookie: "#{@app}_cookie",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: Mix.env() == :prod or [keep: ["Docs"]]
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
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind nx_hailo", "esbuild nx_hailo"],
      "assets.deploy": [
        "tailwind nx_hailo --minify",
        "esbuild nx_hailo --minify",
        "phx.digest"
      ],
      "compile.download_yolov8_model": &download_yolov8_model/1
    ]
  end

  defp download_yolov8_model(_args) do
    Application.ensure_all_started(:req)

    dataset_yml =
      "https://raw.githubusercontent.com/ultralytics/ultralytics/refs/heads/main/ultralytics/cfg/datasets/coco.yaml"

    model_hef_url =
      "https://hailo-model-zoo.s3.eu-west-2.amazonaws.com/ModelZoo/Compiled/v2.15.0/hailo8l/yolov8m.hef"

    priv = to_string(:code.priv_dir(@app))

    download_dataset_to_json_file(dataset_yml, Path.join(priv, "yolov8m_classes.json"))
    download_model(model_hef_url, Path.join(priv, "yolov8m.hef"))
  end

  defp download_dataset_to_json_file(url, filename) do
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

  defp download_model(url, filename) do
    %{body: model_contents} = Req.get!(url)

    File.write!(filename, model_contents)
  end
end
