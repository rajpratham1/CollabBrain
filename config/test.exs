import Config

config :collab_brain, CollabBrainWeb.Endpoint,
  server: false,
  secret_key_base:
    "test-secret-key-base-test-secret-key-base-test-secret-key-base-test-secret-key-base"

config :logger, level: :warning
