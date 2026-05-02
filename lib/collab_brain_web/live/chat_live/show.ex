defmodule CollabBrainWeb.ChatLive.Show do
  use CollabBrainWeb, :live_view

  alias CollabBrain.Chat
  alias CollabBrain.Chat.RoomServer
  alias CollabBrain.Workspaces

  @impl true
  def mount(%{"workspace_id" => workspace_id, "channel_id" => channel_id}, session, socket) do
    bundle = Workspaces.get_workspace_bundle!(workspace_id)
    
    # Check if channel exists in Firestore or use dummy if local
    channel = Enum.find(bundle.channels, & &1["id"] == channel_id) || %{
      "name" => "Private Room",
      "id" => channel_id,
      "description" => "A private collaboration space"
    }

    if connected?(socket) do
      Phoenix.PubSub.subscribe(CollabBrain.PubSub, RoomServer.topic(workspace_id, channel_id))
    end

    messages = Chat.list_recent_messages(workspace_id, channel_id)

    {:ok,
     socket
     |> assign(:workspace_id, workspace_id)
     |> assign(:channel_id, channel_id)
     |> assign(:channel, channel)
     |> assign(:messages, messages)
     |> assign(:draft, "")
     |> assign(:presence, bundle.presence)
     |> assign(:current_user, %{
       uid: session["uid"],
       display_name: session["display_name"] || "Guest",
       email: session["email"]
     })
     |> assign(:page_title, "##{channel["name"]}")}
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
          <div class="section-title">Room Tools</div>
          <button 
            phx-click={JS.dispatch("phx:copy", detail: %{text: url(~p"/workspaces/#{@workspace_id}/channels/#{@channel_id}")})}
            class="secondary-link" 
            style="width: 100%;"
          >
            🔗 Copy Share URL
          </button>
        </div>

        <section class="sidebar-section">
          <div class="section-title">Members in Room</div>
          <div class="presence-list">
            <%= for person <- @presence do %>
              <div class="presence-item">
                <div class="avatar-bubble" style="width: 28px; height: 28px;"><%= String.first(person["display_name"]) %></div>
                <span style="font-size: 0.85rem;"><%= person["display_name"] %></span>
              </div>
            <% end %>
          </div>
        </section>
      </aside>

      <main class="workspace-main">
        <section class="card slide-up" style="display: flex; flex-direction: column; height: 100%; border-color: var(--brand-glow);">
          <header style="margin-bottom: 2rem; display: flex; justify-content: space-between; align-items: start;">
            <div>
              <div class="eyebrow">Public Channel</div>
              <h2 style="font-size: 2rem;">#<%= @channel["name"] %></h2>
              <p style="margin-top: 5px;"><%= @channel["description"] %></p>
            </div>
            <span class="status-pill">Live Chat</span>
          </header>

          <div class="chat-messages" style="flex: 1;">
             <%= if Enum.empty?(@messages) do %>
              <div style="text-align: center; padding: 4rem; color: var(--muted);">
                <p>Welcome to <strong>#<%= @channel["name"] %></strong>! Start chatting below.</p>
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
            <input type="text" name="draft" value={@draft} phx-debounce="200" placeholder={"Message ##{@channel["name"]}..."} autocomplete="off" />
            <button type="submit">Send</button>
          </.form>
        </section>
      </main>
    </div>
    """
  end

  @impl true
  def handle_event("send_message", %{"draft" => draft}, socket) do
    {:ok, _message} =
      Chat.send_message(socket.assigns.workspace_id, socket.assigns.channel_id, %{
        author_id: socket.assigns.current_user.uid,
        author_name: socket.assigns.current_user.display_name,
        body: draft |> String.trim()
      })

    {:noreply, assign(socket, :draft, "")}
  end

  @impl true
  def handle_event("update_draft", %{"draft" => draft}, socket) do
    {:noreply, assign(socket, :draft, draft)}
  end

  @impl true
  def handle_info({:message_created, message}, socket) do
    {:noreply, update(socket, :messages, &(&1 ++ [message]))}
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
