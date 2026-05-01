#!/usr/bin/env elixir
# Starts a named Elixir node for Livebook's Attached Node runtime.
#
# Usage: ./scripts/start_node.exs [opts]
#
# The node IP defaults to the ethernet interface (eth0).
# Override by passing it as an option:
#   ./scripts/start_node.exs --node-ip 192.168.2.4
#
# Options:
#   --node-ip       Node IP. Defaults to the eth0 IP.
#   --node-name     Full node name. Defaults to <whoami>@<node-ip>.
#   --cookie        Erlang cookie. Defaults to the node base name (part before @).
#   --hailo-target  Target device. Defaults to hailo10.
#   --download-dir  Directory for downloaded models. Defaults to <project>/priv.

project_dir = Path.expand("..", __DIR__)

usage = """
Usage: ./scripts/start_node.exs [opts]

Options:
  --node-ip IP            Node IP. Defaults to the eth0 IP.
  --node-name NAME        Full node name. Defaults to <whoami>@<node-ip>.
  --cookie COOKIE         Erlang cookie. Defaults to the node base name.
  --hailo-target TARGET   Target device. Defaults to hailo10.
  --download-dir DIR      Directory for downloaded models. Defaults to <project>/priv.
  --help                  Print this help.
"""

{opts, args} =
  OptionParser.parse!(
    System.argv(),
    strict: [
      node_ip: :string,
      node_name: :string,
      cookie: :string,
      hailo_target: :string,
      download_dir: :string,
      help: :boolean
    ]
  )

if opts[:help] do
  IO.puts(usage)
  System.halt(0)
end

if args != [] do
  Mix.raise("unexpected positional arguments: #{Enum.join(args, " ")}\n\n#{usage}")
end

current_user = fn ->
  case System.cmd("whoami", []) do
    {user, 0} -> String.trim(user)
    _ -> "nx_hailo"
  end
end

detect_eth0_ip = fn ->
  case System.find_executable("ip") do
    nil ->
      nil

    ip ->
      case System.cmd(ip, ["-4", "addr", "show", "eth0"], stderr_to_stdout: true) do
        {output, 0} ->
          case Regex.run(~r/inet\s+(\d+(?:\.\d+){3})/, output) do
            [_, address] -> address
            _ -> nil
          end

        _ ->
          nil
      end
  end
end

node_ip = opts[:node_ip] || if is_nil(opts[:node_name]), do: detect_eth0_ip.()

if is_nil(node_ip) and is_nil(opts[:node_name]) do
  Mix.raise(
    "could not detect eth0 IP. Pass the node IP explicitly, e.g. ./scripts/start_node.exs --node-ip 192.168.2.4"
  )
end

node_name = opts[:node_name] || "#{current_user.()}@#{node_ip}"
cookie = opts[:cookie] || node_name |> String.split("@", parts: 2) |> hd()
hailo_target = opts[:hailo_target] || "hailo10"
download_dir = opts[:download_dir] || Path.join(project_dir, "priv")

Mix.install(
  [
    {:nx_hailo, path: project_dir},
    {:req, "~> 0.5"},
    {:yaml_elixir, "~> 2.10"},
    {:jason, "~> 1.4"},
    {:evision, "~> 0.2"},
    {:image, "~> 0.54.4"},
    {:kino, "~> 0.14.0"}
  ],
  config: [
    nx_hailo: [
      target: hailo_target,
      download_dir: download_dir
    ]
  ]
)

node_atom = String.to_atom(node_name)
cookie_atom = String.to_atom(cookie)

case System.find_executable("epmd") do
  nil -> :ok
  epmd -> System.cmd(epmd, ["-daemon"])
end

case Node.start(node_atom, :longnames) do
  {:ok, _pid} ->
    :ok

  {:error, {:already_started, _pid}} ->
    :ok

  {:error, reason} ->
    Mix.raise("could not start node #{node_name}: #{inspect(reason)}")
end

:erlang.set_cookie(node(), cookie_atom)

IO.puts("""
Project:      #{project_dir}
Node:         #{node_name}
Cookie:       #{cookie}
Hailo target: #{hailo_target}
Download dir: #{download_dir}

Connect Livebook via:
  Runtime -> Attached Node
  Node:   #{node_name}
  Cookie: #{cookie}

Press Ctrl+C twice to stop this node.
""")

Process.sleep(:infinity)
