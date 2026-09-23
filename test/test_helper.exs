# These tests cover the Elixir side only: encoding, validation, output parsing
# and the rules around sharing the accelerator. Everything past the NIF boundary
# needs real hardware, so :test skips building the NIF (see mix.exs) and one
# warning about it is expected on the first test that touches NxHailo.NIF.
ExUnit.start()
