defmodule CollabBrainWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :collab_brain

  @session_options [
    store: :cookie,
    key: "_collab_brain_key",
    signing_salt: "collab-brain-salt"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.Static,
    at: "/",
    from: :collab_brain,
    gzip: false,
    only: ~w(favicon.svg site.webmanifest phoenix.min.js phoenix_live_view.min.js)

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug CollabBrainWeb.Router
end
