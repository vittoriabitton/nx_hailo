import Config

# Applies when building this project on its own — a project depending on
# :nx_hailo has to set :target itself, since its own config is not loaded here.
# Valid targets are listed in mix.exs.
config :nx_hailo, :target, System.get_env("HAILO_TARGET", "hailo10")
