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
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_env: fn ->
        target = Application.get_env(:nx_hailo, :target) || raise "missing :nx_hailo, :target configuration. Must be one of [\"hailo8\", \"hailo10\"]"

        base = %{
          "MIX_BUILD_EMBEDDED" => "#{Mix.Project.config()[:build_embedded]}",
          "FINE_INCLUDE_DIR" => Fine.include_dir(),
          "HAILO_TARGET" => to_string(target)
        }

        base
        |> maybe_put("HAILORT_INCLUDE_DIR", Application.get_env(:nx_hailo, :hailort_include_dir))
        |> maybe_put("HAILORT_LIB_DIR", Application.get_env(:nx_hailo, :hailort_lib_dir))
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
      {:nx, "~> 0.11"},
      {:jason, "~> 1.4"},
      {:elixir_make, "~> 0.6", runtime: false},
      {:fine, "~> 0.1.0", runtime: false}
    ]
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value) when is_binary(value), do: Map.put(map, key, value)
  defp maybe_put(map, key, value) when is_list(value), do: Map.put(map, key, to_string(value))

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
