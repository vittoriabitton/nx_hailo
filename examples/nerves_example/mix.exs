defmodule NervesExample.MixProject do
  use Mix.Project

  @app :nerves_example
  @version "0.1.0"
  @all_targets [:rpi5]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.17",
      archives: [nerves_bootstrap: "~> 1.13"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: [{@app, release()}],
      preferred_cli_target: [run: :host, test: :host]
    ]
  end

  def application do
    [
      mod: {NervesExample.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      # Nerves core
      {:nerves, "~> 1.10", runtime: false},
      {:shoehorn, "~> 0.9.1"},
      {:ring_logger, "~> 0.11.0"},
      {:toolshed, "~> 0.4.0"},
      {:nerves_runtime, "~> 0.13.0"},
      {:nerves_pack, "~> 0.7.1", targets: @all_targets},
      {:nerves_system_rpi5, "~> 0.6", runtime: false, targets: :rpi5},

      # NxHailo library
      {:nx_hailo, path: "../../"},

      # Vision / inference
      {:evision, "~> 0.2"},
      {:nx, "~> 0.6"},

      # Livebook support (attached node)
      {:kino, "~> 0.14"}
    ]
  end

  def release do
    [
      overwrite: true,
      cookie: "nerves-cookie",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: Mix.env() == :prod or [keep: ["Docs"]]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
