defmodule CollabBrain.Accounts.Auth do
  @moduledoc """
  Verifies Firebase ID tokens using Google's public certs.
  """

  @certs_url "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"

  def verify_id_token(token) do
    with {:ok, header} <- peek_header(token),
         {:ok, kid} <- Map.fetch(header, "kid"),
         {:ok, certs} <- fetch_certs(),
         {:ok, cert_pem} <- Map.fetch(certs, kid),
         jwk <- JOSE.JWK.from_pem(cert_pem),
         {true, jwt, _} <- JOSE.JWT.verify_strict(jwk, ["RS256"], token),
         claims when is_map(claims) <- jwt.fields,
         :ok <- validate_claims(claims) do
      {:ok, claims}
    else
      :error -> {:error, :invalid_token}
      {false, _, _} -> {:error, :invalid_signature}
      error -> error
    end
  end

  defp peek_header(token) do
    case String.split(token, ".") do
      [header, _payload, _sig] ->
        with {:ok, decoded} <- Base.url_decode64(header, padding: false),
             {:ok, json} <- Jason.decode(decoded) do
          {:ok, json}
        end

      _ ->
        {:error, :invalid_token}
    end
  end

  defp fetch_certs do
    request = Finch.build(:get, @certs_url)

    with {:ok, response} <- Finch.request(request, CollabBrain.Finch),
         {:ok, certs} <- Jason.decode(response.body) do
      {:ok, certs}
    else
      _ -> {:error, :cert_fetch_failed}
    end
  end

  defp validate_claims(%{"aud" => aud, "iss" => iss, "sub" => sub, "exp" => exp}) do
    project_id = Application.fetch_env!(:collab_brain, :firebase_project_id)
    expected_iss = "https://securetoken.google.com/#{project_id}"

    cond do
      aud != project_id -> {:error, :invalid_audience}
      iss != expected_iss -> {:error, :invalid_issuer}
      sub in [nil, ""] -> {:error, :missing_subject}
      exp <= DateTime.utc_now() |> DateTime.to_unix() -> {:error, :expired}
      true -> :ok
    end
  end

  defp validate_claims(_), do: {:error, :invalid_claims}
end
