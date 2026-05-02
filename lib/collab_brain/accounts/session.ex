defmodule CollabBrain.Accounts.Session do
  @moduledoc """
  Session helpers for local authentication and future Firebase-backed login.
  """

  def build_user(params) do
    display_name = params["display_name"] |> normalize_name()
    email = params["email"] |> normalize_email()
    password = params["password"] || ""

    cond do
      display_name == "" -> {:error, :display_name_required}
      email == "" -> {:error, :email_required}
      String.length(password) < 6 -> {:error, :password_too_short}
      firebase_enabled?() ->
        case CollabBrain.Firebase.Auth.register_user(email, password, display_name) do
          {:ok, %{"localId" => uid}} -> {:ok, %{uid: uid, email: email, display_name: display_name, client_id: "br_" <> uid}}
          {:error, %{"error" => %{"message" => "EMAIL_EXISTS"}}} -> {:error, :email_exists}
          {:error, _} -> {:error, :auth_failed}
        end
      true -> {:ok, user_payload(display_name, email)}
    end
  end

  def sign_in_user(params) do
    email = params["email"] |> normalize_email()
    password = params["password"] || ""

    cond do
      email == "" -> {:error, :email_required}
      String.length(password) < 6 -> {:error, :password_too_short}
      firebase_enabled?() ->
        case CollabBrain.Firebase.Auth.sign_in_with_password(email, password) do
          {:ok, %{"localId" => uid, "displayName" => dname}} ->
            {:ok, %{uid: uid, email: email, display_name: dname || email, client_id: "br_" <> uid}}
          {:error, _} -> {:error, :invalid_credentials}
        end
      true ->
        display_name =
          email
          |> String.split("@")
          |> List.first()
          |> String.replace(~r/[^a-z0-9]+/i, " ")
          |> String.trim()
          |> Phoenix.Naming.humanize()

        {:ok, user_payload(display_name, email)}
    end
  end

  def send_password_reset(email) do
    if email != "" do
      if Application.get_env(:collab_brain, :firebase_project_id) not in [nil, ""] do
        CollabBrain.Firebase.Auth.send_password_reset_email(email)
      else
        # Local mock mode
        :ok
      end
    else
      {:error, :email_required}
    end
  end

  def flash_message(:display_name_required), do: "Display name is required."
  def flash_message(:email_required), do: "Email is required."
  def flash_message(:password_too_short), do: "Password must be at least 6 characters."
  def flash_message(:email_exists), do: "This email is already registered."
  def flash_message(:invalid_credentials), do: "Invalid email or password."
  def flash_message(:auth_failed), do: "Authentication failed. Please check your credentials."
  def flash_message(_), do: "We couldn't complete that authentication request."

  defp firebase_enabled? do
    Application.get_env(:collab_brain, :firebase_project_id) not in [nil, ""]
  end

  defp user_payload(display_name, email) do
    uid =
      :sha256
      |> :crypto.hash(email)
      |> Base.url_encode64(padding: false)
      |> binary_part(0, 12)

    %{
      uid: "user_" <> uid,
      email: email,
      display_name: display_name,
      client_id: "browser_" <> Integer.to_string(System.unique_integer([:positive]))
    }
  end

  defp normalize_name(nil), do: ""
  defp normalize_name(value), do: value |> String.trim()

  defp normalize_email(nil), do: ""
  defp normalize_email(value), do: value |> String.trim() |> String.downcase()
end

