defmodule CollabBrainWeb.Plugs.RequireAuth do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :uid) do
      conn
    else
      conn
      |> put_flash(:error, "Sign in first to access your workspace.")
      |> redirect(to: "/")
      |> halt()
    end
  end
end
