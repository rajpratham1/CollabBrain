defmodule CollabBrainWeb.WorkspaceLive.Show do
  use CollabBrainWeb, :live_view

  alias CollabBrain.Chat
  alias CollabBrain.Chat.RoomServer
  alias CollabBrain.Workspaces

  @impl true
  def mount(%{"workspace_id" => workspace_id}, session, socket) do
    bundle = Workspaces.get_workspace_bundle!(workspace_id)
    workspace = bundle.workspace
    channels = bundle.channels
    messages = Chat.list_recent_messages(workspace_id, "general")

    if connected?(socket) do
      Phoenix.PubSub.subscribe(CollabBrain.PubSub, RoomServer.topic(workspace_id, "general"))
      Phoenix.PubSub.subscribe(CollabBrain.PubSub, "workspace_activity:#{workspace_id}")
      Phoenix.PubSub.subscribe(CollabBrain.PubSub, "workspace_presence:#{workspace_id}")
      Phoenix.PubSub.subscribe(CollabBrain.PubSub, "user_notifications:#{session["uid"]}")
      
      # Ensure user is member and announce presence
      user_attrs = %{
        display_name: session["display_name"] || "New User",
        email: session["email"]
      }
      CollabBrain.Persistence.ensure_member(workspace_id, session["uid"], user_attrs)
      CollabBrain.Persistence.put_presence(workspace_id, session["uid"], %{
        display_name: user_attrs.display_name,
        status: "Online",
        last_active_at: DateTime.utc_now()
      })
    end

    # Fetch all members and live presence
    activity = CollabBrain.Persistence.list_activity(workspace_id)
    members = CollabBrain.Persistence.list_members(workspace_id)
    live_presence = CollabBrain.Persistence.list_presence(workspace_id)
    
    presence = 
      (members ++ live_presence)
      |> Enum.uniq_by(& &1["uid"])
      |> Enum.sort_by(& &1["display_name"])

    {:ok,
     socket
     |> assign(:workspace_id, workspace_id)
     |> assign(:workspace, workspace)
     |> assign(:channels, channels)
     |> assign(:members, bundle.members)
     |> assign(:documents, bundle.documents)
     |> assign(:activity, activity)
     |> assign(:presence, presence)
     |> assign(:messages, messages)
     |> assign(:active_channel_id, "general")
     |> assign(:draft, "")
     |> assign(:in_huddle, false)
     |> assign(:muted, false)
     |> assign(:current_user, %{
       uid: session["uid"],
       display_name: session["display_name"] || "Guest",
       email: session["email"]
     })
     |> assign(:current_user_name, session["display_name"] || "Guest")}
  end

  @impl true
  def handle_event("create_room", _, socket) do
    room_id = "room_#{System.unique_integer([:positive])}"
    attrs = %{
      "name" => "Chat Room #{String.slice(room_id, -4..-1)}",
      "kind" => "public",
      "topic" => "Private shareable room",
      "created_by" => socket.assigns.current_user.uid,
      "unread_count" => 0,
      "created_at" => DateTime.utc_now(),
      "updated_at" => DateTime.utc_now()
    }
    
    case CollabBrain.Persistence.create_channel(socket.assigns.workspace_id, room_id, attrs) do
      {:ok, _} ->
        CollabBrain.Persistence.log_activity(socket.assigns.workspace_id, %{
          kind: "channel",
          title: "🚀 New Room Created",
          detail: "#{socket.assigns.current_user.display_name} created ##{attrs["name"]}",
          actor_name: socket.assigns.current_user.display_name
        })
        
        {:noreply, 
         socket 
         |> put_flash(:info, "Room created successfully!")
         |> push_navigate(to: ~p"/workspaces/#{socket.assigns.workspace_id}/channels/#{room_id}")}
      
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create room: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("toggle_huddle", _, socket) do
    in_huddle = !socket.assigns.in_huddle
    
    CollabBrain.Persistence.log_activity(socket.assigns.workspace_id, %{
      kind: "huddle",
      title: if(in_huddle, do: "🎙️ Huddle Started", else: "🎧 Huddle Left"),
      detail: "#{socket.assigns.current_user.display_name} #{if in_huddle, do: "joined the audio huddle", else: "left the audio huddle"}.",
      actor_name: socket.assigns.current_user.display_name
    })

    CollabBrain.Presence.heartbeat(socket.assigns.workspace_id, socket.assigns.current_user.uid, %{
      huddle_room_id: if(in_huddle, do: "lounge", else: nil),
      huddle_status: if(in_huddle, do: "speaking", else: nil)
    })

    {:noreply, assign(socket, in_huddle: in_huddle, muted: false)}
  end

  @impl true
  def handle_event("toggle_mute", _, socket) do
    muted = !socket.assigns.muted
    
    CollabBrain.Presence.heartbeat(socket.assigns.workspace_id, socket.assigns.current_user.uid, %{
      huddle_status: if(muted, do: "muted", else: "speaking")
    })

    {:noreply, assign(socket, muted: muted)}
  end

  @impl true
  def handle_event("send_message", %{"draft" => draft}, socket) do
    {:ok, _message} =
      Chat.send_message(socket.assigns.workspace_id, socket.assigns.active_channel_id, %{
        author_id: socket.assigns.current_user.uid,
        author_name: socket.assigns.current_user.display_name,
        body: draft |> String.trim()
      })

    CollabBrain.Persistence.log_activity(socket.assigns.workspace_id, %{
      kind: "chat",
      title: "💬 New Message",
      detail: "#{socket.assigns.current_user.display_name} posted in #general",
      actor_name: socket.assigns.current_user.display_name
    })

    {:noreply, assign(socket, :draft, "")}
  end

  @impl true
  def handle_event("update_draft", %{"draft" => draft}, socket) do
    {:noreply, assign(socket, :draft, draft)}
  end

  @impl true
  def handle_info({:activity_created, event}, socket) do
    {:noreply, update(socket, :activity, &[event | Enum.take(&1, 9)])}
  end

  @impl true
  def handle_info({:new_dm, %{from_name: from, text: text}}, socket) do
    {:noreply, 
     socket 
     |> put_flash(:info, "New message from #{from}: #{String.slice(text, 0..30)}...")}
  end

  @impl true
  def handle_info({:presence_updated, _}, socket) do
    workspace_id = socket.assigns.workspace_id
    members = CollabBrain.Persistence.list_members(workspace_id)
    live_presence = CollabBrain.Persistence.list_presence(workspace_id)
    
    presence = 
      (members ++ live_presence)
      |> Enum.uniq_by(& &1["uid"])
      |> Enum.sort_by(& &1["display_name"])

    {:noreply, assign(socket, :presence, presence)}
  end

  @impl true
  def handle_info({:message_created, message}, socket) do
    {:noreply, update(socket, :messages, &(&1 ++ [message]))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="workspace-shell">
      <aside class="workspace-sidebar">
        <section class="sidebar-section">
          <div class="section-title">Navigation</div>
          <.link navigate={~p"/workspaces/#{@workspace_id}/kanban"} class="nav-pill">
            <span>📋 Kanban Board</span>
          </.link>
          <.link navigate={~p"/workspaces/#{@workspace_id}/whiteboard"} class="nav-pill">
            <span>🎨 Shared Whiteboard</span>
          </.link>
        </section>

        <section class="sidebar-section">
          <div class="section-title">⚡ Nerve Center (Activity)</div>
          <div style="font-size: 0.8rem; display: flex; flex-direction: column; gap: 10px;">
            <%= if Enum.empty?(@activity) do %>
              <div style="color: var(--muted); padding-left: 10px;">No recent activity.</div>
            <% else %>
              <%= for event <- @activity do %>
                <div style="padding: 8px; background: rgba(255,255,255,0.03); border-radius: 8px; border-left: 2px solid var(--brand);">
                  <strong style="display: block; color: var(--text);"><%= event["title"] %></strong>
                  <span style="color: var(--muted); font-size: 0.75rem;"><%= event["detail"] %></span>
                </div>
              <% end %>
            <% end %>
          </div>
        </section>

        <section class="sidebar-section">
          <div class="section-title">Public Channels</div>
          <%= for channel <- @channels do %>
            <.link navigate={~p"/workspaces/#{@workspace_id}/channels/#{channel["id"]}"} class={"nav-pill #{if @active_channel_id == channel["id"], do: "active"}"}>
              <span># <%= channel["name"] %></span>
              <span class="status-pill"><%= channel["unread_count"] %></span>
            </.link>
          <% end %>
          <.form for={%{}} phx-submit="create_room">
            <button type="submit" class="primary-link" style="width: 100%; margin-top: 10px; font-size: 0.85rem; border: 1px solid var(--brand);">
              + New Room
            </button>
          </.form>
        </section>

        <section class="sidebar-section">
          <div class="section-title">Team DMs</div>
          <div class="presence-list">
            <%= for person <- @presence do %>
              <%= if person["uid"] != @current_user.uid do %>
                <% dm_id = Enum.sort([@current_user.uid, person["uid"]]) |> Enum.join("_") %>
                <.link navigate={~p"/workspaces/#{@workspace_id}/dm/#{dm_id}"} class="nav-pill">
                  <div class="avatar-bubble" style="width: 32px; height: 32px; font-size: 0.7rem;"><%= String.first(person["display_name"]) %></div>
                  <span><%= person["display_name"] %></span>
                </.link>
              <% end %>
            <% end %>
          </div>
        </section>

        <section class="sidebar-section">
          <div class="section-title">Knowledge Base</div>
          <%= for document <- @documents do %>
            <.link navigate={~p"/workspaces/#{@workspace_id}/documents/#{document["id"]}"} class="nav-pill">
              <span>📄 <%= document["title"] %></span>
            </.link>
          <% end %>
        </section>
      </aside>

      <main class="workspace-main">
        <section class="workspace-hero card glow-card slide-up">
          <div style="display: flex; justify-content: space-between; align-items: flex-start; flex-wrap: wrap; gap: 2rem;">
            <div style="flex: 1; min-width: 300px;">
              <div class="eyebrow">Workspace Overview</div>
              <h1 style="font-size: 2.8rem; margin-bottom: 0.5rem;"><%= @workspace["name"] %></h1>
              <p style="font-size: 1.1rem; max-width: 500px;">Collaborate in real-time with your team on tasks, documents, and private rooms.</p>
              
              <div class="huddle-controls" style="margin-top: 2rem; display: flex; gap: 1rem;">
                <button phx-click="toggle_huddle" class={if @in_huddle, do: "primary-link huddle-speaking", else: "primary-link"}>
                  <%= if @in_huddle, do: "🎙️ Speaking", else: "🎧 Join Huddle" %>
                </button>
                <%= if @in_huddle do %>
                  <button phx-click="toggle_mute" class="secondary-link">
                    <%= if @muted, do: "🔇 Unmute", else: "🎤 Mute" %>
                  </button>
                <% end %>
              </div>
            </div>

            <div class="hero-stat-grid" style="flex: 1; margin-top: 0;">
              <div class="metric-card">
                <strong><%= length(@presence) %></strong>
                <span>Online</span>
              </div>
              <div class="metric-card">
                <strong><%= length(@documents) %></strong>
                <span>Documents</span>
              </div>
              <div class="metric-card">
                <strong><%= @workspace["hero_metric"] || 0 %></strong>
                <span>Velocity</span>
              </div>
            </div>
          </div>
        </section>

        <section class="workspace-content-grid">
          <div class="workspace-column">
            <section class="card slide-up delay-1" style="display: flex; flex-direction: column; min-height: 600px;">
              <div style="margin-bottom: 1.5rem;">
                <div class="eyebrow">General Channel</div>
                <h3>Team Feed</h3>
              </div>

              <div class="chat-messages" style="flex: 1;">
                <%= if Enum.empty?(@messages) do %>
                  <div style="text-align: center; padding: 3rem; color: var(--muted);">
                    <p>No messages yet. Start the conversation!</p>
                  </div>
                <% end %>
                <%= for message <- @messages do %>
                  <article class="message-row">
                    <div class="avatar-bubble"><%= String.first(message["fields"]["author_name"] || "?") %></div>
                    <div class="message-card">
                      <div class="message-meta">
                        <strong><%= message["fields"]["author_name"] %></strong>
                        <span><%= pretty_time(message["fields"]["inserted_at"]) %></span>
                      </div>
                      <p><%= message["fields"]["body"] %></p>
                    </div>
                  </article>
                <% end %>
              </div>

              <.form for={%{}} phx-change="update_draft" phx-submit="send_message" class="composer-form">
                <input type="text" name="draft" value={@draft} phx-debounce="200" placeholder="Broadcast a message..." autocomplete="off" />
                <button type="submit">Send</button>
              </.form>
            </section>
          </div>

          <div class="workspace-column">
            <section class="card slide-up delay-2">
              <div style="margin-bottom: 1.5rem;">
                <div class="eyebrow">Live Activity</div>
                <h3>Team Presence</h3>
              </div>

              <div class="presence-list">
                <%= for person <- @presence do %>
                  <article class="presence-item">
                    <div class={if person["huddle_status"] == "speaking", do: "avatar-bubble huddle-speaking", else: "avatar-bubble"}>
                      <%= String.first(person["display_name"]) %>
                    </div>
                    <div style="flex: 1;">
                      <strong style="display: block;"><%= person["display_name"] %></strong>
                      <span style="font-size: 0.8rem; color: var(--muted);">
                        <%= if person["huddle_room_id"], do: "🎙️ In Huddle", else: person["status"] || "Active" %>
                      </span>
                    </div>
                    <%= if person["uid"] != @current_user.uid do %>
                      <% dm_id = Enum.sort([@current_user.uid, person["uid"]]) |> Enum.join("_") %>
                      <.link navigate={~p"/workspaces/#{@workspace_id}/dm/#{dm_id}"} class="status-pill">
                        Chat
                      </.link>
                    <% else %>
                      <span class="status-pill" style="opacity: 0.5;">You</span>
                    <% end %>
                  </article>
                <% end %>
              </div>
            </section>
          </div>
        </section>
      </main>
    </div>
    """
  end

  defp pretty_time(%DateTime{} = value) do
    minutes = max(DateTime.diff(DateTime.utc_now(), value, :minute), 0)

    cond do
      minutes < 1 -> "just now"
      minutes == 1 -> "1 min ago"
      minutes < 60 -> "#{minutes} min ago"
      true -> "#{div(minutes, 60)}h ago"
    end
  end
  defp pretty_time(_), do: "just now"
end
