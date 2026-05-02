defmodule CollabBrainWeb.DocumentLive.Show do
  use CollabBrainWeb, :live_view

  alias CollabBrain.Collaboration.DocumentSession
  alias CollabBrain.Editor
  alias CollabBrain.Persistence
  alias CollabBrain.Presence

  @impl true
  def mount(%{"workspace_id" => workspace_id, "document_id" => document_id}, session, socket) do
    {:ok, %{body: body, revision: revision}} = Editor.get_document(workspace_id, document_id)
    presence = Persistence.list_presence(workspace_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(CollabBrain.PubSub, DocumentSession.topic(workspace_id, document_id))
      Phoenix.PubSub.subscribe(CollabBrain.PubSub, "presence_updates:#{workspace_id}")

      Presence.heartbeat(workspace_id, session["uid"] || "demo_user", %{
        display_name: session["display_name"] || "Demo User",
        active_document_id: document_id,
        status: "online"
      })
    end

    {:ok,
     socket
     |> assign(:workspace_id, workspace_id)
     |> assign(:document_id, document_id)
     |> assign(:uid, session["uid"] || "demo_user")
     |> assign(:current_user, %{
       uid: session["uid"],
       display_name: session["display_name"] || "Guest",
       email: session["email"]
     })
     |> assign(:display_name, session["display_name"] || "Guest")
     |> assign(:client_id, session["client_id"] || "browser_demo")
     |> assign(:body, body)
      |> assign(:presence, presence)
     |> assign(:revision, revision)}
  end

  @impl true
  def handle_event("insert_text", %{"offset" => offset, "text" => text}, socket) do
    {:ok, %{body: body, revision: revision}} =
      Editor.apply_client_operation(socket.assigns.workspace_id, socket.assigns.document_id, %{
        author_id: socket.assigns.uid,
        client_id: socket.assigns.client_id,
        type: "insert",
        offset: String.to_integer(offset),
        text: text,
        base_revision: socket.assigns.revision
      })

    {:noreply, assign(socket, body: body, revision: revision)}
  end

  @impl true
  def handle_event("delete_text", %{"offset" => offset, "length" => length}, socket) do
    {:ok, %{body: body, revision: revision}} =
      Editor.apply_client_operation(socket.assigns.workspace_id, socket.assigns.document_id, %{
        author_id: socket.assigns.uid,
        client_id: socket.assigns.client_id,
        type: "delete",
        offset: String.to_integer(offset),
        length: String.to_integer(length),
        base_revision: socket.assigns.revision
      })

    {:noreply, assign(socket, body: body, revision: revision)}
  end

  @impl true
  def handle_event("focus_paragraph", %{"index" => index}, socket) do
    Presence.heartbeat(socket.assigns.workspace_id, socket.assigns.uid, %{
      active_paragraph_id: "p-#{index}"
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:document_updated, %{body: body, revision: revision}}, socket) do
    {:noreply, assign(socket, body: body, revision: revision)}
  end

  @impl true
  def handle_info({:presence_updated, presence}, socket) do
    {:noreply, assign(socket, presence: presence)}
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
          <div class="section-title">Collaborators</div>
          <div class="presence-list">
            <%= for person <- @presence do %>
              <div class="presence-item">
                <div class="avatar-bubble" style="width: 28px; height: 28px;"><%= String.first(person["display_name"]) %></div>
                <div style="font-size: 0.85rem;">
                  <strong><%= person["display_name"] %></strong>
                  <p style="font-size: 0.7rem; color: var(--muted);"><%= if person["active_paragraph_id"], do: "At paragraph #{person["active_paragraph_id"]}", else: "Viewing" %></p>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </aside>

      <main class="workspace-main">
        <section class="card slide-up" style="display: flex; flex-direction: column; min-height: 100%;">
          <header style="margin-bottom: 2rem; display: flex; justify-content: space-between; align-items: start; flex-wrap: wrap; gap: 1rem;">
            <div>
              <div class="eyebrow">Collaborative Editor</div>
              <h1 style="font-size: 2.2rem;">Shared Document</h1>
              <p>Real-time synchronization via OTP & Firestore.</p>
            </div>
            <div style="display: flex; gap: 10px;">
              <span class="status-pill">Revision <%= @revision %></span>
              <span class="status-pill online-dot">Sync Active</span>
            </div>
          </header>

          <article class="prose-panel" style="background: rgba(0,0,0,0.2); border: 1px solid var(--border); border-radius: 18px; padding: 2rem; flex: 1; margin-bottom: 2rem;">
            <%= for {para, index} <- Enum.with_index(String.split(@body, "\n\n")) do %>
              <% locked_by = get_locked_by(index, @presence, @uid) %>
              <div 
                class={"paragraph #{if locked_by, do: "locked", else: ""} #{if active_here?(para, index, @presence), do: "editing-now"}"}
                phx-click={!locked_by && "focus_paragraph"} 
                phx-value-index={index}
                style={"position: relative; padding: 10px; margin-bottom: 10px; border-radius: 8px; cursor: #{if locked_by, do: "not-allowed", else: "pointer"}; transition: all 0.2s ease; opacity: #{if locked_by, do: "0.5", else: "1"};"}
              >
                <%= if locked_by do %>
                   <span style="font-size: 0.7rem; color: var(--danger); font-weight: 700; margin-bottom: 4px; display: block;">🔒 Locked by <%= locked_by["display_name"] %></span>
                <% end %>
                <%= para %>
                <%= for p <- @presence, p["active_paragraph_id"] == "p-#{index}" && p["uid"] != @uid do %>
                  <span class="para-presence-indicator" style="position: absolute; right: -30px; top: 10px; background: var(--brand); color: #000; width: 24px; height: 24px; border-radius: 6px; display: flex; align-items: center; justify-content: center; font-size: 0.7rem; font-weight: 800; box-shadow: 0 4px 10px var(--brand-glow);">
                    <%= String.first(p["display_name"]) %>
                  </span>
                <% end %>
              </div>
            <% end %>
          </article>

          <div style="padding-top: 1.5rem; border-top: 1px solid var(--border);">
            <div class="eyebrow">Editor Actions</div>
            <.form for={%{}} phx-submit="insert_text" class="composer-form">
              <input type="number" name="offset" min="0" value="0" style="width: 100px;" />
              <input type="text" name="text" placeholder="Insert text at offset..." autocomplete="off" />
              <button type="submit">Apply</button>
            </.form>
          </div>
        </section>
      </main>
    </div>
    """
  end

  defp active_here?(_para, index, presence) do
    Enum.any?(presence, & &1["active_paragraph_id"] == "p-#{index}")
  end

  defp get_locked_by(index, presence, my_uid) do
    Enum.find(presence, fn p -> 
      p["active_paragraph_id"] == "p-#{index}" && p["uid"] != my_uid
    end)
  end
end
