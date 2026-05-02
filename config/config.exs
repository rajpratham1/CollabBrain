import Config

config :collab_brain,
  default_workspace_id: System.get_env("DEFAULT_WORKSPACE_ID", "demo-space"),
  firebase_project_id: System.get_env("FIREBASE_PROJECT_ID"),
  firebase_client_email: System.get_env("FIREBASE_CLIENT_EMAIL"),
  firebase_private_key: System.get_env("FIREBASE_PRIVATE_KEY"),
  firebase_web_api_key: System.get_env("FIREBASE_WEB_API_KEY")

config :collab_brain, CollabBrain.Firebase.Client,
  base_url: "https://firestore.googleapis.com/v1"

config :collab_brain, CollabBrainWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: CollabBrainWeb.ErrorHTML, json: CollabBrainWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CollabBrain.PubSub,
  live_view: [signing_salt: "replace-me"]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :workspace_id, :document_id, :channel_id, :uid]

import_config "#{config_env()}.exs"
