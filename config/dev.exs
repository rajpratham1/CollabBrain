import Config

config :collab_brain, CollabBrainWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base:
    "dev-secret-key-base-dev-secret-key-base-dev-secret-key-base-dev-secret-key-base",
  watchers: []

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
