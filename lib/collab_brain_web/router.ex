defmodule CollabBrainWeb.Router do
  use CollabBrainWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CollabBrainWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug CollabBrainWeb.Plugs.CurrentUser
    plug :put_coop_header
  end

  defp put_coop_header(conn, _opts) do
    Plug.Conn.put_resp_header(conn, "cross-origin-opener-policy", "same-origin-allow-popups")
  end

  pipeline :authenticated do
    plug CollabBrainWeb.Plugs.RequireAuth
  end

  scope "/", CollabBrainWeb do
    pipe_through :browser

    live "/", HomeLive
    live "/reset-password", ResetPasswordLive
    post "/register", SessionController, :register
    post "/sign-in", SessionController, :sign_in
    post "/auth/google", SessionController, :google_auth
    delete "/logout", SessionController, :delete
  end

  scope "/", CollabBrainWeb do
    pipe_through [:browser, :authenticated]

    live "/workspaces/:workspace_id", WorkspaceLive.Show
    live "/workspaces/:workspace_id/kanban", KanbanLive
    live "/workspaces/:workspace_id/dm/:dm_id", DmLive
    live "/workspaces/:workspace_id/documents/:document_id", DocumentLive.Show
    live "/workspaces/:workspace_id/channels/:channel_id", ChatLive.Show
    live "/workspaces/:workspace_id/whiteboard", WhiteboardLive
  end
end
