defmodule CollabBrainWeb.DmLive do
  use CollabBrainWeb, :live_view

  alias CollabBrain.Chat
  alias CollabBrain.Workspaces

  @impl true
  def mount(%{"workspace_id" => workspace_id, "dm_id" => dm_id}, session, socket) do
    current_uid = session["uid"]
    
    # Simple and robust way to get other UID
    other_uid = 
      dm_id
      |> String.split("_")
      |> Enum.reject(& &1 == current_uid)
      |> List.first()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(CollabBrain.PubSub, "workspace:#{workspace_id}:dm:#{dm_id}")
    end
    
    bundle = Workspaces.get_workspace_bundle!(workspace_id)
    other_member = Enum.find(bundle.presence, & &1["uid"] == other_uid) || 
                   %{ "display_name" => "User #{String.slice(other_uid || "anon", 0..4)}", "uid" => other_uid }
    
    # Direct Messages are stored in a special 'dms' subcollection in Firestore
    messages = Chat.list_recent_messages(workspace_id, "dm-#{dm_id}")

    {:ok,
     socket
     |> assign(:workspace_id, workspace_id)
     |> assign(:dm_id, dm_id)
     |> assign(:other_uid, other_uid)
     |> assign(:other_name, other_member["display_name"])
     |> assign(:messages, messages)
     |> assign(:draft, "")
     |> assign(:current_user, %{
       uid: session["uid"],
       display_name: session["display_name"] || "Guest",
       email: session["email"]
     })}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="workspace-shell">
      <aside class="workspace-sidebar">
        <.link navigate={~p"/workspaces/#{@workspace_id}"} class="nav-pill">
          ← Back to Workspace
        </.link>
        
        <div class="sidebar-section">
          <div class="section-title">Direct Message</div>
          <div class="presence-item">
            <div class="avatar-bubble" style="width: 32px; height: 32px;"><%= String.first(@other_name) %></div>
            <strong><%= @other_name %></strong>
          </div>
        </div>
        
        <div style="margin-top: auto; padding: 10px; font-size: 0.75rem; color: var(--muted); background: rgba(255,255,255,0.03); border-radius: 10px;">
          🔒 This conversation is private between you and <%= @other_name %>.
        </div>
      </aside>

      <main class="workspace-main">
        <section class="card slide-up" style="display: flex; flex-direction: column; height: 100%; border-color: var(--brand-glow);">
          <header style="margin-bottom: 2rem; display: flex; justify-content: space-between; align-items: start;">
            <div>
              <div class="eyebrow">Private Chat</div>
              <h2 style="font-size: 2rem;"><%= @other_name %></h2>
            </div>
            <span class="status-pill">Encrypted Channel</span>
          </header>

          <div class="chat-messages" style="flex: 1;">
            <%= if Enum.empty?(@messages) do %>
              <div style="text-align: center; padding: 4rem; color: var(--muted);">
                <div class="avatar-bubble" style="width: 60px; height: 60px; margin: 0 auto 1rem; font-size: 1.5rem;"><%= String.first(@other_name) %></div>
                <p>This is the start of your private history with <strong><%= @other_name %></strong>.</p>
              </div>
            <% end %>
            <%= for message <- @messages do %>
              <article class="message-row">
                <div class="avatar-bubble"><%= String.first(message["fields"]["author_name"] || "?") %></div>
                <div class="message-card">
                  <div class="message-meta">
                    <strong><%= message["fields"]["author_name"] %></strong>
                  </div>
                  <p><%= message["fields"]["body"] %></p>
                </div>
              </article>
            <% end %>
          </div>

          <.form for={%{}} phx-change="update_draft" phx-submit="send_dm" class="composer-form">
            <input type="text" name="draft" value={@draft} phx-debounce="200" placeholder={"Message @#{@other_name}..."} autocomplete="off" />
            <button type="submit">Send</button>
          </.form>
        </section>
      </main>
    </div>
    """
  end

  @impl true
  def handle_event("send_dm", %{"draft" => draft}, socket) do
    if String.trim(draft) != "" do
      attrs = %{
        author_id: socket.assigns.current_user.uid,
        author_name: socket.assigns.current_user.display_name,
        body: String.trim(draft),
        inserted_at: DateTime.utc_now()
      }

      # Use a unique ID for the message
      message_id = "msg_#{System.unique_integer([:positive])}"
      
      # Save to persistence
      {:ok, persisted} = CollabBrain.Persistence.create_message(socket.assigns.workspace_id, "dm-#{socket.assigns.dm_id}", message_id, attrs)
      
      decoded = if CollabBrain.Persistence.firebase_enabled?(), do: CollabBrain.Firebase.Client.decode_document(persisted), else: persisted

      # Broadcast to both users
      Phoenix.PubSub.broadcast(CollabBrain.PubSub, "workspace:#{socket.assigns.workspace_id}:dm:#{socket.assigns.dm_id}", {:message_created, decoded})
      
      # Notify recipient
      Phoenix.PubSub.broadcast(CollabBrain.PubSub, "user_notifications:#{socket.assigns.other_uid}", {:new_dm, %{
        from_name: socket.assigns.current_user.display_name,
        text: attrs.body
      }})
      
      # Bot Auto-Response logic
      if socket.assigns.other_uid == "collabbrain_ai" do
        Task.start(fn ->
          Process.sleep(1000)
          bot_attrs = %{
            author_id: "collabbrain_ai",
            author_name: "CollabBrain AI",
            body: "I am your Virtual Assistant. I can help you navigate the workspace, manage your Kanban tasks, or use the Shared Whiteboard. How can I help you today?",
            inserted_at: DateTime.utc_now()
          }
          bot_msg_id = "msg_#{System.unique_integer([:positive])}"
          {:ok, bot_persisted} = CollabBrain.Persistence.create_message(socket.assigns.workspace_id, "dm-#{socket.assigns.dm_id}", bot_msg_id, bot_attrs)
          bot_decoded = if CollabBrain.Persistence.firebase_enabled?(), do: CollabBrain.Firebase.Client.decode_document(bot_persisted), else: bot_persisted
          Phoenix.PubSub.broadcast(CollabBrain.PubSub, "workspace:#{socket.assigns.workspace_id}:dm:#{socket.assigns.dm_id}", {:message_created, bot_decoded})
        end)
      end

      {:noreply, assign(socket, draft: "")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_draft", %{"draft" => draft}, socket) do
    {:noreply, assign(socket, draft: draft)}
  end

  @impl true
  def handle_info({:message_created, message}, socket) do
    {:noreply, update(socket, :messages, &(&1 ++ [message]))}
  end
end
