defmodule CollabBrain.Chat do
  alias CollabBrain.Chat.RoomServer
  alias CollabBrain.Persistence

  def send_message(workspace_id, channel_id, attrs) do
    pid = RoomServer.ensure_started(workspace_id, channel_id)
    GenServer.call(pid, {:send_message, attrs}, 15_000)
  end

  def list_recent_messages(workspace_id, channel_id) do
    Persistence.list_messages(workspace_id, channel_id)
  end
end
