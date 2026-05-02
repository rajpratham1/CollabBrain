defmodule CollabBrain.Firebase.Client do
  @moduledoc """
  Thin Firestore REST client for document reads and writes.
  """

  @base_url Application.compile_env!(:collab_brain, [__MODULE__, :base_url])

  def get_document(path) do
    request(:get, "/projects/#{project_id()}/databases/(default)/documents/#{path}")
  end

  def create_document(collection_path, document_id, attrs) do
    encoded = encode_fields(attrs)

    request(
      :post,
      "/projects/#{project_id()}/databases/(default)/documents/#{collection_path}?documentId=#{document_id}",
      %{fields: encoded}
    )
  end

  def patch_document(path, attrs, opts \\ []) do
    encoded = encode_fields(attrs)
    query = encode_update_mask(Keyword.get(opts, :update_mask, Map.keys(attrs)))

    request(
      :patch,
      "/projects/#{project_id()}/databases/(default)/documents/#{path}#{query}",
      %{fields: encoded}
    )
  end

  def list_documents(collection_path, opts \\ []) do
    page_size = Keyword.get(opts, :page_size, 50)
    request(:get, "/projects/#{project_id()}/databases/(default)/documents/#{collection_path}?pageSize=#{page_size}")
  end

  def request(method, path, body \\ nil) do
    token = CollabBrain.Firebase.TokenProvider.access_token()

    if is_nil(token) do
      {:error, :missing_access_token}
    else
      headers = [
        {"authorization", "Bearer " <> token},
        {"content-type", "application/json"}
      ]

      request =
        Finch.build(method, @base_url <> path, headers, body && Jason.encode!(body))

      with {:ok, response} <- Finch.request(request, CollabBrain.Finch),
           {:ok, decoded} <- Jason.decode(response.body) do
        {:ok, decoded}
      else
        {:error, reason} -> {:error, reason}
        _ -> {:error, :invalid_response}
      end
    end
  end

  def decode_document(%{"fields" => fields} = document) do
    document
    |> Map.put("fields", decode_fields(fields))
  end

  def encode_fields(map) do
    Map.new(map, fn {key, value} -> {to_string(key), encode_value(value)} end)
  end

  def decode_fields(map) do
    Map.new(map, fn {key, value} -> {key, decode_value(value)} end)
  end

  defp encode_value(value) when is_binary(value), do: %{"stringValue" => value}
  defp encode_value(value) when is_integer(value), do: %{"integerValue" => Integer.to_string(value)}
  defp encode_value(value) when is_boolean(value), do: %{"booleanValue" => value}
  defp encode_value(nil), do: %{"nullValue" => nil}
  defp encode_value(%DateTime{} = value), do: %{"timestampValue" => DateTime.to_iso8601(value)}
  defp encode_value(value) when is_map(value), do: %{"mapValue" => %{"fields" => encode_fields(value)}}

  defp encode_value(value) when is_list(value) do
    %{"arrayValue" => %{"values" => Enum.map(value, &encode_value/1)}}
  end

  defp decode_value(%{"stringValue" => value}), do: value
  defp decode_value(%{"integerValue" => value}), do: String.to_integer(value)
  defp decode_value(%{"booleanValue" => value}), do: value
  defp decode_value(%{"nullValue" => _}), do: nil
  defp decode_value(%{"timestampValue" => value}), do: DateTime.from_iso8601(value) |> elem(1)
  defp decode_value(%{"mapValue" => %{"fields" => fields}}), do: decode_fields(fields)
  defp decode_value(%{"arrayValue" => %{"values" => values}}), do: Enum.map(values, &decode_value/1)
  defp decode_value(_), do: nil

  defp encode_update_mask([]), do: ""

  defp encode_update_mask(fields) do
    query =
      fields
      |> Enum.map(&"updateMask.fieldPaths=#{&1}")
      |> Enum.join("&")

    "?" <> query
  end

  defp project_id, do: Application.fetch_env!(:collab_brain, :firebase_project_id)
end

