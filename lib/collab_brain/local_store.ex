defmodule CollabBrain.LocalStore do
  @moduledoc """
  In-memory demo persistence so the app can run locally before Firebase is configured.
  """

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def list_workspaces, do: GenServer.call(__MODULE__, :list_workspaces)
  def get_workspace(workspace_id), do: GenServer.call(__MODULE__, {:get_workspace, workspace_id})
  def get_workspace_bundle(workspace_id), do: GenServer.call(__MODULE__, {:get_workspace_bundle, workspace_id})
  def list_messages(workspace_id, channel_id), do: GenServer.call(__MODULE__, {:list_messages, workspace_id, channel_id})
  def append_message(workspace_id, channel_id, attrs), do: GenServer.call(__MODULE__, {:append_message, workspace_id, channel_id, attrs})
  def get_document(workspace_id, document_id), do: GenServer.call(__MODULE__, {:get_document, workspace_id, document_id})
  def update_document(workspace_id, document_id, attrs), do: GenServer.call(__MODULE__, {:update_document, workspace_id, document_id, attrs})
  def append_operation(workspace_id, document_id, attrs), do: GenServer.call(__MODULE__, {:append_operation, workspace_id, document_id, attrs})
  def put_presence(workspace_id, uid, attrs), do: GenServer.call(__MODULE__, {:put_presence, workspace_id, uid, attrs})
  def list_presence(workspace_id), do: GenServer.call(__MODULE__, {:list_presence, workspace_id})
  def create_channel(workspace_id, channel_id, attrs), do: GenServer.call(__MODULE__, {:create_channel, workspace_id, channel_id, attrs})
  def list_channels(workspace_id), do: GenServer.call(__MODULE__, {:list_channels, workspace_id})

  @impl true
  def init(_) do
    now = DateTime.utc_now()
    
    # We keep the workspace container but remove the hardcoded people/activity
    workspace = %{
      "id" => "demo-space",
      "name" => "Main Workspace",
      "slug" => "demo-space",
      "owner_id" => "system",
      "member_count" => 1,
      "active_users" => 1,
      "open_documents" => 0,
      "channels_count" => 1,
      "typing_users" => 0,
      "hero_metric" => "100%",
      "hero_metric_label" => "System Health",
      "created_at" => now,
      "updated_at" => now
    }

    state = %{
      workspaces: %{"demo-space" => workspace},
      workspace_members: %{"demo-space" => []},
      channels: %{},
      channel_lists: %{"demo-space" => []},
      messages: %{},
      documents: %{},
      document_lists: %{"demo-space" => []},
      operations: %{},
      presence: %{},
      activity: %{"demo-space" => []}
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:list_workspaces, _from, state) do
    {:reply, Map.values(state.workspaces), state}
  end

  @impl true
  def handle_call({:get_workspace, workspace_id}, _from, state) do
    {:reply, Map.fetch(state.workspaces, workspace_id), state}
  end

  @impl true
  def handle_call({:get_workspace_bundle, workspace_id}, _from, state) do
    bundle =
      case Map.fetch(state.workspaces, workspace_id) do
        {:ok, workspace} ->
          {:ok,
           %{
             workspace: workspace,
             members: Map.get(state.workspace_members, workspace_id, []),
             channels: Map.get(state.channel_lists, workspace_id, []),
             documents: Map.get(state.document_lists, workspace_id, []),
             activity: Map.get(state.activity, workspace_id, []),
             presence: list_presence_entries(state.presence, workspace_id)
           }}

        error ->
          error
      end

    {:reply, bundle, state}
  end

  @impl true
  def handle_call({:list_messages, workspace_id, channel_id}, _from, state) do
    {:reply, Map.get(state.messages, {workspace_id, channel_id}, []), state}
  end

  @impl true
  def handle_call({:append_message, workspace_id, channel_id, attrs}, _from, state) do
    message_id = "msg_" <> Integer.to_string(System.unique_integer([:positive]))
    payload = wrap_message(message_id, attrs)

    next_messages =
      Map.update(state.messages, {workspace_id, channel_id}, [payload], &(&1 ++ [payload]))

    {:reply, {:ok, payload}, %{state | messages: next_messages}}
  end

  @impl true
  def handle_call({:get_document, workspace_id, document_id}, _from, state) do
    {:reply, Map.fetch(state.documents, {workspace_id, document_id}), state}
  end

  @impl true
  def handle_call({:update_document, workspace_id, document_id, attrs}, _from, state) do
    current = Map.fetch!(state.documents, {workspace_id, document_id})
    updated = Map.merge(current, attrs)
    next_documents = Map.put(state.documents, {workspace_id, document_id}, updated)
    next_lists = put_document_in_list(state.document_lists, workspace_id, updated)

    {:reply, {:ok, updated}, %{state | documents: next_documents, document_lists: next_lists}}
  end

  @impl true
  def handle_call({:append_operation, workspace_id, document_id, attrs}, _from, state) do
    operation_id = "op_" <> Integer.to_string(System.unique_integer([:positive]))
    payload = Map.put(attrs, "id", operation_id)

    next_ops =
      Map.update(state.operations, {workspace_id, document_id}, [payload], &(&1 ++ [payload]))

    {:reply, {:ok, payload}, %{state | operations: next_ops}}
  end

  @impl true
  def handle_call({:put_presence, workspace_id, uid, attrs}, _from, state) do
    next_presence = Map.put(state.presence, {workspace_id, uid}, attrs)
    {:reply, {:ok, attrs}, %{state | presence: next_presence}}
  end

  @impl true
  def handle_call({:list_presence, workspace_id}, _from, state) do
    {:reply, list_presence_entries(state.presence, workspace_id), state}
  end

  @impl true
  def handle_call({:create_channel, workspace_id, channel_id, attrs}, _from, state) do
    channel = Map.put(attrs, "id", channel_id)
    next_lists = Map.update(state.channel_lists, workspace_id, [channel], &(&1 ++ [channel]))
    next_channels = Map.put(state.channels, {workspace_id, channel_id}, channel)
    
    {:reply, {:ok, channel}, %{state | channel_lists: next_lists, channels: next_channels}}
  end

  @impl true
  def handle_call({:list_channels, workspace_id}, _from, state) do
    {:reply, Map.get(state.channel_lists, workspace_id, []), state}
  end

  defp list_presence_entries(presence, workspace_id) do
    # Filter for this workspace
    entries = 
      presence
      |> Enum.filter(fn {{scope_id, _uid}, _attrs} -> scope_id == workspace_id end)
      |> Enum.map(fn {{_id, uid}, attrs} -> Map.put(attrs, "uid", uid) end)

    # Add a Virtual Assistant so the workspace never feels empty
    bot = %{
      "uid" => "collabbrain_ai",
      "display_name" => "CollabBrain AI",
      "status" => "online",
      "headline" => "Virtual Team Assistant",
      "avatar_color" => "brand",
      "huddle_status" => nil,
      "huddle_room_id" => nil
    }

    [bot | entries]
    |> Enum.uniq_by(& &1["uid"])
    |> Enum.sort_by(& &1["display_name"])
  end

  defp presence_weight("online"), do: 0
  defp presence_weight("idle"), do: 1
  defp presence_weight(_), do: 2

  defp put_document_in_list(document_lists, workspace_id, updated) do
    current = Map.get(document_lists, workspace_id, [])

    next =
      Enum.map(current, fn document ->
        if document["id"] == updated["id"], do: updated, else: document
      end)

    Map.put(document_lists, workspace_id, next)
  end

  defp wrap_message(message_id, attrs) do
    %{
      "name" => message_id,
      "fields" => attrs
    }
  end
end
