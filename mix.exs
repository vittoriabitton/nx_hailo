defmodule NxHailo.MixProject do
  use Mix.Project

  @app :nx_hailo
  @version "0.1.0"

  # The Hailo-8 family and the Hailo-10/15 family need different HailoRT
  # branches and different NIF backends. The Makefile makes the same split.
  @targets ~w(hailo8 hailo8l hailo8r hailo10 hailo10h hailo15 hailo15h hailo15l)

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      compilers: compilers(),
      make_env: &make_env/0
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
      {:elixir_make, "~> 0.6", runtime: false},
      {:fine, "~> 0.1.0", runtime: false}
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
      setup: ["deps.get"]
    ]
  end

  # Building the NIF needs HailoRT headers, which only exist on a machine set up
  # for a Hailo device. Set NX_HAILO_SKIP_NIF=1 to skip it and work on the
  # Elixir side — including running the test suite — anywhere else.
  defp compilers do
    if System.get_env("NX_HAILO_SKIP_NIF") do
      Mix.compilers()
    else
      [:elixir_make] ++ Mix.compilers()
    end
  end

  defp make_env do
    %{
      "MIX_BUILD_EMBEDDED" => to_string(Mix.Project.config()[:build_embedded]),
      "FINE_INCLUDE_DIR" => Fine.include_dir(),
      "HAILO_TARGET" => target()
    }
    |> maybe_put("HAILORT_INCLUDE_DIR", Application.get_env(:nx_hailo, :hailort_include_dir))
    |> maybe_put("HAILORT_LIB_DIR", Application.get_env(:nx_hailo, :hailort_lib_dir))
  end

  defp target do
    case Application.get_env(:nx_hailo, :target) do
      nil ->
        Mix.raise("""
        missing :target configuration for :nx_hailo. Add it to your config:

            config :nx_hailo, :target, "hailo10"

        Expected one of: #{Enum.join(@targets, ", ")}.
        """)

      target ->
        target = to_string(target)

        if target in @targets do
          target
        else
          Mix.raise("""
          unknown :target #{inspect(target)} for :nx_hailo.

          Expected one of: #{Enum.join(@targets, ", ")}.
          """)
        end
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value) when is_binary(value), do: Map.put(map, key, value)
  defp maybe_put(map, key, value) when is_list(value), do: Map.put(map, key, to_string(value))
end
