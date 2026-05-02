defmodule CollabBrainWeb.Plugs.CurrentUser do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    current_user =
      case get_session(conn, :uid) do
        nil ->
          nil

        uid ->
          %{
            uid: uid,
            display_name: get_session(conn, :display_name) || "Guest",
            email: get_session(conn, :email),
            client_id: get_session(conn, :client_id)
          }
      end

    assign(conn, :current_user, current_user)
  end
end
