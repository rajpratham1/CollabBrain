defmodule CollabBrain.Firebase.Auth do
  @moduledoc """
  Firebase Authentication REST client for password resets and user management.
  """

  @identity_toolkit_url "https://identitytoolkit.googleapis.com/v1/accounts"

  def send_password_reset_email(email) do
    api_key = Application.get_env(:collab_brain, :firebase_web_api_key)
    
    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      url = "#{@identity_toolkit_url}:sendOobCode?key=#{api_key}"
      body = Jason.encode!(%{
        "requestType" => "PASSWORD_RESET",
        "email" => email
      })

      request = Finch.build(:post, url, [{"content-type", "application/json"}], body)

      case Finch.request(request, CollabBrain.Finch) do
        {:ok, %{status: 200}} -> :ok
        {:ok, %{body: body}} -> {:error, Jason.decode!(body)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def register_user(email, password, display_name \\ nil) do
    api_key = Application.get_env(:collab_brain, :firebase_web_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      url = "#{@identity_toolkit_url}:signUp?key=#{api_key}"
      body = Jason.encode!(%{
        "email" => email,
        "password" => password,
        "returnSecureToken" => true
      })

      request = Finch.build(:post, url, [{"content-type", "application/json"}], body)

      case Finch.request(request, CollabBrain.Finch) do
        {:ok, %{status: 200, body: body}} ->
          decoded = Jason.decode!(body)

          if display_name do
            update_profile(decoded["idToken"], %{"displayName" => display_name})
          end

          {:ok, decoded}

        {:ok, %{body: body}} ->
          {:error, Jason.decode!(body)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def update_profile(id_token, attrs) do
    api_key = Application.get_env(:collab_brain, :firebase_web_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      url = "#{@identity_toolkit_url}:update?key=#{api_key}"
      body = Jason.encode!(Map.put(attrs, "idToken", id_token))

      request = Finch.build(:post, url, [{"content-type", "application/json"}], body)
      Finch.request(request, CollabBrain.Finch)
    end
  end

  def sign_in_with_password(email, password) do
    api_key = Application.get_env(:collab_brain, :firebase_web_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      url = "#{@identity_toolkit_url}:signInWithPassword?key=#{api_key}"
      body = Jason.encode!(%{
        "email" => email,
        "password" => password,
        "returnSecureToken" => true
      })

      request = Finch.build(:post, url, [{"content-type", "application/json"}], body)

      case Finch.request(request, CollabBrain.Finch) do
        {:ok, %{status: 200, body: body}} -> {:ok, Jason.decode!(body)}
        {:ok, %{body: body}} -> {:error, Jason.decode!(body)}
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
