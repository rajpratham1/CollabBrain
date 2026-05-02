import Config

dotenv_path = Path.expand("../.env", __DIR__)

if File.exists?(dotenv_path) do
  dotenv_path
  |> File.stream!([], :line)
  |> Stream.map(&String.trim/1)
  |> Stream.reject(&(String.starts_with?(&1, "#") || &1 == ""))
  |> Enum.each(fn line ->
    case String.split(line, "=", parts: 2) do
      [key, value] ->
        unless System.get_env(key) do
          cleaned =
            value
            |> String.trim()
            |> String.trim("\"")

          System.put_env(key, cleaned)
        end

      _ ->
        :ok
    end
  end)
end

firebase_project_id = System.get_env("FIREBASE_PROJECT_ID")
firebase_client_email = System.get_env("FIREBASE_CLIENT_EMAIL")

firebase_private_key =
  case System.get_env("FIREBASE_PRIVATE_KEY") do
    nil -> nil
    key -> String.replace(key, "\\n", "\n")
  end

secret_key_base =
  System.get_env(
    "SECRET_KEY_BASE",
    "dev-secret-key-base-dev-secret-key-base-dev-secret-key-base-dev-secret-key-base"
  )

config :collab_brain,
  default_workspace_id: System.get_env("DEFAULT_WORKSPACE_ID", "demo-space"),
  firebase_project_id: firebase_project_id,
  firebase_client_email: firebase_client_email,
  firebase_private_key: firebase_private_key,
  firebase_web_api_key: System.get_env("FIREBASE_WEB_API_KEY")

config :collab_brain, CollabBrainWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4000"))],
  secret_key_base: secret_key_base,
  server: true
