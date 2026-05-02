defmodule CollabBrain.Firebase.TokenProvider do
  @moduledoc """
  Caches a Google OAuth access token derived from the Firebase service account.
  """

  use GenServer

  @token_uri "https://oauth2.googleapis.com/token"
  @scope "https://www.googleapis.com/auth/datastore"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def access_token do
    GenServer.call(__MODULE__, :access_token)
  end

  @impl true
  def init(_) do
    {:ok, refresh_state()}
  end

  @impl true
  def handle_call(:access_token, _from, state) do
    state =
      if DateTime.diff(state.expires_at, DateTime.utc_now(), :second) < 60 do
        refresh_state()
      else
        state
      end

    {:reply, state.access_token, state}
  end

  defp refresh_state do
    project_id = Application.get_env(:collab_brain, :firebase_project_id)
    project_email = Application.get_env(:collab_brain, :firebase_client_email)
    private_key = Application.get_env(:collab_brain, :firebase_private_key)

    cond do
      is_nil(project_id) or project_id == "" ->
        %{access_token: nil, expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)}

      is_nil(project_email) or project_email == "" or is_nil(private_key) or private_key == "" ->
        %{access_token: nil, expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)}

      true ->
        now = DateTime.utc_now() |> DateTime.to_unix()

        claims = %{
          "iss" => project_email,
          "scope" => @scope,
          "aud" => @token_uri,
          "iat" => now,
          "exp" => now + 3600
        }

        signer = JOSE.JWK.from_pem(private_key)

        assertion =
          JOSE.JWT.sign(signer, %{"alg" => "RS256", "typ" => "JWT"}, claims)
          |> JOSE.JWS.compact()
          |> elem(1)

        body =
          URI.encode_query(%{
            "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion" => assertion
          })

        request =
          Finch.build(:post, @token_uri, [{"content-type", "application/x-www-form-urlencoded"}], body)

        {:ok, response} = Finch.request(request, CollabBrain.Finch)
        %{"access_token" => access_token, "expires_in" => expires_in} = Jason.decode!(response.body)

        %{
          access_token: access_token,
          expires_at: DateTime.add(DateTime.utc_now(), expires_in, :second)
        }
    end
  end
end
