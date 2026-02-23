import Config

config :logger, backends: [RingLogger]

config :shoehorn,
  init: [:nerves_runtime, :nerves_pack],
  app: Mix.Project.config()[:app]

config :nerves, :erlinit, update_clock: true

# SSH access. Reads your local public key; falls back gracefully if not found.
authorized_keys =
  [
    "~/.ssh/id_rsa.pub",
    "~/.ssh/id_ed25519.pub"
  ]
  |> Enum.map(&Path.expand/1)
  |> Enum.filter(&File.exists?/1)
  |> Enum.map(&File.read!/1)

if authorized_keys != [] do
  config :nerves_ssh, authorized_keys: authorized_keys
end

# Networking via vintage_net
config :vintage_net,
  regulatory_domain: "US",
  config: [
    {"usb0", %{type: VintageNetDirect}},
    {"eth0",
     %{
       type: VintageNetEthernet,
       ipv4: %{method: :dhcp}
     }},
    {"wlan0", %{type: VintageNetWiFi}}
  ]

config :mdns_lite,
  hosts: [:hostname, "nerves"],
  ttl: 120,
  instance_name: "Nerves Example",
  services: [
    %{
      protocol: "ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "sftp-ssh",
      transport: "tcp",
      port: 22
    }
  ]
