import Config

config :nx_hailo, :target, System.get_env("HAILO_TARGET", "hailo10")