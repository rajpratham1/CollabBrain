defmodule CollabBrainWeb.SessionController do
  use CollabBrainWeb, :controller

  alias CollabBrain.AppConfig
  alias CollabBrain.Accounts.Session

  def register(conn, %{"user" => user_params}) do
    case Session.build_user(user_params) do
      {:ok, user} ->
        conn
        |> put_authenticated_session(user)
        |> put_flash(:info, "Workspace account created. Welcome to CollabBrain.")
        |> redirect(to: ~p"/workspaces/#{AppConfig.default_workspace_id()}")

      {:error, reason} ->
        conn
        |> put_flash(:error, Session.flash_message(reason))
        |> redirect(to: ~p"/")
    end
  end

  def sign_in(conn, %{"user" => user_params}) do
    case Session.sign_in_user(user_params) do
      {:ok, user} ->
        conn
        |> put_authenticated_session(user)
        |> put_flash(:info, "Signed in successfully.")
        |> redirect(to: ~p"/workspaces/#{AppConfig.default_workspace_id()}")

      {:error, reason} ->
        conn
        |> put_flash(:error, Session.flash_message(reason))
        |> redirect(to: ~p"/")
    end
  end

  def google_auth(conn, params) do
    user = %{
      uid: params["uid"],
      email: params["email"],
      display_name: params["display_name"] || params["email"],
      client_id: "google_" <> params["uid"]
    }

    conn
    |> put_authenticated_session(user)
    |> put_flash(:info, "Welcome, #{user.display_name}. Signed in with Google.")
    |> redirect(to: ~p"/workspaces/#{AppConfig.default_workspace_id()}")
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "You have been signed out.")
    |> redirect(to: ~p"/")
  end

  defp put_authenticated_session(conn, user) do
    conn
    |> put_session(:uid, user.uid)
    |> put_session(:email, user.email)
    |> put_session(:display_name, user.display_name)
    |> put_session(:client_id, user.client_id)
  end
end
