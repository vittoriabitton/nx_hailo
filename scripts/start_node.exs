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
#   --cookie        Erlang cookie. Defaults to a freshly generated random one.
#   --hailo-target  Target device. Defaults to hailo10.
#   --download-dir  Directory for downloaded models. Defaults to <project>/priv.
#   --short-names   Use Erlang short names (Node.start(..., :shortnames)). Use this when
#                   attaching from the Livebook desktop app, which usually runs short names.
#                   Node defaults to <whoami>@<hostname -s> (host part must not contain dots).
#                   Add the Pi IP to the Mac's /etc/hosts for that hostname if needed.

project_dir = Path.expand("..", __DIR__)

usage = """
Usage: ./scripts/start_node.exs [opts]

Options:
  --node-ip IP            Node IP. Defaults to the eth0 IP (ignored for default name if --short-names).
  --node-name NAME        Full node name. Defaults to <whoami>@<node-ip> or <whoami>@<short-hostname>.
  --cookie COOKIE         Erlang cookie. Defaults to a freshly generated random one.
  --hailo-target TARGET   Target device. Defaults to hailo10.
  --download-dir DIR      Directory for downloaded models. Defaults to <project>/priv.
  --short-names           Short names for Livebook GUI attach (see script header).
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
      short_names: :boolean,
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

detect_short_hostname = fn ->
  case System.cmd("hostname", ["-s"], stderr_to_stdout: true) do
    {h, 0} ->
      h = String.trim(h)
      if h != "", do: h, else: nil

    _ ->
      nil
  end
end

short_names? = opts[:short_names] == true

node_ip =
  opts[:node_ip] || if is_nil(opts[:node_name]) and not short_names?, do: detect_eth0_ip.()

if not short_names? and is_nil(node_ip) and is_nil(opts[:node_name]) do
  Mix.raise(
    "could not detect eth0 IP. Pass the node IP explicitly, e.g. ./scripts/start_node.exs --node-ip 192.168.2.4"
  )
end

node_name =
  cond do
    opts[:node_name] ->
      opts[:node_name]

    short_names? ->
      case detect_short_hostname.() do
        nil ->
          Mix.raise(
            "could not detect short hostname (hostname -s). Pass --node-name explicitly, e.g. --node-name vittoria@raspberrypi"
          )

        host ->
          "#{current_user.()}@#{host}"
      end

    true ->
      "#{current_user.()}@#{node_ip}"
  end

if short_names? do
  case String.split(node_name, "@", parts: 2) do
    [_user, host] ->
      if String.contains?(host, ".") do
        Mix.raise(
          "short names require a host part without dots (got #{inspect(host)}). Example: --node-name vittoria@raspberrypi and add '192.168.2.4 raspberrypi' to your Mac's /etc/hosts."
        )
      end

    _ ->
      Mix.raise("invalid --node-name, expected name@host")
  end
end

# Anyone who can reach epmd on this device and guess the cookie can run code on
# it, so generate one rather than defaulting to something guessable.
cookie = opts[:cookie] || Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
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

dist = if short_names?, do: :shortnames, else: :longnames

# Set the cookie before distribution starts, so the node is never briefly
# reachable with the default one.
:erlang.set_cookie(cookie_atom)

case Node.start(node_atom, dist) do
  {:ok, _pid} ->
    :ok

  {:error, {:already_started, _pid}} ->
    :ok

  {:error, reason} ->
    Mix.raise("could not start node #{node_name}: #{inspect(reason)}")
end

attach_note =
  if short_names? do
    """
    Short names: attaching from the Livebook desktop app should just work. If the host
    part is not in DNS, add it to your machine's /etc/hosts, e.g.
      192.168.2.4 #{node_name |> String.split("@") |> List.last()}
    """
  else
    """
    Long names: start Livebook from a terminal, or attaching will usually fail:
      export LIVEBOOK_DISTRIBUTION=name LIVEBOOK_COOKIE=#{cookie}
      export LIVEBOOK_NODE="livebook@$(hostname -f 2>/dev/null || hostname)"
      livebook server
    """
  end

IO.puts("""
Project:      #{project_dir}
Node:         #{node_name}
Distribution: #{if short_names?, do: "short names", else: "long names"}
Cookie:       #{cookie}#{if opts[:cookie], do: "", else: " (generated, pass --cookie to choose one)"}
Hailo target: #{hailo_target}
Download dir: #{download_dir}

Connect Livebook via Runtime -> Attached Node, using the node and cookie above.

#{attach_note}
Press Ctrl+C twice to stop this node.
""")

Process.sleep(:infinity)
