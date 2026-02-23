import Config

# Allow Nerves.Runtime KV to work on host for development/testing.
config :nerves_runtime,
  kv_backend:
    {Nerves.Runtime.KVBackend.UBootEnv,
     [
       path: Path.join(System.tmp_dir!(), "nerves_example_kv.bin"),
       kv_size: 0x20000
     ]}
