defmodule CollabBrain.Chat.RoomServer do
  use GenServer

  alias CollabBrain.Firebase.Client
  alias CollabBrain.Persistence

  def ensure_started(workspace_id, channel_id) do
    name = via(workspace_id, channel_id)

    case GenServer.whereis(name) do
      nil ->
        {:ok, pid} =
          DynamicSupervisor.start_child(
            CollabBrain.RoomSupervisor,
            {__MODULE__, {workspace_id, channel_id}}
          )

        pid

      pid ->
        pid
    end
  end

  def start_link({workspace_id, channel_id}) do
    GenServer.start_link(__MODULE__, {workspace_id, channel_id}, name: via(workspace_id, channel_id))
  end

  @impl true
  def init({workspace_id, channel_id}) do
    {:ok, %{workspace_id: workspace_id, channel_id: channel_id}}
  end

  @impl true
  def handle_call({:send_message, attrs}, _from, state) do
    now = DateTime.utc_now()
    message_id = "msg_" <> Integer.to_string(System.unique_integer([:positive]))

    payload = %{
      body: Map.fetch!(attrs, :body),
      author_id: Map.fetch!(attrs, :author_id),
      author_name: Map.get(attrs, :author_name, Map.fetch!(attrs, :author_id)),
      kind: Map.get(attrs, :kind, "text"),
      inserted_at: now,
      edited_at: nil
    }

    {:ok, persisted} =
      Persistence.create_message(state.workspace_id, state.channel_id, message_id, payload)

    decoded =
      if Persistence.firebase_enabled?() do
        Client.decode_document(persisted)
      else
        persisted
      end

    Phoenix.PubSub.broadcast(
      CollabBrain.PubSub,
      topic(state.workspace_id, state.channel_id),
      {:message_created, decoded}
    )

    {:reply, {:ok, decoded}, state}
  end

  def topic(workspace_id, channel_id), do: "workspace:#{workspace_id}:channel:#{channel_id}"

  defp via(workspace_id, channel_id) do
    {:via, Registry, {CollabBrain.Registry, {:room, workspace_id, channel_id}}}
  end
end
