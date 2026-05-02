defmodule CollabBrain.Presence do
  alias CollabBrain.Persistence

  def track_presence(workspace_id, uid, attrs) do
    Persistence.put_presence(workspace_id, uid, %{
      status: Map.get(attrs, :status, "online"),
      display_name: Map.fetch!(attrs, :display_name),
      active_channel_id: Map.get(attrs, :active_channel_id),
      active_document_id: Map.get(attrs, :active_document_id),
      typing_channel_id: Map.get(attrs, :typing_channel_id),
      typing_document_id: Map.get(attrs, :typing_document_id),
      last_heartbeat_at: DateTime.utc_now()
    })
  end

  def heartbeat(workspace_id, uid, attrs \\ %{}) do
    Persistence.put_presence(
      workspace_id,
      uid,
      %{
        status: Map.get(attrs, :status, "online"),
        display_name: Map.get(attrs, :display_name, ""),
        active_channel_id: Map.get(attrs, :active_channel_id),
        active_document_id: Map.get(attrs, :active_document_id),
        typing_channel_id: Map.get(attrs, :typing_channel_id),
        typing_document_id: Map.get(attrs, :typing_document_id),
        last_heartbeat_at: DateTime.utc_now()
      },
      update_mask: [
        "status",
        "display_name",
        "active_channel_id",
        "active_document_id",
        "typing_channel_id",
        "typing_document_id",
        "last_heartbeat_at"
      ]
    )
  end
end
