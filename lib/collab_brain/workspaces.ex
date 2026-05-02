defmodule CollabBrain.Workspaces do
  alias CollabBrain.Firebase.Client
  alias CollabBrain.Persistence

  def list_workspaces do
    Persistence.list_workspaces()
  end

  def get_workspace!(workspace_id) do
    {:ok, workspace} = Persistence.get_workspace(workspace_id)
    workspace
  end

  def get_workspace_bundle!(workspace_id) do
    case Persistence.get_workspace_bundle(workspace_id) do
      {:ok, bundle} -> bundle
      {:error, _} -> 
        # Fallback to local store if Firestore fails
        {:ok, bundle} = CollabBrain.LocalStore.get_workspace_bundle(workspace_id)
        bundle
    end
  end

  def member?(workspace_id, uid) do
    case {workspace_id, uid, Persistence.firebase_enabled?()} do
      {"demo-space", allowed_uid, _} when allowed_uid in ["demo_user", "system"] -> true
      {_workspace_id, _uid, true} -> true
      _ -> false
    end
  end

  def seed_workspace(owner_uid, attrs) do
    now = DateTime.utc_now()
    workspace_id = attrs[:slug]

    Client.create_document("workspaces", workspace_id, %{
      name: attrs[:name],
      slug: attrs[:slug],
      owner_id: owner_uid,
      member_count: 1,
      created_at: now,
      updated_at: now
    })

    Client.create_document("workspaces/#{workspace_id}/members", owner_uid, %{
      role: "owner",
      status: "active",
      joined_at: now,
      last_active_at: now
    })
  end
end
