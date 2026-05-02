defmodule CollabBrain.Persistence do
  alias CollabBrain.Firebase.Client
  alias CollabBrain.LocalStore

  def firebase_enabled? do
    project_id = Application.get_env(:collab_brain, :firebase_project_id)
    client_email = Application.get_env(:collab_brain, :firebase_client_email)
    
    project_id not in [nil, ""] and client_email not in [nil, ""]
  end

  def list_workspaces do
    if firebase_enabled?() do
      []
    else
      LocalStore.list_workspaces()
    end
  end

  def get_workspace(workspace_id) do
    if firebase_enabled?() do
      with {:ok, doc} <- Client.get_document("workspaces/#{workspace_id}") do
        {:ok, Client.decode_document(doc)}
      end
    else
      case LocalStore.get_workspace(workspace_id) do
        {:ok, workspace} -> {:ok, %{"name" => "workspaces/#{workspace_id}", "fields" => workspace}}
        error -> error
      end
    end
  end

  def get_workspace_bundle(workspace_id) do
    if firebase_enabled?() do
      with {:ok, workspace} <- get_workspace(workspace_id),
           {:ok, document} <- get_document(workspace_id, "doc-1") do
        
        # Fetch actual channels and presence
        channels = list_channels(workspace_id) |> Enum.map(& &1["fields"])
        presence = list_presence(workspace_id)
        
        {:ok,
         %{
           workspace: workspace["fields"],
           members: [], # Members collection is large, we keep it simple for now or fetch if needed
           channels: channels,
           documents: [document["fields"]],
           activity: [],
           presence: presence
         }}
      end
    else
      LocalStore.get_workspace_bundle(workspace_id)
    end
  end

  def list_messages(workspace_id, channel_id) do
    if firebase_enabled?() do
      path = "workspaces/#{workspace_id}/channels/#{channel_id}/messages"

      case Client.list_documents(path, page_size: 50) do
        {:ok, %{"documents" => docs}} -> 
          Enum.map(docs, &Client.decode_document/1)
          |> Enum.reject(& &1["fields"]["author_name"] in ["CollabBrain AI", "Demo User", "Leo Design", "Maya Ops", "System"])
        _ -> []
      end
    else
      LocalStore.list_messages(workspace_id, channel_id)
    end
  end

  def create_message(workspace_id, channel_id, message_id, attrs) do
    if firebase_enabled?() do
      Client.create_document("workspaces/#{workspace_id}/channels/#{channel_id}/messages", message_id, attrs)
    else
      LocalStore.append_message(workspace_id, channel_id, stringify_keys(attrs))
    end
  end

  def get_document(workspace_id, document_id) do
    if firebase_enabled?() do
      with {:ok, doc} <- Client.get_document("workspaces/#{workspace_id}/documents/#{document_id}") do
        {:ok, Client.decode_document(doc)}
      end
    else
      case LocalStore.get_document(workspace_id, document_id) do
        {:ok, document} -> {:ok, %{"name" => "documents/#{document_id}", "fields" => document}}
        error -> error
      end
    end
  end

  def update_document(workspace_id, document_id, attrs, update_mask) do
    if firebase_enabled?() do
      Client.patch_document("workspaces/#{workspace_id}/documents/#{document_id}", attrs, update_mask: update_mask)
    else
      LocalStore.update_document(workspace_id, document_id, stringify_keys(attrs))
    end
  end

  def create_operation(workspace_id, document_id, operation_id, attrs) do
    if firebase_enabled?() do
      Client.create_document("workspaces/#{workspace_id}/documents/#{document_id}/operations", operation_id, attrs)
    else
      LocalStore.append_operation(workspace_id, document_id, attrs)
    end
  end

  def put_presence(workspace_id, uid, attrs, update_mask \\ []) do
    if firebase_enabled?() do
      path = "workspaces/#{workspace_id}/presence/#{uid}"

      res = case Client.get_document(path) do
        {:ok, _} -> Client.patch_document(path, attrs, update_mask: update_mask)
        _ -> Client.create_document("workspaces/#{workspace_id}/presence", uid, attrs)
      end
      
      Phoenix.PubSub.broadcast(CollabBrain.PubSub, "workspace_presence:#{workspace_id}", {:presence_updated, workspace_id})
      res
    else
      LocalStore.put_presence(workspace_id, uid, stringify_keys(attrs))
      Phoenix.PubSub.broadcast(CollabBrain.PubSub, "workspace_presence:#{workspace_id}", {:presence_updated, workspace_id})
      {:ok, attrs}
    end
  end

  def create_channel(workspace_id, channel_id, attrs) do
    if firebase_enabled?() do
      Client.create_document("workspaces/#{workspace_id}/channels", channel_id, attrs)
    else
      LocalStore.create_channel(workspace_id, channel_id, stringify_keys(attrs))
    end
  end

  def list_channels(workspace_id) do
    if firebase_enabled?() do
      path = "workspaces/#{workspace_id}/channels"
      case Client.list_documents(path) do
        {:ok, %{"documents" => docs}} -> Enum.map(docs, &Client.decode_document/1)
        _ -> []
      end
    else
      LocalStore.list_channels(workspace_id)
    end
  end

  def ensure_member(workspace_id, uid, attrs) do
    if firebase_enabled?() do
      path = "workspaces/#{workspace_id}/members/#{uid}"
      case Client.get_document(path) do
        {:ok, _} -> :ok
        _ -> 
          Client.create_document("workspaces/#{workspace_id}/members", uid, %{
            display_name: attrs[:display_name] || "New Member",
            email: attrs[:email],
            role: "member",
            joined_at: DateTime.utc_now()
          })
      end
    else
      :ok
    end
  end

  def list_presence(workspace_id) do
    if firebase_enabled?() do
      path = "workspaces/#{workspace_id}/presence"
      case Client.list_documents(path) do
        {:ok, %{"documents" => docs}} -> 
          Enum.map(docs, &Client.decode_document/1)
          |> Enum.map(fn doc -> 
             uid = String.split(doc["name"], "/") |> List.last()
             Map.put(doc["fields"], "uid", uid)
          end)
          |> Enum.reject(& &1["display_name"] in ["CollabBrain AI", "Demo User", "Leo Design", "Maya Ops"])
        _ -> []
      end
    else
      LocalStore.list_presence(workspace_id)
    end
  end

  def stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  def log_activity(workspace_id, attrs) do
    event_id = "evt_#{System.unique_integer([:positive])}"
    payload = Map.put(attrs, "inserted_at", DateTime.utc_now())
    
    # Broadcast for real-time UI updates (instant)
    Phoenix.PubSub.broadcast(CollabBrain.PubSub, "workspace_activity:#{workspace_id}", {:activity_created, payload})

    if firebase_enabled?() do
      # Fire and forget to avoid blocking the UI
      Task.start(fn -> 
        Client.create_document("workspaces/#{workspace_id}/activity", event_id, payload)
      end)
      {:ok, payload}
    else
      {:ok, payload}
    end
  end

  def list_activity(workspace_id) do
    if firebase_enabled?() do
      path = "workspaces/#{workspace_id}/activity"
      case Client.list_documents(path) do
        {:ok, %{"documents" => docs}} -> 
          Enum.map(docs, &Client.decode_document/1)
          |> Enum.reject(& &1["fields"]["actor_name"] in ["CollabBrain AI", "Demo User", "Leo Design", "Maya Ops", "System"])
          |> Enum.sort_by(& &1["inserted_at"], {:desc, DateTime})
          |> Enum.take(10)
        _ -> []
      end
    else
      case LocalStore.get_workspace_bundle(workspace_id) do
        {:ok, bundle} -> bundle.activity
        _ -> []
      end
    end
  end

  def list_members(workspace_id) do
    if firebase_enabled?() do
      path = "workspaces/#{workspace_id}/members"
      case Client.list_documents(path) do
        {:ok, %{"documents" => docs}} -> 
          Enum.map(docs, &Client.decode_document/1)
          |> Enum.map(fn doc -> 
             # Merge fields with the document name (which contains the UID)
             uid = String.split(doc["name"], "/") |> List.last()
             Map.put(doc["fields"], "uid", uid)
          end)
          |> Enum.reject(& &1["display_name"] in ["CollabBrain AI", "Demo User", "Leo Design", "Maya Ops"])
        _ -> []
      end
    else
      # Fallback for local testing (No fake users)
      []
    end
  end

  def list_tasks(workspace_id) do
    if firebase_enabled?() do
      path = "workspaces/#{workspace_id}/tasks"
      case Client.list_documents(path) do
        {:ok, %{"documents" => docs}} when is_list(docs) -> 
          Enum.map(docs, &Client.decode_document/1)
        _ -> []
      end
    else
      case LocalStore.get_workspace_bundle(workspace_id) do
        {:ok, bundle} -> Map.get(bundle, :tasks, [])
        _ -> []
      end
    end
  end

  def create_task(workspace_id, task_id, attrs) do
    if firebase_enabled?() do
      Task.start(fn -> 
        Client.create_document("workspaces/#{workspace_id}/tasks", task_id, attrs)
      end)
      {:ok, attrs}
    else
      {:ok, attrs}
    end
  end

  def update_task(workspace_id, task_id, attrs) do
    if firebase_enabled?() do
      Task.start(fn -> 
        Client.patch_document("workspaces/#{workspace_id}/tasks/#{task_id}", attrs)
      end)
      {:ok, attrs}
    else
      {:ok, attrs}
    end
  end
end
