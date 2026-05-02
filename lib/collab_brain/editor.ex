defmodule CollabBrain.Editor do
  alias CollabBrain.Collaboration.DocumentSession

  def get_document(workspace_id, document_id) do
    DocumentSession.fetch_snapshot(workspace_id, document_id)
  end

  def apply_client_operation(workspace_id, document_id, attrs) do
    operation = %{
      "author_id" => Map.fetch!(attrs, :author_id),
      "client_id" => Map.fetch!(attrs, :client_id),
      "type" => Map.fetch!(attrs, :type),
      "offset" => Map.fetch!(attrs, :offset),
      "text" => Map.get(attrs, :text, ""),
      "length" => Map.get(attrs, :length, 0),
      "base_revision" => Map.fetch!(attrs, :base_revision)
    }

    DocumentSession.submit_operation(workspace_id, document_id, operation)
  end
end
