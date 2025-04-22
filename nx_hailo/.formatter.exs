# Used by "mix format"
[
  import_deps: [:phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  locals_without_parens: [defnif: 1],
  inputs: [
    "{mix,.formatter}.exs",
    "rootfs_overlay/etc/iex.exs",
    "*.{heex,ex,exs}",
    "{config,lib,test}/**/*.{heex,ex,exs}"
  ]
]
